#!/bin/bash

# abort on error
set -e

export WORKSPACE=$PWD

export NDK_ROOT=$WORKSPACE/android-ndk-r10e
export SDK_ROOT=$WORKSPACE/android-sdk

# Number of CPU
NBPROC=$(getconf _NPROCESSORS_ONLN)

# Setup PATH
PATH=$PATH:$NDK_ROOT:$SDK_ROOT/tools

if [ ! -f .patches-applied ]; then
	echo "patching libraries"

	# Patch cpufeatures, hangs in Android 4.0.3
	patch -Np0 < cpufeatures.patch

	# disable pixman examples and tests
	cd pixman-0.34.0
	sed -i.bak 's/SUBDIRS = pixman demos test/SUBDIRS = pixman/' Makefile.am
	autoreconf -fi
	cd ..

	# modernize libmad
	cd libmad-0.15.1b
	patch -Np1 < ../libmad-pkg-config.diff
	autoreconf -fi
	cd ..

	# use android config
	cd SDL
	mv include/SDL_config_android.h include/SDL_config.h
	mkdir -p jni
	cd ..

	# enable jni config loading
	cd SDL_mixer
	patch -Np1 -d timidity < ../timidity-android.patch
	patch -Np0 < ../sdl-mixer-config.patch
	sh autogen.sh
	cd ..

	touch .patches-applied
fi

# Install libpng
function install_lib_png {
	cd libpng-1.6.21
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install freetype
function install_lib_freetype() {
	cd freetype-2.6.3
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static --with-harfbuzz=no
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install pixman
function install_lib_pixman() {
	cd pixman-0.34.0
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install libogg
function install_lib_ogg() {
	cd libogg-1.3.2
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install libvorbis
function install_lib_vorbis() {
	cd libvorbis-1.3.5
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install libmodplug
function install_lib_modplug() {
	cd libmodplug-0.8.8.5
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install libmad
function install_lib_mad() {
	cd libmad-0.15.1b
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-shared --enable-static $@
	make clean
	make -j$NBPROC
	make install
	cd ..
}

# Install SDL2
function install_lib_sdl {
	# $1 => platform (armeabi armeabi-v7a x86 mips)

	cd SDL
	echo "APP_STL := gnustl_static" > "jni/Application.mk"
	echo "APP_ABI := $1" >> "jni/Application.mk"
	ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk APP_PLATFORM=android-9
	cp libs/$1/* $PLATFORM_PREFIX/lib/
	cp include/* $PLATFORM_PREFIX/include/
	cd ..
}

# Install SDL2_mixer
function install_lib_mixer() {
	cd SDL_mixer
	./configure --host=$TARGET_HOST --prefix=$PLATFORM_PREFIX --disable-sdltest \
		--enable-music-mp3-mad-gpl --disable-music-mp3-smpeg
	make clean
	make -j$NBPROC
	make install
	cd ..
}

export OLD_PATH=$PATH

####################################################
# Install standalone toolchain x86
cd $WORKSPACE

echo "preparing x86 toolchain"

export PLATFORM_PREFIX=$WORKSPACE/x86-toolchain
$NDK_ROOT/build/tools/make-standalone-toolchain.sh --platform=android-9 --ndk-dir=$NDK_ROOT --toolchain=x86-4.9 --install-dir=$PLATFORM_PREFIX --stl=gnustl

export PATH=$PLATFORM_PREFIX/bin:$PATH

export CPPFLAGS="-I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/android/support/include"
export LDFLAGS="-L$PLATFORM_PREFIX/lib"
export PKG_CONFIG_PATH=$PLATFORM_PREFIX/lib/pkgconfig
export TARGET_HOST="i686-linux-android"

install_lib_png
install_lib_freetype
install_lib_pixman
install_lib_ogg
install_lib_vorbis
install_lib_modplug
install_lib_mad
install_lib_sdl "x86"
install_lib_mixer

# Install host ICU
unset CPPFLAGS
unset LDFLAGS

cp -r icu icu-native
cp icudt56l.dat icu/source/data/in/
cp icudt56l.dat icu-native/source/data/in/
cd icu-native/source
sed -i.bak 's/SMALL_BUFFER_MAX_SIZE 512/SMALL_BUFFER_MAX_SIZE 2048/' tools/toolutil/pkg_genc.h
chmod u+x configure
./configure --enable-static --enable-shared=no --enable-tests=no --enable-samples=no --enable-dyload=no --enable-tools --enable-extras=no --enable-icuio=no --with-data-packaging=static
make -j$NBPROC
export ICU_CROSS_BUILD=$PWD

# Cross compile ICU
cd ../../icu/source

export CPPFLAGS="-I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/cxx-stl/stlport/stlport -O3 -fno-short-wchar -DU_USING_ICU_NAMESPACE=0 -DU_GNUC_UTF16_STRING=0 -fno-short-enums -nostdlib"
export LDFLAGS="-lc -Wl,-rpath-link=$PLATFORM_PREFIX/lib -L$PLATFORM_PREFIX/lib/"

chmod u+x configure
./configure --with-cross-build=$ICU_CROSS_BUILD --enable-strict=no --enable-static --enable-shared=no --enable-tests=no --enable-samples=no --enable-dyload=no --enable-tools=no --enable-extras=no --enable-icuio=no --host=$TARGET_HOST --with-data-packaging=static --prefix=$PLATFORM_PREFIX
make clean
make -j$NBPROC
make install

unset CPPFLAGS
unset LDFLAGS

################################################################
# Install standalone toolchain ARMeabi

cd $WORKSPACE

echo "preparing ARMeabi toolchain"

export PATH=$OLD_PATH
export PLATFORM_PREFIX=$WORKSPACE/armeabi-toolchain
$NDK_ROOT/build/tools/make-standalone-toolchain.sh --platform=android-9 --ndk-dir=$NDK_ROOT --toolchain=arm-linux-androideabi-4.9 --install-dir=$PLATFORM_PREFIX  --stl=gnustl
export PATH=$PLATFORM_PREFIX/bin:$PATH

export CPPFLAGS="-I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/android/support/include -I$NDK_ROOT/sources/android/cpufeatures"
export LDFLAGS="-L$PLATFORM_PREFIX/lib"
export PKG_CONFIG_PATH=$PLATFORM_PREFIX/lib/pkgconfig
export TARGET_HOST="arm-linux-androideabi"

install_lib_png
install_lib_freetype
install_lib_pixman
install_lib_ogg
install_lib_vorbis
install_lib_modplug
install_lib_mad
install_lib_sdl "armeabi"
install_lib_mixer

# Cross compile ICU
cd icu/source

export CPPFLAGS="-I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/cxx-stl/stlport/stlport -O3 -fno-short-wchar -DU_USING_ICU_NAMESPACE=0 -DU_GNUC_UTF16_STRING=0 -fno-short-enums -nostdlib"
export LDFLAGS="-lc -Wl,-rpath-link=$PLATFORM_PREFIX/lib -L$PLATFORM_PREFIX/lib/"

chmod u+x configure
./configure --with-cross-build=$ICU_CROSS_BUILD --enable-strict=no --enable-static --enable-shared=no --enable-tests=no --enable-samples=no --enable-dyload=no --enable-tools=no --enable-extras=no --enable-icuio=no --host=$TARGET_HOST --with-data-packaging=static --prefix=$PLATFORM_PREFIX
make clean
make -j$NBPROC
make install

################################################################
# Install standalone toolchain ARMeabi-v7a
cd $WORKSPACE

echo "preparing ARMeabi-v7a toolchain"

# Setting up new toolchain not required, only difference is CPPFLAGS

export PLATFORM_PREFIX_ARM=$WORKSPACE/armeabi-toolchain
export PLATFORM_PREFIX=$WORKSPACE/armeabi-v7a-toolchain

export CPPFLAGS="-I$PLATFORM_PREFIX_ARM/include -I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/android/support/include -I$NDK_ROOT/sources/android/cpufeatures -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3"
export LDFLAGS="-L$PLATFORM_PREFIX_ARM/lib -L$PLATFORM_PREFIX/lib"
export PKG_CONFIG_PATH=$PLATFORM_PREFIX/lib/pkgconfig
export TARGET_HOST="arm-linux-androideabi"

install_lib_png
install_lib_freetype
install_lib_pixman
install_lib_ogg
install_lib_vorbis
install_lib_modplug
install_lib_mad
install_lib_sdl "armeabi-v7a"
install_lib_mixer

# Cross compile ICU
cd icu/source

export CPPFLAGS="-I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/cxx-stl/stlport/stlport -O3 -fno-short-wchar -DU_USING_ICU_NAMESPACE=0 -DU_GNUC_UTF16_STRING=0 -fno-short-enums -nostdlib -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3"
export LDFLAGS="-lc -Wl,-rpath-link=$PLATFORM_PREFIX/lib -L$PLATFORM_PREFIX/lib/"

chmod u+x configure
./configure --with-cross-build=$ICU_CROSS_BUILD --enable-strict=no --enable-static --enable-shared=no --enable-tests=no --enable-samples=no --enable-dyload=no --enable-tools=no --enable-extras=no --enable-icuio=no --host=$TARGET_HOST --with-data-packaging=static --prefix=$PLATFORM_PREFIX
make clean
make -j$NBPROC
make install

################################################################
# Install standalone toolchain MIPS
cd $WORKSPACE

echo "preparing MIPS toolchain"

export PATH=$OLD_PATH
export PLATFORM_PREFIX=$WORKSPACE/mips-toolchain
$NDK_ROOT/build/tools/make-standalone-toolchain.sh --platform=android-9 --ndk-dir=$NDK_ROOT --toolchain=mipsel-linux-android-4.9 --install-dir=$PLATFORM_PREFIX  --stl=gnustl
export PATH=$PLATFORM_PREFIX/bin:$PATH

export CPPFLAGS="-I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/android/support/include -I$NDK_ROOT/sources/android/cpufeatures"
export LDFLAGS="-L$PLATFORM_PREFIX/lib"
export PKG_CONFIG_PATH=$PLATFORM_PREFIX/lib/pkgconfig
export TARGET_HOST="mipsel-linux-android"

install_lib_png
install_lib_freetype
install_lib_pixman
install_lib_ogg
install_lib_vorbis
install_lib_modplug
install_lib_mad "--enable-fpm=default"
install_lib_sdl "mips"
install_lib_mixer

# Cross compile ICU
cd icu/source

export CPPFLAGS="-I$PLATFORM_PREFIX/include -I$NDK_ROOT/sources/cxx-stl/stlport/stlport -O3 -fno-short-wchar -DU_USING_ICU_NAMESPACE=0 -DU_GNUC_UTF16_STRING=0 -fno-short-enums -nostdlib"
export LDFLAGS="-lc -Wl,-rpath-link=$PLATFORM_PREFIX/lib -L$PLATFORM_PREFIX/lib/"

chmod u+x configure
./configure --with-cross-build=$ICU_CROSS_BUILD --enable-strict=no --enable-static --enable-shared=no --enable-tests=no --enable-samples=no --enable-dyload=no --enable-tools=no --enable-extras=no --enable-icuio=no --host=$TARGET_HOST --with-data-packaging=static --prefix=$PLATFORM_PREFIX
make clean
make -j$NBPROC
make install

################################################################
# Cleanup library build folders and other stuff

cd $WORKSPACE
rm -rf freetype-*/ harfbuzz-*/ icu/ libmad-*/ libmodplug-*/ libogg-*/ libpng-*/ libvorbis-*/ pixman-*/ SDL/ SDL_mixer/ .patches-applied