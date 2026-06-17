#!/bin/sh
# SETUP FOR MAC AND LINUX SYSTEMS!!!
# REMINDER THAT YOU NEED HAXE INSTALLED PRIOR TO USING THIS (MAC ONLY)
# https://haxe.org/download
cd ..

set -e

echo "Setting up local haxelib repository ..."
haxelib newrepo

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
echo "Installing hxcpp from git first (so no haxelib release of hxcpp ever lands on disk)..."
install_git hxcpp https://github.com/HaxeFoundation/hxcpp

echo
echo "Installing haxelib dependencies (--skip-dependencies, all transitive deps are pinned below)..."
echo "This might take a few moments depending on your internet speed."

haxelib install lime               8.3.2  --quiet --always --skip-dependencies
haxelib install openfl             9.5.2  --quiet --always --skip-dependencies
haxelib install flixel             6.1.2  --quiet --always --skip-dependencies
haxelib install flixel-addons      4.0.1  --quiet --always --skip-dependencies
haxelib install flixel-tools       1.5.1  --quiet --always --skip-dependencies
haxelib install hscript            2.7.0  --quiet --always --skip-dependencies
haxelib install hxcpp-debug-server 1.2.4  --quiet --always --skip-dependencies
haxelib install hxdiscord_rpc      1.3.0  --quiet --always --skip-dependencies
haxelib install hxvlc              2.3.0  --quiet --always --skip-dependencies
haxelib install tink_core          1.26.0 --quiet --always --skip-dependencies
haxelib install tjson              1.4.0  --quiet --always --skip-dependencies
haxelib install thx.core           0.44.0 --quiet --always --skip-dependencies

echo
echo "Installing remaining git dependencies..."
install_git flixel-animate   https://github.com/MaybeMaru/flixel-animate
install_git funkin.vis       https://github.com/FunkinCrew/funkVis
install_git grig.audio       https://gitlab.com/haxe-grig/grig.audio
install_git hxluajit         https://github.com/MAJigsaw77/hxluajit
install_git hxluajit-wrapper https://github.com/MAJigsaw77/hxluajit-wrapper
# Script interpreter (replaces hscript-iris); pinned to match hmm.json.
install_git hscript-insanity https://github.com/MeguminBOT/hscript-insanity
# CPU/GPU/memory metrics for the FPS counter (HARDWARE_ALLOWED); native C++, not on haxelib.
install_git hxhardware       https://github.com/Vortex2Oblivion/hxhardware

echo
echo "Re-asserting hxcpp = git and wiping any release version folders that snuck in..."
repo_root="$(haxelib config 2>/dev/null | tr -d '\r')"
if [ -n "$repo_root" ] && [ -d "$repo_root/hxcpp" ]; then
	for v in "$repo_root/hxcpp"/*; do
		[ -d "$v" ] || continue
		name="$(basename "$v")"
		if [ "$name" != "git" ]; then
			echo "Removing stray hxcpp version $name ..."
			chmod -R u+w "$v" 2>/dev/null || true
			rm -rf "$v"
		fi
	done
fi
haxelib set hxcpp git --always

echo
echo "Building hxcpp command-line tool from source..."
if [ -f "$repo_root/hxcpp/git/tools/hxcpp/compile.hxml" ]; then
	(cd "$repo_root/hxcpp/git/tools/hxcpp" && haxe compile.hxml)
fi

echo
echo "Patching funkin.vis SpectralAnalyzer for current grig.audio API..."
SA="$repo_root/funkin,vis/git/src/funkin/vis/dsp/SpectralAnalyzer.hx"
if [ -f "$SA" ]; then
	sed -i.bak 's|vis\.makeLogGraph(freqs, barCount + 1, Math\.floor(maxDb - minDb), range, fftN, audioClip\.audioBuffer\.sampleRate, minFreq, maxFreq)|vis.makeLogGraph(freqs, barCount + 1, Math.floor(maxDb - minDb), range)|' "$SA"
	rm -f "$SA.bak"
fi

echo
echo "Finished!"
