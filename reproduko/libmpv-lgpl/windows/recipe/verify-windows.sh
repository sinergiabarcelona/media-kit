#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Verificación de libmpv-2.dll (Windows). Falla (exit 1) si algo no se cumple.
# Uso: verify-windows.sh <x86_64|aarch64> <libmpv-2.dll> <build-ffmpeg-dir> <ref-exports.txt>
set -uo pipefail
ARCH=$1 DLL=$2 FF=$3 REFEXP=$4
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); ROOT=$(cd "$HERE/.." && pwd -P)
source "$HERE/versions.env"
OBJDUMP=$ROOT/tools/$LLVM_MINGW_DIR/bin/llvm-objdump
STRINGS=$ROOT/tools/$LLVM_MINGW_DIR/bin/llvm-strings
CH=$FF/config.h CC=$FF/config_components.h
fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
want() { # want <fichero> <MACRO> <0|1>
  local v; v=$(awk -v m="$2" '$1=="#define" && $2==m {print $3}' "$1")
  [[ "$v" == "$3" ]] && ok "$2=$3" || bad "$2=${v:-?} (se esperaba $3)"
}

echo "== [$ARCH] 1. binario"
[[ -f "$DLL" ]] && ok "$(basename "$DLL") $(stat -f %z "$DLL") bytes" || { bad "no existe $DLL"; exit 1; }
fmt=$($OBJDUMP -f "$DLL" | awk '/file format/{print $NF}')
case $ARCH in x86_64) exp=coff-x86-64 ;; aarch64) exp=coff-arm64 ;; esac
[[ "$fmt" == "$exp" ]] && ok "formato $fmt" || bad "formato $fmt (se esperaba $exp)"

echo "== [$ARCH] 2. licencia (config.h y cadenas del binario)"
for m in CONFIG_GPL CONFIG_VERSION3 CONFIG_NONFREE; do want "$CH" $m 0; done
S=$($STRINGS "$DLL")
grep -q 'LGPL version 2.1 or later' <<< "$S" && ok "avcodec_license(): LGPL version 2.1 or later" || bad "falta la cadena de licencia LGPL 2.1+"
for s in -- --enable-gpl --enable-nonfree --enable-version3; do
  [[ $s == -- ]] && continue
  grep -qe "$s\\b" <<< "$S" && bad "aparece $s" || ok "sin $s"
done
grep -q -- '-Dgpl=false' <<< "$S" && ok "mpv: -Dgpl=false" || bad "mpv sin -Dgpl=false"
grep -q 'GNU General Public License\|GPL version [23] or later' <<< "$S" && bad "cadena de licencia GPL" || ok "sin cadenas GPL"

echo "== [$ARCH] 3. catálogo (config_components.h)"
# r2: tampoco E-AC-3 (eac3) ni DTS (dca); AC-3 sí (ac3 y ac3_fixed).
for m in TRUEHD_DECODER MLP_DECODER VVC_DECODER EAC3_DECODER DCA_DECODER; do want "$CC" CONFIG_$m 0; done
for m in AC3_PARSER MLP_PARSER DCA_PARSER DOLBY_E_PARSER \
         AC3_DEMUXER EAC3_DEMUXER DTS_DEMUXER DTSHD_DEMUXER TRUEHD_DEMUXER MLP_DEMUXER SPDIF_DEMUXER \
         SPDIF_MUXER \
         AC3_DECODER AC3_FIXED_DECODER FFV1_DECODER HEVC_DECODER H264_DECODER AV1_DECODER \
         LIBDAV1D_DECODER VP9_DECODER AAC_DECODER OPUS_DECODER FLAC_DECODER PRORES_DECODER \
         PNG_ENCODER MJPEG_ENCODER LJPEG_ENCODER JPEGLS_ENCODER JPEG2000_ENCODER \
         YADIF_FILTER BWDIF_FILTER LOUDNORM_FILTER DYNAUDNORM_FILTER ACOMPRESSOR_FILTER ALIMITER_FILTER \
         SPEECHNORM_FILTER OVERLAY_FILTER EQUALIZER_FILTER SCALE_FILTER FORMAT_FILTER NULL_FILTER \
         HWDOWNLOAD_FILTER HWUPLOAD_FILTER ARESAMPLE_FILTER AFORMAT_FILTER ANULL_FILTER VOLUME_FILTER PAN_FILTER \
         HTTPS_PROTOCOL TLS_PROTOCOL HTTP_PROTOCOL HLS_PROTOCOL RTMPS_PROTOCOL FTP_PROTOCOL \
         DASH_DEMUXER HLS_DEMUXER MATROSKA_DEMUXER MOV_DEMUXER \
         H264_D3D11VA_HWACCEL HEVC_D3D11VA_HWACCEL VP9_D3D11VA_HWACCEL AV1_D3D11VA_HWACCEL \
         H264_D3D12VA_HWACCEL HEVC_D3D12VA_HWACCEL H264_DXVA2_HWACCEL HEVC_DXVA2_HWACCEL; do
  want "$CC" CONFIG_$m 1
done
for m in D3D11VA D3D12VA DXVA2 SCHANNEL LIBDAV1D LIBXML2 ZLIB; do want "$CH" CONFIG_$m 1; done
for m in MBEDTLS OPENSSL GNUTLS; do want "$CH" CONFIG_$m 0; done
want "$CH" HAVE_W32THREADS 1; want "$CH" HAVE_PTHREADS 0
# buffer/buffersink/abuffer/abuffersink (puente af/vf=lavfi de mpv) se compilan
# siempre y no salen en config_components.h: se buscan por nombre.
for f in buffer buffersink abuffer abuffersink; do
  grep -qx "$f" <<< "$S" && ok "filtro $f" || bad "falta el filtro $f"
done
dec=$(grep -c '^#define CONFIG_[A-Z0-9_]*_DECODER 1' "$CC"); dmx=$(grep -c '^#define CONFIG_[A-Z0-9_]*_DEMUXER 1' "$CC")
par=$(grep -c '^#define CONFIG_[A-Z0-9_]*_PARSER 1' "$CC"); flt=$(grep -c '^#define CONFIG_[A-Z0-9_]*_FILTER 1' "$CC")
hw=$(grep -c '^#define CONFIG_[A-Z0-9_]*_HWACCEL 1' "$CC"); enc=$(grep -c '^#define CONFIG_[A-Z0-9_]*_ENCODER 1' "$CC")
mux=$(grep -c '^#define CONFIG_[A-Z0-9_]*_MUXER 1' "$CC"); pro=$(grep -c '^#define CONFIG_[A-Z0-9_]*_PROTOCOL 1' "$CC")
echo "  cuenta: decoders=$dec demuxers=$dmx parsers=$par filtros=$flt hwaccels=$hw encoders=$enc muxers=$mux protocolos=$pro"

echo "== [$ARCH] 4. importaciones (solo DLL del sistema)"
imports=$($OBJDUMP -p "$DLL" | awk '/DLL Name:/{print $3}' | sort -fu)
allowed='^(kernel32|user32|gdi32|ole32|oleaut32|advapi32|shell32|shlwapi|shcore|ws2_32|secur32|ncrypt|crypt32|bcrypt|d3d11|d3d12|dxgi|d3d9|dxva2|opengl32|avrt|dwmapi|dwrite|imm32|uxtheme|ntdll|version|winmm|mfplat|mfuuid|setupapi|cfgmgr32|api-ms-win-[a-z0-9-]+)\.dll$'
while read -r d; do
  [[ -z $d ]] && continue
  if grep -qiE "$allowed" <<< "$d"; then :; else bad "importa $d"; fi
done <<< "$imports"
grep -qiE 'libc\+\+|libunwind|winpthread|libgcc|libstdc|libssl|libcrypto|libEGL|libGLESv2' <<< "$imports" \
  && bad "importa un runtime o biblioteca no del sistema" || ok "sin libc++/libunwind/winpthread/ANGLE en las importaciones"
echo "  $(wc -l <<< "$imports" | tr -d ' ') DLL: $(tr '\n' ' ' <<< "$imports")"

echo "== [$ARCH] 5. exportaciones (API de libmpv)"
exports=$($OBJDUMP -p "$DLL" | awk '/Export Table/{f=1} f && $1 ~ /^[0-9]+$/ && $2 ~ /^0x/ {print $3}')
missing=$(comm -23 <(sort -u "$REFEXP") <(grep '^mpv_' <<< "$exports" | sort -u))
[[ -z $missing ]] && ok "exporta las $(wc -l < "$REFEXP" | tr -d ' ') funciones mpv_* de referencia" || bad "faltan: $missing"
echo "  mpv_*: $(grep -c '^mpv_' <<< "$exports"), otros: $(grep -vc '^mpv_' <<< "$exports") (pl_* de libplacebo, como hoy)"
grep -q '^mpv_get_time_ns$' <<< "$exports" && ok "mpv_get_time_ns (API 2.5)" || bad "sin mpv_get_time_ns"

echo "== [$ARCH] 6. rutas de esta máquina en el binario"
# /Users/runner/work/llvm-mingw es la ruta de CI del runtime precompilado de
# llvm-mingw (__FILE__ de libc++abi), no de esta máquina.
leak=$(grep -E '/private/tmp|/Users/|claude-501|/opt/homebrew|/usr/local' <<< "$S" | grep -v '^/Users/runner/work/llvm-mingw/' | head -5)
[[ -z $leak ]] && ok "sin rutas del host" || bad "rutas incrustadas: $leak"

[[ $fail == 0 ]] && echo "== [$ARCH] VERIFICACIÓN OK" || { echo "== [$ARCH] VERIFICACIÓN FALLIDA"; exit 1; }
