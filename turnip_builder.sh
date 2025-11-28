#!/bin/bash -e

# Define variables
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'
deps="meson ninja patchelf unzip curl pip flex bison zip glslang glslangValidator"
workdir="$(pwd)/turnip_workdir"
magiskdir="$workdir/turnip_module"
ndkver="android-ndk-r28c"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="36"
# 这里用于统一化修改Mesa3D最新的稳定代码分支,这样就不需要再在后面到处改Mesa3D稳定版本号,而提升构建效率
mesa_stable_branch="25.3"

# 更改Mesa3D驱动源码地址,让其跟随的是Mesa3D的稳定代码分支,当前最新的稳定版本分支是25.1
mesasrc="https://gitlab.freedesktop.org/mesa/mesa/-/archive/$mesa_stable_branch/mesa-$mesa_stable_branch.zip"

clear

#There are 4 functions here, simply comment to disable.
#You can insert your own function and make a pull request.
run_all(){
	check_deps
	prepare_workdir
	build_lib_for_android
	port_lib_for_magisk
	port_lib_for_adrenotools
}

check_deps(){
	echo "Checking system for required Dependencies ..."
		for deps_chk in $deps;
			do
				sleep 0.25
				if command -v "$deps_chk" >/dev/null 2>&1 ; then
					echo -e "$green - $deps_chk found $nocolor"
				else
					echo -e "$red - $deps_chk not found, can't countinue. $nocolor"
					deps_missing=1
				fi;
			done

		if [ "$deps_missing" == "1" ]
			then echo "Please install missing dependencies" && exit 1
		fi

	echo "Installing python Mako dependency (if missing) ..." $'\n'
		pip install mako &> /dev/null
}

prepare_workdir(){
	echo "Preparing work directory ..." $'\n'
		mkdir -p "$workdir" && cd "$_"

	echo "Downloading android-ndk from google server ..." $'\n'
		curl https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip &> /dev/null
	echo "Exracting android-ndk ..." $'\n'
		unzip "$ndkver"-linux.zip &> /dev/null

	echo "Downloading mesa source ..." $'\n'
		curl "$mesasrc" --output mesa-main.zip &> /dev/null
	echo "Exracting mesa source ..." $'\n'
		unzip mesa-main.zip &> /dev/null
  		# 注意:这里及之后,我用$mesa_stable_branch顶替了原本的main分支,防止脚本报错
		cd mesa-$mesa_stable_branch
}


build_lib_for_android(){
	#Workaround for using Clang as c compiler instead of GCC
	mkdir -p "$workdir/bin"
	ln -sf "$ndk/clang" "$workdir/bin/cc"
	ln -sf "$ndk/clang++" "$workdir/bin/c++"
	export PATH="$workdir/bin:$ndk:$PATH"
	export CC=clang
	export CXX=clang++
	export AR=llvm-ar
	export RANLIB=llvm-ranlib
	export STRIP=llvm-strip
	export OBJDUMP=llvm-objdump
	export OBJCOPY=llvm-objcopy
	export LDFLAGS="-fuse-ld=lld"

	echo "Generating build files ..." $'\n'
		cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$ndk/ld.lld'
cpp_ld = '$ndk/ld.lld'
strip = '$ndk/aarch64-linux-android-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$ndk/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

		cat <<EOF >"native.txt"
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

		meson setup build-android-aarch64 \
			--cross-file "android-aarch64.txt" \
			--native-file "native.txt" \
			-Dbuildtype=release \
			-Dplatforms=android \
			-Dplatform-sdk-version="$sdkver" \
			-Dandroid-stub=true \
			-Dgallium-drivers= \
			-Dvulkan-drivers=freedreno \
			-Dvulkan-beta=true \
			-Dfreedreno-kmds=kgsl \
			-Db_lto=true \
   			-Db_lto_mode=thin \
			-Dstrip=true \
			-Degl=disabled &> "$workdir/meson_log"

	echo "Compiling build files ..." $'\n'
		ninja -C build-android-aarch64 &> "$workdir/ninja_log"
  
        # 注意:在Mesa稳定分支更新后,需要更改下一行的mesa-<稳定版本>的版本号
	if ! [ -a "$workdir"/mesa-$mesa_stable_branch/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so ]; then
		echo -e "$red Build failed! $nocolor" && exit 1
	fi
}

port_lib_for_magisk(){
	echo "Using patchelf to match soname ..." $'\n'
 		# 注意:在Mesa稳定分支更新后,需要更改下一行的mesa-<稳定版本>的版本号
		cp "$workdir"/mesa-$mesa_stable_branch/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"
		cd "$workdir"
		patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so
		mv libvulkan_freedreno.so vulkan.adreno.so

	echo "Prepare magisk module structure ..." $'\n'
		p1="system/vendor/lib64/hw"
		mkdir -p "$magiskdir" && cd "$_"
		mkdir -p "$p1"

		meta="META-INF/com/google/android"
		mkdir -p "$meta"

		cat <<EOF >"$meta/update-binary"
#################
# Initialization
#################
umask 022
ui_print() { echo "\$1"; }
OUTFD=\$2
ZIPFILE=\$3
. /data/adb/magisk/util_functions.sh
install_module
exit 0
EOF

		cat <<EOF >"$meta/updater-script"
#MAGISK
EOF

		cat <<EOF >"module.prop"
id=freedreno_turnip_driver
name=Turnip-Stable
version=$mesa_stable_branch
versionCode=1
author=MrMiy4mo,LFRon
description=Mesa3D Freedreno子项目的Turnip开源驱动,适配Adreno 6xx+的骁龙集成显卡 .
EOF

		cat <<EOF >"customize.sh"
set_perm_recursive $MODPATH/system 0 0 0755 0644
set_perm $MODPATH/system/vendor/lib64/hw/vulkan.adreno.so 0 0 0644
EOF

	echo "Copy necessary files from work directory ..." $'\n'
		cp "$workdir"/vulkan.adreno.so "$magiskdir"/"$p1"

	echo "Packing files in to magisk module ..." $'\n'
		zip -r "$workdir"/turnip-magisk.zip ./* &> /dev/null
		if ! [ -a "$workdir"/turnip-magisk.zip ];
			then echo -e "$red-Packing failed!$nocolor" && exit 1
			else echo -e "$green-All done, the module saved to;$nocolor" && echo "$workdir"/turnip-magisk.zip
		fi
}

port_lib_for_adrenotools(){
	libname=vulkan.freedreno.so
	echo "Using patchelf to match soname" $'\n'
		cp "$workdir"/$mesa_stable_branch/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"/$libname
		cd "$workdir"
		patchelf --set-soname $libname $libname
	echo "Preparing meta.json" $'\n'
		cat <<EOF > "meta.json"
{
	"schemaVersion": 1,
	"name": "freedreno_turnip",
	"description": "$(date)",
	"author": "MrMiy4mo, kethen, LFRon",
	"packageVersion": "1",
	"vendor": "Mesa",
	"driverVersion": "$(cat $workdir/mesa-main/VERSION)",
	"minApi": $sdkver,
	"libraryName": "$libname"
}
EOF

	zip -9 "$workdir"/turnip_adrenotools.zip $libname meta.json &> /dev/null
	if ! [ -a "$workdir"/turnip_adrenotools.zip ];
		then echo -e "$red-Packing turnip_adrenotools.zip failed!$nocolor" && exit 1
		else echo -e "$green-All done, the module saved to;$nocolor" && echo "$workdir"/turnip_adrenotools.zip
	fi
}

run_all
