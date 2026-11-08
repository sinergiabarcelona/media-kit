#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Empaqueta libmpv-2.dll en el formato que consume
# libs/windows/media_kit_libs_windows_video/windows/CMakeLists.txt del fork:
#   mpv-dev-<arch>-<rev>.7z
#     include/mpv/{client,render,render_gl,stream_cb}.h
#     libmpv.dll.a
#     libmpv-2.dll
# (la misma estructura que mpv-dev-x86_64-20241021-git-0f78584.7z).
# Uso: package-windows.sh <x86_64|aarch64> [rev]
set -euo pipefail
ARCH=$1 REV=${2:-lgpl-r2}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ROOT=$(cd "$HERE/.." && pwd -P)
source "$HERE/versions.env"
BIN=$ROOT/tools/$LLVM_MINGW_DIR/bin
Z=$ROOT/tools/7zip/7zz
B=$ROOT/build/$ARCH
DIST=$ROOT/dist
STG=$ROOT/build/pkg-$ARCH
NAME=mpv-dev-$ARCH-$REV
# Fecha fija en el paquete (publicación de mpv v0.41.0) para que sea reproducible.
STAMP=202512211917.10
rm -rf "$STG"; mkdir -p "$STG/include/mpv" "$DIST"

cp "$B/mpv/libmpv-2.dll" "$STG/libmpv-2.dll"
"$BIN/llvm-strip" --strip-all "$STG/libmpv-2.dll"
cp "$B/mpv/libmpv.dll.a" "$STG/libmpv.dll.a"
for h in client render render_gl stream_cb; do
  cp "$ROOT/src/mpv-$MPV_VERSION/include/mpv/$h.h" "$STG/include/mpv/"
done
find "$STG" -exec touch -h -t $STAMP {} +

rm -f "$DIST/$NAME.7z"
(cd "$STG" && "$Z" a -t7z -mx=9 -m0=lzma2 -mf=BCJ -mtc=off -mta=off -bso0 -bsp0 \
   "$DIST/$NAME.7z" include libmpv.dll.a libmpv-2.dll)

# Símbolos: la DLL sin quitar (tabla de símbolos COFF) para llvm-symbolizer.
DBG=$ROOT/build/dbg-$ARCH; rm -rf "$DBG"; mkdir -p "$DBG"
cp "$B/mpv/libmpv-2.dll" "$DBG/libmpv-2.unstripped.dll"
touch -t $STAMP "$DBG/libmpv-2.unstripped.dll"
rm -f "$DIST/debug-windows-$ARCH-$REV.zip"
(cd "$DBG" && "$Z" a -tzip -mx=9 -bso0 -bsp0 "$DIST/debug-windows-$ARCH-$REV.zip" libmpv-2.unstripped.dll)

# Línea de configure, opciones de mpv y cross-files (rutas sustituidas).
CFG=$DIST/configure-windows-$ARCH.txt
P=$ROOT/prefix/$ARCH/opt/reproduko-libmpv
{
  echo "# libmpv $REV, Windows $ARCH"
  echo "# FFmpeg $FFMPEG_VERSION: avcodec_configuration()"
  sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"$/\1/p' "$B/ffmpeg/config.h"
  echo
  echo "# FFmpeg: avcodec_license()"
  sed -n 's/^#define FFMPEG_LICENSE "\(.*\)"$/\1/p' "$B/ffmpeg/config.h"
  echo
  echo "# mpv $MPV_VERSION: Configuration"
  sed -n 's/^#define CONFIGURATION "\(.*\)"$/\1/p' "$B/mpv/config.h"
  echo
  echo "# mpv: features"
  grep -m1 'List of enabled features' "$B/mpv/meson-logs/meson-log.txt" | sed 's/.*features: //'
  for f in "reproduko-windows-$ARCH.ini" "reproduko-windows-$ARCH-mpv.ini"; do
    echo; echo "# meson cross-file $f (\$PREFIX = <DESTDIR>/opt/reproduko-libmpv)"
    sed "s|$P|\$PREFIX|g; s|$ROOT|\$ROOT|g" "$B/xdg/meson/cross/$f"
  done
} > "$CFG"
echo "OK $DIST/$NAME.7z"
