@echo off
color 0a
cd ..
setlocal enabledelayedexpansion

if not exist ".haxelib" (
	echo Creating local haxelib repository...
	call haxelib newrepo
)

echo.
echo Installing hxcpp from git first (so no haxelib installs outdated versions)...
echo.

call :installGit hxcpp https://github.com/HaxeFoundation/hxcpp

echo.
echo Installing haxelib dependencies (--skip-dependencies, all transitive deps are manually asserted)...
echo This might take a few moments depending on your internet speed.
echo.

call haxelib install lime               8.3.2  --quiet --always --skip-dependencies
call haxelib install openfl             9.5.2  --quiet --always --skip-dependencies
call haxelib install flixel             6.1.2  --quiet --always --skip-dependencies
call haxelib install flixel-addons      4.0.1  --quiet --always --skip-dependencies
call haxelib install flixel-tools       1.5.1  --quiet --always --skip-dependencies
call haxelib install hscript            2.7.0  --quiet --always --skip-dependencies
call haxelib install hxcpp-debug-server 1.2.4  --quiet --always --skip-dependencies
call haxelib install hxdiscord_rpc      1.3.0  --quiet --always --skip-dependencies
call haxelib install hxvlc              2.2.6  --quiet --always --skip-dependencies
call haxelib install tink_core          1.26.0 --quiet --always --skip-dependencies
call haxelib install tjson              1.4.0  --quiet --always --skip-dependencies
call haxelib install thx.core           0.44.0 --quiet --always --skip-dependencies

echo.
echo Installing remaining git dependencies...
echo.

call :installGit flixel-animate   https://github.com/MaybeMaru/flixel-animate
call :installGit funkin.vis       https://github.com/FunkinCrew/funkVis
call :installGit grig.audio       https://gitlab.com/haxe-grig/grig.audio
call :installGit hxluajit         https://github.com/MAJigsaw77/hxluajit
call :installGit hxluajit-wrapper https://github.com/MAJigsaw77/hxluajit-wrapper
rem Script interpreter (replaces hscript-iris); pinned to match hmm.json.
call :installGit hscript-insanity https://github.com/MeguminBOT/hscript-insanity
rem CPU/GPU/memory metrics for the FPS counter (HARDWARE_ALLOWED); native C++, not on haxelib.
call :installGit hxhardware       https://github.com/Vortex2Oblivion/hxhardware

echo.
echo Re-asserting hxcpp = 'git' just in case and wipe any 4.3.2 version if it somehow snuck in.
for /d %%V in (".haxelib\hxcpp\*") do (
	if /i not "%%~nxV"=="git" (
		echo Removing stray hxcpp version %%~nxV ...
		attrib -r -s -h "%%V\*.*" /s /d >nul 2>&1
		rmdir /s /q "%%V"
	)
)
call haxelib set hxcpp git --always

echo.
echo Building hxcpp command-line tool from source...
if exist ".haxelib\hxcpp\git\tools\hxcpp\compile.hxml" (
	pushd ".haxelib\hxcpp\git\tools\hxcpp"
	call haxe compile.hxml
	popd
)

echo.
echo Patching funkin.vis SpectralAnalyzer for current grig.audio API...
set "SA=.haxelib\funkin,vis\git\src\funkin\vis\dsp\SpectralAnalyzer.hx"
if exist "!SA!" (
	powershell -NoProfile -Command "(Get-Content -Raw '!SA!') -replace 'vis\.makeLogGraph\(freqs, barCount \+ 1, Math\.floor\(maxDb - minDb\), range, fftN, audioClip\.audioBuffer\.sampleRate, minFreq, maxFreq\)', 'vis.makeLogGraph(freqs, barCount + 1, Math.floor(maxDb - minDb), range)' | Set-Content -NoNewline '!SA!'"
)

echo.
echo Performing a quick reformat of the repository...
echo.

call haxelib fixrepo

echo.
echo Finished!
endlocal
pause
exit /b 0

:installGit
rem %1 = library name, %2 = git url, %3 = optional git ref/commit to pin
rem Translate dots in lib name to commas for the on-disk folder (haxelib's encoding).
set "LIB_DIR=%~1"
set "LIB_DIR=!LIB_DIR:.=,!"
rem Wipe any leftover folder so haxelib never hits sys_remove_dir on read-only .git files.
if exist ".haxelib\!LIB_DIR!" (
	echo Cleaning existing .haxelib\!LIB_DIR! ...
	attrib -r -s -h ".haxelib\!LIB_DIR!\*.*" /s /d >nul 2>&1
	rmdir /s /q ".haxelib\!LIB_DIR!"
)
call haxelib git %~1 %~2 %~3 --skip-dependencies
exit /b 0
