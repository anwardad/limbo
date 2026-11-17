#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JNI_DIR="$ROOT_DIR/limbo-android-lib/src/main/jni"
PATCH_DIR="$JNI_DIR/patches"
DOWNLOAD_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/limbo-native-sources"
mkdir -p "$DOWNLOAD_DIR" "$JNI_DIR"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar is required" >&2; exit 1; }
command -v patch >/dev/null || { echo "patch is required" >&2; exit 1; }

fetch_extract() {
    local url="$1" archive="$2" destination="$3"
    if [[ -d "$destination" && -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        echo "Keeping existing source directory: $destination"
        return
    fi
    mkdir -p "$destination"
    echo "Downloading $url"
    curl --fail --location --retry 5 --retry-delay 2 "$url" --output "$DOWNLOAD_DIR/$archive"
    tar -tf "$DOWNLOAD_DIR/$archive" >/dev/null
    tar -xf "$DOWNLOAD_DIR/$archive" --strip-components=1 -C "$destination"
}

apply_patch_once() {
    local source_dir="$1" patch_file="$2"
    if [[ ! -f "$patch_file" ]]; then
        echo "Missing patch: $patch_file" >&2
        exit 1
    fi
    if patch --silent --reverse --dry-run -p1 -d "$source_dir" < "$patch_file" >/dev/null 2>&1; then
        echo "Patch already applied: $(basename "$patch_file")"
    else
        echo "Applying $(basename "$patch_file")"
        patch --batch --forward -p1 -d "$source_dir" < "$patch_file"
    fi
}

fetch_extract "https://download.qemu.org/qemu-5.1.0.tar.xz" "qemu-5.1.0.tar.xz" "$JNI_DIR/qemu"
fetch_extract "https://download.gnome.org/sources/glib/2.56/glib-2.56.1.tar.xz" "glib-2.56.1.tar.xz" "$JNI_DIR/glib"
fetch_extract "https://sourceware.org/pub/libffi/libffi-3.3.tar.gz" "libffi-3.3.tar.gz" "$JNI_DIR/libffi"
fetch_extract "https://www.cairographics.org/releases/pixman-0.40.0.tar.gz" "pixman-0.40.0.tar.gz" "$JNI_DIR/pixman"
fetch_extract "https://www.libsdl.org/release/SDL2-2.0.8.tar.gz" "SDL2-2.0.8.tar.gz" "$JNI_DIR/SDL2"

apply_patch_once "$JNI_DIR/qemu" "$PATCH_DIR/qemu-5.1.0.patch"
apply_patch_once "$JNI_DIR/glib" "$PATCH_DIR/glib-2.56.1.patch"
apply_patch_once "$JNI_DIR/SDL2" "$PATCH_DIR/sdl2-2.0.8.patch"

for required in \
    "$JNI_DIR/qemu/configure" \
    "$JNI_DIR/glib/autogen.sh" \
    "$JNI_DIR/libffi/configure" \
    "$JNI_DIR/pixman/configure" \
    "$JNI_DIR/SDL2/Android.mk"; do
    [[ -e "$required" ]] || { echo "Expected source file missing: $required" >&2; exit 1; }
done

echo "Limbo native source trees are prepared under $JNI_DIR"
