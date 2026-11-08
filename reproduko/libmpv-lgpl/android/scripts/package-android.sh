#!/usr/bin/env bash
# Empaqueta full-<abi>.jar con el mismo contrato que libmpv-android-video-build
# v1.1.11 (lib/<abi>/libmediakitandroidhelper.so + lib/<abi>/libmpv.so), más
# debug-symbols-android.zip, configure-android-<abi>.txt y SHA256SUMS.txt.
# Uso: package-android.sh <dir-helper-v1.1.11>   (contiene full-<abi>/lib/<abi>/...)
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER=${1:-$ROOT/ref-v1.1.11}
NDK=${NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}
TC=$NDK/toolchains/llvm/prebuilt/darwin-x86_64
DIST=$ROOT/dist
STAGE=$ROOT/stage
rm -rf "$DIST" "$STAGE"; mkdir -p "$DIST" "$STAGE/debug"
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)
for a in "${ABIS[@]}"; do
  so=$ROOT/prefix/$a/lib/libmpv.so
  mkdir -p "$STAGE/$a/lib/$a" "$STAGE/debug/lib/$a"
  cp "$so" "$STAGE/debug/lib/$a/libmpv.so"
  "$TC/bin/llvm-strip" --strip-all -o "$STAGE/$a/lib/$a/libmpv.so" "$so"
  cp "$HELPER/full-$a/lib/$a/libmediakitandroidhelper.so" "$STAGE/$a/lib/$a/"
  # Línea de configure, versión y licencia, tal como están en el binario.
  strings -a "$so" > "$STAGE/strings-$a.txt"
  st=$STAGE/strings-$a.txt
  {
    echo "# libmpv LGPL r2, Android $a"
    echo "# mpv: $(grep -m1 -E '^mpv v0\.41' "$st")"
    echo "# FFmpeg: $(grep -m1 -E '^FFmpeg version 8\.0' "$st")"
    grep -m1 -- '^--disable-autodetect' "$st"
    echo
    echo "# mpv meson.build_options():"
    awk -F'"' '/#define CONFIGURATION /{print $2}' "$ROOT/build/$a/mpv/config.h"
    echo "# mpv features:"
    awk -F'"' '/#define FULLCONFIG /{print $2}' "$ROOT/build/$a/mpv/config.h"
    echo "# licencias:"
    grep 'license: ' "$st" | sort -u
  } > "$DIST/configure-android-$a.txt"
done
python3 -I - "$STAGE" "$DIST" "${ABIS[@]}" <<'EOF'
import os, sys, zipfile
stage, dist, abis = sys.argv[1], sys.argv[2], sys.argv[3:]
def add(z, base, rel):
    info = zipfile.ZipInfo(rel, date_time=(1981, 1, 1, 1, 1, 2))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100755 << 16
    info.create_system = 3
    with open(os.path.join(base, rel), "rb") as f:
        z.writestr(info, f.read(), compresslevel=9)
for a in abis:
    with zipfile.ZipFile(os.path.join(dist, f"full-{a}.jar"), "w") as z:
        for n in ("libmediakitandroidhelper.so", "libmpv.so"):
            add(z, os.path.join(stage, a), f"lib/{a}/{n}")
with zipfile.ZipFile(os.path.join(dist, "debug-symbols-android.zip"), "w") as z:
    for a in abis:
        add(z, os.path.join(stage, "debug"), f"lib/{a}/libmpv.so")
EOF
( cd "$DIST" && shasum -a 256 full-*.jar debug-symbols-android.zip configure-android-*.txt > SHA256SUMS.txt && md5 -r full-*.jar > MD5SUMS.txt )
cat "$DIST/SHA256SUMS.txt"
