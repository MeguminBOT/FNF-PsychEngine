#!/bin/sh
# Build the Android APK.
#
# Lives in art/buildScripts/; cd's up to the repo root (where Project.xml is) so it
# works no matter where it's launched from. Portable: no hardcoded SDK/NDK/JDK paths --
# relies on your lime Android config (run `haxelib run lime setup android` once, or set
# ANDROID_SDK / ANDROID_NDK_ROOT / JAVA_HOME in ~/.lime/config.xml) and on JAVA_HOME.
#
# Why this exists: `lime build android` on Windows currently dies invoking the Gradle
# wrapper ("'gradlew' is not recognized"). This script lets lime do the Haxe -> C++ ->
# arm64 link, then finishes packaging by calling the Gradle wrapper directly. On Linux/
# macOS lime completes everything itself and the wrapper step is skipped.
#
# Usage: ./build_android.sh [debug|release]   (default: release)
set -e
cd "$(dirname "$0")/../.."

if [ ! -f Project.xml ]; then
	echo "Could not find Project.xml at $(pwd). Keep this script in art/buildScripts/." >&2
	exit 1
fi

MODE="${1:-release}"
case "$MODE" in
	debug)   LIME_FLAGS="-debug"; GRADLE_TASK="assembleDebug";   OUT="debug";   EXPORT="export/debug/android/bin" ;;
	release) LIME_FLAGS="";       GRADLE_TASK="assembleRelease"; OUT="release"; EXPORT="export/release/android/bin" ;;
	*) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac

APK_DIR="$EXPORT/app/build/outputs/apk/$OUT"

# Remove any stale APK first, so a previous build's output can't be mistaken for
# this run's (lime's gradlew step fails on Windows, so the APK-exists check below
# must only pass when packaging actually happened this run).
rm -f "$APK_DIR"/*.apk 2>/dev/null || true

echo ">> haxelib run lime build android $LIME_FLAGS"
# Don't abort if lime's own gradlew invocation fails (Windows); we finish below.
haxelib run lime build android $LIME_FLAGS || true

# If lime already produced the APK (Linux/macOS), we're done.
if ls "$APK_DIR"/*.apk >/dev/null 2>&1; then
	echo ">> APK built by lime:"
	ls -1 "$APK_DIR"/*.apk
	exit 0
fi

echo ">> Finishing with the Gradle wrapper ($GRADLE_TASK)"
cd "$EXPORT"
# Use the POSIX wrapper -- works on Linux, macOS and git-bash on Windows alike.
# (Native cmd.exe users should run build_android.bat instead.)
chmod +x ./gradlew 2>/dev/null || true
./gradlew "$GRADLE_TASK" --no-daemon

echo ">> APK:"
ls -1 "app/build/outputs/apk/$OUT"/*.apk
