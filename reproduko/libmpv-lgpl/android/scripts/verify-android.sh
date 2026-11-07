#!/usr/bin/env bash
# Verificación de un libmpv.so Android (receta LGPL r1). Falla (exit 1) si algo
# no se cumple. Uso: verify-android.sh <abi> <libmpv.so> <dir-con-config_components.h>
set -uo pipefail
ABI=$1 SO=$2 CFG=$3
NDK=${NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}
TC=$NDK/toolchains/llvm/prebuilt/darwin-x86_64
API=21
case $ABI in
  arm64-v8a) TRIPLE=aarch64-linux-android; MACH=AArch64 ;;
  armeabi-v7a) TRIPLE=arm-linux-androideabi; MACH=ARM ;;
  x86_64) TRIPLE=x86_64-linux-android; MACH=X86-64 ;;
  x86) TRIPLE=i686-linux-android; MACH=80386 ;;
esac
bad=0
ok() { echo "  ok   $*"; }
ko() { echo "  FALLO $*"; bad=1; }
echo "== $ABI: $SO"

# 1. Arquitectura
hdr=$("$TC/bin/llvm-readelf" -h "$SO"); grep -q "Machine:.*$MACH" <<< "$hdr" && ok "arquitectura $MACH" || ko "arquitectura"

# 2. NEEDED permitidos, sin libc++_shared
ALLOWED=" libm.so libandroid.so libOpenSLES.so libEGL.so libdl.so libc.so liblog.so libmediandk.so libz.so "
needed=$("$TC/bin/llvm-readelf" -d "$SO" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p')
for n in $needed; do [[ $ALLOWED == *" $n "* ]] || ko "NEEDED no permitido: $n"; done
ok "NEEDED: $(echo $needed)"
dyn=$("$TC/bin/llvm-readelf" -d "$SO"); grep -q TEXTREL <<< "$dyn" && ko "TEXTREL" || ok "sin TEXTREL"

# 3. Alineación 16 KB
aligns=$("$TC/bin/llvm-readelf" -lW "$SO" | awk '$1=="LOAD"{print $NF}' | sort -u)
[[ $aligns == 0x4000 ]] && ok "LOAD alineado a 0x4000" || ko "alineación LOAD: $aligns"

# 4. Exporta solo mpv_*, incluido mpv_lavc_set_java_vm
exp=$("$TC/bin/llvm-nm" -D --defined-only "$SO" | awk '{print $3}')
other=$(grep -v '^mpv_' <<< "$exp" || true)
[[ -z $other ]] && ok "exporta solo mpv_* ($(grep -c '^mpv_' <<< "$exp"))" || ko "exporta además: $(echo $other | head -c 300)"
grep -qx mpv_lavc_set_java_vm <<< "$exp" && ok "mpv_lavc_set_java_vm exportado" || ko "falta mpv_lavc_set_java_vm"
if [[ -f ${REF_SYMS:-} ]]; then
  miss=$(comm -23 <(sort -u "$REF_SYMS") <(sort -u <<< "$exp"))
  [[ -z $miss ]] && ok "superconjunto de la API de mpv 0.36 ($(wc -l < "$REF_SYMS" | tr -d ' ') símbolos)" || ko "faltan frente a 0.36: $miss"
fi

# 5. Indefinidos resueltos por los NEEDED de la API $API
SYSLIB=$TC/sysroot/usr/lib/$TRIPLE/$API
provided=$(for n in $needed; do "$TC/bin/llvm-nm" -D --defined-only "$SYSLIB/$n" 2>/dev/null | awk '{print $3}'; done | sed 's/@.*//' | sort -u)
undef=$("$TC/bin/llvm-nm" -D -u "$SO" | awk '{print $2}' | sed 's/@.*//' | sort -u)
unres=$(comm -23 <(echo "$undef") <(echo "$provided") | grep -v '^__cxa_finalize$\|^__cxa_atexit$\|^__register_atfork$' || true)
# Los débiles pueden quedar sin resolver.
weak=$("$TC/bin/llvm-nm" -D -u "$SO" | awk '$1=="w"{print $2}' | sed 's/@.*//' | sort -u)
unres=$(comm -23 <(echo "$unres" | sort -u) <(echo "$weak") || true)
[[ -z ${unres//[[:space:]]/} ]] && ok "$(wc -l <<< "$undef" | tr -d ' ') indefinidos, todos en los NEEDED de API $API" || ko "sin resolver en API $API: $(echo $unres)"

# 6. Licencia en el binario
text=$(strings -a "$SO")
n=$(grep -c 'license: LGPL version 2.1 or later' <<< "$text")
[[ $n -ge 6 ]] && ok "licencia LGPL 2.1+ en $n bibliotecas de FFmpeg" || ko "cadenas de licencia: $n"
grep -q 'license: .*GPL version [23]' <<< "$(grep -v 'LGPL' <<< "$text")" && ko "licencia GPL en el binario"
conf=$(grep -m1 -- '^--disable-autodetect' <<< "$text")
[[ -n $conf ]] && ok "configure de FFmpeg incrustado" || ko "sin configure de FFmpeg en el binario"
for f in --enable-gpl --enable-nonfree --enable-version3; do
  grep -qw -- "$f" <<< "$conf" && ko "configure con $f"
done
grep -q -- '-Dgpl=false' <<< "$text" && ok "mpv -Dgpl=false" || ko "mpv sin -Dgpl=false"
grep -q '/private/tmp\|/Users/' <<< "$text" && ko "rutas del host en el binario: $(grep -m3 '/private/tmp\|/Users/' <<< "$text")" || ok "sin rutas del host"

# 7. config.h (buffer/abuffer/buffersink/abuffersink, que usa el puente lavfi
#    de mpv, se compilan siempre en FFmpeg 8 y no tienen CONFIG_*) / config_components.h
cfg() { awk -v k="$1" '$1=="#define" && $2==k {print $3}' "$CFG/config.h" "$CFG/config_components.h"; }
want() { local k v=$1; shift; for k in "$@"; do [[ $(cfg "$k") == "$v" ]] || ko "$k != $v"; done; }
want 0 CONFIG_GPL CONFIG_VERSION3 CONFIG_NONFREE CONFIG_TRUEHD_DECODER CONFIG_MLP_DECODER CONFIG_VVC_DECODER
want 1 CONFIG_MLP_PARSER CONFIG_AC3_PARSER CONFIG_DCA_PARSER \
  CONFIG_TRUEHD_DEMUXER CONFIG_MLP_DEMUXER CONFIG_DTS_DEMUXER CONFIG_DTSHD_DEMUXER CONFIG_SPDIF_DEMUXER CONFIG_AC3_DEMUXER CONFIG_EAC3_DEMUXER \
  CONFIG_SPDIF_MUXER CONFIG_OPENSSL CONFIG_HTTPS_PROTOCOL CONFIG_TLS_PROTOCOL CONFIG_MEDIACODEC CONFIG_JNI \
  CONFIG_LIBDAV1D CONFIG_LIBXML2 CONFIG_ZLIB CONFIG_DASH_DEMUXER CONFIG_HLS_DEMUXER HAVE_PTHREADS \
  CONFIG_AC3_DECODER CONFIG_EAC3_DECODER CONFIG_DCA_DECODER CONFIG_FFV1_DECODER CONFIG_HEVC_DECODER CONFIG_H264_DECODER \
  CONFIG_AV1_DECODER CONFIG_LIBDAV1D_DECODER CONFIG_H264_MEDIACODEC_DECODER CONFIG_HEVC_MEDIACODEC_DECODER \
  CONFIG_PNG_ENCODER CONFIG_MJPEG_ENCODER
for f in overlay equalizer yadif bwdif scale format null hwdownload hwupload aresample aformat anull volume pan \
         loudnorm dynaudnorm acompressor alimiter speechnorm; do
  want 1 "CONFIG_$(tr a-z A-Z <<< "$f")_FILTER"
done
echo "  decoders=$(grep -c '^#define CONFIG_[A-Z0-9_]*_DECODER 1' "$CFG/config_components.h") demuxers=$(grep -c '^#define CONFIG_[A-Z0-9_]*_DEMUXER 1' "$CFG/config_components.h") parsers=$(grep -c '^#define CONFIG_[A-Z0-9_]*_PARSER 1' "$CFG/config_components.h") filters=$(grep -c '^#define CONFIG_[A-Z0-9_]*_FILTER 1' "$CFG/config_components.h") muxers=$(grep -c '^#define CONFIG_[A-Z0-9_]*_MUXER 1' "$CFG/config_components.h") encoders=$(grep -c '^#define CONFIG_[A-Z0-9_]*_ENCODER 1' "$CFG/config_components.h") protocols=$(grep -c '^#define CONFIG_[A-Z0-9_]*_PROTOCOL 1' "$CFG/config_components.h")"
[[ $bad == 0 ]] && echo "== $ABI: OK" || { echo "== $ABI: FALLO"; exit 1; }
