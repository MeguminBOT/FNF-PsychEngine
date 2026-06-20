#!/bin/sh
# ANDROID-ONLY Haxe setup for Mac/Linux (and git-bash on Windows).
# Run AFTER setup/unix.sh -- it relies on hxcpp already being installed from git.
#
# This does two Android-specific things kept out of the shared setup:
#   1. Installs the Android extension libs (storage/permissions/toasts + haptics).
#   2. Patches a hxcpp NDK compile bug (CountingSemaphore.posix.cpp lacks <errno.h>).
#
# (The native Android SDK/NDK/JDK toolchain is separate -- set that up with
#  `haxelib run lime setup android`.)
cd ..

set -e

# Wipe any leftover folder so haxelib never hits sys_remove_dir on read-only .git files.
install_git () {
	name="$1"
	url="$2"
	ref="$3" # optional git ref/commit to pin
	repo_root="$(haxelib config 2>/dev/null | tr -d '\r')"
	if [ -n "$repo_root" ] && [ -d "$repo_root/$name" ]; then
		echo "Cleaning existing $repo_root/$name ..."
		chmod -R u+w "$repo_root/$name" 2>/dev/null || true
		rm -rf "$repo_root/$name"
	fi
	haxelib git "$name" "$url" $ref --skip-dependencies
}

echo
echo "Installing Android extension libraries..."
install_git extension-androidtools https://github.com/MAJigsaw77/extension-androidtools
install_git extension-haptics      https://github.com/MAJigsaw77/extension-haptics

echo
echo "Patching hxcpp CountingSemaphore.posix.cpp (missing <errno.h>) for the Android NDK..."
repo_root="$(haxelib config 2>/dev/null | tr -d '\r')"
SEM="$repo_root/hxcpp/git/src/hx/thread/CountingSemaphore.posix.cpp"
if [ -f "$SEM" ] && ! grep -q '<errno.h>' "$SEM"; then
	sed -i.bak 's|#include <sys/time.h>|#include <sys/time.h>\n#include <errno.h>|' "$SEM"
	rm -f "$SEM.bak"
	echo "  patched."
elif [ -f "$SEM" ]; then
	echo "  already patched."
else
	echo "  WARNING: hxcpp not found -- run setup/unix.sh first."
fi

echo
echo "Finished Android setup!"
