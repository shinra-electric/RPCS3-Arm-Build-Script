# Build Script for RPCS3 - Arm

This script will compile an Arm64 build of the PlayStation 3 Emulator RPCS3 for modern M-series Macs. 

> [!WARNING]
> The script is provided for experimentation purposes only. <br>
> The Arm build of RPCS3 can only run a few games. <br>
> If you would like to play games, then download the official x86 build [here](https://rpcs3.net/download) and run through Rosetta.

> [!NOTE]
> Only a short list of games have been confirmed to run on Arm, including:
> 
> - The Arkedo series
> - Dragon's Crown (Issue with characters in shadow)
> - Odin Sphere Leifthrasir
> - Ryu Ga Gotoku 1 & 2 HD Remaster (Released in Japan only)
> - Ratchet & Clank 1-2-3 HD Remasters (Broken cutscenes)

## Setting up the emulator
> In the Arm build the LLVM recompiler does not work.<br>
> In order to run games make these changes in the CPU settings: 
> - Change the PPU decoder to Interpreter (static)
> - Change the SPU Decoder to Interpreter (dynamic)

When trying to run a game, always look up the RPCS3 Compatibility list to check the recommended settings. Settings can be saved on a per-game basis.

