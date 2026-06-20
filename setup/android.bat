@echo off
color 0a
rem ANDROID-ONLY Haxe setup for Windows.
rem Run AFTER setup\windows.bat -- it relies on hxcpp already being installed from git.
rem
rem This does two Android-specific things kept out of the shared setup:
rem   1. Installs the Android extension libs (storage/permissions/toasts + haptics).
rem   2. Patches a hxcpp NDK compile bug (CountingSemaphore.posix.cpp lacks ^<errno.h^>).
rem
rem (The native Android SDK/NDK/JDK toolchain is separate -- set that up with
rem  "haxelib run lime setup android".)
cd ..
setlocal enabledelayedexpansion

echo.
echo Installing Android extension libraries...
echo.

call :installGit extension-androidtools https://github.com/MAJigsaw77/extension-androidtools
call :installGit extension-haptics      https://github.com/MAJigsaw77/extension-haptics

echo.
echo Patching hxcpp CountingSemaphore.posix.cpp ^(missing ^<errno.h^>^) for the Android NDK...
set "SEM=.haxelib\hxcpp\git\src\hx\thread\CountingSemaphore.posix.cpp"
if exist "!SEM!" (
	powershell -NoProfile -Command "$f='!SEM!'; $c=Get-Content -Raw $f; if($c -notmatch '<errno.h>'){ ((Get-Content $f) -replace '#include <sys/time.h>','#include <sys/time.h>`r`n#include <errno.h>') | Set-Content $f }"
) else (
	echo   WARNING: hxcpp not found -- run setup\windows.bat first.
)

echo.
echo Finished Android setup!
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
