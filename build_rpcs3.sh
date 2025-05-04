#!/usr/bin/env zsh

# ANSI color codes
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# This gets the location that the script is being run from and moves there.
SCRIPT_DIR=${0:a:h}
cd "$SCRIPT_DIR"

# Detect CPU architecture
ARCH="$(uname -m)"

introduction() {
	echo "\n${PURPLE}This script is for compiling ${GREEN}RPCS3${PURPLE} for ${GREEN}Apple Silicon${NC}\n"
	
	if [[ $ARCH == "x86_64" ]]; then 
		echo "\n${PURPLE}Your CPU architecture is ${RED}$ARCH${NC}\n"
		echo "${RED}This script can't be run on an Intel Mac${NC}\n"
		exit 0
	fi
	
	echo "${GREEN}Homebrew${PURPLE} and the ${GREEN}Xcode command-line tools${PURPLE} are required${NC}"
	echo "${PURPLE}If they are not present you will be prompted to install them${NC}\n"
}

homebrew_check() {
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
}

# Function for checking for an individual dependency
single_dependency_check() {
	if [ -d "$(brew --prefix)/opt/$1" ]; then
		echo "${GREEN}Found $1. Checking for updates...${NC}"
			brew upgrade $1
	else
		 echo "${PURPLE}Did not find $1. Installing...${NC}"
		brew install $1
	fi
}

dependencies_check() {
	echo "${PURPLE}Checking for native Homebrew dependencies...${NC}"
	# Required native Homebrew packages
	deps=( cmake ffmpeg glew libpng libusb llvm molten-vk nasm ninja opencv pkg-config qt@6 sdl3 vulkan-headers )
	
	for dep in $deps[@]
	do 
		single_dependency_check $dep
	done
}

# Make sure cubeb(macOS 14) is uninstalled, otherwise building will fail
# Will reinstall at the end of the script if it was detected

cubeb_check() {
	echo "${PURPLE}Checking for cubeb installation...${NC}"
	reinstall_cubeb=false
	
	if [ -d "/opt/homebrew/opt/cubeb" ]; then
		echo "${GREEN}Removing cubeb${NC}"
		echo "${GREEN}It will be reinstalled at the end of the script${NC}"
		brew rm cubeb 
		reinstall_cubeb=true
	else
		echo "${GREEN}cubeb not found${NC}"
	fi
}

reinstall_cubeb() {
	if [ $reinstall_cubeb = true ]; then
		echo -e "${PURPLE}Reinstalling cubeb${NC}"
		brew install cubeb
	fi
}

# Update individual submodule
git_update_submodule() {
	echo "${PURPLE}Updating $1...${NC}"
	git submodule update --init --recursive ./3rdparty/$1
}

# Update submodules 
git_update_submodules() {
	echo "\n${PURPLE}Updating submodules...${NC}\n"
	# Update only the submodules that are needed
	submodules=( 7zip \
			asmjit \
			# bcdec \
			cubeb \
			curl \
			# discord-rpc \
   			# FAudio \
      		# ffmpeg \
			flatbuffers \
			fusion \
			# GL \
			glslang \
			GPUOpen \
			hidapi \
    		libpng \
			# libsdl-org \
			libusb \
			# llvm \
			miniupnp \
   			# MoltenVK \
			OpenAL \
			opencv \
			# pine \
			pugixml \
			rtmidi \
			SoundTouch \
			stblib \
			# unordered_dense \
   			wolfssl \
			yaml-cpp \
			# zlib \
			zstd \
				)
	
	for module in $submodules[@]
	do 
		git_update_submodule $module
	done
}

clone_repo() { 
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
}

build() {
	
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

	# Configure build system
	cmake . -B build \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
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
		-DUSE_DISCORD_RPC=OFF \
		-DUSE_SYSTEM_SDL=ON \
		-DUSE_SYSTEM_FFMPEG=on \
		-DUSE_SYSTEM_MVK=on \
		-DUSE_SYSTEM_OPENCV=ON \
		-DUSE_SYSTEM_LIBPNG=OFF
	
	# Build
	ninja -C build
	
	# Check whether the build was successful
	if [ $? -ne 0 ]; then
		echo "\n${RED}Building failed${NC}\n"
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
	fi
}

main_menu() {
	PS3='What would you like to do? '
	OPTIONS=(
		"Build"
		"Build without Homebrew checks"
		"Quit")
	select opt in $OPTIONS[@]
	do
		case $opt in
			"Build")
				homebrew_check
				dependencies_check
				cubeb_check
				clone_repo
				continue_menu
				build
				reinstall_cubeb
				cleanup_menu
				break
				;;
			"Build without Homebrew checks")
				echo "\n${RED}Skipping Homebrew checks${NC}"
				echo "${PURPLE}The script will fail if any of the dependencies are missing${NC}\n"
				clone_repo
				continue_menu
				build
				cleanup_menu
				break
				;;
			"Quit")
				echo "${RED}Quitting${NC}"
				exit 0
				;;
			*) 
				echo "\"$REPLY\" is not one of the options..."
				echo "Enter the number of the option and press enter to select"
				;;
		esac
	done
}

continue_menu() {
	echo "\n${PURPLE}Ready to build${NC}"
	echo "${PURPLE}You can modify the code now before building${NC}\n"
	PS3='Would you like to continue building? '
	OPTIONS=(
		"Continue"
		"Quit")
	select opt in $OPTIONS[@]
	do
		case $opt in
			"Continue")
				break
				;;
			"Quit")
				echo "${PURPLE}Quitting${NC}"
				exit 0
				;;
			*) 
				echo "\"$REPLY\" is not one of the options..."
				echo "Enter the number of the option and press enter to select"
				;;
		esac
	done
}

cleanup_menu() {
	echo "\n${GREEN}The script has completed${NC}"
	
	PS3='Would you like to delete the source folder? '
	OPTIONS=(
		"Delete"
		"Quit")
	select opt in $OPTIONS[@]
	do
		case $opt in
			"Delete")
				echo "${PURPLE}Cleaning up${NC}"
				rm -rf rpcs3
				exit 0
				;;
			"Quit")
				echo "${PURPLE}Quitting${NC}"
				exit 0
				;;
			*) 
				echo "\"$REPLY\" is not one of the options..."
				echo "Enter the number of the option and press enter to select"
				;;
		esac
	done
}

introduction
main_menu
