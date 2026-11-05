#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# libmpv LGPL para Linux x86_64/arm64 (Ubuntu 22.04+). Salida: out/linux-$ARCH
set -euo pipefail
source "$(dirname "$0")/common.sh"
ARCH=${ARCH:-$(uname -m)}; P=$PWD/out/linux-$ARCH; mkdir -p src "$P"
export PKG_CONFIG_PATH=$P/lib/pkgconfig
fetch https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" src/dav1d
meson setup src/dav1d/b src/dav1d --prefix="$P" --libdir=lib -Denable_tools=false -Denable_tests=false && ninja -C src/dav1d/b install
fetch https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_VERSION" src/ffmpeg
(cd src/ffmpeg && ./configure --prefix="$P" $(ffmpeg_flags) --enable-vaapi --enable-vdpau && make -j"$(nproc)" install)
fetch https://github.com/libass/libass.git "$LIBASS_VERSION" src/libass
(cd src/libass && ./autogen.sh && ./configure --prefix="$P" --disable-static && make -j"$(nproc)" install)
fetch https://github.com/haasn/libplacebo.git "$LIBPLACEBO_VERSION" src/libplacebo
(cd src/libplacebo && git submodule update --init --depth 1 && meson setup b --prefix="$P" --libdir=lib -Ddemos=false && ninja -C b install)
fetch https://github.com/mpv-player/mpv.git "$MPV_VERSION" src/mpv
meson setup src/mpv/b src/mpv --prefix="$P" --libdir=lib $(mpv_flags) && ninja -C src/mpv/b install
check_lgpl "$P"
