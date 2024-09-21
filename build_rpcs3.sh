#!/usr/bin/env zsh

# ANSI color codes
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# This gets the location that the script is being run from and moves there.
SCRIPT_DIR=${0:a:h}
cd "$SCRIPT_DIR"

if [[ $(uname -m) == "x86_64" ]]; then 
	echo "\n${RED}This script can't be run on an Intel Mac${NC}\n"
	exit 0
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
	echo -e "${PURPLE}Homebrew not found. Installing Homebrew...${NC}"
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	if [[ "${ARCH_NAME}" == "arm64" ]]; then 
		(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> $HOME/.zprofile
		eval "$(/opt/homebrew/bin/brew shellenv)"
		else 
		(echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> $HOME/.zprofile
		eval "$(/usr/local/bin/brew shellenv)"
	fi
	
	# Check for errors
	if [ $? -ne 0 ]; then
		echo "${RED}There was an issue installing Homebrew${NC}"
		echo "${PURPLE}Quitting script...${NC}"	
		exit 1
	fi
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

deps=( cmake ffmpeg glew libpng libusb llvm molten-vk nasm ninja pkg-config qt@6 sdl2 vulkan-headers )

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
export LLVM_DIR=$(brew --prefix)/opt/llvm

# Workaround for issues with SDL framework and non-standard OpenGL installs
SEARCH_FRAMEWORKS_SEQUENCE=FIRST
if [ -d /Library/Frameworks/SDL2.framework ]; then
	echo "${PURPLE}Found SDL2.framework${NC}"
	SEARCH_FRAMEWORKS_SEQUENCE=LAST
fi

# Update individual submodule
git_update_submodule() {
	echo -e "${PURPLE}Updating $1...${NC}"
	git submodule update --init --recursive ./3rdparty/$1
}

# Update submodules 
git_update_submodules() {
	echo -e "${PURPLE}Updating submodules...${NC}"
	# Update only the submodules that are needed
	submodules=( 7zip \
				asmjit \
				cubeb \
				curl \
				flatbuffers \
				glslang \
				hidapi \
    				libpng \
				libusb \
				miniupnp \
				OpenAL \
				pugixml \
				rtmidi \
				SoundTouch \
				SPIRV \
				stblib \
				wolfssl \
				xxHash \
				yaml-cpp \
				zstd \
				# GPUOpen \
				# pine \
				# llvm
				# FAudio
				)
	
	for module in $submodules[@]
	do 
		git_update_submodule $module
	done
}

# Check to see if the source folder exists
if [ ! -d "rpcs3" ]; then
	echo "${PURPLE}Cloning RPCS3 Repository...${NC}"
	git clone https://github.com/RPCS3/rpcs3
	cd rpcs3
	git_update_submodules

	# Change bundle identifier to be unique
	echo "${PURPLE}Changing bundle identifier to be unique...${NC}"
	sed -i -e 's/net.rpcs3.rpcs3/net.rpcs3.rpcs3-arm/' ./rpcs3/rpcs3.plist.in
	
	# Fix hidapi
	echo "${PURPLE}Applying HIDAPI workaround...${NC}"
	sed -i '' "s/extern const double NSAppKitVersionNumber;/const double NSAppKitVersionNumber = 1343;/g" 3rdparty/hidapi/hidapi/mac/hid.c
	
else
	echo "${PURPLE}RPCS3 repository already exists${NC}"
	cd rpcs3
	rm -rf build
	git pull origin master
fi

# Configure build system
cmake . -B build \
	-Wno-deprecated \
	-GNinja \
	-DUSE_NATIVE_INSTRUCTIONS=OFF \
	-DCMAKE_OSX_ARCHITECTURES="arm64" \
	-DLLVM_TARGETS_TO_BUILD="AArch64;ARM" \
	-DBUILD_LLVM=OFF\
	-DUSE_ALSA=OFF \
	-DUSE_AUDIOUNIT=ON \
	-DUSE_FAUDIO=OFF \
	-DUSE_PULSE=OFF \
	-DUSE_SDL=ON \
	-DUSE_SYSTEM_SDL=ON \
	-DUSE_SYSTEM_FFMPEG=on \
	-DUSE_SYSTEM_MVK=on \
	-DUSE_SYSTEM_LIBPNG=OFF

# Build
ninja -C build

# Check whether the build was successful
if [ $? -ne 0 ]; then
	echo -e "${RED}Building failed${NC}"
	exit 1
fi 

# Get an icon from macosicons.com
curl -o build/bin/rpcs3.app/Contents/Resources/rpcs3.icns https://parsefiles.back4app.com/JPaQcFfEEQ1ePBxbf6wvzkPMEqKYHhPYv8boI1Rc/8cfaf8a5f5d112be82708d9baf62e74e_RPCS3-Arm.icns

# Codesign
codesign --force --deep --sign - build/bin/rpcs3.app/Contents/MacOS/rpcs3

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

echo "${PURPLE}Script has completed${NC}"
