#!/usr/bin/env bash
# Compara los componentes de FFmpeg de hoy (v1.1.11, símbolos ff_* exportados)
# con los de la build nueva (config_components.h). Uso: compare-today.sh <libmpv-v1.1.11.so> <config_components.h>
set -uo pipefail
T=${NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}/toolchains/llvm/prebuilt/darwin-x86_64/bin
old=$("$T/llvm-nm" -D --defined-only "$1" | awk '{print $3}')
for k in decoder demuxer parser filter muxer encoder protocol bsf hwaccel; do
  K=$(tr a-z A-Z <<< "$k")
  o=$(grep "^ff_.*_$k\$" <<< "$old" | sed "s/^ff_//; s/_$k\$//" | sort -u)
  n=$(grep "^#define CONFIG_.*_$K 1" "$2" | awk '{print $2}' | sed "s/^CONFIG_//; s/_$K\$//" | tr A-Z a-z | sort -u)
  [[ $k == bsf ]] && n=$(grep "^#define CONFIG_.*_BSF 1" "$2" | awk '{print $2}' | sed "s/^CONFIG_//; s/_BSF\$//" | tr A-Z a-z | sort -u)
  lost=$(comm -23 <(echo "$o") <(echo "$n") | grep . | tr '\n' ' ')
  gained=$(comm -13 <(echo "$o") <(echo "$n") | grep . | wc -l | tr -d ' ')
  printf '%-9s hoy=%-4s nuevo=%-4s nuevos=%-4s perdidos: %s\n' "$k" "$(grep -c . <<< "$o")" "$(grep -c . <<< "$n")" "$gained" "${lost:-ninguno}"
done
