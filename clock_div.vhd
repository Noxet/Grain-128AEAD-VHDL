library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.math_real.all;

entity clock_div is
	generic (
		ctype     : integer;
		clkdivnum : integer -- How much clock division. Put to 1 to disable.
	);
	port (
		clk    : in STD_LOGIC;
		reset  : in STD_LOGIC;
		clkdiv : out STD_LOGIC
	);
end clock_div;

architecture Behavioral of clock_div is

	constant CounterBits          : integer := integer(ceil(log2(real(clkdivnum)))); -- Get the highest counter needed.
    signal shiftReg, shiftRegNext : unsigned(0 to CounterBits - 1); -- 31 STD_LOGIC_VECTOR. For counting the clock cycles in each stage.

begin
	seq : process (clk, reset)
	begin
		if (ctype = 1) then
			if (reset = '1') then
				shiftReg    <= (others => '0');
				shiftReg(0) <= '1'; -- When using original for new one.
			elsif (rising_edge(clk)) then
				shiftReg <= shiftRegNext;
			end if;
		end if;
	end process;
	comb : process (shiftReg, clk)
	begin
		if (ctype = 1) then
			shiftRegNext <= shiftReg + 1;
			clkdiv       <= shiftReg(0);
		else
			clkdiv <= clk; -- Just output normal clock otherwise.
		end if;

	end process;

end Behavioral;