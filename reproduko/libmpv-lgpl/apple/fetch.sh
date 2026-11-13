#!/bin/bash
# fetch.sh: descarga las fuentes fijadas, comprueba sha256 (y commits de
# libplacebo y sus submódulos), las extrae en src/ y aplica patches/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
source "$ROOT/versions.env"
DL=$ROOT/dl; SRC=$ROOT/src; mkdir -p "$DL"
get() { [[ -f "$DL/$1" ]] || curl -sSfL --retry 3 -o "$DL/$1" "$2"; }
get ffmpeg-$FFMPEG_VERSION.tar.xz https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz
get mpv-$MPV_VERSION.tar.gz https://github.com/mpv-player/mpv/archive/refs/tags/v$MPV_VERSION.tar.gz
get libass-$LIBASS_VERSION.tar.xz https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.xz
get freetype-$FREETYPE_VERSION.tar.xz https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz
get harfbuzz-$HARFBUZZ_VERSION.tar.xz https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz
get fribidi-$FRIBIDI_VERSION.tar.xz https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz
get dav1d-$DAV1D_VERSION.tar.bz2 https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.bz2
get libxml2-$LIBXML2_VERSION.tar.xz https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-$LIBXML2_VERSION.tar.xz
get uchardet-$UCHARDET_VERSION.tar.xz https://www.freedesktop.org/software/uchardet/releases/uchardet-$UCHARDET_VERSION.tar.xz
get libpng-$LIBPNG_VERSION.tar.gz https://github.com/pnggroup/libpng/archive/refs/tags/v$LIBPNG_VERSION.tar.gz
( cd "$DL" && shasum -a 256 -c "$ROOT/sources.sha256" )
# libplacebo: git, por commit, con submódulos (los tarballs de upstream no los traen)
if [[ ! -d "$DL/libplacebo-git" ]]; then
  git clone -q --depth 1 --branch v$LIBPLACEBO_VERSION --recurse-submodules --shallow-submodules \
    https://code.videolan.org/videolan/libplacebo.git "$DL/libplacebo-git"
fi
[[ $(git -C "$DL/libplacebo-git" rev-parse HEAD) == "$LIBPLACEBO_COMMIT" ]] || { echo "libplacebo: commit inesperado"; exit 1; }
diff <(git -C "$DL/libplacebo-git" submodule status | awk '{sub(/^[-+ ]/,"",$1); print $2, $1}' | sort) <(sort "$ROOT/libplacebo-submodules.txt") \
  || { echo "libplacebo: submódulos inesperados"; exit 1; }

rm -rf "$SRC"; mkdir -p "$SRC"
for f in ffmpeg-$FFMPEG_VERSION.tar.xz mpv-$MPV_VERSION.tar.gz libass-$LIBASS_VERSION.tar.xz freetype-$FREETYPE_VERSION.tar.xz \
         harfbuzz-$HARFBUZZ_VERSION.tar.xz fribidi-$FRIBIDI_VERSION.tar.xz dav1d-$DAV1D_VERSION.tar.bz2 \
         libxml2-$LIBXML2_VERSION.tar.xz uchardet-$UCHARDET_VERSION.tar.xz libpng-$LIBPNG_VERSION.tar.gz; do
  tar xf "$DL/$f" -C "$SRC"
done
mkdir -p "$SRC/libplacebo-$LIBPLACEBO_VERSION"
( cd "$DL/libplacebo-git" && tar --exclude=.git -cf - . ) | tar xf - -C "$SRC/libplacebo-$LIBPLACEBO_VERSION"
for p in ffmpeg-fix-dash-base-url-escape ffmpeg-fix-hls-mp4-seek ffmpeg-fix-ios-hdr-texture ffmpeg-fix-vp9-hwaccel-8.0 ffmpeg-fix-yadif-videotoolbox-autorelease ffmpeg-fix-visionos-vt-metal; do
  patch -d "$SRC/ffmpeg-$FFMPEG_VERSION" -p1 -s --no-backup-if-mismatch < "$ROOT/patches/$p.patch"
done
for p in mpv-darwin-no-host-sdk mpv-audiounit-shared-session mpv-cocoa-without-swift mpv-coreaudio-channelmap-macos27; do
  patch -d "$SRC/mpv-$MPV_VERSION" -p1 -s --no-backup-if-mismatch < "$ROOT/patches/$p.patch"
done
echo "fuentes listas en $SRC"
