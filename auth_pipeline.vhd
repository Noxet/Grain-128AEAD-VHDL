library IEEE;
use IEEE.std_logic_1164.all;

entity authPipeline is
	generic (
		n     : integer;
		ndiv2 : integer;
		ia    : integer -- Isolation or not
	);
	port (
		iAuthPipelineMsgIn         : in std_logic_vector (0 to ndiv2 - 1);
		oAuthPipelineMsgReg        : out std_logic_vector (0 to ndiv2 - 1);
		iAuthPipelineYAccum        : in std_logic_vector (0 to n - 1);
		oAuthPipelineYAccumReg     : out std_logic_vector (0 to n - 1);
		iAuthPipelineAccumStart    : in std_logic;
		oAuthPipelineAccumStartReg : out std_logic;
		iAuthPipelineClk           : in std_logic;
		iAuthPipelineReset         : in std_logic
	);
end authPipeline;

architecture Behavioral of authPipeline is

	signal MsgReg, MsgNext, MsgReg2, MsgNext2         : std_logic_vector(0 to ndiv2 - 1); -- Current value 
	signal YAccumReg, YAccumNext                      : std_logic_vector(0 to n - 1); -- Current value 
	signal startReg, startNext, startReg2, startNext2 : std_logic;
	----------------------------------------------------------------------------------
begin
	----------------------------------------------------------------------------------
	seq : process (iAuthPipelineClk, iAuthPipelineReset)
	begin
		if (iAuthPipelineReset = '1') then
			MsgReg    <= (others => '0');
			YAccumReg <= (others => '0');
			startReg  <= '0';
			MsgReg2   <= (others => '0');
			startReg2 <= '0';
		elsif (rising_edge(iAuthPipelineClk)) then
			YAccumReg <= YAccumNext;
			MsgReg    <= MsgNext;
			startReg  <= startNext;
			MsgReg2   <= MsgNext2;
			startReg2 <= startNext2;
		end if;
	end process; 

	----------------------------------------------------------------------------------
	comb : process (iAuthPipelineMsgIn, iAuthPipelineYAccum, MsgReg, MsgReg2, YAccumReg, startReg, startReg2, iAuthPipelineAccumStart)
	begin
		YAccumNext <= iAuthPipelineYAccum;
		MsgNext    <= iAuthPipelineMsgIn;
		startNext  <= iAuthPipelineAccumStart;
		MsgNext2   <= MsgReg;
		startNext2 <= startReg;
 
		if (ia = 1) then
			oAuthPipelineMsgReg        <= MsgReg;
			oAuthPipelineYAccumReg     <= YAccumReg;
			oAuthPipelineAccumStartReg <= startReg;
 
		else -- No isolation.
			oAuthPipelineMsgReg        <= iAuthPipelineMsgIn; 
			oAuthPipelineYAccumReg     <= iAuthPipelineYAccum; 
			oAuthPipelineAccumStartReg <= iAuthPipelineAccumStart;
		end if;

	end process;
	----------------------------------------------------------------------------------
end Behavioral;