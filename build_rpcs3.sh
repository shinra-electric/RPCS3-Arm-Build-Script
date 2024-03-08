#!/usr/bin/env zsh

# ANSI color codes
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# This gets the location that the script is being run from and moves there.
SCRIPT_DIR=${0:a:h}
cd "$SCRIPT_DIR"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
	echo -e "${PURPLE}Homebrew not found. Installing Homebrew...${NC}"
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
	echo -e "${PURPLE}Homebrew found. Updating Homebrew...${NC}"
	brew update
fi

## Homebrew dependencies
# Install required dependencies
echo -e "${PURPLE}Checking for Homebrew dependencies...${NC}"
brew_dependency_check() {
	if [ -d "$(brew --prefix)/opt/$1" ]; then
		echo -e "${GREEN}Found $1. Checking for updates...${NC}"
			brew upgrade $1
	else
		 echo -e "${PURPLE}Did not find $1. Installing...${NC}"
		brew install $1
	fi
}

deps=( cmake ffmpeg glew libusb llvm@17 molten-vk nasm ninja pkg-config qt@6 sdl2 vulkan-headers )

for dep in $deps[@]
do 
	brew_dependency_check $dep
done

# Make sure cubeb(macOS 14) is uninstalled, otherwise building will fail
# Will reinstall at the end of the script
reinstall_cubeb=false

brew_remove() {
	echo -e "${PURPLE}Checking for $1 installation...${NC}"
	if [ -d "$(brew --prefix)/opt/$1" ]; then
		brew rm $1 && echo -e "${GREEN}Removing $1${NC}"
		if [ "$1" = cubeb ]; then
			reinstall_cubeb=true
		fi
	else
		echo -e "${GREEN}$1 not found${NC}"
	fi
}

brew_remove cubeb

# Set variables
export Qt6_DIR=$(brew --prefix)/opt/qt6
export VULKAN_SDK=$(brew --prefix)/opt/molten-vk
if [ ! -h "$VULKAN_SDK/lib/libvulkan.dylib" ]; then 
	echo -e "${PURPLE}Creating libvulkan.dylib symlink${NC}"
	ln -s "$VULKAN_SDK/lib/libMoltenVK.dylib" "$VULKAN_SDK/lib/libvulkan.dylib"
fi 
export VK_ICD_FILENAMES=$VULKAN_SDK/share/vulkan/icd.d/MoltenVK_icd.json
export LLVM_DIR=$(brew --prefix)/opt/llvm@17

# Update Repository
git clone https://github.com/RPCS3/rpcs3
cd rpcs3

# Change bundle identifier to be unique
sed -i -e 's/net.rpcs3.rpcs3/net.rpcs3.rpcs3-arm/' ./rpcs3/rpcs3.plist.in

# Update only the submodules that are needed
git submodule update --init ./3rdparty/asmjit
git submodule update --init ./3rdparty/cubeb
git submodule update --init ./3rdparty/curl
git submodule update --init ./3rdparty/flatbuffers
git submodule update --init ./3rdparty/glslang
git submodule update --init ./3rdparty/GPUOpen
git submodule update --init ./3rdparty/hidapi
git submodule update --init ./3rdparty/libusb
git submodule update --init ./3rdparty/miniupnp
git submodule update --init ./3rdparty/pine
git submodule update --init ./3rdparty/pugixml
git submodule update --init ./3rdparty/rtmidi
git submodule update --init ./3rdparty/SoundTouch
git submodule update --init ./3rdparty/SPIRV
git submodule update --init ./3rdparty/stblib
git submodule update --init ./3rdparty/wolfssl
git submodule update --init ./3rdparty/xxHash
git submodule update --init ./3rdparty/yaml-cpp
#git submodule update --init ./3rdparty/libpng
#git submodule update --init ./3rdparty/llvm
#git submodule update --init ./3rdparty/FAudio

# Fix hidapi
sed -i '' "s/extern const double NSAppKitVersionNumber;/const double NSAppKitVersionNumber = 1343;/g" 3rdparty/hidapi/hidapi/mac/hid.c

# Configure build system
mkdir build && cd build
cmake .. -DUSE_ALSA=OFF -DUSE_PULSE=OFF -DUSE_AUDIOUNIT=ON -DUSE_NATIVE_INSTRUCTIONS=OFF -DUSE_SYSTEM_FFMPEG=on -DCMAKE_OSX_ARCHITECTURES="arm64" -DLLVM_TARGETS_TO_BUILD="AArch64;ARM" -GNinja -DUSE_SYSTEM_MVK=on -DUSE_FAUDIO=OFF -DBUILD_LLVM=OFF -DUSE_SYSTEM_LIBPNG=ON -Wno-deprecated

cmake .. -DUSE_ALSA=OFF \
		-DUSE_PULSE=OFF \
		-DUSE_AUDIOUNIT=ON \
		-DUSE_NATIVE_INSTRUCTIONS=OFF \
		-DUSE_SYSTEM_FFMPEG=on \
		-DCMAKE_OSX_ARCHITECTURES="arm64" \
		-DLLVM_TARGETS_TO_BUILD="AArch64;ARM" \
		-GNinja \
		-DUSE_SYSTEM_MVK=on \
		-DUSE_FAUDIO=OFF \
		-DBUILD_LLVM=OFF\
		-DUSE_SYSTEM_LIBPNG=ON \
		-Wno-deprecated

# Build
ninja 

# Get an icon from macosicons.com
curl -o bin/rpcs3.app/Contents/Resources/rpcs3.icns https://parsefiles.back4app.com/JPaQcFfEEQ1ePBxbf6wvzkPMEqKYHhPYv8boI1Rc/ae136945718671fffd7989eb3ac276ee_RPCS3-Arm.icns

# Codesign
codesign --force --deep --sign - bin/rpcs3.app/Contents/MacOS/rpcs3

# Check that the build was successful
if [ $? -eq 0 ]; then
	# Remove existing app
	cd "$SCRIPT_DIR"
	rm -rf RPCS3-Arm.app
	
	# Move app
	cp -R ./rpcs3/build/bin/rpcs3.app ./RPCS3-Arm.app
	
	# Cleanup 
	rm -rf rpcs3
fi 

# Reinstall cubeb if it was originally installed
if [ $reinstall_cubeb = true ]; then
	echo -e "${PURPLE}Reinstalling cubeb${NC}"
	brew install cubeb
fi
