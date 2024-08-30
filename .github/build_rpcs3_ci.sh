#!/usr/bin/env zsh

# This gets the location that the script is being run from and moves there.
SCRIPT_DIR=${0:a:h}
cd "$SCRIPT_DIR"

## Homebrew dependencies
# Install required dependencies
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
brew install ffmpeg glew llvm nasm pipenv sdl2 vulkan-headers 
curl -L https://raw.githubusercontent.com/Homebrew/homebrew-core/0d9f25fbd1658e975d00bd0e8cccd20a0c2cb74b/Formula/m/molten-vk.rb > molten-vk.rb && brew install --formula molten-vk.rb

# Get Qt
export WORKDIR;
WORKDIR="$(pwd)"
# Get Qt
if [ ! -d "/tmp/Qt/6.6.3" ]; then
  mkdir -p "/tmp/Qt"
  git clone https://github.com/engnr/qt-downloader.git
  cd qt-downloader
  git checkout f52efee0f18668c6d6de2dec0234b8c4bc54c597
  cd "/tmp/Qt"
  "$(brew --prefix)/bin/pipenv" run pip3 install py7zr requests semantic_version lxml
  mkdir -p "6.6.3/macos" ; ln -s "macos" "6.6.3/clang_64"
  "$(brew --prefix)/bin/pipenv" run "$WORKDIR/qt-downloader/qt-downloader" macos desktop 6.6.3 clang_64 --opensource --addons qtmultimedia
fi

cd "$WORKDIR"
ditto "/tmp/Qt/6.6.3" "qt-downloader/6.6.3"

export Qt6_DIR="$WORKDIR/qt-downloader/6.6.3/clang_64/lib/cmake/Qt6"
export PATH="$WORKDIR/qt-downloader/6.6.3/clang_64/bin:$PATH"

# Set variables
export VULKAN_SDK=$(brew --prefix)/opt/molten-vk
if [ ! -h "$VULKAN_SDK/lib/libvulkan.dylib" ]; then 
	ln -s "$VULKAN_SDK/lib/libMoltenVK.dylib" "$VULKAN_SDK/lib/libvulkan.dylib"
fi 
export VK_ICD_FILENAMES=$VULKAN_SDK/share/vulkan/icd.d/MoltenVK_icd.json
export LLVM_DIR=$(brew --prefix)/opt/llvm

git clone https://github.com/rpcs3/rpcs3
cd rpcs3
git submodule -q update --init --depth=1 --jobs=8 $(awk '/path/ && !/GPUOpen/ && !/llvm/ && !/FAudio/ { print $3 }' .gitmodules)

# Fixes
# Change bundle identifier to be unique
sed -i -e 's/net.rpcs3.rpcs3/net.rpcs3.rpcs3-arm/' ./rpcs3/rpcs3.plist.in

# Change variable name to fix ffmpeg issue
# Remove in the future when fixed
sed -i -e 's/frame_number/frame_num/' ./rpcs3/util/media_utils.cpp

# Fix hidapi
sed -i '' "s/extern const double NSAppKitVersionNumber;/const double NSAppKitVersionNumber = 1343;/g" 3rdparty/hidapi/hidapi/mac/hid.c

# Configure build system
cmake . -B build \
	-DUSE_NATIVE_INSTRUCTIONS=OFF \
	-DCMAKE_OSX_ARCHITECTURES="arm64" \
	-DLLVM_TARGETS_TO_BUILD="AArch64;ARM" \
	-DBUILD_LLVM=OFF\
	-DLLVM_BUILD_RUNTIME=OFF \
	-DLLVM_BUILD_TOOLS=OFF \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_INCLUDE_TOOLS=OFF \
	-DLLVM_INCLUDE_UTILS=OFF \
	-DLLVM_USE_PERF=OFF \
	-DLLVM_ENABLE_Z3_SOLVER=OFF \
	-DUSE_ALSA=OFF \
	-DUSE_AUDIOUNIT=ON \
	-DUSE_PULSE=OFF \
	-DUSE_SDL=ON \
	-DUSE_VULKAN=ON \
	-DUSE_SYSTEM_FAUDIO=OFF \
	-DUSE_SYSTEM_FFMPEG=on \
	-DUSE_SYSTEM_LIBPNG=ON \
	-DUSE_SYSTEM_MVK=on \
	-DUSE_SYSTEM_SDL=ON \
	-DCMAKE_IGNORE_PATH="$(brew --prefix)/lib"
	
# Build
cmake --build build/ --parallel 3

mkdir ./build/bin/rpcs3.app/Contents/lib
ditto "/opt/homebrew/opt/llvm@16/lib/c++/libc++abi.1.0.dylib" "./build/bin/rpcs3.app/Contents/lib/libc++abi.1.dylib"
ditto "$(realpath /opt/homebrew/lib/libsharpyuv.0.dylib)" "./build/bin/rpcs3.app/Contents/lib/libsharpyuv.0.dylib"
ditto "$(realpath /opt/homebrew/lib/libintl.8.dylib)" "./build/bin/rpcs3.app/Contents/lib/libintl.8.dylib"
	
# Remove unused Qt frameworks
rm -rf "build/bin/rpcs3.app/Contents/Frameworks/QtPdf.framework" \
"build/bin/rpcs3.app/Contents/Frameworks/QtQml.framework" \
"build/bin/rpcs3.app/Contents/Frameworks/QtQmlModels.framework" \
"build/bin/rpcs3.app/Contents/Frameworks/QtQuick.framework" \
"build/bin/rpcs3.app/Contents/Frameworks/QtVirtualKeyboard.framework" \
"build/bin/rpcs3.app/Contents/Plugins/platforminputcontexts" \
"build/bin/rpcs3.app/Contents/Plugins/virtualkeyboard" \
"build/bin/rpcs3.app/Contents/Resources/git"

# Make an icon
mkdir rpcs3.iconset
sips -z 16 16     ./RCPS3-Arm.png --out rpcs3.iconset/icon_16x16.png
sips -z 32 32     ./RCPS3-Arm.png --out rpcs3.iconset/icon_16x16@2x.png
sips -z 128 128   ./RCPS3-Arm.png --out rpcs3.iconset/icon_128x128.png
sips -z 256 256   ./RCPS3-Arm.png --out rpcs3.iconset/icon_128x128@2x.png
sips -z 512 512   ./RCPS3-Arm.png --out rpcs3.iconset/icon_512x512.png
cp ./RCPS3-Arm.png rpcs3.iconset/icon_512x512@2x.png
iconutil -c icns rpcs3.iconset
rm -R rpcs3.iconset

cp -R ./rpcs3.icns ./rpcs3/build/bin/rpcs3.app/Contents/Resources/rpcs3.icns

# Rename the app so it doesn't clash with the x86 build
mv /rpcs3/build/bin/rpcs3.app /rpcs3/build/bin/RPCS3-Arm.app
rm -rf rpcs3.app

# Codesign
codesign --force --deep --sign - build/bin/RPCS3-Arm.app/Contents/MacOS/rpcs3