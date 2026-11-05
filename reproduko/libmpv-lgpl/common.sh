#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
# Funciones comunes: descarga fijada y flags LGPL de FFmpeg y mpv.
# Uso: source common.sh ; FLAVOR=tiendas|completo
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/versions.env"
FLAVOR=${FLAVOR:-tiendas}

fetch() { # fetch <url-git> <tag> <dir>
  [[ -d "$3" ]] || git clone --depth 1 --branch "$2" "$1" "$3"
}

# FFmpeg: LGPL. Nunca --enable-gpl ni --enable-nonfree. Sin x264/x265/fdk.
ffmpeg_flags() {
  local f=(
    --disable-gpl --disable-nonfree --disable-version3
    --enable-shared --disable-static --disable-programs --disable-doc
    --disable-encoders --disable-muxers --disable-devices --disable-avdevice
    --disable-postproc --enable-libdav1d --enable-network
    --disable-debug --enable-pic
  )
  if [[ "$FLAVOR" == tiendas ]]; then
    # Códecs con patentes/licencias pendientes de revisión legal: solo por
    # el decodificador del sistema (hwaccel), no por software.
    f+=(--disable-decoder=hevc --disable-decoder=ac3 --disable-decoder=eac3
        --disable-decoder=dca --disable-decoder=truehd --disable-decoder=mlp)
  fi
  printf '%s\n' "${f[@]}"
}

# mpv: -Dgpl=false fuerza LGPL y falla si alguna opción exige GPL.
mpv_flags() {
  printf '%s\n' -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false \
    -Dlua=disabled -Djavascript=disabled -Dmanpage-build=disabled
}

# Verificación: la build no puede declarar GPL.
check_lgpl() { # check_lgpl <prefix>
  local bad=0
  if grep -RIl -- '--enable-gpl\|--enable-nonfree' "$1" 2>/dev/null; then bad=1; fi
  for lib in "$1"/lib/libavcodec* "$1"/bin/avcodec*.dll; do
    [[ -e "$lib" ]] || continue
    strings "$lib" | grep -q 'enable-gpl' && { echo "GPL en $lib"; bad=1; }
  done
  if ls "$1"/lib/pkgconfig/x264.pc "$1"/lib/pkgconfig/x265.pc 2>/dev/null; then bad=1; fi
  [[ $bad == 0 ]] && echo "OK: build LGPL ($1)" || { echo "FALLO: build no LGPL"; exit 1; }
}
