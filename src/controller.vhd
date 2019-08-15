library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.NUMERIC_STD.all;

use IEEE.math_real.all;

---------------------------------------------------------------------------------
entity controller is
	generic (
		n         : integer;--;
		ndiv2     : integer;
		ctype     : integer;
		clkdivnum : integer -- How much clock division.

 
		--b1 : INTEGER -- How many bits you wanna load.
	);
	port (
		iControllerEnable      : in std_logic; -- Enable signal from top. Paused if zero. 
 
		oControllerYFlag       : out std_logic; -- If keystream is available just goes to output 
		oControllerYEnable     : out std_logic; -- Input to F and G, is in init stage if 1. coming from contr
		oControllerMsgNewval   : out std_logic_vector(0 to ndiv2 - 1); -- Input to accumlogic from controlle
		iControllerMsgIn       : in std_logic_vector(0 to ndiv2 - 1); -- Input to controller from Top. 
 
		oControllerAccumStart  : out std_logic; -- (Decides whether or not accum should be used or not. Will be
		oControllerGrainStart  : out std_logic; -- Controls if the grain runs. Is automatically stopped during
		oControllerFP1         : out std_logic; -- Sending out if we should do FP1 
		iControllerYFeedback   : in std_logic_vector(0 to n - 1); -- Get the Y values for outputting from the
		oControllerYAccum      : out std_logic_vector(0 to n - 1); -- Output Y that goes to accum. When it's
		oControllerYOut        : out std_logic_vector(0 to ndiv2 - 1); 

		iControllerCryptMode   : std_logic; -- 1 = decryption. 0 = Encryption
		iControllerCryptEnable : std_logic; -- Enable/disable encryption 
		iControllerReset       : in std_logic; 
		iControllerClk         : in std_logic; -- For the counter register so it shifts 1 every 32 clock cycles.
		iControllerClk2        : in std_logic -- Used in 1 para modified/new controller.
	);

end controller;

----------------------------------------------------------------------------------

architecture Behavioral of controller is
	type stateType is (RESET, LOAD, INIT, ACCUMLOAD, NORMAL);
	signal state, nextState : stateType;
 
	-- Key/iv must be n or else FP1 doesn't work.
	constant ees                                         : integer := 1;
	constant LoadClock                                   : integer := (128/n); -- Clock cycles for accumulator loading and also grain loading.
	constant InitClock                                   : integer := (256/n); -- For initilization.
	constant TotalClock                                  : integer := LoadClock * 2 + InitClock; -- Total amount of clock cycles.
	constant CounterBits                                 : integer := integer(ceil(log2(real(InitClock)))); -- Get the highest counter needed.
 
	constant Index1                                      : integer := (LoadClock/(clkdivnum)) - 1; -- Register that is 1 when init (3
	constant Index2                                      : integer := ((LoadClock + InitClock)/clkdivnum) - 1; -- Register that is 1 when accumload(11. 2
	constant Index3                                      : integer := ((2 * LoadClock + InitClock)/clkdivnum) - 1; -- When all finished. (15
 
	signal controllerCounterReg, controllerCounterNext   : unsigned(0 to Index3); -- Different counter size depending on the controller
	signal controllerCounterReg2, controllerCounterNext2 : unsigned(0 to (CounterBits - 1)); -- Different counter size depending on the controller

	signal grainStartReg, grainStartNext                 : std_logic;
	signal FP1Reg, FP1Next                               : std_logic;
	signal YEnableReg, YEnableNext                       : std_logic;
 
	-- For 1 para only
	signal modeReg, modeNext : std_logic; -- 1 = doing accum, 0 = keystream for the 1 para version which cant do both at the same time.
	signal prevReg, prevNext : std_logic; -- Used to store the keystream xor ciphertext (ciphertext will be message then), which will be used during decrypt.

	----------------------------------------------------------------------------------
begin
	----------------------------------------------------------------------------------
 
	seq : process (iControllerClk, iControllerReset)
	begin
		if (iControllerReset = '1') then
			state                 <= RESET;
			controllerCounterReg2 <= (others => '0');
			controllerCounterReg  <= (others => '0');
			grainStartReg         <= '0';
			FP1Reg                <= '0';
			YEnableReg            <= '0';
		elsif (rising_edge(iControllerClk)) then
			state                 <= nextState;
			controllerCounterReg  <= controllerCounterNext;
			controllerCounterReg2 <= controllerCounterNext2;
			grainStartReg         <= grainStartNext;
			FP1Reg                <= FP1Next;
			YEnableReg            <= YEnableNext;

		end if;
	end process; 

	seq2 : process (iControllerClk2, iControllerReset) -- 1 para with modified controller requires the normal clock to run the other two registers.
	begin
		if (n = 1) then
			if (iControllerReset = '1') then
				modeReg <= '0';
				prevReg <= '0';
			elsif (rising_edge(iControllerClk2)) then
				modeReg <= modeNext;
				prevReg <= prevNext;
			end if;
		end if;
	end process;
	---------------------------------------------------------------------------------- 
	comb : process (state, iControllerMsgIn, FP1Reg, grainStartReg, YEnableReg, controllerCounterReg, iControllerCryptMode,
		    iControllerCryptEnable, controllerCounterReg2, iControllerEnable, iControllerYFeedback, modeReg, prevReg) -- iControllerMsgFlag
		variable yAccumWire : std_logic_vector(0 to n - 1); -- Wire for
		variable yOutWire   : std_logic_vector(0 to ndiv2 - 1);
	begin
		----------------------------------- 

		-- Code used in both controllers.
		yAccumWire := (others => '0');
		yOutWire   := (others => '0');
		if (n > 1) then
			for k in 0 to ndiv2 - 1 loop
				yAccumWire(k) := iControllerYFeedback(k * 2 + 1);
				yOutWire(k)   := iControllerYFeedback(k * 2);
			end loop;
		end if;

		if (ctype = 0) then
			grainStartNext         <= grainStartReg;
			FP1Next                <= FP1Reg;
			YEnableNext            <= YEnableReg;
			oControllerGrainStart  <= grainStartReg;
			oControllerFP1         <= FP1Reg;
			oControllerYEnable     <= YEnableReg;

			oControllerYFlag       <= '0'; -- If keystream is available just goes to output

			nextState              <= state;
			controllerCounterNext2 <= controllerCounterReg2;
			oControllerMsgNewval   <= (others => '0');
			oControllerAccumStart  <= '0'; -- Loading.

			oControllerYAccum      <= (others => '0');

			oControllerYOut        <= yOutWire;
 
			modeNext               <= modeReg;
			prevNext               <= prevReg;

			----------------------------------- 
			case (state) is
 
				when RESET => 
					controllerCounterNext2 <= (others => '0');

					grainStartNext         <= '0';
					FP1Next                <= '0';
					YEnableNext            <= '0';

					if (iControllerEnable = '1') then
						nextState <= LOAD;

                    end if;

					----------------------------------- 
				when LOAD => 

					controllerCounterNext2 <= controllerCounterReg2 + 1;
					if (controllerCounterReg2 = LoadClock - 2) then -- All loading clock cycles.
						nextState              <= INIT;
						grainStartNext         <= '1';
						YEnableNext            <= '1';
						controllerCounterNext2 <= (others => '0');
                    end if;

					----------------------------------- 
				when INIT => 

					controllerCounterNext2 <= controllerCounterReg2 + 1;
					if (controllerCounterReg2 = InitClock - 1) then
						nextState              <= ACCUMLOAD;
						FP1Next                <= '1';
						YEnableNext            <= '0';
						controllerCounterNext2 <= (others => '0');
					end if;

					----------------------------------- 
				when ACCUMLOAD => 
					-- Run for 32 clock with message sent into logic = 0.
					-- Then we set message to one to put into accum
					-- Then message zero again for 32 cloc => loading of accum & shift reg.

					oControllerYFlag       <= '1';
					oControllerMsgNewval   <= iControllerMsgIn;
 
					controllerCounterNext2 <= controllerCounterReg2 + 1;

					if (n = 1) then
						oControllerAccumStart <= '1'; -- 1 para has paused or no pause. 1 means we shift in 1 value.
					else
						oControllerAccumStart <= '0'; -- n values shifted in during loading when accum 0.
					end if;
					oControllerYAccum <= iControllerYFeedback; -- Loads all 32 values.
					if (controllerCounterReg2 = LoadClock/2) then -- After half we put message to 1 to just load the shift register values into the accumulator. 

					end if;
 
					if (controllerCounterReg2 = LoadClock - 1) then -- All bits are shifted into the shift register. 
						nextState              <= NORMAL;
						FP1Next                <= '0';
						controllerCounterNext2 <= (others => '0');
					end if;

					----------------------------------- 
				when NORMAL => 
 
					oControllerYFlag <= '1'; -- If keystream is available just goes to output
 
 
					if (n = 1) then
						modeNext              <= not modeReg; -- Every second clock cycle this occurs.
						oControllerAccumStart <= modeReg; -- Only active every second clock cycle.
						if (modeReg = '0') then -- Always send zero when everything is paused.
							yOutWire(0) := iControllerYFeedback(0); -- Keystream bit.
 
						else
							yAccumWire(0) := iControllerYFeedback(0); -- Mac bit.
						end if;
					else
 
						oControllerAccumStart <= '1'; --
					end if;
 
					if (n = 1) then
						if (iControllerCryptEnable = '0') then
 
							prevNext <= iControllerMsgIn(0); -- Needs to be the message when cryptenable is off.
							yOutWire := (others => '0'); -- No encryption/decryption in the current clock. YOut will be just 0 xor Message = message.
						else
							prevNext <= yOutWire(0) xor iControllerMsgIn(0); -- Will only be used when 1 para.
						end if;
 
					else
						if (iControllerCryptEnable = '0') then
 
 
							yOutWire := (others => '0');
						end if;
 
					end if;
 
					-- Encrypt and decrypt.
					if (iControllerCryptMode = '1') then -- Decryption.
						if (n = 1) then
							if (modeReg = '0') then
								oControllerMsgNewval(0) <= '0'; -- Message going to accum is 0 zero when accum is paused.
							else
								oControllerMsgNewval(0) <= prevReg;
							end if;
						else
							oControllerMsgNewval <= yOutWire xor iControllerMsgIn; -- mi = KeyStream xor ci (ciphertext send in)
						end if;
					else
						oControllerMsgNewval <= iControllerMsgIn;
 
					end if;
 
					-- Makes wires for the signals so that everything can be grouped together.
					oControllerYAccum <= yAccumWire; -- Ports the wires out of the design.
					oControllerYOut   <= yOutWire xor iControllerMsgIn;
					----------------------------------- 
 
				when others => 

			end case; -- Ends all the states.
		else -- Alternative controller.

			-- 1 para: Register for saving message. modereg as accumstart? Then YOut should zero when modereg is zero.
			controllerCounterNext(0 to Index3) <= iControllerEnable & controllerCounterReg(0 to Index3 - 1);
 
			oControllerYFlag                   <= controllerCounterReg(Index2); --AND (NOT controllerCounterReg2(511)); -- When 1 we are doing keystream generation otherwise doing accum. Always 1 during accumload. Note that in the other code we used a register value that was 0 when we did keystream.
			oControllerYEnable                 <= controllerCounterReg(Index1) and (not controllerCounterReg(Index2)); -- When loading is done and when init is not finished, we YEnable.
			oControllerGrainStart              <= controllerCounterReg(Index1);
			oControllerFP1                     <= controllerCounterReg(Index2) and (not controllerCounterReg(Index3));
 
			oControllerYOut                    <= (others => '0');
			oControllerYAccum                  <= (others => '0');
 
			modeNext                           <= modeReg;
			prevNext                           <= prevReg;
 
			oControllerAccumStart              <= '0'; -- Zero by default. 1 in normal state for all paras. 1 in accumload and then when accumulator is active in the normal state, for 1 para.
 
 
			-- Muxes for the output signal as well as the yaccum signal going to the accumulator.
			if (controllerCounterReg(Index3) = '1') then -- Normal state.
				if (n = 1) then -- If 1 para
					modeNext              <= ((not modeReg) and controllerCounterReg(Index3)); -- Changes value between 1 and 0 after we reach the normal state.
					oControllerAccumStart <= modeReg and controllerCounterReg(Index3);
					if (modeReg = '0') then -- Always send zero when everything is paused.
						yOutWire(0) := iControllerYFeedback(0); -- Keystream bit.
 
					else
						yAccumWire(0) := iControllerYFeedback(0); -- Mac bit.
					end if;
				else
					oControllerAccumStart <= controllerCounterReg(Index3); -- 1 when in normal.
				end if;

				if (iControllerCryptEnable = '0') then 
 
					yOutWire := (others => '0'); -- No encryption/decryption in the current clock.
				else
					oControllerYOut <= yOutWire; -- XOR iControllerMsgIn; Every second bit.
 
				end if;
 
				if (n = 1) then
					prevNext <= yOutWire(0) xor iControllerMsgIn(0); -- Used for decryption in 1 para to store the plaintext (message) needed for next clock.
				end if;
				oControllerYAccum <= yAccumWire; -- Every other second bit.
 
			elsif (controllerCounterReg(Index2) = '1') then -- In accumload.
				oControllerYAccum <= iControllerYFeedback;
				if (n = 1) then
					oControllerAccumStart <= '1'; -- 1 para needs accumload active
				end if;
			end if;
 
			if (controllerCounterReg(Index3) = '1') then -- Adding encryption/decryption.
				if (iControllerCryptMode = '1') then -- Decryption.
					if (n = 1) then --
						if (modeReg = '0') then
							oControllerMsgNewval(0) <= '0'; -- Message going to accum is 0 zero when accum is paused.
						else
							oControllerMsgNewval(0) <= prevReg; -- The message is the plaintext generated last clock.
						end if;
					else
						oControllerMsgNewval <= yOutWire xor iControllerMsgIn; -- mi = KeyStream xor ci (ciphertext send in)
					end if;
				else
					oControllerMsgNewval <= iControllerMsgIn;
				end if;

			else
				oControllerMsgNewVal <= iControllerMsgIn; -- Always just send in the message.
			end if;

		end if;
 
	end process;

end Behavioral;