#!/usr/bin/env bash
# libmpv LGPL-2.1+ para Android (reproduko, receta propia r1).
# mpv v0.41.0 + FFmpeg n8.0.3 + libplacebo v7.360.1, todo estático dentro de un
# único libmpv.so por ABI, con libc++ estático y solo mpv_* exportado.
#
# Uso: build-android.sh <abi>... (arm64-v8a armeabi-v7a x86_64 x86) | all
# Entorno limpio: se re-ejecuta con env -i y un PATH sin /usr/local ni
# /opt/homebrew (el Homebrew del host trae un FFmpeg GPL y OpenSSL).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NDK=${NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}
TC=$NDK/toolchains/llvm/prebuilt/darwin-x86_64
API=21
JOBS=${JOBS:-6}

if [[ -z ${RK_CLEAN_ENV:-} ]]; then
  exec env -i RK_CLEAN_ENV=1 HOME="$HOME" JOBS="$JOBS" NDK="$NDK" LANG=C LC_ALL=C TERM=dumb \
    PATH="$ROOT/tools/wrap:$ROOT/tools/bin:$TC/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${BASH_SOURCE[0]}" "$@"
fi

SRC=$ROOT/src
PATCHES=$ROOT/patches
# Rutas de build fuera del binario: el wrapper del compilador reescribe
# $ROOT y el NDK con -ffile-prefix-map.
MAP_ROOT=/libmpv-lgpl
MAP_NDK=/android-ndk

# ---------------------------------------------------------------------------
# Wrappers del compilador: mismo nombre que los del NDK (<triple><api>-clang),
# primero en el PATH, para que configure y meson guarden nombres sin rutas.
make_wrappers() {
  mkdir -p "$ROOT/tools/wrap"
  local t
  for t in aarch64-linux-android armv7a-linux-androideabi x86_64-linux-android i686-linux-android; do
    for cc in clang clang++; do
      cat > "$ROOT/tools/wrap/$t$API-$cc" <<EOF
#!/bin/sh
exec "$TC/bin/$cc" --target=$t$API -ffile-prefix-map=$ROOT=$MAP_ROOT -ffile-prefix-map=$NDK=$MAP_NDK "\$@"
EOF
      chmod +x "$ROOT/tools/wrap/$t$API-$cc"
    done
  done
  ln -sf "$ROOT/tools/venv/bin/python3" "$ROOT/tools/bin/python3"
}

# ---------------------------------------------------------------------------
loadabi() {
  ABI=$1
  case $ABI in
    arm64-v8a)   TRIPLE=aarch64-linux-android;     CCT=aarch64-linux-android;     FF_ARCH=aarch64; FF_CPU=armv8-a; FAM=aarch64; CPU=armv8a;  OSSL=android-arm64;  CPUFLAGS="" ;;
    armeabi-v7a) TRIPLE=arm-linux-androideabi;     CCT=armv7a-linux-androideabi;  FF_ARCH=arm;     FF_CPU=armv7-a; FAM=arm;     CPU=armv7a;  OSSL=android-arm;    CPUFLAGS="-mfpu=neon -mcpu=cortex-a8" ;;
    x86_64)      TRIPLE=x86_64-linux-android;      CCT=x86_64-linux-android;      FF_ARCH=x86_64;  FF_CPU=generic; FAM=x86_64;  CPU=x86_64;  OSSL=android-x86_64; CPUFLAGS="" ;;
    x86)         TRIPLE=i686-linux-android;        CCT=i686-linux-android;        FF_ARCH=x86;     FF_CPU=i686;    FAM=x86;     CPU=i686;    OSSL=android-x86;    CPUFLAGS="" ;;
    *) echo "ABI desconocida: $ABI" >&2; exit 2 ;;
  esac
  CC=$CCT$API-clang
  CXX=$CCT$API-clang++
  P=$ROOT/prefix/$ABI          # DESTDIR; prefijo lógico /usr/local
  B=$ROOT/build/$ABI
  L=$ROOT/logs/$ABI
  mkdir -p "$P" "$B" "$L"
  [[ -e $P/usr ]] || ln -s . "$P/usr"
  [[ -e $P/local ]] || ln -s . "$P/local"
  export PKG_CONFIG_SYSROOT_DIR=$P
  export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
  unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH CFLAGS CXXFLAGS CPPFLAGS LDFLAGS || true
  local cflags="" q
  for q in $CPUFLAGS; do cflags+="'$q', "; done
  cat > "$B/cross.txt" <<EOF
[built-in options]
buildtype = 'release'
default_library = 'static'
wrap_mode = 'nodownload'
c_args = [${cflags}'-fPIC']
cpp_args = [${cflags}'-fPIC']
c_link_args = ['-Wl,-z,max-page-size=16384']
cpp_link_args = ['-Wl,-z,max-page-size=16384']

[binaries]
c = '$CC'
cpp = '$CXX'
ar = 'llvm-ar'
nm = 'llvm-nm'
strip = 'llvm-strip'
ranlib = 'llvm-ranlib'
pkg-config = 'pkg-config'
nasm = 'nasm'

[host_machine]
system = 'android'
cpu_family = '$FAM'
cpu = '$CPU'
endian = 'little'
EOF
}

meson_dep() { # meson_dep <nombre> <srcdir> [opciones]
  local name=$1 s=$2; shift 2
  [[ -f $B/.done-$name ]] && return 0
  rm -rf "$B/$name"
  echo "[$ABI] $name" >&2
  meson setup "$B/$name" "$s" --cross-file "$B/cross.txt" --prefix=/usr/local --libdir=lib "$@" > "$L/$name.setup.log" 2>&1 \
    || { tail -40 "$L/$name.setup.log"; exit 1; }
  ninja -C "$B/$name" -j"$JOBS" > "$L/$name.build.log" 2>&1 || { tail -40 "$L/$name.build.log"; exit 1; }
  DESTDIR=$P ninja -C "$B/$name" install > "$L/$name.install.log" 2>&1
  touch "$B/.done-$name"
}

build_openssl() {
  [[ -f $B/.done-openssl ]] && return 0
  echo "[$ABI] openssl" >&2
  rm -rf "$B/openssl"; cp -R "$SRC/openssl-3.5.9" "$B/openssl"
  # Compilación dentro del árbol: __FILE__ queda relativo (crypto/...).
  ( cd "$B/openssl" &&
    export ANDROID_NDK_ROOT=$NDK &&
    ./Configure "$OSSL" -D__ANDROID_API__=$API no-shared no-tests no-apps no-docs no-module \
      no-engine no-legacy no-ui-console $CPUFLAGS \
      --prefix=/usr/local --openssldir=/usr/local/ssl --libdir=lib &&
    make -j"$JOBS" build_libs &&
    make DESTDIR="$P" install_dev ) > "$L/openssl.log" 2>&1 || { tail -40 "$L/openssl.log"; exit 1; }
  touch "$B/.done-openssl"
}

build_libiconv() {
  [[ -f $B/.done-libiconv ]] && return 0
  echo "[$ABI] libiconv" >&2
  rm -rf "$B/libiconv"; mkdir -p "$B/libiconv"
  ( cd "$B/libiconv" &&
    "$SRC/libiconv-1.18/configure" --host=$TRIPLE --prefix=/usr/local --libdir=/usr/local/lib \
      --enable-static --disable-shared --disable-nls --with-pic \
      CC="$CC" AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm STRIP=llvm-strip CFLAGS="-O2 $CPUFLAGS" &&
    make -j"$JOBS" &&
    make DESTDIR="$P" install ) > "$L/libiconv.log" 2>&1 || { tail -40 "$L/libiconv.log"; exit 1; }
  touch "$B/.done-libiconv"
}

build_uchardet() {
  [[ -f $B/.done-uchardet ]] && return 0
  echo "[$ABI] uchardet" >&2
  rm -rf "$B/uchardet"
  ( cmake -S "$SRC/uchardet-0.0.8" -B "$B/uchardet" -G Ninja \
      -DCMAKE_MAKE_PROGRAM="$ROOT/tools/bin/ninja" \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI=$ABI -DANDROID_PLATFORM=android-$API -DANDROID_STL=c++_static \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC=ON -DBUILD_BINARY=OFF -DCHECK_SSE2=OFF \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$ROOT=$MAP_ROOT -ffile-prefix-map=$NDK=$MAP_NDK" \
      -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY &&
    ninja -C "$B/uchardet" -j"$JOBS" &&
    DESTDIR="$P" ninja -C "$B/uchardet" install ) > "$L/uchardet.log" 2>&1 || { tail -40 "$L/uchardet.log"; exit 1; }
  # Libs.private: -lstdc++ apuntaría al libstdc++.so mínimo de bionic.
  sed -i '' 's/^Libs.private:.*/Libs.private: -lc++_static -lc++abi/' "$P/lib/pkgconfig/uchardet.pc"
  touch "$B/.done-uchardet"
}

ffmpeg_flags() {
  local f=(
    # COMUNES (plan r1)
    --disable-autodetect --disable-programs --disable-doc --disable-avdevice
    --disable-debug --enable-small --enable-pic --enable-network
    --disable-gpl --disable-nonfree --disable-version3
    --enable-avcodec --enable-avformat --enable-avfilter --enable-swresample --enable-swscale
    --disable-vulkan --disable-iconv --disable-bzlib --disable-lzma --enable-zlib --enable-libdav1d --enable-libxml2
    --enable-decoders --disable-decoder=truehd,mlp,vvc --enable-parsers --enable-demuxers --enable-bsfs --enable-hwaccels --enable-protocols
    --disable-encoders --enable-encoder=png,mjpeg,ljpeg,jpegls,jpeg2000
    --disable-muxers --enable-muxer=spdif
    --disable-filters --enable-filter=overlay,equalizer,yadif,bwdif,scale,format,null,hwdownload,hwupload,aresample,aformat,anull,volume,pan,loudnorm,dynaudnorm,acompressor,alimiter,speechnorm
    # ANDROID
    --enable-pthreads --target-os=android --enable-cross-compile --enable-jni --enable-mediacodec --enable-openssl
    --enable-v4l2-m2m  # hoy (v1.1.11) entraba por autodetección: se mantiene el catálogo
    --enable-static --disable-shared --pkg-config-flags=--static --enable-runtime-cpudetect --disable-stripping
    --cross-prefix=$TRIPLE- --cc=$CC --cxx=$CXX --ar=llvm-ar --nm=llvm-nm --ranlib=llvm-ranlib --strip=llvm-strip
    --pkg-config=pkg-config --arch=$FF_ARCH --cpu=$FF_CPU
  )
  [[ $ABI == x86 ]] && f+=(--disable-asm)
  [[ -n $CPUFLAGS ]] && f+=(--extra-cflags="$CPUFLAGS")
  printf '%s\n' "${f[@]}"
}

build_ffmpeg() {
  [[ -f $B/.done-ffmpeg ]] && return 0
  echo "[$ABI] ffmpeg" >&2
  rm -rf "$B/ffmpeg"; mkdir -p "$B/ffmpeg"
  local flags=(); while IFS= read -r l; do flags+=("$l"); done < <(ffmpeg_flags)
  ( cd "$B/ffmpeg" &&
    "$ROOT/work/ffmpeg-src/configure" "${flags[@]}" &&
    make -j"$JOBS" &&
    make DESTDIR="$P" install ) > "$L/ffmpeg.log" 2>&1 || { tail -60 "$L/ffmpeg.log"; exit 1; }
  cp "$B/ffmpeg/config.h" "$B/ffmpeg/config_components.h" "$L/"
  touch "$B/.done-ffmpeg"
}

MPV_LINK="-Wl,-O1,--icf=safe -Wl,--no-undefined -Wl,--exclude-libs,ALL -lc++_static -lc++abi -Wl,-z,max-page-size=16384 -Wl,-u,avcodec_license -Wl,-u,avcodec_configuration"

build_mpv() {
  [[ -f $B/.done-mpv ]] && return 0
  echo "[$ABI] mpv" >&2
  rm -rf "$B/mpv"
  # libiconv en el prefijo: dependency('iconv') usa find_library, no pkg-config.
  cat > "$B/cross-mpv.txt" <<EOF
[built-in options]
c_args = [$(for q in $CPUFLAGS; do printf "'%s', " "$q"; done)'-fPIC', '-I$P/include']
c_link_args = [$(for q in $MPV_LINK; do printf "'%s', " "$q"; done)'-L$P/lib', '-liconv']
EOF
  ( cd "$B" &&
    meson setup mpv "$ROOT/work/mpv-src" --cross-file cross.txt --cross-file cross-mpv.txt \
      --prefix=/usr/local --libdir=lib --prefer-static -Ddefault_library=shared \
      -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false -Dfuzzers=false -Dbuild-date=false \
      -Dlua=disabled -Djavascript=disabled -Dcplugins=disabled -Dlibarchive=disabled -Dlibbluray=disabled \
      -Ddvdnav=disabled -Dcdda=disabled -Ddvbin=disabled -Dlcms2=disabled -Drubberband=disabled \
      -Dvapoursynth=disabled -Dzimg=disabled -Djpeg=disabled \
      -Dsdl2-audio=disabled -Dsdl2-video=disabled -Dsdl2-gamepad=disabled -Dvulkan=disabled \
      -Dshaderc=disabled -Dspirv-cross=disabled -Dlibavdevice=disabled \
      -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled \
      -Dgl=enabled -Dplain-gl=enabled -Dzlib=enabled -Duchardet=enabled -Diconv=enabled \
      -Degl-android=enabled -Dandroid-media-ndk=enabled -Daudiotrack=enabled -Dopensles=enabled -Daaudio=disabled
  ) > "$L/mpv.setup.log" 2>&1 || { tail -60 "$L/mpv.setup.log"; exit 1; }
  ninja -C "$B/mpv" -j"$JOBS" > "$L/mpv.build.log" 2>&1 || { tail -60 "$L/mpv.build.log"; exit 1; }
  DESTDIR=$P ninja -C "$B/mpv" install > "$L/mpv.install.log" 2>&1
  touch "$B/.done-mpv"
}

prepare_sources() {
  # Árboles parcheados compartidos por todas las ABI (build fuera del árbol).
  if [[ ! -f $ROOT/work/.ffmpeg-ok ]]; then
    rm -rf "$ROOT/work/ffmpeg-src"; cp -R "$SRC/ffmpeg-8.0.3" "$ROOT/work/ffmpeg-src"
    for p in "$PATCHES"/ffmpeg/*.patch; do patch -p1 -d "$ROOT/work/ffmpeg-src" < "$p"; done
    touch "$ROOT/work/.ffmpeg-ok"
  fi
  if [[ ! -f $ROOT/work/.mpv-ok ]]; then
    rm -rf "$ROOT/work/mpv-src"; cp -R "$SRC/mpv-0.41.0" "$ROOT/work/mpv-src"
    for p in "$PATCHES"/mpv/*.patch; do patch -p1 -d "$ROOT/work/mpv-src" < "$p"; done
    touch "$ROOT/work/.mpv-ok"
  fi
}

build_abi() {
  loadabi "$1"
  build_openssl
  build_libiconv
  meson_dep dav1d "$SRC/dav1d-1.5.3" -Denable_tools=false -Denable_tests=false -Denable_examples=false -Denable_docs=false -Dxxhash_muxer=disabled -Dstack_alignment=16
  meson_dep libxml2 "$SRC/libxml2-2.15.4" -Dminimum=true -Dthreads=enabled -Ddocs=disabled -Dpython=disabled
  meson_dep freetype "$SRC/freetype-2.14.3" -Dharfbuzz=disabled -Dpng=disabled -Dbzip2=disabled -Dbrotli=disabled -Dzlib=system -Dtests=disabled
  meson_dep fribidi "$SRC/fribidi-1.0.16" -Ddocs=false -Dbin=false -Dtests=false
  meson_dep harfbuzz "$SRC/harfbuzz-14.6.0" -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
    -Dchafa=disabled -Dicu=disabled -Dgraphite2=disabled -Dpng=disabled -Dzlib=disabled -Dtests=disabled \
    -Dintrospection=disabled -Ddocs=disabled -Dutilities=disabled -Dbenchmark=disabled -Dsubset=disabled \
    -Draster=disabled -Dvector=disabled -Dgpu=disabled
  meson_dep libass "$SRC/libass-0.17.4" -Dfontconfig=disabled -Drequire-system-font-provider=false -Dtest=disabled \
    -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled -Dcheckasm=disabled -Dlibunibreak=disabled -Dasm=disabled
  build_uchardet
  meson_dep libplacebo "$SRC/libplacebo-7.360.1" -Dvulkan=disabled -Dopengl=enabled -Dglslang=disabled -Dshaderc=disabled \
    -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dd3d11=disabled -Ddemos=false -Dtests=false -Dbench=false \
    -Dfuzz=false -Dunwind=disabled -Dxxhash=disabled
  build_ffmpeg
  build_mpv
  echo "[$ABI] OK" >&2
}

make_wrappers
prepare_sources
abis=("$@"); [[ ${abis[0]:-all} == all ]] && abis=(arm64-v8a armeabi-v7a x86_64 x86)
for a in "${abis[@]}"; do build_abi "$a"; done
