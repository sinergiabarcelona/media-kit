#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# libmpv LGPL-2.1+ para Windows (x86_64 | aarch64), en cruzado desde macOS con
# llvm-mingw UCRT nativo (sin Docker). Una sola libmpv-2.dll con todo dentro.
#
# Uso: build-windows.sh <x86_64|aarch64>
# Variables: ROOT (carpeta de trabajo; por defecto la del script/..), JOBS.
#
# Aislamiento del host: env -i, PATH solo con llvm-mingw, las herramientas
# propias (nasm, pkgconf, meson, ninja, 7zz) y /usr/bin:/bin; PKG_CONFIG_LIBDIR
# es el prefijo; sin PKG_CONFIG_PATH, CPATH ni LIBRARY_PATH. Nada de
# /opt/homebrew ni /usr/local.
#
# Rutas neutras: todo se instala con --prefix=/opt/reproduko-libmpv dentro de
# un DESTDIR, y los compiladores van envueltos con -ffile-prefix-map, para que
# ni la línea de configure ni __FILE__ incrusten rutas de esta máquina.
set -euo pipefail

ARCH=${1:?uso: build-windows.sh x86_64|aarch64}
case $ARCH in x86_64|aarch64) ;; *) echo "arquitectura no soportada: $ARCH" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=${ROOT:-$(cd "$HERE/.." && pwd -P)}
source "$HERE/versions.env"
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}

# Re-ejecutar en un entorno limpio.
if [[ -z "${_RK_CLEAN:-}" ]]; then
  exec env -i _RK_CLEAN=1 HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" LANG=C LC_ALL=C \
    ROOT="$ROOT" JOBS="$JOBS" /bin/bash "$0" "$@"
fi

T=$ARCH-w64-mingw32
LLVM=$ROOT/tools/$LLVM_MINGW_DIR
WRAP=$ROOT/tools/wrap
NEUTRAL=/opt/reproduko-libmpv
STAGE=$ROOT/prefix/$ARCH            # DESTDIR
P=$STAGE$NEUTRAL                    # prefijo real en disco
B=$ROOT/build/$ARCH
SRC=$ROOT/src
LOG=$ROOT/logs/$ARCH
mkdir -p "$WRAP" "$P"/{lib/pkgconfig,include,bin} "$B" "$LOG"

# Envoltorios del compilador: -ffile-prefix-map para no incrustar rutas.
for tool in clang clang++; do
  cat > "$WRAP/$T-$tool" <<EOF
#!/bin/sh
exec "$LLVM/bin/$T-$tool" -ffile-prefix-map=$ROOT=/build -ffile-prefix-map=${ROOT#/private}=/build "\$@"
EOF
  chmod +x "$WRAP/$T-$tool"
done

export PATH=$WRAP:$LLVM/bin:$ROOT/tools/host/bin:$ROOT/tools/venv/bin:$ROOT/tools/7zip:/usr/bin:/bin
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=$STAGE
unset PKG_CONFIG_PATH CPATH C_INCLUDE_PATH LIBRARY_PATH CFLAGS CXXFLAGS LDFLAGS

# Los cross-files se buscan por nombre en $XDG_DATA_HOME/meson/cross, para que la
# cadena «Configuration:» de mpv no lleve rutas de esta máquina.
export XDG_DATA_HOME=$B/xdg
mkdir -p "$XDG_DATA_HOME/meson/cross"
CROSS_NAME=reproduko-windows-$ARCH.ini
CROSS=$XDG_DATA_HOME/meson/cross/$CROSS_NAME
cat > "$CROSS" <<EOF
[binaries]
c = '$T-clang'
cpp = '$T-clang++'
ar = '$T-ar'
nm = '$T-nm'
strip = '$T-strip'
windres = '$T-windres'
pkg-config = 'pkg-config'
nasm = 'nasm'

[built-in options]
c_args = ['-I$P/include']
cpp_args = ['-I$P/include']
c_link_args = ['-L$P/lib']
cpp_link_args = ['-L$P/lib']

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'windows'
cpu_family = '$ARCH'
cpu = '$ARCH'
endian = 'little'
EOF

MESON_COMMON=(--cross-file "$CROSS" --prefix="$NEUTRAL" --libdir=lib --buildtype=release
              --default-library=static --wrap-mode=nodownload)

stamp() { [[ -f "$B/.done-$1" ]]; }
done_() { touch "$B/.done-$1"; }

meson_dep() { # meson_dep <nombre> <dir-fuente> [opciones...]
  local name=$1 src=$2; shift 2
  stamp "$name" && return 0
  echo "== $name ($ARCH)"
  rm -rf "$B/$name"
  meson setup "$B/$name" "$src" "${MESON_COMMON[@]}" "$@" > "$LOG/$name.setup.log" 2>&1 \
    || { tail -40 "$LOG/$name.setup.log"; exit 1; }
  ninja -C "$B/$name" -j"$JOBS" > "$LOG/$name.build.log" 2>&1 || { tail -40 "$LOG/$name.build.log"; exit 1; }
  meson install -C "$B/$name" --destdir "$STAGE" > "$LOG/$name.install.log" 2>&1
  done_ "$name"
}

# --- zlib (Makefile.gcc de win32; solo la estática) ---------------------------
if ! stamp zlib; then
  echo "== zlib ($ARCH)"
  rm -rf "$B/zlib"; cp -R "$SRC/zlib-$ZLIB_VERSION" "$B/zlib"
  make -C "$B/zlib" -f win32/Makefile.gcc -j"$JOBS" CC=$T-clang AR=$T-ar RC=$T-windres \
    STRIP=$T-strip CFLAGS="-O2 -Wall" libz.a > "$LOG/zlib.build.log" 2>&1
  cp "$B/zlib/libz.a" "$P/lib/"; cp "$B/zlib"/{zlib.h,zconf.h} "$P/include/"
  cat > "$P/lib/pkgconfig/zlib.pc" <<EOF
prefix=$NEUTRAL
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: zlib
Description: zlib compression library
Version: $ZLIB_VERSION
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF
  done_ zlib
fi

# --- GNU libiconv (LGPL-2.1+), estática -------------------------------------
if ! stamp libiconv; then
  echo "== libiconv ($ARCH)"
  rm -rf "$B/libiconv"; mkdir -p "$B/libiconv"
  (cd "$B/libiconv" && "$SRC/libiconv-$LIBICONV_VERSION/configure" --host=$T --prefix=$NEUTRAL \
      --enable-static --disable-shared --disable-nls --disable-rpath CC=$T-clang AR=$T-ar \
      RANLIB=$T-ranlib CFLAGS=-O2 > "$LOG/libiconv.setup.log" 2>&1 \
    && make lib/localcharset.h > "$LOG/libiconv.build.log" 2>&1 \
    && make -j"$JOBS" -C libcharset >> "$LOG/libiconv.build.log" 2>&1 \
    && make -j"$JOBS" -C lib >> "$LOG/libiconv.build.log" 2>&1 \
    && make -C libcharset install DESTDIR="$STAGE" > "$LOG/libiconv.install.log" 2>&1 \
    && make -C lib install DESTDIR="$STAGE" >> "$LOG/libiconv.install.log" 2>&1 \
    && cp include/iconv.h.inst "$P/include/iconv.h") \
    || { tail -40 "$LOG"/libiconv.*.log; exit 1; }
  rm -f "$P"/lib/*.la
  done_ libiconv
fi

# --- dav1d (BSD-2) ------------------------------------------------------------
meson_dep dav1d "$SRC/dav1d-$DAV1D_VERSION" -Denable_tools=false -Denable_tests=false \
  -Denable_examples=false -Denable_docs=false -Denable_asm=true

# --- libxml2 (MIT), mínimo para el demuxer DASH --------------------------------
meson_dep libxml2 "$SRC/libxml2-$LIBXML2_VERSION" -Dpython=disabled -Dreadline=disabled \
  -Dhistory=disabled -Dhttp=disabled -Dcatalog=disabled -Dmodules=disabled -Ddocs=disabled \
  -Dicu=disabled -Dlegacy=disabled -Dzlib=disabled -Ddebugging=disabled -Diconv=enabled \
  -Dthreads=enabled
# Estática en Windows: sin LIBXML_STATIC las cabeceras declaran dllimport.
grep -q LIBXML_STATIC "$P/lib/pkgconfig/libxml-2.0.pc" \
  || sed -i '' 's|^Cflags: \(.*\)$|Cflags: \1 -DLIBXML_STATIC|' "$P/lib/pkgconfig/libxml-2.0.pc"

# --- freetype (FTL) -----------------------------------------------------------
meson_dep freetype "$SRC/freetype-$FREETYPE_VERSION" -Dharfbuzz=disabled -Dpng=disabled \
  -Dbzip2=disabled -Dbrotli=disabled -Dzlib=system -Dtests=disabled

# --- fribidi (LGPL-2.1+) ------------------------------------------------------
meson_dep fribidi "$SRC/fribidi-$FRIBIDI_VERSION" -Ddocs=false -Dbin=false -Dtests=false

# --- harfbuzz (MIT antigua) ---------------------------------------------------
meson_dep harfbuzz "$SRC/harfbuzz-$HARFBUZZ_VERSION" -Dfreetype=enabled -Ddirectwrite=enabled \
  -Dgdi=disabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled \
  -Dpng=disabled -Dzlib=disabled -Dicu=disabled -Dgraphite=disabled -Dgraphite2=disabled \
  -Dfontations=disabled -Dharfrust=disabled -Dkbts=disabled -Dwasm=disabled -Draster=disabled \
  -Dvector=disabled -Dgpu=disabled -Dsubset=disabled -Dtests=disabled -Dintrospection=disabled \
  -Ddocs=disabled -Dutilities=disabled -Dbenchmark=disabled -Dcoretext=disabled

# --- libass (ISC), proveedor de fuentes DirectWrite --------------------------
meson_dep libass "$SRC/libass-$LIBASS_VERSION" -Ddirectwrite=enabled -Dfontconfig=disabled \
  -Dcoretext=disabled -Drequire-system-font-provider=true -Dlibunibreak=disabled \
  -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled -Dcheckasm=disabled \
  -Dasm=$([[ $ARCH == x86_64 ]] && echo enabled || echo disabled)

# --- uchardet (LGPL-2.1+ de su triple licencia), CMake ------------------------
if ! stamp uchardet; then
  echo "== uchardet ($ARCH)"
  rm -rf "$B/uchardet"
  cat > "$B/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR $ARCH)
set(CMAKE_C_COMPILER $T-clang)
set(CMAKE_CXX_COMPILER $T-clang++)
set(CMAKE_RC_COMPILER $T-windres)
set(CMAKE_AR $LLVM/bin/$T-ar)
set(CMAKE_RANLIB $LLVM/bin/$T-ranlib)
set(CMAKE_FIND_ROOT_PATH $P)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
  cmake -S "$SRC/uchardet-$UCHARDET_VERSION" -B "$B/uchardet" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$B/toolchain.cmake" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$NEUTRAL -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_BINARY=OFF -DBUILD_STATIC=ON -DCMAKE_MAKE_PROGRAM=ninja \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 > "$LOG/uchardet.setup.log" 2>&1 \
    || { tail -40 "$LOG/uchardet.setup.log"; exit 1; }
  ninja -C "$B/uchardet" -j"$JOBS" > "$LOG/uchardet.build.log" 2>&1 || { tail -40 "$LOG/uchardet.build.log"; exit 1; }
  DESTDIR="$STAGE" cmake --install "$B/uchardet" > "$LOG/uchardet.install.log" 2>&1
  # llvm-mingw no tiene libstdc++: el runtime C++ es libc++ (+ libunwind).
  sed -i '' 's/-lstdc++/-lc++/' "$P/lib/pkgconfig/uchardet.pc"
  done_ uchardet
fi

# --- libplacebo (LGPL-2.1+), solo OpenGL --------------------------------------
meson_dep libplacebo "$SRC/libplacebo" -Dvulkan=disabled -Dopengl=enabled -Dd3d11=disabled \
  -Dglslang=disabled -Dshaderc=disabled -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled \
  -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false -Dunwind=disabled -Dxxhash=disabled

# --- FFmpeg (LGPL-2.1+), estático ---------------------------------------------
FF_COMMON=(
  --disable-autodetect --disable-programs --disable-doc --disable-avdevice
  --disable-debug --enable-small --enable-pic --enable-network
  --disable-gpl --disable-nonfree --disable-version3
  --enable-avcodec --enable-avformat --enable-avfilter --enable-swresample --enable-swscale
  --disable-vulkan --disable-iconv --disable-bzlib --disable-lzma --enable-zlib
  --enable-libdav1d --enable-libxml2
  --enable-decoders --disable-decoder=truehd,mlp,vvc
  --enable-parsers --enable-demuxers --enable-bsfs --enable-hwaccels --enable-protocols
  --disable-encoders --enable-encoder=png,mjpeg,ljpeg,jpegls,jpeg2000
  --disable-muxers --enable-muxer=spdif
  --disable-filters
  --enable-filter=overlay,equalizer,yadif,bwdif,scale,format,null,hwdownload,hwupload,aresample,aformat,anull,volume,pan,loudnorm,dynaudnorm,acompressor,alimiter,speechnorm
)
FF_WIN=(
  --enable-w32threads --disable-pthreads
  --target-os=mingw32 --arch=$ARCH --enable-cross-compile --cross-prefix=$T-
  --cc=$T-clang --cxx=$T-clang++
  --enable-d3d11va --enable-d3d12va --enable-dxva2 --enable-schannel
  --enable-static --disable-shared --pkg-config=pkg-config --pkg-config-flags=--static
  --enable-runtime-cpudetect
)
if ! stamp ffmpeg; then
  echo "== ffmpeg ($ARCH)"
  rm -rf "$B/ffmpeg"; mkdir -p "$B/ffmpeg"
  (cd "$B/ffmpeg" && "$SRC/ffmpeg-$FFMPEG_VERSION/configure" --prefix=$NEUTRAL \
     "${FF_COMMON[@]}" "${FF_WIN[@]}" > "$LOG/ffmpeg.configure.log" 2>&1) \
    || { tail -40 "$LOG/ffmpeg.configure.log"; tail -60 "$B/ffmpeg/ffbuild/config.log"; exit 1; }
  make -C "$B/ffmpeg" -j"$JOBS" > "$LOG/ffmpeg.build.log" 2>&1 || { grep -m5 -B2 -A5 'error' "$LOG/ffmpeg.build.log"; exit 1; }
  make -C "$B/ffmpeg" install DESTDIR="$STAGE" > "$LOG/ffmpeg.install.log" 2>&1
  done_ ffmpeg
fi

# --- cabeceras EGL/KHR de ANGLE (BSD-3) para egl-angle ------------------------
mkdir -p "$P/include/EGL" "$P/include/KHR"
cp "$ROOT/dl/angle-headers/include/EGL/"*.h "$P/include/EGL/"
cp "$ROOT/dl/angle-headers/include/KHR/"*.h "$P/include/KHR/"

# --- mpv (LGPL-2.1+), libmpv-2.dll --------------------------------------------
# Enlace: -static (winpthreads, libc++ y libunwind dentro de la DLL); -lc++ porque
# libplacebo y uchardet traen C++ y libmpv se enlaza con el driver de C; -u para
# que avcodec_license/avcodec_configuration estén siempre en la DLL.
MPV_LINK_NAME=reproduko-windows-$ARCH-mpv.ini
MPV_LINK=$XDG_DATA_HOME/meson/cross/$MPV_LINK_NAME
cat > "$MPV_LINK" <<EOF
[built-in options]
c_link_args = ['-L$P/lib', '-static', '-Wl,--exclude-all-symbols', '-Wl,--no-insert-timestamp', '-Wl,-u,avcodec_license', '-Wl,-u,avcodec_configuration', '-lc++', '-liconv']
cpp_link_args = ['-L$P/lib', '-static', '-Wl,--exclude-all-symbols', '-Wl,--no-insert-timestamp', '-Wl,-u,avcodec_license', '-Wl,-u,avcodec_configuration', '-lc++', '-liconv']
EOF
MPV_OPTS=(
  -Dauto_features=disabled
  -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false -Dfuzzers=false -Dbuild-date=false
  -Dlua=disabled -Djavascript=disabled -Dcplugins=disabled -Dlibarchive=disabled -Dlibbluray=disabled
  -Ddvdnav=disabled -Dcdda=disabled -Ddvbin=disabled -Dlcms2=disabled -Drubberband=disabled
  -Dvapoursynth=disabled -Dzimg=disabled -Djpeg=disabled
  -Dsdl2-audio=disabled -Dsdl2-video=disabled -Dsdl2-gamepad=disabled -Dvulkan=disabled
  -Dshaderc=disabled -Dspirv-cross=disabled -Dlibavdevice=disabled
  -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled
  -Dgl=enabled -Dplain-gl=enabled -Dzlib=enabled -Duchardet=enabled -Diconv=enabled -Dvector=enabled
  -Dgl-win32=enabled -Degl-angle=enabled -Degl-angle-win32=enabled -Degl-angle-lib=disabled
  -Dd3d-hwaccel=enabled -Dd3d9-hwaccel=enabled -Dd3d11=disabled -Dwasapi=enabled
  -Dwin32-threads=enabled -Dwin32-smtc=disabled
)
if ! stamp mpv; then
  echo "== mpv ($ARCH)"
  rm -rf "$B/mpv"
  meson setup "$B/mpv" "$SRC/mpv-$MPV_VERSION" --cross-file "$CROSS_NAME" --cross-file "$MPV_LINK_NAME" \
    --buildtype=release --default-library=shared --prefer-static --wrap-mode=nodownload \
    "${MPV_OPTS[@]}" > "$LOG/mpv.setup.log" 2>&1 || { tail -60 "$LOG/mpv.setup.log"; exit 1; }
  ninja -C "$B/mpv" -j"$JOBS" > "$LOG/mpv.build.log" 2>&1 || { grep -m5 -B2 -A8 'error' "$LOG/mpv.build.log"; exit 1; }
  done_ mpv
fi
echo "OK build $ARCH: $B/mpv/libmpv-2.dll"
