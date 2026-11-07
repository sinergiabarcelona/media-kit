#!/bin/bash
# package-apple.sh <macos|ios> [etiqueta]
# Convierte las dylib de stage/<segmento> en <Nombre>.framework (id
# @rpath/<Nombre>.framework/[Versions/A/]<Nombre>), las une en xcframework y
# empaqueta el tar.gz con el mismo contrato que media-kit/libmpv-darwin-build:
#   libmpv-xcframeworks_<etiqueta>_<os>-universal-video-full/<Nombre>.xcframework
# macos: macos-arm64 + macos-amd64 (lipo) -> macos-arm64_x86_64
# ios:   ios-arm64 -> ios-arm64 ; iossimulator-arm64 + iossimulator-amd64 -> ios-arm64_x86_64-simulator
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
OS=${1:?macos|ios}; TAG=${2:-lgpl-r1}
DIST=$ROOT/dist; OUT=$ROOT/out/$OS; DSYM=$ROOT/out/dsym-$OS
rm -rf "$OUT" "$DSYM"; mkdir -p "$OUT" "$DSYM" "$DIST"

# Framework -> nombre de la dylib sin versión (enlace simbólico en lib/)
LIBS="Ass:libass Avcodec:libavcodec Avfilter:libavfilter Avformat:libavformat Avutil:libavutil
Dav1d:libdav1d Freetype:libfreetype Fribidi:libfribidi Harfbuzz:libharfbuzz Mpv:libmpv Placebo:libplacebo
Png16:libpng16 Swresample:libswresample Swscale:libswscale Uchardet:libuchardet Xml2:libxml2"

case $OS in
  macos) GROUPS_="macos:macos-arm64,macos-amd64" ; PLIST_KEY=LSMinimumSystemVersion ;;
  ios)   GROUPS_="ios:ios-arm64 iossimulator:iossimulator-arm64,iossimulator-amd64" ; PLIST_KEY=MinimumOSVersion ;;
  *) exit 2 ;;
esac

plist() { # plist <fw> <min> <dest>
  cat > "$3" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
   <dict>
      <key>CFBundleExecutable</key>
      <string>$1</string>
      <key>CFBundleIdentifier</key>
      <string>com.github.media-kit.$1</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1.0</string>
      <key>$PLIST_KEY</key>
      <string>$2</string>
   </dict>
</plist>
EOF
  plutil -convert binary1 "$3"
}

for G in $GROUPS_; do
  KIND=${G%%:*}; SEGS=${G#*:}; FWD=$OUT/$KIND; mkdir -p "$FWD"
  # mapa id original -> framework (igual en todos los segmentos del grupo)
  MAPF=$OUT/idmap-$KIND.txt; : > "$MAPF"
  first=${SEGS%%,*}
  for e in $LIBS; do
    fw=${e%%:*}; ln=${e#*:}
    real=$(cd "$ROOT/stage/$first/reproduko/$first/lib" && python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$ln.dylib")
    echo "$(otool -D "$real" | tail -n +2) $fw" >> "$MAPF"
  done
  for e in $LIBS; do
    fw=${e%%:*}; ln=${e#*:}
    inputs=()
    for s in ${SEGS//,/ }; do
      f="$ROOT/stage/$s/reproduko/$s/lib/$ln.dylib"
      [[ -e $f ]] || { echo "falta $f"; exit 1; }
      inputs+=("$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$f")")
    done
    if [[ $OS == macos ]]; then
      D="$FWD/$fw.framework/Versions/A"; BIN="$D/$fw"; NEWID="@rpath/$fw.framework/Versions/A/$fw"; RES="$D/Resources"
    else
      D="$FWD/$fw.framework"; BIN="$D/$fw"; NEWID="@rpath/$fw.framework/$fw"; RES="$D"
    fi
    mkdir -p "$D" "$RES"
    if (( ${#inputs[@]} > 1 )); then lipo -create "${inputs[@]}" -output "$BIN"; else cp "${inputs[0]}" "$BIN"; fi
    # símbolos de depuración (mapa de .o) antes de quitar los locales
    dsymutil "$BIN" -o "$DSYM/$KIND/$fw.framework.dSYM" 2>/dev/null || true
    strip -S -x "$BIN" 2>/dev/null
    install_name_tool -id "$NEWID" "$BIN" 2>/dev/null
    for dep in $(otool -L "$BIN" | grep $'^\t' | awk '{print $1}' | sort -u); do
      case $dep in
        /usr/lib/*|/System/Library/*) continue ;;
        "$NEWID") continue ;;
      esac
      t=$(awk -v d="$dep" '$1==d {print $2}' "$MAPF")
      [[ -n $t ]] || { echo "dependencia sin framework en $fw: $dep"; exit 1; }
      if [[ $OS == macos ]]; then nd="@rpath/$t.framework/Versions/A/$t"; else nd="@rpath/$t.framework/$t"; fi
      install_name_tool -change "$dep" "$nd" "$BIN" 2>/dev/null
    done
    # mínimo de SO más bajo entre arquitecturas
    MIN=$(for a in $(lipo -archs "$BIN"); do vtool -arch $a -show-build "$BIN" | awk '/minos/ {print $2}'; done | sort -V | head -1)
    plist "$fw" "$MIN" "$RES/Info.plist"
    if [[ $fw == Mpv ]]; then
      mkdir -p "$D/Headers" "$D/Modules"
      for h in client.h render.h render_gl.h stream_cb.h; do
        cp "$ROOT/stage/$first/reproduko/$first/include/mpv/$h" "$D/Headers/"
        echo "#import \"$h\"" >> "$D/Headers/Mpv.h"
      done
      printf 'framework module Mpv {\n  umbrella header "Mpv.h"\n  export *\n  module * { export * }\n}\n' > "$D/Modules/module.modulemap"
    fi
    if [[ $OS == macos ]]; then
      ln -s A "$FWD/$fw.framework/Versions/Current"
      ln -s "Versions/Current/$fw" "$FWD/$fw.framework/$fw"
      ln -s Versions/Current/Resources "$FWD/$fw.framework/Resources"
      [[ $fw == Mpv ]] && { ln -s Versions/Current/Headers "$FWD/$fw.framework/Headers"; ln -s Versions/Current/Modules "$FWD/$fw.framework/Modules"; }
    fi
    # firma ad hoc fuera del bundle: así no se crea _CodeSignature/ (como v0.7.3,
    # que solo lleva la firma del enlazador); Xcode vuelve a firmar al incrustar.
    T=$(mktemp "$ROOT/tmp/sign.XXXXXX"); cp "$BIN" "$T"; codesign -f -s - "$T" 2>/dev/null; cp "$T" "$BIN"; rm -f "$T"
    chmod 644 "$BIN"
  done
done

NAME=libmpv-xcframeworks_${TAG}_${OS}-universal-video-full
X=$ROOT/out/xc-$OS/$NAME; rm -rf "$ROOT/out/xc-$OS"; mkdir -p "$X"
for e in $LIBS; do
  fw=${e%%:*}; args=()
  for G in $GROUPS_; do args+=(-framework "$OUT/${G%%:*}/$fw.framework"); done
  xcodebuild -create-xcframework "${args[@]}" -output "$X/$fw.xcframework" > /dev/null
done
( cd "$ROOT/out/xc-$OS" && tar --uid 0 --gid 0 --uname root --gname wheel -czf "$DIST/$NAME.tar.gz" "$NAME" )
( cd "$DSYM" && zip -qry "$DIST/debug-symbols-$OS-$TAG.zip" . )
echo "$DIST/$NAME.tar.gz"
