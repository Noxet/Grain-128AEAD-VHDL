library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.NUMERIC_STD.all;

----------------------------------------------------------------------------------

entity grain is
	generic (
		n  : integer; -- Parallelization level
		g  : integer; -- Galois if 1.
		yt : integer -- Y transform / pipeline if 1
	);
	port (
		iGrainStart   : in std_logic; -- When 1 the cipher runs.
		iGrainFP1     : in std_logic; -- Active when doing FP1
		iGrainYEnable : in std_logic;
		iGrainIv      : in std_logic_vector(0 to n - 1);
		iGrainKey     : in std_logic_vector(0 to n - 1);
		oGrainY       : out std_logic_vector(0 to n - 1);
		iGrainReset   : in std_logic;
		iGrainClk     : in std_logic
	);
end grain;

----------------------------------------------------------------------------------

architecture behavioral of grain is
	----------------------------------------------------------------------------------
	-- Define the two registers: LFSR & NFSR (You can't use the same signal for input & output in hardware)
	signal grainLfsrReg                : std_logic_vector(0 to 127); -- Current value
	signal grainLfsrNext               : std_logic_vector(0 to 127); -- Next value
	signal grainNfsrReg                : std_logic_vector(0 to 127); -- Current value
	signal grainNfsrNext               : std_logic_vector(0 to 127); -- Next value
	signal enableReg, enableNext       : std_logic;
	signal enableReg2, enableNext2     : std_logic;

	signal PipelineReg, PipelineNext   : std_logic_vector(0 to n - 1); -- When using Y transform you need these registers for pipelinning.
	signal PipelineReg2, PipelineNext2 : std_logic_vector(0 to n - 1); -- If they are unused they are removed automatically in synthesis script at least in synposis.
	signal PipelineReg3, PipelineNext3 : std_logic_vector(0 to n - 1); -- If they are unused they are removed automatically in synthesis script at least in synposis.
	-- (-32, 0, 0) (-16, 0, 0) (-32, 0, 32), (-32, 0, 16) (-32, 0, 15) (-31, 0, 15) (-31, 0, 16) (-16, 0, 16)
	constant tconst  : integer := 0; -- Just using this when trying to find a bug with the transformations.
	constant tconst2 : integer := 32; -- For Y transform
	constant tconst3 : integer := 0; -- For the first values in F and G (the shift value)
	----------------------------------------------------------------------------------

begin
	----------------------------------------------------------------------------------
	seq : process (iGrainClk, iGrainReset)
	begin
		if (iGrainReset = '1') then
			grainNfsrReg <= (others => '0');
			grainLfsrReg <= (others => '0');
			PipelineReg  <= (others => '0');
			PipelineReg2 <= (others => '0');
			PipelineReg3 <= (others => '0');
			enableReg    <= '0';
			enableReg2   <= '0';

		elsif (rising_edge(iGrainClk)) then
			grainNfsrReg <= grainNfsrNext;
			grainLfsrReg <= grainLfsrNext;
			PipelineReg  <= PipelineNext;
			PipelineReg2 <= PipelineNext2;
			PipelineReg3 <= PipelineNext3;
			enableReg    <= enableNext;
			enableReg2   <= enableNext2;
		end if;
	end process;

	----------------------------------------------------------------------------------
	comb : process (iGrainReset, grainLfsrReg, PipelineReg, PipelineReg2, PipelineReg2, enableReg, enableReg2, 
		grainNfsrReg, iGrainIv, iGrainKey, iGrainYEnable, iGrainstart, iGrainFP1)

		variable fWire  : std_logic_vector(0 to 127 + n + g * ( - n + 32)); -- The last values after 127 are the new values generated for the NFSR and LFSR.
		variable gWire  : std_logic_vector(0 to 127 + n + g * ( - n + 32)); -- For galois we need a little more variable space, max will be 32.

		variable yWire  : std_logic_vector(0 to n - 1);
		variable yWire2 : std_logic_vector(0 to n - 1);
		variable yWire3 : std_logic_vector(0 to n - 1); -- Allowing for 3 pipelines.
	begin
		fWire(0 to 127) := grainLfsrReg; -- We store the last values at
		gWire(0 to 127) := grainNfsrReg;
		grainLfsrNext <= grainLfsrReg(n to 127) & iGrainIv; -- Shift to the left.
		grainNfsrNext <= grainNfsrReg(n to 127) & iGrainKey; -- Default values. when loading

		enableNext    <= iGrainYEnable;
		enableNext2   <= enableReg;

		-- For loop starts
		for k in 0 to n - 1 loop -- Generate 1 bit at a time for G, f and Y

			if (g = 0) then -- NOT USING GALOIS
				fWire(128 + k) := fWire(k) xor fWire(k + 7) xor fWire(k + 38) xor fWire(70 + k) xor fWire(81 + k) xor fWire(96 + k);

				gWire(128 + k) := gWire(k) xor fWire(k) xor gWire(k + 26) xor gWire(k + 56) xor gWire(k + 91) xor gWire(k + 96) xor
                    (gWire(k + 3) and gWire(k + 67)) xor (gWire(k + 11) and gWire(k + 13)) xor (gWire(k + 17) and gWire(k + 18)) xor
                    (gWire(k + 27) and gWire(k + 59)) xor (gWire(k + 40) and gWire(k + 48)) xor (gWire(k + 61) and gWire(k + 65)) xor
                    (gWire(k + 68) and gWire(k + 84)) xor (gWire(k + 88) and gWire(k + 92) and gWire(k + 93) and gWire(k + 95)) xor
                    (gWire(k + 22) and gWire(k + 24) and gWire(k + 25)) xor (gWire(k + 70) and gWire(k + 78) and gWire(k + 82));
			else -- USING GALOIS
				if (n = 16) then -- 16 PARA
					fWire(128 + k) := fWire(k) xor fWire(k + 7) xor fWire(k + 38) xor fWire(k + 70);--f127 = s0 ? s7 ? s38 ? s70

					--fWire(k+112 + tconst3) xor
					fWire(128 + k + 16) := fWire(k + 112 + tconst3) xor fWire(k + 65 + tconst) xor fWire(k + 80 + tconst);--f111 = s112 ? s65 ? s80
					gWire(128 + k)      := fWire(k) xor gWire(k) xor gWire(k + 56) xor (gWire(k + 3) and gWire(k + 67))
					    xor (gWire(k + 11) and gWire(k + 13)) xor (gWire(k + 40) and gWire(k + 48)) xor
					    (gWire(k + 22) and gWire(k + 24) and gWire(k + 25)) xor (gWire(k + 70) and gWire(k + 78) and gWire(k + 82));

                    gWire(128 + k + 16) := gWire(k + 112 + tconst3) xor gWire(k + 10 + tconst) xor gWire(k + 75 + tconst)
                        xor gWire(k + 80 + tconst) xor (gWire(k + 1 + tconst) and gWire(k + 2 + tconst))
                        xor (gWire(k + 11 + tconst) and gWire(k + 43 + tconst)) xor (gWire(k + 45 + tconst)
                        and gWire(k + 49 + tconst)) xor (gWire(k + 72 + tconst) and gWire(k + 76 + tconst) 
                        and gWire(k + 77 + tconst) and gWire(k + 79 + tconst)) xor (gWire(k + 68 + tconst) and gWire(k + 52 + tconst));

				elsif (n = 8) then
					fWire(128 + k)      := fWire(k + 0) xor fWire(k + 7) xor fWire(k + 38);
					fWire(128 + k + 8)  := fWire(k + 120) xor fWire(k + 62);
					fWire(128 + k + 16) := fWire(k + 112) xor fWire(k + 65);
					fWire(128 + k + 24) := fWire(k + 104) xor fWire(k + 72);

					gWire(128 + k)      := fWire(k + 0) xor gWire(k + 0) xor (gWire(k + 3) and gWire(k + 67)) xor (gWire(k + 88) and gWire(k + 92) and gWire(k + 93) and gWire(k + 95));
					gWire(128 + k + 8)  := gWire(k + 120) xor (gWire(k + 9) and gWire(k + 10)) xor (gWire(k + 3) and gWire(k + 5)) xor (gWire(k + 32) and gWire(k + 40)) xor (gWire(k + 60) and gWire(k + 76));
					gWire(128 + k + 16) := gWire(k + 112) xor gWire(k + 10) xor gWire(k + 40) xor (gWire(k + 11) and gWire(k + 43)) xor gWire(k + 75) xor (gWire(k + 6) and gWire(k + 8) and gWire(k + 9));
					gWire(128 + k + 24) := gWire(k + 104) xor gWire(k + 72) xor (gWire(k + 37) and gWire(k + 41)) xor (gWire(k + 46) and gWire(k + 54) and gWire(k + 58));

				elsif (n <= 4) then
					fWire(128 + k)      := fWire(k + 0) xor fWire(k + 7);
					fWire(128 + k + 4)  := fWire(k + 124) xor fWire(k + 34);
					fWire(128 + k + 8)  := fWire(k + 120) xor fWire(k + 62);
					fWire(128 + k + 12) := fWire(k + 116) xor fWire(k + 69);
					fWire(128 + k + 16) := fWire(k + 112) xor fWire(k + 80);

					if (n = 4) then
						gWire(128 + k)      := fWire(k + 0) xor gWire(k + 0) xor (gWire(k + 3) and gWire(k + 67));
						gWire(128 + k + 4)  := gWire(k + 124) xor gWire(k + 22) xor gWire(k + 52) xor (gWire(k + 23) and gWire(k + 55));
						gWire(128 + k + 8)  := gWire(k + 120) xor (gWire(k + 9) and gWire(k + 10)) xor (gWire(k + 3) and gWire(k + 5));
						gWire(128 + k + 12) := gWire(k + 116) xor (gWire(k + 70) and gWire(k + 66) and gWire(k + 58));
						gWire(128 + k + 16) := gWire(k + 112) xor (gWire(k + 6) and gWire(k + 8) and gWire(k + 9));
						gWire(128 + k + 20) := gWire(k + 108) xor (gWire(k + 68) and gWire(k + 72) and gWire(k + 73) and gWire(k + 75));
						gWire(128 + k + 24) := gWire(k + 104) xor gWire(k + 72) xor (gWire(k + 37) and gWire(k + 41));
						gWire(128 + k + 28) := gWire(k + 100) xor (gWire(k + 40) and gWire(k + 56)) xor gWire(k + 63) xor (gWire(k + 12) and gWire(k + 20));
					elsif (n = 2) then

						gWire(128 + k)     := gWire(k + 0) xor fWire(k + 0);
						gWire(128 + k + 2) := gWire(k + 126) xor (gWire(k + 1) and gWire(k + 65));
						gWire(128 + k + 4) := gWire(k + 124) xor (gWire(k + 57) and gWire(k + 61));
						gWire(128 + k + 6) := gWire(k + 122) xor (gWire(k + 5) and gWire(k + 7));
						gWire(128 + k + 8) := gWire(k + 120) xor (gWire(k + 9) and gWire(k + 10));
						-- g119 to g115, extra space here.
						gWire(128 + k + 12) := gWire(k + 116) xor (gWire(k + 15) and gWire(k + 47));
						gWire(128 + k + 14) := gWire(k + 114) xor gWire(k + 12);
						gWire(128 + k + 16) := gWire(k + 112) xor (gWire(k + 6) and gWire(k + 8) and gWire(k + 9));
						gWire(128 + k + 18) := gWire(k + 110) xor gWire(k + 73);
						gWire(128 + k + 20) := gWire(k + 108) xor (gWire(k + 62) and gWire(k + 58) and gWire(k + 50));
						gWire(128 + k + 22) := gWire(k + 106) xor (gWire(k + 18) and gWire(k + 26));
						gWire(128 + k + 24) := gWire(k + 104) xor gWire(k + 72);
						gWire(128 + k + 26) := gWire(k + 102) xor gWire(k + 30);
						gWire(128 + k + 28) := gWire(k + 100) xor (gWire(k + 40) and gWire(k + 56));
						gWire(128 + k + 30) := gWire(k + 98) xor (gWire(k + 58) and gWire(k + 62) and gWire(k + 63) and gWire(k + 65));
					end if;

				end if;

			end if; -- Done generating f and g for alla para versions
			-- Generating Y for all para versions + when and when not using y para.

			if (yt = 0) then -- NOT USING Y transform

				yWire(k) := (gWire(k + 12) and fWire(k + 8)) xor (fWire(k + 13) and fWire(k + 20)) xor
				(gWire(k + 95) and fWire(k + 42)) xor (fWire(k + 60) and fWire(k + 79)) xor
				(gWire(k + 12) and gWire(95 + k) and fWire(94 + k)) xor -- This is the h function (to the left and up)
				fWire(k + 93) xor gWire(k + 2) xor gWire(k + 15) xor gWire(k + 36) xor gWire(k + 45) xor
				gWire(k + 64) xor gWire(k + 73) xor gWire(k + 89);

			else -- USING y Transform.

				if (n <= 16) then
					yWire(k) := (gWire(k + 12) and fWire(k + 8)) xor (fWire(k + 13) and fWire(k + 20)) xor gWire(k + 15) xor
					    (gWire(k + 12) and gWire(k + 95) and fWire(k + 94)) xor gWire(k + 2) xor gWire(k + 64);
					yWire2(k) := (gWire(k + 79) and fWire(k + 26)) xor fWire(k + 77) xor gWire(k + 73) xor gWire(k + 57) xor
					    (fWire(k + 44) and fWire(k + 63)) xor gWire(k + 20) xor gWire(k + 29);
					    --(fWire(k + 44 + tconst2) and fWire(k + 63 + tconst2)) xor gWire(k + 20 + tconst2) xor gWire(k + 29 + tconst2);

					PipelineNext(k) <= yWire2(k);

					if (iGrainYEnable = '0') then -- Pipeline
						yWire(k) := yWire(k) xor PipelineReg(k);
					end if;
 
					gWire(128 + k + 16) := gWire(128 + k + 16) xor (yWire2(k) and enableReg);--iGrainYEnable);
					fWire(128 + k + 16) := fWire(128 + k + 16) xor (yWire2(k) and enableReg);
				end if;

			end if;

			gWire(128 + k) := gWire(128 + k) xor (yWire(k) and iGrainYEnable);
			fWire(128 + k) := fWire(128 + k) xor (iGrainKey(k) and iGrainFP1) xor (yWire(k) and iGrainYEnable); -- iGrainFP1 and iGrainYEnable will never be one at the same time.
 
			if (iGrainStart = '1') then -- Loading which value is shifted in
				grainLfsrNext(128 - n + k) <= fWire(128 + k); --xor (iGrainIv(k) AND (NOT iGrainStart));
				grainNfsrNext(128 - n + k) <= gWire(128 + k); -- xor (iGrainKey(k) AND (NOT iGrainStart))
 
				if (g = 0) then -- Not doing galois

				else
					if (n = 16) then -- 112 96
						grainLfsrNext(128 - n + k - 16) <= fWire(128 + k + 16); -- First feedback function goes here.
						grainNfsrNext(128 - n + k - 16) <= gWire(128 + k + 16);
					elsif (n = 8) then
						grainLfsrNext(128 - n + k - 8)  <= fWire(128 + k + 8);
						grainLfsrNext(128 - n + k - 16) <= fWire(128 + k + 16);
						grainLfsrNext(128 - n + k - 24) <= fWire(128 + k + 24);
						grainNfsrNext(128 - n + k - 8)  <= gWire(128 + k + 8);
						grainNfsrNext(128 - n + k - 16) <= gWire(128 + k + 16);
						grainNfsrNext(128 - n + k - 24) <= gWire(128 + k + 24);
					elsif (n <= 4) then
						grainLfsrNext(128 - n + k - 4)  <= fWire(128 + k + 4);
						grainLfsrNext(128 - n + k - 8)  <= fWire(128 + k + 8);
						grainLfsrNext(128 - n + k - 12) <= fWire(128 + k + 12);
						grainLfsrNext(128 - n + k - 16) <= fWire(128 + k + 16);
 
						if (n = 4) then
							grainNfsrNext(128 - n + k - 4)  <= gWire(128 + k + 4);
							grainNfsrNext(128 - n + k - 8)  <= gWire(128 + k + 8);
							grainNfsrNext(128 - n + k - 12) <= gWire(128 + k + 12);
							grainNfsrNext(128 - n + k - 16) <= gWire(128 + k + 16);
							grainNfsrNext(128 - n + k - 20) <= gWire(128 + k + 20);
							grainNfsrNext(128 - n + k - 24) <= gWire(128 + k + 24);
							grainNfsrNext(128 - n + k - 28) <= gWire(128 + k + 28);
						elsif (n = 2) then
							grainNfsrNext(128 - n + k - 2)  <= gWire(128 + k + 2);
							grainNfsrNext(128 - n + k - 4)  <= gWire(128 + k + 4);
							grainNfsrNext(128 - n + k - 6)  <= gWire(128 + k + 6);
							grainNfsrNext(128 - n + k - 8)  <= gWire(128 + k + 8);
							grainNfsrNext(128 - n + k - 12) <= gWire(128 + k + 12);
							grainNfsrNext(128 - n + k - 14) <= gWire(128 + k + 14);
							grainNfsrNext(128 - n + k - 16) <= gWire(128 + k + 16);
							grainNfsrNext(128 - n + k - 18) <= gWire(128 + k + 18);
							grainNfsrNext(128 - n + k - 20) <= gWire(128 + k + 20);
							grainNfsrNext(128 - n + k - 22) <= gWire(128 + k + 22);
							grainNfsrNext(128 - n + k - 24) <= gWire(128 + k + 24);
							grainNfsrNext(128 - n + k - 26) <= gWire(128 + k + 26);
							grainNfsrNext(128 - n + k - 28) <= gWire(128 + k + 28);
							grainNfsrNext(128 - n + k - 30) <= gWire(128 + k + 30);
						end if;

					end if;

				end if;
			end if;
        end loop;

        oGrainY <= yWire(0 to n-1);

	end process;
	----------------------------------------------------------------------------------

end behavioral;