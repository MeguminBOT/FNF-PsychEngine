@echo off
color 0a
rem Build the Android APK on Windows.
rem
rem Lives in art\buildScripts\; cd's up to the repo root (where Project.xml is) so it
rem works no matter where it's launched from. Portable: no hardcoded SDK/NDK/JDK paths --
rem relies on your lime Android config ("haxelib run lime setup android", or ANDROID_SDK /
rem ANDROID_NDK_ROOT / JAVA_HOME in %USERPROFILE%\.lime\config.xml) and JAVA_HOME.
rem
rem lime's own Gradle-wrapper invocation is broken on Windows, so this lets lime do the
rem Haxe -> C++ -> arm64 link, then finishes by calling gradlew.bat directly.
rem
rem Usage: build_android.bat [debug^|release]   (default: release)
setlocal enabledelayedexpansion
cd /d "%~dp0..\.."

if not exist "Project.xml" (
	echo Could not find Project.xml at "%cd%". Keep this script in art\buildScripts\.
	exit /b 1
)

set "MODE=%~1"
if "%MODE%"=="" set "MODE=release"

if /i "%MODE%"=="debug" (
	set "LIME_FLAGS=-debug"
	set "GRADLE_TASK=assembleDebug"
	set "OUT=debug"
	set "EXPORT=export\debug\android\bin"
) else if /i "%MODE%"=="release" (
	set "LIME_FLAGS="
	set "GRADLE_TASK=assembleRelease"
	set "OUT=release"
	set "EXPORT=export\release\android\bin"
) else (
	echo Usage: build_android.bat [debug^|release]
	exit /b 1
)

set "APK_DIR=%EXPORT%\app\build\outputs\apk\%OUT%"

rem Remove any stale APK first, so a previous build's output can't be mistaken for
rem this run's (lime's gradlew step fails on Windows, so the APK-exists check below
rem must only pass when packaging actually happened this run).
if exist "%APK_DIR%\*.apk" del /q "%APK_DIR%\*.apk"

echo ^>^> haxelib run lime build android %LIME_FLAGS%
call haxelib run lime build android %LIME_FLAGS%

if exist "%APK_DIR%\*.apk" (
	echo ^>^> APK built by lime:
	dir /b "%APK_DIR%\*.apk"
	exit /b 0
)

echo ^>^> Finishing with the Gradle wrapper (%GRADLE_TASK%)
pushd "%EXPORT%"
call gradlew.bat %GRADLE_TASK% --no-daemon
set "RC=!ERRORLEVEL!"
popd
if not "!RC!"=="0" exit /b !RC!

echo ^>^> APK:
dir /b "%APK_DIR%\*.apk"
endlocal
