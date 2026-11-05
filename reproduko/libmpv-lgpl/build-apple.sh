#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# libmpv LGPL para tvOS y visionOS (y simuladores) como xcframework.
# Requiere macOS con Xcode 16+ (SDK appletvos/xros). PLATFORM=tvos|visionos
# Base: el mismo esquema que media-kit/libmpv-darwin-build, añadiendo los SDK
# que no publica. Salida: out/apple/<plataforma>/Mpv.xcframework (+ FFmpeg).
set -euo pipefail
source "$(dirname "$0")/common.sh"
PLATFORM=${PLATFORM:-tvos}
case $PLATFORM in
  tvos) SDKS="appletvos appletvsimulator"; MIN="-mtvos-version-min=17.0" ;;
  visionos) SDKS="xros xrsimulator"; MIN="" ;; # mínimo lo fija el SDK (xros 1.0+)
  *) echo "PLATFORM=tvos|visionos"; exit 2 ;;
esac
mkdir -p src
fetch https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" src/dav1d
fetch https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_VERSION" src/ffmpeg
fetch https://github.com/libass/libass.git "$LIBASS_VERSION" src/libass
fetch https://github.com/haasn/libplacebo.git "$LIBPLACEBO_VERSION" src/libplacebo
fetch https://github.com/mpv-player/mpv.git "$MPV_VERSION" src/mpv
for SDK in $SDKS; do
  P=$PWD/out/apple/$PLATFORM/$SDK; mkdir -p "$P"; B=$PWD/build/$SDK; mkdir -p "$B"
  SYSROOT=$(xcrun --sdk $SDK --show-sdk-path); CC="$(xcrun --sdk $SDK -f clang) -arch arm64 -isysroot $SYSROOT $MIN"
  cat > "$B/cross.txt" <<CROSS
[binaries]
c = ['$(xcrun --sdk $SDK -f clang)', '-arch', 'arm64', '-isysroot', '$SYSROOT']
objc = ['$(xcrun --sdk $SDK -f clang)', '-arch', 'arm64', '-isysroot', '$SYSROOT']
ar = '$(xcrun --sdk $SDK -f ar)'
strip = '$(xcrun --sdk $SDK -f strip)'
[host_machine]
system = 'darwin'
subsystem = '${SDK}'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
CROSS
  export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
  meson setup "$B/dav1d" src/dav1d --cross-file "$B/cross.txt" --prefix="$P" --libdir=lib -Ddefault_library=static -Denable_tools=false -Denable_tests=false && ninja -C "$B/dav1d" install
  (mkdir -p "$B/ffmpeg" && cd "$B/ffmpeg" && "$OLDPWD/src/ffmpeg/configure" --prefix="$P" --enable-cross-compile --target-os=darwin --arch=arm64 \
     --cc="$CC" --sysroot="$SYSROOT" $(ffmpeg_flags) --enable-videotoolbox --enable-audiotoolbox && make -j"$(sysctl -n hw.ncpu)" install)
  # TODO: confirmar opciones de vo para tvOS/xros en mpv 0.40.
  meson setup "$B/mpv" src/mpv --cross-file "$B/cross.txt" --prefix="$P" --libdir=lib $(mpv_flags) -Dswift-build=disabled && ninja -C "$B/mpv" install
  check_lgpl "$P"
done
# Empaquetado: xcodebuild -create-xcframework -library ... por SDK (ver README).
