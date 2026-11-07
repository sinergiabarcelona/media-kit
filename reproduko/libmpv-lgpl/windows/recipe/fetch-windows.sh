#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Descarga, verifica (sha256) y prepara fuentes y herramientas para
# build-windows.sh. Deja: dl/, src/, tools/{llvm-mingw,7zip,venv,host}.
# Uso: fetch-windows.sh [ROOT]
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${1:-$(cd "$HERE/.." && pwd -P)}
source "$HERE/versions.env"
DL=$ROOT/dl SRC=$ROOT/src TOOLS=$ROOT/tools
mkdir -p "$DL" "$SRC" "$TOOLS/host/bin"

# 1. Tarballs (URL en sources.urls, hash en sources.sha256).
grep -E '^https://' "$HERE/sources.urls" | grep -v raw.githubusercontent | while read -r u; do
  f=$(basename "$u"); [[ $f == v$MPV_VERSION.tar.gz ]] && f=mpv-$MPV_VERSION.tar.gz
  [[ -f "$DL/$f" ]] || curl -fsSL -o "$DL/$f" "$u"
done
(cd "$DL" && grep -v angle-headers "$HERE/sources.sha256" | shasum -a 256 -c --quiet)

# 2. libplacebo con submódulos fijados.
if [[ ! -d "$DL/libplacebo-git" ]]; then
  git clone -q --depth 1 --branch "$LIBPLACEBO_VERSION" https://code.videolan.org/videolan/libplacebo.git "$DL/libplacebo-git"
  git -C "$DL/libplacebo-git" submodule update -q --init --depth 1 \
    3rdparty/Vulkan-Headers 3rdparty/fast_float 3rdparty/glad 3rdparty/jinja 3rdparty/markupsafe
fi
[[ $(git -C "$DL/libplacebo-git" rev-parse HEAD) == cee9b076f2c63104ccfd497fa79c39a867293ec4 ]]

# 3. Cabeceras EGL/KHR de ANGLE en un commit fijo.
mkdir -p "$DL/angle-headers/include/EGL" "$DL/angle-headers/include/KHR"
for f in EGL/egl.h EGL/eglext.h EGL/eglext_angle.h EGL/eglplatform.h KHR/khrplatform.h; do
  [[ -f "$DL/angle-headers/include/$f" ]] || curl -fsSL -o "$DL/angle-headers/include/$f" \
    "https://raw.githubusercontent.com/google/angle/$ANGLE_HEADERS_COMMIT/include/$f"
done
[[ -f "$DL/angle-headers/LICENSE" ]] || curl -fsSL -o "$DL/angle-headers/LICENSE" \
  "https://raw.githubusercontent.com/google/angle/$ANGLE_HEADERS_COMMIT/LICENSE"
echo "$ANGLE_HEADERS_COMMIT" > "$DL/angle-headers/COMMIT"
(cd "$DL" && grep angle-headers "$HERE/sources.sha256" | shasum -a 256 -c --quiet)

# 4. Herramientas: llvm-mingw, 7-Zip, meson/ninja (venv), nasm y pkgconf propios.
[[ -d "$TOOLS/$LLVM_MINGW_DIR" ]] || tar -xJf "$DL/$LLVM_MINGW_DIR.tar.xz" -C "$TOOLS"
[[ -x "$TOOLS/7zip/7zz" ]] || { mkdir -p "$TOOLS/7zip"; tar -xJf "$DL/7z2604-mac.tar.xz" -C "$TOOLS/7zip"; }
[[ -x "$TOOLS/venv/bin/meson" ]] || { python3 -m venv "$TOOLS/venv"; \
  "$TOOLS/venv/bin/pip" install -q meson==1.12.1 ninja==1.13.2 jinja2==3.1.6 markupsafe==3.0.4; }
H=$TOOLS/host; HB=$ROOT/build/host; mkdir -p "$HB"
if [[ ! -x "$H/bin/nasm" ]]; then
  tar -xJf "$DL/nasm-2.16.03.tar.xz" -C "$HB"
  (cd "$HB/nasm-2.16.03" && env -i PATH=/usr/bin:/bin HOME="$HOME" CC=/usr/bin/clang ./configure --prefix="$H" >/dev/null \
    && env -i PATH=/usr/bin:/bin make -j8 nasm ndisasm >/dev/null && cp nasm ndisasm "$H/bin/")
fi
if [[ ! -x "$H/bin/pkgconf" ]]; then
  tar -xJf "$DL/pkgconf-2.5.1.tar.xz" -C "$HB"
  (cd "$HB/pkgconf-2.5.1" && env -i PATH="$TOOLS/venv/bin:/usr/bin:/bin" HOME="$HOME" CC=/usr/bin/clang \
     meson setup b --prefix="$H" -Dtests=disabled >/dev/null \
   && env -i PATH="$TOOLS/venv/bin:/usr/bin:/bin" ninja -C b install >/dev/null)
  ln -sf pkgconf "$H/bin/pkg-config"
fi
# cmake (solo para uchardet): el del sistema, enlazado uno a uno; nada más de Homebrew.
[[ -e "$H/bin/cmake" ]] || ln -sf "$(command -v cmake)" "$H/bin/cmake"

# 5. Fuentes extraídas y parcheadas.
x() { [[ -d "$SRC/$2" ]] || tar -xf "$DL/$1" -C "$SRC"; }
x ffmpeg-$FFMPEG_VERSION.tar.xz ffmpeg-$FFMPEG_VERSION
x mpv-$MPV_VERSION.tar.gz mpv-$MPV_VERSION
x libass-$LIBASS_VERSION.tar.xz libass-$LIBASS_VERSION
x freetype-$FREETYPE_VERSION.tar.xz freetype-$FREETYPE_VERSION
x harfbuzz-$HARFBUZZ_VERSION.tar.xz harfbuzz-$HARFBUZZ_VERSION
x fribidi-$FRIBIDI_VERSION.tar.xz fribidi-$FRIBIDI_VERSION
x dav1d-$DAV1D_VERSION.tar.xz dav1d-$DAV1D_VERSION
x libxml2-$LIBXML2_VERSION.tar.xz libxml2-$LIBXML2_VERSION
x uchardet-$UCHARDET_VERSION.tar.xz uchardet-$UCHARDET_VERSION
x libiconv-$LIBICONV_VERSION.tar.gz libiconv-$LIBICONV_VERSION
x zlib-$ZLIB_VERSION.tar.xz zlib-$ZLIB_VERSION
if [[ ! -f "$SRC/ffmpeg-$FFMPEG_VERSION/.patched" ]]; then
  for p in "$HERE"/patches/ffmpeg-*.patch; do patch -s -d "$SRC/ffmpeg-$FFMPEG_VERSION" -p1 --forward < "$p"; done
  touch "$SRC/ffmpeg-$FFMPEG_VERSION/.patched"
fi
[[ -d "$SRC/libplacebo" ]] || { cp -R "$DL/libplacebo-git" "$SRC/libplacebo"; rm -rf "$SRC/libplacebo/.git"; }
echo "OK fuentes en $SRC, herramientas en $TOOLS"
