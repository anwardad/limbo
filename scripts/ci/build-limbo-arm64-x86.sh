#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JNI_DIR="$ROOT_DIR/limbo-android-lib/src/main/jni"

: "${ANDROID_HOME:?ANDROID_HOME must point to the Android SDK}"
NDK_ROOT="${NDK_ROOT:-$ANDROID_HOME/ndk/23.1.7779620}"
[[ -x "$NDK_ROOT/ndk-build" ]] || { echo "NDK not found at $NDK_ROOT" >&2; exit 1; }

export NDK_ROOT
export NDK_ENV=linux-x86_64
export BUILD_HOST=arm64-v8a
export BUILD_GUEST=x86_64-softmmu
export USE_QEMU_VERSION=5.1.0
export USE_AAUDIO=false
export BUILD_THREADS="${BUILD_THREADS:-2}"

cd "$JNI_DIR"
echo "Building baseline Limbo native libraries: host=$BUILD_HOST guest=$BUILD_GUEST QEMU=$USE_QEMU_VERSION"
make limbo

cd "$ROOT_DIR"
gradle --no-daemon :limbo-android-x86:assembleDebug

APK_DIR="$ROOT_DIR/limbo-android-x86/build/outputs/apk/debug"
mkdir -p "$ROOT_DIR/artifacts"
find "$APK_DIR" -maxdepth 1 -type f -name '*.apk' -print -exec cp -f {} "$ROOT_DIR/artifacts/" \;
if ! compgen -G "$ROOT_DIR/artifacts/*.apk" >/dev/null; then
    echo "No debug APK was produced in $APK_DIR" >&2
    exit 1
fi

echo "Baseline APK(s) copied to $ROOT_DIR/artifacts/"
