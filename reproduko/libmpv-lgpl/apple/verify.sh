#!/bin/bash
# verify.sh <segmento>: falla si la build del segmento no es la pedida.
# Afirma licencia, componentes de FFmpeg (configure apaga opciones sin avisar),
# features de mpv, enlaces (otool) y mínimo de SO. Escribe logs/<seg>/verify.txt.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
SEG=${1:?segmento}
source "$ROOT/versions.env"
P=$ROOT/stage/$SEG/reproduko/$SEG
L=$ROOT/logs/$SEG
CH=$L/config.h; CC=$L/config_components.h; MC=$ROOT/build/$SEG/mpv/config.h
OUT=$L/verify.txt; : > "$OUT"
bad=0
ok()   { echo "OK   $*" >> "$OUT"; }
fail() { echo "FALLO $*" >> "$OUT"; bad=1; }
want() { # want <fichero> <MACRO> <0|1>
  local v; v=$(awk -v m="$2" '$1=="#define" && $2==m {print $3}' "$1")
  [[ "$v" == "$3" ]] && ok "$2=$3" || fail "$2=${v:-ausente} (se esperaba $3)"
}

# 1. Licencia
for m in CONFIG_GPL CONFIG_VERSION3 CONFIG_NONFREE; do want "$CH" $m 0; done
lic=$(awk '$2=="FFMPEG_LICENSE" {sub(/^[^"]*"/,""); sub(/"$/,""); print}' "$CH")
[[ "$lic" == "LGPL version 2.1 or later" ]] && ok "FFMPEG_LICENSE=$lic" || fail "FFMPEG_LICENSE=$lic"
for lib in "$P"/lib/libav*.dylib "$P"/lib/libsw*.dylib; do
  [[ -L $lib ]] && continue
  t=$(strings -a "$lib")
  grep -q 'LGPL version 2.1 or later' <<<"$t" && ok "licencia en $(basename "$lib")" || fail "sin cadena LGPL en $(basename "$lib")"
  for s in -- '--enable-gpl' '--enable-nonfree' '--enable-version3'; do
    [[ $s == -- ]] && continue
    grep -qF -- "$s" <<<"$t" && fail "$s en $(basename "$lib")"
  done
done
grep -qF -- '-Dgpl=false' <<<"$(strings -a "$P/lib/libmpv.2.dylib")" && ok "mpv -Dgpl=false" || fail "mpv sin -Dgpl=false"
want "$MC" HAVE_GPL 0
ls "$P"/lib/pkgconfig/{x264,x265,fdk-aac,rubberband,mbedtls}.pc >/dev/null 2>&1 && fail "hay .pc GPL/mbedtls en el prefijo"

# 2. Componentes de FFmpeg
# r2: tampoco E-AC-3 (eac3) ni DTS (dca); AC-3 sí (ac3, ac3_fixed y ac3_at), y
# E-AC-3 por AudioToolbox (eac3_at), que lo decodifica el sistema.
for m in TRUEHD_DECODER MLP_DECODER VVC_DECODER EAC3_DECODER DCA_DECODER; do want "$CC" CONFIG_$m 0; done
for m in MLP_PARSER AC3_PARSER DCA_PARSER TRUEHD_DEMUXER MLP_DEMUXER DTS_DEMUXER DTSHD_DEMUXER SPDIF_DEMUXER \
         SPDIF_MUXER EAC3_DEMUXER AC3_DEMUXER DASH_DEMUXER HLS_DEMUXER HTTPS_PROTOCOL TLS_PROTOCOL HLS_PROTOCOL \
         AC3_DECODER AC3_FIXED_DECODER FFV1_DECODER HEVC_DECODER H264_DECODER AV1_DECODER LIBDAV1D_DECODER \
         AAC_AT_DECODER AC3_AT_DECODER EAC3_AT_DECODER H264_VIDEOTOOLBOX_HWACCEL HEVC_VIDEOTOOLBOX_HWACCEL \
         YADIF_FILTER BWDIF_FILTER YADIF_VIDEOTOOLBOX_FILTER LOUDNORM_FILTER DYNAUDNORM_FILTER ACOMPRESSOR_FILTER \
         ALIMITER_FILTER SPEECHNORM_FILTER EQUALIZER_FILTER OVERLAY_FILTER SCALE_FILTER FORMAT_FILTER NULL_FILTER \
         HWDOWNLOAD_FILTER HWUPLOAD_FILTER ARESAMPLE_FILTER AFORMAT_FILTER ANULL_FILTER VOLUME_FILTER PAN_FILTER \
         PNG_ENCODER MJPEG_ENCODER; do
  want "$CC" CONFIG_$m 1
done
for m in SECURETRANSPORT VIDEOTOOLBOX AUDIOTOOLBOX METAL LIBDAV1D LIBXML2 ZLIB SMALL; do want "$CH" CONFIG_$m 1; done
for m in MBEDTLS OPENSSL GNUTLS VULKAN; do want "$CH" CONFIG_$m 0; done
nd=$(grep -c '^#define CONFIG_[A-Z0-9_]*_DECODER 1' "$CC"); ndm=$(grep -c '^#define CONFIG_[A-Z0-9_]*_DEMUXER 1' "$CC")
np=$(grep -c '^#define CONFIG_[A-Z0-9_]*_PARSER 1' "$CC"); nf=$(grep -c '^#define CONFIG_[A-Z0-9_]*_FILTER 1' "$CC")
nm=$(grep -c '^#define CONFIG_[A-Z0-9_]*_MUXER 1' "$CC"); ne=$(grep -c '^#define CONFIG_[A-Z0-9_]*_ENCODER 1' "$CC")
echo "INFO decoders=$nd demuxers=$ndm parsers=$np filters=$nf muxers=$nm encoders=$ne" >> "$OUT"
(( nm == 1 )) || fail "muxers=$nm (solo spdif)"

# 3. mpv
for m in HAVE_LIBPLACEBO HAVE_UCHARDET HAVE_ICONV HAVE_ZLIB HAVE_GL HAVE_LIBASS; do want "$MC" $m 1; done
for m in HAVE_LUA HAVE_JAVASCRIPT HAVE_LIBARCHIVE HAVE_LIBBLURAY HAVE_RUBBERBAND HAVE_VULKAN HAVE_SWIFT; do want "$MC" $m 0; done
if [[ $SEG == macos-* ]]; then
  for m in HAVE_COCOA HAVE_GL_COCOA HAVE_VIDEOTOOLBOX_GL HAVE_COREAUDIO; do want "$MC" $m 1; done
  want "$MC" HAVE_AUDIOUNIT 0
else
  for m in HAVE_AUDIOUNIT HAVE_IOS_GL; do want "$MC" $m 1; done
  for m in HAVE_COCOA HAVE_VIDEOTOOLBOX_GL HAVE_COREAUDIO; do want "$MC" $m 0; done
fi

# 4. Enlaces, rutas y mínimo de SO
case $SEG in macos-*) MIN=$MACOS_MIN ;; *) MIN=$IOS_MIN ;; esac
for lib in $(find "$P/lib" -maxdepth 1 -name '*.dylib' -type f); do
  b=$(basename "$lib")
  id=$(otool -D "$lib" | tail -n +2)
  [[ $id == @rpath/* ]] && ok "id $b -> $id" || fail "id absoluto en $b: $id"
  while read -r dep; do
    case $dep in
      @rpath/*|/usr/lib/*|/System/Library/*) ;;
      *) fail "dependencia no permitida en $b: $dep" ;;
    esac
  done < <(otool -L "$lib" | tail -n +3 | awk '{print $1}')
  mo=$(vtool -show-build "$lib" | awk '/minos/ {print $2}')
  [[ $mo == "$MIN" ]] && ok "minos $b=$mo" || fail "minos $b=$mo (se esperaba $MIN)"
  strings -a "$lib" | grep -q 'claude-501\|/Users/samuel\|scratchpad' && fail "ruta de build incrustada en $b"
  arch=$(lipo -archs "$lib"); [[ $arch == "$([[ $SEG == *amd64 ]] && echo x86_64 || echo arm64)" ]] || fail "arquitectura $b=$arch"
done
grep -rl '/opt/homebrew\|/usr/local' "$P/lib/pkgconfig" >/dev/null 2>&1 && fail "rutas del host en .pc"
grep -h -- '-L/usr/local\|-L/opt/homebrew\|/usr/local/lib\|/opt/homebrew/lib' "$ROOT"/build/$SEG/*/build.ninja "$ROOT"/build/$SEG/ffmpeg/ffbuild/config.mak 2>/dev/null | grep -q . && fail "rutas del host en comandos de enlace"

# 5. API exportada (superconjunto de 0.36)
nm -gU "$P/lib/libmpv.2.dylib" | awk '{print $3}' | sed 's/^_//' | grep '^mpv_' | sort > "$L/mpv-exports.txt"
for s in mpv_create mpv_initialize mpv_command mpv_set_property mpv_get_property mpv_observe_property \
         mpv_wait_event mpv_render_context_create mpv_render_context_render mpv_render_context_free mpv_get_time_ns; do
  grep -qx "$s" "$L/mpv-exports.txt" || fail "falta export $s"
done
echo "INFO exports mpv_*=$(wc -l < "$L/mpv-exports.txt" | tr -d ' ')" >> "$OUT"

grep -c '^OK' "$OUT" | sed 's/^/OK: /'; grep '^FALLO\|^INFO' "$OUT"
[[ $bad == 0 ]] && echo "VERIFY $SEG: OK" || { echo "VERIFY $SEG: FALLO"; exit 1; }
