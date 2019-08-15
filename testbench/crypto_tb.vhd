library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
--------------------------------
entity cryptoTb is
	-- Port ();
end cryptoTb;
-------------------------------------
architecture Behavioral of cryptoTb is
	-------------------------------------
	component grainTop is
		generic (
			n         : integer;
			ndiv2     : integer;
			g         : integer;
			yt        : integer;
			ctype     : integer;
			clkdivnum : integer;
			ia        : integer -- Isolation or not
		);
		port (
			oGraintopY           : out std_logic_vector(0 to (ndiv2) - 1); -- Key stream out. 
			iGraintopIv          : in std_logic_vector(0 to n - 1); -- IV in.
			iGraintopKey         : in std_logic_vector(0 to n - 1); -- Key in
			iGraintopEnable      : in std_logic; -- Start
			iGraintopReset       : in std_logic;
			iGraintopClk         : in std_logic;
			oGraintopYFlag       : out std_logic; -- When keystream available.
			oGraintopTag         : out std_logic_vector(0 to 63); -- The tag if using authentication.
			iGraintopCryptMode   : std_logic; -- 1 = decryption. 0 = Encryption
			iGraintopCryptEnable : std_logic; -- Enable/disable encryption 
			iGraintopMsg         : in std_logic_vector(0 to (ndiv2) - 1) -- Message
		);
	end component;
	------------------------------------
	constant period                   : time := 5 ns;
	constant halfperiod               : time := 2.5 ns;
	constant n                        : integer := 1;
	constant ndiv2                    : integer := 1; -- Half of n in normal cases. If n is 1, this will be one as well.

	signal tbCryptMode                : std_logic := '1'; -- 0 = encryption. 1 = decryption.
	signal cryptMode                  : integer := 1; -- Change this value with tbCryptmode. as the same value.
	signal tbCryptEnable              : std_logic := '1'; -- Enable/disable encryption/decryption.
	constant IndexStart               : integer := 0; -- When to encrypt start. Length of Adlen + AD. Put to like 9999 when there is no encryption.
	constant IndexEnd                 : integer := 100; -- Everything but the last 8 bits.
 
 

 
	signal tbReset                    : std_logic := '0'; 
	signal tbClk                      : std_logic := '0'; 
	signal tbEnable                   : std_logic := '0';
	signal tbMessage                  : std_logic_vector(0 to ndiv2 - 1) := (others => '0');
	signal tbY                        : std_logic_vector(0 to ndiv2 - 1) := (others => '0'); 
	signal tbIv                       : std_logic_vector(0 to n - 1) := (others => '0'); 
	signal tbKey                      : std_logic_vector(0 to n - 1) := (others => '0');
	signal tbYFlag                    : std_logic := '0';

	signal tbTag                      : std_logic_vector(63 downto 0); -- The tag is defined in the opposite way according to the Grain-128a/grain-128AEAD paper.

	signal preout23                   : std_logic_vector(0 to 319);
	signal preout1, preout2           : std_logic_vector(0 to 319);
	signal preout3, preout4           : std_logic_vector(0 to 255);
	signal key1, key2, key3, key4     : std_logic_vector(0 to 127);
	signal iv1, iv2, iv3, iv4         : std_logic_vector(0 to 127);
	signal accum1, reg1, accum2, reg2 : std_logic_vector(0 to 31);
	---new added message---
	signal m0 : std_logic_vector(0 to 8);
	signal m1 : std_logic_vector(0 to 1);
	signal m2 : std_logic_vector(0 to 1);
	signal m3 : std_logic_vector(0 to 20); -- 20. 11 extra zeros
	signal m4 : std_logic_vector(0 to 41); -- 41. 6 extra zeros
	---------------------------------------

	----------------------------------------------------------------------------------
begin
	----------------------------------------------------------------------------------
	grainTopInst3 : grainTop
		generic map(-- Change when selecting optimization and controller.
		n         => n, 
		ndiv2     => ndiv2, -- Put at 1 when doing 1 para. n/2
		g         => 0, 
		yt        => 0, 
		ctype     => 1, 
		clkdivnum => 64, -- Put it to 2 by default so the program doesn't complain. Won't affect anything unless ctype is 1.
		ia        => 1-- Isolation or not
		)
		port map(
			oGraintopY           => tbY, --these are wire or signal
 
			iGraintopIv          => tbIv, 
			iGraintopKey         => tbKey, 
			iGraintopEnable      => tbEnable, 
			iGraintopReset       => tbReset, 
			iGraintopClk         => tbClk, 
 
			oGraintopTag         => tbTag, -- The tag if using authentication 
 
			oGraintopYFlag       => tbYFlag, 
			iGraintopMsg         => tbMessage, 
			iGraintopCryptMode   => tbCryptMode, -- 1 = decryption. 0 = Encryption
			iGraintopCryptEnable => tbCryptEnable -- Enable/disable encryption 
 
		); 
			-------------------------

			tbClk <= not(tbClk) after halfperiod * 1;

			-----------------------------------------------------------------------------------------------
			--test1

			key1 <= X"00000000000000000000000000000000"; 
			iv1  <= X"000000000000000000000000fffffffe";
			--iv1 <= X"00000000000000000000000100000000";
			preout1 <= X"c0207f221660650b6a952ae26586136fa0904140c8621cfe8660c0dec0969e9436f4ace92cf1ebb7";

			---test2
			key2 <= X"0123456789abcdef123456789abcdef0";
			--key2 <= (others=>'0');
			iv2      <= X"0123456789abcdef12345678fffffffe"; -- 80c4a2e691d5b3f7482c6a1e
 
			preout23 <= X"c0207f221660650b6a952ae26586136fa0904140c8621cfe8660c0dec0969e9436f4ace92cf1ebb7";
			preout2  <= X"f88720c13f46e6a43c07eeed89161a4dd73bd6b8be8b6b116879714ebb630e0a4c12f0399412982c";
			----test3
			key3    <= (others => '0');
			iv3     <= X"800000000000000000000000fffffffe";
			accum1  <= X"564b3622"; --new add
			reg1    <= X"19bd90e3"; --new add
			preout3 <= X"01f259cf52bf5da9deb1845be6993abd2d3c77c4acb90e422640fbd6e8ae642a";

 
			----test4
			key4    <= X"0123456789abcdef123456789abcdef0";
			iv4     <= X"8123456789abcdef12345678fffffffe";
			accum2  <= X"7f2acdb7"; --new add
			reg2    <= X"adfb701f"; --new add
			preout4 <= X"8d2083b3c32b43f1962b3dcabf679378db3536bfc25bed483008e6bcb395a156";
 
			------5 different Message (MARTIN'S PAPER)
			m0 <= "100000000";
			m1 <= "01"; -- Reading it from the other way because Martin used that notation in his paper. 0 is first bit to be read.
			m2 <= "11"; --
			m3 <= "000100100011010000001";

			m4 <= "000100100011010001010110011110001001111011"; 

			process
			variable MsgIndex  : integer := 0;
			variable MsgFinish : integer := 0;
	begin
		wait for halfperiod;
 
		for t in 0 to 3 loop
			for m in 0 to 2 loop
				MsgIndex  := 0; -- Set it 0 zero at the start.
				MsgFinish := 0;
				tbReset  <= '1';
				tbEnable <= '0';
				wait for 3 * period;
				tbReset  <= '0';
				tbEnable <= '1';
				for f in 0 to 1 loop
					for k in 0 to (128/n) - 1 loop
						if (t = 0) then
							tbKey <= key1((k * n) to ((k + 1) * n - 1)); -- Input last bit first.
							tbIv  <= iv1((k * n) to ((k + 1) * n - 1));
						elsif (t = 1) then
							tbKey <= key2((k * n) to ((k + 1) * n - 1)); -- Input last bit first.
							tbIv  <= iv2((k * n) to ((k + 1) * n - 1));
						elsif (t = 2) then
							tbKey <= key3((k * n) to ((k + 1) * n - 1)); -- Input last bit first.
							tbIv  <= iv3((k * n) to ((k + 1) * n - 1)); 
						else 
							tbKey <= key4((k * n) to ((k + 1) * n - 1)); -- Input last bit first.
							tbIv  <= iv4((k * n) to ((k + 1) * n - 1));
						end if;
						if (f = 1) then -- When doing accumload
							tbMessage <= (others => '0');
							if (k = 128/(2 * n)) then -- Half the accumload
								tbMessage(0) <= '1'; --ndiv2 -1
							end if;
						end if;
						wait for period; 
					end loop;
 
					if (f = 0) then
						tbKey <= (others => '0'); -- Stop sending in key and IV
						tbIv  <= (others => '0'); -- Stop sending in
						wait until tbYFlag = '1';
					end if;
 
					if (f = 1) then
						tbKey <= (others => '0'); -- Stop sending in
						tbIv  <= (others => '0'); -- Stop sending in
					end if;
				end loop;

				tbCryptEnable <= '1';
				case m is
					when 0 => 
 
						if (MsgFinish = 0) then

							tbMessage <= (others => '0'); -- Reset it.

							for g in 0 to m0'LENGTH - 1 loop -- (ndiv2 - 1) --(ndiv2 - 1)
								tbMessage((g mod (ndiv2))) <= m0(g); -- Sends in most signficant value first.
								--report integer'image(g) & ".Value. message = " & std_logic'image(m0(g)) & integer'image((g MOD (n/2)));
								if ((g mod (ndiv2)) = ndiv2 - 1) then -- n/2 bit msg generated send it in and wait 1 clock cycle.
									--report "New message";
 
									wait for period;
									tbMessage <= (others => '0'); -- Sets a default value for next msg round.
									if (n = 1) then -- In 1 para we need to wait 1 extra clock cycle since the next msg round won't be until the next accum/mac bit is generated
										wait for period; -- One extra wait.
									end if;
									--tbMessage <= (others => '0'); -- Sets a default value for next msg round.
								elsif (g = m0'LENGTH - 1) then -- Message is smaller or not dividable by parallelization. Pads on zeros
									wait for period;
									tbMessage <= (others => '0'); -- Sets a default value for next msg round.
 
								end if;
 
							end loop;
							MsgFinish := 1; -- message finish, we stop encrypting/decrypting
 
							wait for period;
							tbCryptEnable <= '0'; -- we stop encrypting/decryption when the message is sent in.
							tbMessage     <= (others => '0');
 
						else -- In all clock cycles after message finished.
							tbMessage <= (others => '0');
							-- tbCryptEnable <= '0'; -- we stop encrypting/decryption when the message is sent in.
						end if;
					when 1 => 
 
						if (MsgFinish = 0) then
							tbMessage <= (others => '0'); -- Reset it.
							for g in 0 to m1'LENGTH - 1 loop --(ndiv2) - 1) -
								tbMessage(((g mod (ndiv2)))) <= m1(g); -- Sends in most signficant value first.
 
								if ((g mod (ndiv2)) = ndiv2 - 1) then -- n/2 bit msg generated send it in and wait 1 clock cycle.
 
									wait for period;
									tbMessage <= (others => '0'); -- Sets a default value for next msg round.
									if (n = 1) then -- In 1 para we need to wait 1 extra clock cycle since the next msg round won't be until the next accum/mac bit is generated
										wait for period; -- One extra wait.
									end if;
									--tbMessage <= (others => '0'); -- Sets a default value for next msg round.
								elsif (g = m1'LENGTH - 1) then -- Message is smaller or not dividable by parallelization. Pads on zeros
									wait for period;
									tbMessage <= (others => '0'); -- Sets a default value for next msg round.
 
								end if;
 
							end loop;
							MsgFinish := 1;
							tbCryptEnable <= '0'; -- we stop encrypting/decryption when the message is sent in.
							wait for period;
							tbCryptEnable <= '0'; -- we stop encrypting/decryption when the message is sent in.
							tbMessage     <= (others => '0');
						else
							tbMessage <= (others => '0');
							-- tbCryptEnable <= '0'; -- we stop encrypting/decryption when the message is sent in.
						end if;
					when 2 => 
 
						if (MsgFinish = 0) then
							tbMessage <= (others => '0'); -- Reset it.
							for g in 0 to m3'LENGTH - 1 loop-- ((ndiv2) - 1) -
								tbMessage((g mod (ndiv2))) <= m3(g); -- Sends in most signficant value first.
 
								if ((g mod (ndiv2)) = (ndiv2) - 1) then -- n/2 bit msg generated send it in and wait 1 clock cycle.
 
									wait for period;
									tbMessage <= (others => '0'); -- Sets a default value for next msg round.
									if (n = 1) then -- In 1 para we need to wait 1 extra clock cycle since the next msg round won't be until the next accum/mac bit is generated
										wait for period; -- One extra wait.
									end if;
									--tbMessage <= (others => '0'); -- Sets a default value for next msg round.
								elsif (g = m3'LENGTH - 1) then -- Message is smaller or not dividable by parallelization. Pads on zeros
									wait for period;
									tbMessage <= (others => '0'); -- Sets a default value for next msg round.
 
								end if;
 
							end loop;
							MsgFinish := 1;
 
							wait for period;
							tbCryptEnable <= '0'; -- we stop encrypting/decryption when the message is sent in.
							tbMessage     <= (others => '0');
						else
							tbMessage <= (others => '0');
							--tbCryptEnable <= '0'; -- we stop encrypting/decryption when the message is sent in.
						end if;
 
				end case;
 

				wait for period;
				--end loop;

				-- Here we are done!

				wait for 5 * period;
 
			end loop;

		end loop;
		wait for halfperiod; -- For starting over.



	end process;
	----------------------------------------------------------------------------------

end Behavioral;