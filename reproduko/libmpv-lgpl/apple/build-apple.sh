#!/bin/bash
# libmpv LGPL-2.1+ para Apple (macOS, iOS, tvOS y sus simuladores), sin Nix.
# Uso: build-apple.sh <segmento> [paquete...]
#   segmento: macos-arm64 macos-amd64 ios-arm64 iossimulator-arm64 iossimulator-amd64
#             tvos-arm64 tvossimulator-arm64 tvossimulator-amd64
# Equivale a media-kit/libmpv-darwin-build (video-full) con mpv 0.41.0,
# FFmpeg 8.0.3, libplacebo y SecureTransport en lugar de mbedTLS.
# Entorno aislado: env -i, PATH sin /usr/local ni /opt/homebrew/bin,
# pkg-config limitado al prefijo del segmento.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
SEG=${1:?segmento}; shift || true

if [[ -z "${REPRODUKO_CLEAN_ENV:-}" ]]; then
  exec env -i REPRODUKO_CLEAN_ENV=1 FORCE="${FORCE:-}" JOBS="${JOBS:-12}" HOME="$ROOT/tmp/home" TMPDIR="$ROOT/tmp/" \
    LANG=C LC_ALL=C TERM=dumb \
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    PATH="$ROOT/tools/bin:$ROOT/tools/venv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    /bin/bash "$0" "$SEG" "$@"
fi
mkdir -p "$ROOT/tmp/home"

source "$ROOT/versions.env"
JOBS=${JOBS:-12}
XC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
case $SEG in
  macos-arm64)        SDK=macosx;          ARCH=arm64;  CPUF=aarch64; SUB=macos;         TRIPLE=arm64-apple-macos$MACOS_MIN ;;
  macos-amd64)        SDK=macosx;          ARCH=x86_64; CPUF=x86_64;  SUB=macos;         TRIPLE=x86_64-apple-macos$MACOS_MIN ;;
  ios-arm64)          SDK=iphoneos;        ARCH=arm64;  CPUF=aarch64; SUB=ios;           TRIPLE=arm64-apple-ios$IOS_MIN ;;
  iossimulator-arm64) SDK=iphonesimulator; ARCH=arm64;  CPUF=aarch64; SUB=ios-simulator; TRIPLE=arm64-apple-ios$IOS_MIN-simulator ;;
  iossimulator-amd64) SDK=iphonesimulator; ARCH=x86_64; CPUF=x86_64;  SUB=ios-simulator; TRIPLE=x86_64-apple-ios$IOS_MIN-simulator ;;
  # tvOS: mismas opciones que iOS (OpenGL ES por EAGL y AudioUnit). El SDK marca
  # fork/exec/posix_spawn como no disponibles: mpv cae solo en subprocess-dummy.
  tvos-arm64)          SDK=appletvos;        ARCH=arm64;  CPUF=aarch64; SUB=tvos;           TRIPLE=arm64-apple-tvos$TVOS_MIN ;;
  tvossimulator-arm64) SDK=appletvsimulator; ARCH=arm64;  CPUF=aarch64; SUB=tvos-simulator; TRIPLE=arm64-apple-tvos$TVOS_MIN-simulator ;;
  tvossimulator-amd64) SDK=appletvsimulator; ARCH=x86_64; CPUF=x86_64;  SUB=tvos-simulator; TRIPLE=x86_64-apple-tvos$TVOS_MIN-simulator ;;
  *) echo "segmento desconocido: $SEG"; exit 2 ;;
esac
OS=${SEG%%-*}
case $OS in  # familia: decide CMAKE_SYSTEM_NAME y el mínimo de SO
  macos) CM_SYS=Darwin; OS_MIN=$MACOS_MIN ;;
  ios|iossimulator) CM_SYS=iOS; OS_MIN=$IOS_MIN ;;
  tvos|tvossimulator) CM_SYS=tvOS; OS_MIN=$TVOS_MIN ;;
esac
SYSROOT=$(xcrun --sdk $SDK --show-sdk-path)
PREFIX=/reproduko/$SEG           # prefijo lógico (neutro; queda en .pc y en la cadena de configure)
STAGE=$ROOT/stage/$SEG           # DESTDIR real
P=$STAGE$PREFIX                  # prefijo real
B=$ROOT/build/$SEG
SRC=$ROOT/src
LOG=$ROOT/logs/$SEG
mkdir -p "$P/lib/pkgconfig" "$B" "$LOG"

MAP="-ffile-prefix-map=$ROOT=/reproduko"
CFL=(-target "$TRIPLE" -isysroot "$SYSROOT" "$MAP")

export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=$STAGE
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH SDKROOT

# zlib del SDK (sin rutas: libz.tbd del sysroot), para quien la pida por pkg-config.
ZV=$(sed -n 's/^#define ZLIB_VERSION "\(.*\)"/\1/p' "$SYSROOT/usr/include/zlib.h")
printf 'Name: zlib\nDescription: zlib del SDK\nVersion: %s\nLibs: -lz\nCflags:\n' "$ZV" > "$P/lib/pkgconfig/zlib.pc"

q() { printf "'%s', " "$@"; }
# El cross file va a $XDG_DATA_HOME/meson/cross y se pasa por nombre: así la
# cadena «Configuration» de mpv (meson.build_options()) no lleva rutas locales.
export XDG_DATA_HOME=$ROOT/tmp/xdg
mkdir -p "$XDG_DATA_HOME/meson/cross"
CROSS=reproduko-$SEG
cat > "$XDG_DATA_HOME/meson/cross/$CROSS" <<EOF
[host_machine]
system     = 'darwin'
subsystem  = '$SUB'
kernel     = 'xnu'
cpu_family = '$CPUF'
cpu        = '$ARCH'
endian     = 'little'

[binaries]
c          = '$XC/clang'
cpp        = '$XC/clang++'
objc       = '$XC/clang'
objcpp     = '$XC/clang++'
nm         = '$XC/nm'
ar         = '$XC/ar'
strip      = '$XC/strip'
ranlib     = '$XC/ranlib'
pkg-config = '$ROOT/tools/bin/pkg-config'

[built-in options]
c_args           = [$(q "${CFL[@]}")]
cpp_args         = [$(q "${CFL[@]}") '-stdlib=libc++']
objc_args        = [$(q "${CFL[@]}")]
objcpp_args      = [$(q "${CFL[@]}") '-stdlib=libc++']
c_link_args      = [$(q -target "$TRIPLE" -isysroot "$SYSROOT" -Wl,-headerpad_max_install_names)]
cpp_link_args    = [$(q -target "$TRIPLE" -isysroot "$SYSROOT" -Wl,-headerpad_max_install_names)]
objc_link_args   = [$(q -target "$TRIPLE" -isysroot "$SYSROOT" -Wl,-headerpad_max_install_names)]
objcpp_link_args = [$(q -target "$TRIPLE" -isysroot "$SYSROOT" -Wl,-headerpad_max_install_names)]

[properties]
needs_exe_wrapper = true
sys_root          = '$STAGE'
pkg_config_libdir = ['$P/lib/pkgconfig']
EOF

fixup_names() { # ids y dependencias del prefijo -> @rpath (meson instala con rutas absolutas)
  local f id dep
  for f in $(find "$P/lib" -maxdepth 1 -name '*.dylib' -type f); do
    id=$(otool -D "$f" | tail -n +2)
    [[ $id == "$PREFIX/lib/"* ]] && install_name_tool -id "@rpath/${id##*/}" "$f" 2>/dev/null
    for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep "^$PREFIX/lib/" || true); do
      install_name_tool -change "$dep" "@rpath/${dep##*/}" "$f" 2>/dev/null
    done
  done
}

stamp() { [[ -f "$B/$1.done" ]]; }
done_() { touch "$B/$1.done"; }

msetup() { # msetup <nombre> <src> [opciones meson...]
  local n=$1 s=$2; shift 2
  rm -rf "$B/$n"
  cd "$B"
  meson setup "$B/$n" "$s" --cross-file "$CROSS" --prefix="$PREFIX" --libdir=lib \
    --buildtype=release -Ddefault_library=shared --wrap-mode=nodownload "$@" > "$LOG/$n.configure.log" 2>&1 \
    || { tail -40 "$LOG/$n.configure.log"; exit 1; }
  ninja -C "$B/$n" -j$JOBS > "$LOG/$n.build.log" 2>&1 || { tail -60 "$LOG/$n.build.log"; exit 1; }
  DESTDIR=$STAGE meson install -C "$B/$n" --no-rebuild > "$LOG/$n.install.log" 2>&1 || { tail -20 "$LOG/$n.install.log"; exit 1; }
}

csetup() { # csetup <nombre> <src> [opciones cmake...]
  local n=$1 s=$2; shift 2
  rm -rf "$B/$n"
  cmake -S "$s" -B "$B/$n" -G Ninja -DCMAKE_MAKE_PROGRAM="$ROOT/tools/venv/bin/ninja" \
    -DCMAKE_SYSTEM_NAME=$CM_SYS -DCMAKE_OSX_SYSROOT="$SYSROOT" -DCMAKE_OSX_ARCHITECTURES=$ARCH \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$OS_MIN \
    -DCMAKE_C_COMPILER="$XC/clang" -DCMAKE_CXX_COMPILER="$XC/clang++" \
    -DCMAKE_C_FLAGS="-target $TRIPLE $MAP" -DCMAKE_CXX_FLAGS="-target $TRIPLE $MAP" \
    -DCMAKE_SHARED_LINKER_FLAGS="-target $TRIPLE -Wl,-headerpad_max_install_names" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT;$P" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_MACOSX_RPATH=ON -DCMAKE_INSTALL_NAME_DIR=@rpath -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    "$@" > "$LOG/$n.configure.log" 2>&1 || { tail -40 "$LOG/$n.configure.log"; exit 1; }
  ninja -C "$B/$n" -j$JOBS > "$LOG/$n.build.log" 2>&1 || { tail -60 "$LOG/$n.build.log"; exit 1; }
  DESTDIR=$STAGE cmake --install "$B/$n" > "$LOG/$n.install.log" 2>&1 || { tail -20 "$LOG/$n.install.log"; exit 1; }
}

b_dav1d() {
  local asm=true; [[ $ARCH == x86_64 ]] && asm=false   # x86_64 sin nasm, como hoy
  msetup dav1d "$SRC/dav1d-$DAV1D_VERSION" -Dbitdepths="['8','16']" -Denable_asm=$asm \
    -Denable_tools=false -Denable_examples=false -Denable_tests=false -Denable_docs=false \
    -Dlogging=true -Dtestdata_tests=false -Dfuzzing_engine=none -Dxxhash_muxer=disabled -Dtrim_dsp=if-release
}
b_libpng() {
  csetup libpng "$SRC/libpng-$LIBPNG_VERSION" -DPNG_SHARED=ON -DPNG_STATIC=OFF -DPNG_TESTS=OFF \
    -DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF -DSKIP_INSTALL_PROGRAMS=ON
}
b_harfbuzz() {
  msetup harfbuzz "$SRC/harfbuzz-$HARFBUZZ_VERSION" -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
    -Dchafa=disabled -Dpng=disabled -Dzlib=disabled -Dicu=disabled -Dgraphite=disabled -Dgraphite2=disabled \
    -Dfreetype=disabled -Dfontations=disabled -Dgdi=disabled -Ddirectwrite=disabled -Dcoretext=enabled \
    -Dharfrust=disabled -Dkbts=disabled -Dwasm=disabled -Draster=disabled -Dvector=disabled -Dgpu=disabled \
    -Dgpu_demo=disabled -Dsubset=disabled -Dtests=disabled -Dintrospection=disabled -Ddocs=disabled \
    -Ddoc_tests=false -Dutilities=disabled -Dbenchmark=disabled -Dicu_builtin=false -Dexperimental_api=false \
    -Dragel_subproject=false
}
b_freetype() {
  msetup freetype "$SRC/freetype-$FREETYPE_VERSION" -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=enabled \
    -Dmmap=disabled -Dpng=enabled -Dtests=disabled -Dzlib=system
}
b_fribidi() {
  msetup fribidi "$SRC/fribidi-$FRIBIDI_VERSION" -Ddeprecated=false -Ddocs=false -Dbin=false -Dtests=false
}
b_libass() {
  msetup libass "$SRC/libass-$LIBASS_VERSION" -Dtest=disabled -Dcompare=disabled -Dprofile=disabled \
    -Dfuzz=disabled -Dcheckasm=disabled -Dfontconfig=disabled -Ddirectwrite=disabled -Dcoretext=enabled \
    -Dasm=disabled -Dlibunibreak=disabled -Drequire-system-font-provider=true -Dlarge-tiles=false
}
b_uchardet() {
  csetup uchardet "$SRC/uchardet-$UCHARDET_VERSION" -DBUILD_BINARY=OFF -DBUILD_STATIC=OFF -DBUILD_SHARED_LIBS=ON
}
b_libxml2() {
  msetup libxml2 "$SRC/libxml2-$LIBXML2_VERSION" -Dpython=disabled -Dicu=disabled -Dzlib=disabled \
    -Dhttp=disabled -Dreadline=disabled -Dhistory=disabled -Ddocs=disabled -Diconv=enabled -Dthreads=enabled \
    -Dmodules=disabled -Dlegacy=disabled -Ddebugging=disabled -Dcatalog=disabled
}
b_libplacebo() {
  msetup libplacebo "$SRC/libplacebo-$LIBPLACEBO_VERSION" -Dvulkan=disabled -Dopengl=enabled \
    -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dd3d11=disabled \
    -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false -Dunwind=disabled -Dxxhash=disabled
}
b_ffmpeg() {
  local n=ffmpeg arch=$ARCH archopt=()
  [[ $ARCH == arm64 ]] && { arch=aarch64; archopt=(--enable-neon); }
  [[ $ARCH == x86_64 ]] && archopt=(--disable-x86asm)
  rm -rf "$B/$n"; mkdir -p "$B/$n"
  # Rutas neutras: el compilador es «clang» del PATH (envoltorio que añade
  # -ffile-prefix-map), para que no quede la ruta de build en la cadena de configure.
  ( cd "$B/$n" && "$SRC/ffmpeg-$FFMPEG_VERSION/configure" \
      --prefix="$PREFIX" --libdir="$PREFIX/lib" --install-name-dir=@rpath \
      --enable-cross-compile --target-os=darwin --arch=$arch \
      --cc=clang --cxx=clang++ --objcc=clang --ld=clang --as=clang --host-cc=/usr/bin/clang \
      --nm="$XC/nm" --ar="$XC/ar" --ranlib="$XC/ranlib" --strip="$XC/strip" --pkg-config=pkg-config \
      --extra-cflags="-target $TRIPLE -isysroot $SYSROOT" \
      --extra-cxxflags="-target $TRIPLE -isysroot $SYSROOT" \
      --extra-objcflags="-target $TRIPLE -isysroot $SYSROOT" \
      --extra-ldflags="-target $TRIPLE -isysroot $SYSROOT -Wl,-headerpad_max_install_names" \
      --metalcc="xcrun -sdk $SDK metal" --metallib="xcrun -sdk $SDK metallib" \
      --enable-shared --disable-static \
      "${FFMPEG_COMMON[@]}" "${FFMPEG_APPLE[@]}" "${archopt[@]}" ) > "$LOG/$n.configure.log" 2>&1 \
    || { tail -40 "$LOG/$n.configure.log"; tail -40 "$B/$n/ffbuild/config.log"; exit 1; }
  cp "$B/$n/ffbuild/config.log" "$LOG/ffmpeg.config.log"
  cp "$B/$n/config.h" "$B/$n/config_components.h" "$LOG/"
  make -C "$B/$n" -j$JOBS > "$LOG/$n.build.log" 2>&1 || { tail -60 "$LOG/$n.build.log"; exit 1; }
  make -C "$B/$n" install DESTDIR="$STAGE" > "$LOG/$n.install.log" 2>&1 || { tail -20 "$LOG/$n.install.log"; exit 1; }
}
b_mpv() {
  local os_opts=()
  if [[ $OS == macos ]]; then
    os_opts=(-Dcocoa=enabled -Dgl-cocoa=enabled -Dvideotoolbox-gl=enabled -Dcoreaudio=enabled -Daudiounit=disabled)
  else  # iOS y tvOS
    os_opts=(-Daudiounit=enabled -Dios-gl=enabled -Dvideotoolbox-gl=disabled -Dcocoa=disabled -Dcoreaudio=disabled)
  fi
  msetup mpv "$SRC/mpv-$MPV_VERSION" -Dauto_features=disabled --buildtype=debugoptimized \
    -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false -Dfuzzers=false -Dbuild-date=false \
    -Dgl=enabled -Dplain-gl=enabled -Dzlib=enabled -Duchardet=enabled -Diconv=enabled \
    -Dvideotoolbox-pl=disabled -Davfoundation=disabled -Dswift-build=disabled \
    -Dmacos-cocoa-cb=disabled -Dmacos-media-player=disabled -Dmacos-touchbar=disabled \
    "${os_opts[@]}"
  cp "$LOG/mpv.configure.log" "$LOG/mpv-features.txt"
}

PKGS=("$@"); [[ ${#PKGS[@]} -eq 0 ]] && PKGS=(dav1d libpng harfbuzz freetype fribidi libass uchardet libxml2 libplacebo ffmpeg mpv)
for p in "${PKGS[@]}"; do
  if stamp $p && [[ -z "${FORCE:-}" ]]; then echo "[$SEG] $p ya compilado"; continue; fi
  t0=$(date +%s); echo "[$SEG] $p ..."
  b_$p; fixup_names; done_ $p
  echo "[$SEG] $p OK ($(( $(date +%s) - t0 )) s)"
done
