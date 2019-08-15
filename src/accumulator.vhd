library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity accumulator is
	generic (
		n1 : integer; -- Parallellization/unrolling for accumulator. (half of the grain)
		n2 : integer -- Parallellization/unrolling for grain. n1*2
	);
	port (
		iAccumStart       : in STD_LOGIC;
		iAccumY           : in STD_LOGIC_VECTOR(0 to n2 - 1); -- Send n2 bits. The last half only used for loading. 
		oAccumRegFeedback : out STD_LOGIC_vector(63 downto 0); -- Basically tag.
 
		iAccumMsg         : in STD_LOGIC_VECTOR(0 to n1 - 1);
		iAccumClk         : in STD_LOGIC;
		iAccumReset       : in STD_LOGIC
	);
end accumulator;

architecture Behavioral of accumulator is
	----------------------------------------------------------------------------------
 
	-- Define the two registers: LFSR & NFSR (You can't use the same signal for input end Behavioral;
	signal AccumReg       : STD_LOGIC_vector(63 downto 0); -- Current value 
	signal AccumNext      : STD_LOGIC_vector(63 downto 0); -- Next value 
	signal AccumShiftReg  : STD_LOGIC_vector(63 downto 0); -- Current value 
	signal AccumShiftNext : STD_LOGIC_vector(63 downto 0); -- Next value

	-- Since the tag is defined as ti = a^i_L+1, 0 <= i <= 31.
	-- It's better if the shift and accum are encoded that way. Which is why downto is used instead of to.
	--constant n1 : integer := 32; -- Accum parallellization. Supports up to 64
	--constant n2 : integer := n1*2; -- real parallelization. 
 
	----------------------------------------------------------------------------------
begin
	----------------------------------------------------------------------------------
	seq : process (iAccumClk, iAccumReset)
	begin
		if (iAccumReset = '1') then
			AccumReg      <= (others => '0');
			AccumShiftReg <= (others => '0');
		elsif (rising_edge(iAccumClk)) then
			AccumReg      <= AccumNext;
			AccumShiftReg <= AccumShiftNext;
		end if;
	end process; 

	----------------------------------------------------------------------------------

	comb : process (iAccumStart, iAccumY, 
		iAccumReset, AccumReg, AccumShiftReg, 
		iAccumMsg)
		variable AccumRegNewval    : STD_LOGIC_VECTOR(63 downto 0); -- New generated values for accum. 
		variable AccumShiftRegWire : STD_LOGIC_VECTOR(63 + (n1 - 1) downto 0); -- Wire for ShiftReg | n1-1 YAccum bits, that are required in accumlogic.
	begin
		AccumShiftRegWire(63 + (n1 - 1) downto n1 - 1) := AccumShiftReg; -- Rest n1-2.
		if (n1 > 1) then -- Needs to used the YAccum value in updating.
 
			AccumShiftRegWire := AccumShiftReg & iAccumY(0 to n1 - 2);
			-- AccumShiftRegWire(n1-2 downto 0) := iAccumY(n1-1 downto 1); -- Only n1-1 values are of the yAccum is required for the wire
 
		else
			AccumShiftRegWire := AccumShiftReg; --
		end if;
 
		for k in 0 to 63 loop
			AccumRegNewval(k) := AccumReg(k);
			for a in 0 to n1 - 1 loop -- Accum logic for the parallellization.
				AccumRegNewval(k) := AccumRegNewval(k) xor (iAccumMsg(n1 - 1 - a) and AccumShiftRegWire(a + k)); -- 
			end loop;
 
		end loop;
		--iAccumMsg
 
		-- It's mentioned in the paper that ti = a^i_l+1, 0 <= i <= 31. Which means we need to reverse the bits for the output.
		AccumNext         <= AccumRegNewval;
		oAccumRegFeedback <= AccumReg; 
		if (iAccumStart = '1') then -- Normal mode n/2 shift.
			AccumShiftNext <= AccumShiftReg(63 - n1 downto 0) & iAccumY(0 to (n1 - 1)); -- Does accumulation with n2/2 bits
 
		else -- Loading. n shift
			if (n2 = 64) then
				AccumShiftNext <= iAccumY; -- Loads all values directly into the reg.
 
			elsif (n2 = 1) then
				AccumShiftNext <= AccumShiftReg; -- paused.
 
			else
				AccumShiftNext <= AccumShiftReg(63 - n2 downto 0) & iAccumY(0 to (n2 - 1)); -- Loads all the Y values sent in. n2 bits.
 
			end if;
		end if;
 
	end process;
	----------------------------------------------------------------------------------
end behavioral;