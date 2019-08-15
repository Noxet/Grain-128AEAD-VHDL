library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

----------------------------------------------------------------------------------

entity grainTop is
	generic (
		n         : integer := 64; -- Parallelization level. When using the testbench ignore these values, These are to be set when running synthesis without the testbench
		ndiv2     : integer := 32; -- For non-parallelized version, set this to one, otherwise n/2.
		g         : integer := 0; -- 1 if Galois transform, else 0. If using with testbench you only need to change those values.
		yt        : integer := 0; -- 1 if using Y-transform, else 0
		ctype     : integer := 1; -- 1 for optimized controller, 0 for standard.
		clkdivnum : integer := 2; -- clkdivnum * n = 128 for best result
		ia        : integer := 1 -- 1 for authentication isolation, else 0.
	);
	port (
		oGraintopY           : out STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Key stream out. 
		iGraintopIv          : in STD_LOGIC_VECTOR(0 to n - 1); -- IV in.
		iGraintopKey         : in STD_LOGIC_vector(0 to n - 1); -- Key in
		iGraintopEnable      : in STD_LOGIC; -- Start
		iGraintopReset       : in STD_LOGIC;
		iGraintopClk         : in STD_LOGIC;
		oGraintopYFlag       : out STD_LOGIC; -- When keystream available.
		oGraintopTag         : out STD_LOGIC_VECTOR(63 downto 0); -- The tag if using authentication.
		iGraintopMsg         : in STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Message
		iGraintopCryptMode   : STD_LOGIC; -- 1 = decryption. 0 = Encryption
	iGraintopCryptEnable : STD_LOGIC); -- Enable/disable encryption 
 
end grainTop;

----------------------------------------------------------------------------------

architecture structural of grainTop is

	-----------------------------CREATE COMPONENTS-----------------------------------------------------
	component clock_div is
		generic (
			ctype     : integer;
			clkdivnum : integer
		);
 
		port (
			clk    : in STD_LOGIC;
			reset  : in STD_LOGIC;
			clkdiv : out STD_LOGIC 
		);
	end component;

	component authPipeline is
		generic (
			n     : integer;
			ndiv2 : integer;
		ia    : integer); -- Isolation or not
 
		port (
			iAuthPipelineMsgIn         : in STD_LOGIC_VECTOR (0 to (ndiv2) - 1);
			oAuthPipelineMsgReg        : out STD_LOGIC_VECTOR (0 to (ndiv2) - 1);
			iAuthPipelineYAccum        : in STD_LOGIC_VECTOR (0 to n - 1);
			oAuthPipelineYAccumReg     : out STD_LOGIC_VECTOR (0 to n - 1);
			iAuthPipelineAccumStart    : in STD_LOGIC;
			oAuthPipelineAccumStartReg : out STD_LOGIC;
			iAuthPipelineClk           : in STD_LOGIC;
			iAuthPipelineReset         : in STD_LOGIC 
		);
	end component;
	component controller is
		generic (
			n         : integer;
			ndiv2     : integer;
			ctype     : integer;
			clkdivnum : integer
		);
 
		port (
			iControllerEnable      : in STD_LOGIC; -- Enable signal from top. Paused if zero. 
			oControllerYFlag       : out STD_LOGIC; -- Flag used for testbench to know when to send in messages and get the output. 
			oControllerYEnable     : out STD_LOGIC; -- If y is feedback it's one.
			oControllerMsgNewval   : out STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Input to accumlogic from controlle
			iControllerMsgIn       : in STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Input to controller from Top. 
			oControllerAccumStart  : out STD_LOGIC; -- Decides whether or not accum should be used or not.
			oControllerGrainStart  : out STD_LOGIC; -- For controlling if the cipher is running.
			oControllerFP1         : out STD_LOGIC; -- Sending out if we should do FP1 
			iControllerYFeedback   : in STD_LOGIC_VECTOR(0 to n - 1); -- Get the Y values for outputting.
			oControllerYAccum      : out STD_LOGIC_VECTOR(0 to n - 1); -- Y output going to accum
			oControllerYOut        : out STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Y output going to out from the design 
			iControllerCryptMode   : STD_LOGIC; -- 1 = decryption. 0 = Encryption
			iControllerCryptEnable : STD_LOGIC; -- 1 = Enable, 0 = disable encryption in current clock 
			iControllerReset       : in STD_LOGIC; 
			iControllerClk         : in STD_LOGIC; -- For the counter register so it shifts 1 every 32 clock cycles.
		iControllerClk2        : in STD_LOGIC); -- For the counter register so it shifts 1 every 32 clock cycles.
	end component;
 
 

 
	component grain is
		generic (
			n  : integer;
			g  : integer; -- Galois if 1.
		yt : integer); -- Y transform / pipeline if 1
 
		port (
			iGrainStart   : in STD_LOGIC; -- When 1 the cipher runs. 
			iGrainFP1     : in STD_LOGIC; -- Active when doing FP1
			iGrainYEnable : in STD_LOGIC;
			iGrainIv      : in STD_LOGIC_VECTOR(0 to n - 1); 
			iGrainKey     : in STD_LOGIC_VECTOR(0 to n - 1); 
			oGrainY       : out STD_LOGIC_VECTOR(0 to n - 1); 
			iGrainReset   : in STD_LOGIC; 
			iGrainClk     : in STD_LOGIC 
		);
	end component;
 
 
	component accumulator is
		generic (
			n1 : integer; -- Parallellization/unrolling for accumulator. (half of the grain)
		n2 : integer); -- Parallellization/unrolling for grain. n1*2

		port (
			iAccumStart       : in STD_LOGIC;
			iAccumY           : in STD_LOGIC_VECTOR(0 to n2 - 1); -- Send n2 bits. The last half only used for loading. 
			oAccumRegFeedback : out STD_LOGIC_vector(0 to 63); -- Basically tag.
			iAccumMsg         : in STD_LOGIC_VECTOR(0 to n1 - 1);
			iAccumClk         : in STD_LOGIC;
			iAccumReset       : in STD_LOGIC 
		);
	end component;
	----------------------------------------------------------------------------------

	-- Define the signals 

	signal graintopLfsrFeedback          : STD_LOGIC_vector(0 to 127); -- Output from grain's LFSR going to F's input
	signal graintopLfsrIn                : STD_LOGIC_VECTOR(0 to n - 1); -- Input for grain's LFSR coming from controller (either Iv or LfsrIn, depending on state)
	signal graintopLfsrNewval            : STD_LOGIC_VECTOR(0 to n - 1); -- Output coming from F going to controller input

	signal graintopNfsrFeedback          : STD_LOGIC_vector(0 to 127); -- Output from NFSR going to G's input
	signal graintopNfsrIn                : STD_LOGIC_VECTOR(0 to n - 1); -- Input for grain's NFSR from controller. (either key or NfsrIn, depending on state)
	signal graintopNfsrNewval            : STD_LOGIC_VECTOR(0 to n - 1); -- Output coming from G going to controller input
	signal graintopYFeedback             : STD_LOGIC_VECTOR(0 to n - 1); -- Input to F and G containing Y, Used during INIT STAGE.
	signal graintopYEnable               : STD_LOGIC; -- Input to F and G, is in init stage if 1 coming from controller.
	signal graintopYFlag                 : STD_LOGIC; -- Output from controller to notify when keystream is ready.
	signal graintopAccumlogicRegFeedback : STD_LOGIC_vector(63 downto 0); -- Output from accumulator containing the accum register values

	signal graintopMsgNewval             : STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Input to accumlogic from controller, (Will be MsgIn normally, but is modified during loading to save hardware)
	signal graintopAccumStart            : STD_LOGIC; -- (Decides whether or not accum should be used or not. Will be Enable or 0 when y bit is keystream)
	signal grainTopGrainStart            : STD_LOGIC; -- Controls if the grain runs. Is automatically stopped during accum
	signal grainTopFP1                   : STD_LOGIC; -- Controls if the grain runs. Is automatically stopped during accum 
 
	signal grainTopYAccum                : STD_LOGIC_VECTOR(0 to n - 1); -- Output Y that goes to accum. When it's turned on.
	signal grainTopYOut                  : STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Output Y that goes to �ut every second bit

	signal grainTopMsgReg                : STD_LOGIC_VECTOR(0 to (ndiv2) - 1); -- Pipeline auth stage to sepearate them
	signal grainTopYAccumReg             : STD_LOGIC_VECTOR(0 to n - 1);
	signal grainTopAccumStartReg         : STD_LOGIC;

	signal designClk                     : STD_LOGIC;
	----------------------------------------------------------------------------------

begin
	clockdivInst : clock_div
        generic map(
            ctype     => ctype, 
            clkdivnum => clkdivnum -- How much clock division. Put to 1 to disable.
        )

        port map(
            clk    => iGraintopClk, 
            reset  => iGraintopReset, 
            clkdiv => designClk 
        );
 
    grainInst : grain
        generic map(
            n  => n, 
            g  => g, 
            yt => yt -- Y transform / pipeline if 1
        )

        port map(
            iGrainStart   => grainTopGrainStart, -- When 1 the cipher runs. 
            iGrainFP1     => grainTopFP1, -- Active when doing FP1
            iGrainYEnable => grainTopYEnable, 
            iGrainIv      => iGrainTopIv, 
            iGrainKey     => iGrainTopKey, 
            oGrainY       => grainTopYFeedback, 
            iGrainReset   => iGraintopReset, 
            iGrainClk     => iGraintopClk 
        ); 
 
 
 
 
    contInst : controller
        generic map(
            n         => n, -- Parallellization/unrolling for accumulator. (half of the grain)
            ndiv2     => ndiv2, 
            ctype     => ctype, 
            clkdivnum => clkdivnum -- How much clock division. Put to 1 to disable.
        ) 
        port map(
            iControllerEnable      => iGraintopEnable, -- Enable signal from top. Paused if zero. 
            oControllerYFlag       => graintopYFlag, -- If keystream is available.
            oControllerYEnable     => graintopYEnable, -- Input to F and G, is in init stage if 1. coming from controller.
            oControllerMsgNewval   => graintopMsgNewval, -- Input to accumlogic from controller, (Will be MsgIn normally, but is modified during loading to save hardware)
            iControllerMsgIn       => iGraintopMsg, -- Input to controller from Top.
            oControllerAccumStart  => graintopAccumStart, -- (Decides whether or not accum should be used or not. Will be Enable or 0 when y bit is keystream)
            oControllerGrainStart  => grainTopGrainStart, -- Controls if the grain runs. Is automatically stopped during accum
            oControllerFP1         => grainTopFP1, -- Controls if the grain runs. Is automatically stopped during accum
            iControllerYFeedback   => grainTopYFeedback, -- Get the Y values used for accum
            oControllerYAccum      => grainTopYAccum, -- Sends y values to accumulator
            oControllerYOut        => grainTopYOut, -- Y values sent out (keystream. 
            iControllerCryptMode   => iGraintopCryptMode, -- 1 = decryption. 0 = Encryption
            iControllerCryptEnable => iGraintopCryptEnable, -- Enable/disable encryption 
            iControllerReset       => iGraintopReset, 
            iControllerClk         => designClk, 
            iControllerClk2        => iGraintopClk -- For 1 para. 
        ); 
 

 
 
    accumulatorInst : accumulator
        generic map(
            n1 => ndiv2, -- Parallellization/unrolling for accumulator. (half of the grain)
            n2 => n -- Parallellization/unrolling for grain. n1*2
        ) 
        port map(
            iAccumY           => graintopYAccumReg, -- Either first 15 or last 32 bits of Y (during loading) or every second bit
            iAccumReset       => iGraintopReset, 
            iAccumClk         => iGraintopClk, 
            iAccumStart       => graintopAccumStartReg, 
            oAccumRegFeedback => graintopAccumlogicRegFeedback, 

            iAccumMsg         => grainTopMsgReg
        );

    AuthPipeInst : authPipeline
        generic map(
            n     => n, 
            ndiv2 => ndiv2, 
            ia    => ia
        )
        port map(
            iAuthPipelineMsgIn         => graintopMsgNewval, 
            oAuthPipelineMsgReg        => grainTopMsgReg, 
            iAuthPipelineYAccum        => grainTopYAccum, 
            oAuthPipelineYAccumReg     => grainTopYAccumReg, 
            iAuthPipelineAccumStart    => graintopAccumStart, 
            oAuthPipelineAccumStartReg => grainTopAccumStartReg, 
            iAuthPipelineClk           => iGraintopClk, 
            iAuthPipelineReset         => iGraintopReset
        );

    oGraintopY     <= grainTopYOut; -- keystream.
    oGraintopYFlag <= graintopYFlag;
    oGraintopTag   <= graintopAccumlogicRegFeedback; -- TagFlag will be high when we got the tag.
    ----------------------------------------------------------------------------------

end structural;