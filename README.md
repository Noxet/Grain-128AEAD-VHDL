# Grain-128AEAD-VHDL
The VHDL reference implementation along with optimized versions of the stream cipher Grain-128AEAD.

The top file is `grain_top.vhd` which includes all other components. The testbench is `crypto_tb.vhd` and is only used for simulations.
When synthesizing the design, the only warning that should occur, for parallelization levels > 1, is that `iControllerClk2` is not used. The signal is only used in the non-parallelized version.

See the .vhd files for comments on how to configure the design to your liking.

Developed by [Mattias Sönnerup](Zerox-1337), [Ripudaman Khattar](ripudamank2) and [Jonathan Sönnerup](https://github.com/Noxet)
