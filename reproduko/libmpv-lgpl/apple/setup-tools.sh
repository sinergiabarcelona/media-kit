#!/bin/bash
# setup-tools.sh: herramientas de build sin sudo ni Nix.
#   - meson 1.9.1 y ninja 1.13.0 en un venv propio (tools/venv)
#   - pkgconf y cmake de Homebrew (brew install pkgconf cmake), enlazados en tools/bin
#   - envoltorios clang/clang++ que añaden -ffile-prefix-map (rutas neutras)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
XC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
mkdir -p "$ROOT/tools/bin" "$ROOT/tmp"
[[ -x "$ROOT/tools/venv/bin/meson" ]] || { python3 -m venv "$ROOT/tools/venv"; "$ROOT/tools/venv/bin/pip" install -q meson==1.9.1 ninja==1.13.0; }
ln -sf "$(command -v pkgconf)" "$ROOT/tools/bin/pkg-config"
ln -sf "$(command -v cmake)" "$ROOT/tools/bin/cmake"
for c in clang clang++; do
  printf '#!/bin/sh\n# Envoltorio neutro: añade -ffile-prefix-map para no incrustar la ruta de build.\nexec %s/%s "-ffile-prefix-map=%s=/reproduko" "$@"\n' "$XC" "$c" "$ROOT" > "$ROOT/tools/bin/$c"
  chmod +x "$ROOT/tools/bin/$c"
done
echo "herramientas listas en $ROOT/tools"
