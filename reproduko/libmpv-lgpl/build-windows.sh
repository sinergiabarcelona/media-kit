#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# libmpv LGPL para Windows x86_64/arm64, compilación cruzada con llvm-mingw
# desde Linux (sustituye a los mpv-dev de shinchiro, que son GPL).
# Salida: out/windows-$ARCH/bin/libmpv-2.dll + .lib/.def
set -euo pipefail
source "$(dirname "$0")/common.sh"
ARCH=${ARCH:-x86_64}; T=$ARCH-w64-mingw32; P=$PWD/out/windows-$ARCH; mkdir -p src "$P"
cat > cross.txt <<CROSS
[binaries]
c = '$T-clang'
cpp = '$T-clang++'
ar = '$T-ar'
strip = '$T-strip'
windres = '$T-windres'
pkg-config = 'pkg-config'
[host_machine]
system = 'windows'
cpu_family = '$ARCH'
cpu = '$ARCH'
endian = 'little'
CROSS
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
fetch https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" src/dav1d
meson setup src/dav1d/b src/dav1d --cross-file cross.txt --prefix="$P" --libdir=lib -Denable_tools=false -Denable_tests=false && ninja -C src/dav1d/b install
fetch https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_VERSION" src/ffmpeg
(cd src/ffmpeg && ./configure --prefix="$P" --target-os=mingw32 --arch=$ARCH --cross-prefix=$T- --cc=$T-clang \
  $(ffmpeg_flags) --enable-d3d11va --enable-dxva2 --enable-mediafoundation && make -j"$(nproc)" install)
for dep in "libass $LIBASS_VERSION https://github.com/libass/libass.git" "libplacebo $LIBPLACEBO_VERSION https://github.com/haasn/libplacebo.git"; do
  set -- $dep; fetch "$3" "$2" "src/$1"
done
(cd src/libass && ./autogen.sh && ./configure --host=$T --prefix="$P" --disable-static && make -j"$(nproc)" install)
(cd src/libplacebo && git submodule update --init --depth 1 && meson setup b --cross-file ../../cross.txt --prefix="$P" --libdir=lib -Ddemos=false && ninja -C b install)
fetch https://github.com/mpv-player/mpv.git "$MPV_VERSION" src/mpv
meson setup src/mpv/b src/mpv --cross-file cross.txt --prefix="$P" --libdir=lib $(mpv_flags) -Dd3d11=enabled && ninja -C src/mpv/b install
check_lgpl "$P"
