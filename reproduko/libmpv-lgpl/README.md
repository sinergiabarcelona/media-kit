# Recetas libmpv + FFmpeg en LGPL (para el fork de media_kit)

Preparado en local, **sin publicar ni compilar en CI**. Destino: el fork
`sinergiabarcelona/media-kit` cuando Samu lo confirme (copiar esta carpeta a
`reproduko/libmpv-lgpl/` y `workflows/libmpv-lgpl.yml` a `.github/workflows/`).

| Plataforma | Script | Máquina | Estado |
|---|---|---|---|
| Linux x86_64/arm64 | `build-linux.sh` | Ubuntu 24.04 | sin compilar (no hay Linux aquí) |
| Windows x86_64/arm64 | `build-windows.sh` | Linux + llvm-mingw | sin compilar; sustituye al mpv-dev GPL actual |
| tvOS / visionOS | `build-apple.sh` | macOS + Xcode 16 | sin compilar; opciones de vo por confirmar |

Reglas comunes (`common.sh`):
- FFmpeg con `--disable-gpl --disable-nonfree` (nunca `--enable-gpl`/`--enable-nonfree`),
  sin x264/x265/fdk-aac, sin encoders, enlace dinámico, AV1 con dav1d (BSD-2).
- mpv con `-Dgpl=false` (falla si algo exige GPL).
- Sabor `tiendas`: sin decodificadores por software de HEVC, AC-3, E-AC-3, DTS,
  TrueHD/MLP (solo por el decodificador del sistema). `completo`: todo LGPL.
- `check_lgpl` falla la build si encuentra rastros de GPL o x264/x265.
- Versiones fijadas en `versions.env`.

Pendiente antes de usar: publicar las fuentes exactas y la línea de configure
junto a cada binario (obligación LGPL), y revisar las opciones de mpv para tvOS/xros.

## r1: libmpv LGPL que usa reproduko (macOS, iOS, Android, Windows)

Recetas compiladas y probadas el 2026-11-07. Sustituyen a los binarios «full» de
libmpv-darwin-build v0.7.3, libmpv-android-video-build v1.1.11 y al mpv-dev de
libmpv-win32-video-cmake. Binarios en la Release `libmpv-lgpl-r1` de este fork.

- Versiones comunes: mpv 0.41.0, FFmpeg n8.0.3, libplacebo v7.360.1 (con
  submódulos, por commit). Misma lista de componentes FFmpeg en las tres:
  `--disable-gpl --disable-nonfree` (LGPL-2.1+), sin decoders `truehd`/`mlp`/`vvc`,
  con sus parsers y demuxers, muxer `spdif`, yadif/bwdif (y `yadif_videotoolbox`
  en Apple), loudnorm/dynaudnorm/acompressor/alimiter/speechnorm.
- `apple/`: `./setup-tools.sh && ./fetch.sh`, `./build-apple.sh <seg>` y
  `./verify.sh <seg>` para macos-arm64 macos-amd64 ios-arm64 iossimulator-arm64
  iossimulator-amd64; después `./package-apple.sh macos` y `./package-apple.sh ios`.
- `android/`: fuentes en `dl/` según `sources.urls`/`sources.sha256`;
  `scripts/build-android.sh all`, `scripts/verify-android.sh`,
  `scripts/package-android.sh <dir con libmediakitandroidhelper.so de v1.1.11>`.
  NDK 28.2.13676358, API 21.
- `windows/recipe/`: `fetch-windows.sh`, `build-windows.sh x86_64|aarch64`,
  `verify-windows.sh`, `package-windows.sh`. llvm-mingw 20261006 en macOS.
- Parches propios en `*/patches/`. `ffmpeg-fix-yadif-videotoolbox-autorelease`
  corrige un over-release de FFmpeg 8 que tumbaba la app al cerrar un reproductor
  que había usado `yadif_videotoolbox`.
- Cada Release debe llevar, junto a los binarios, las fuentes exactas, estas
  recetas y las líneas de configure (LGPL-2.1, sección 6).

## r2: sin decoders E-AC-3 ni DTS (2026-11-08)

Las mismas recetas y fuentes que r1, con una sola diferencia en FFmpeg:
`--disable-decoder=truehd,mlp,vvc,eac3,dca`. Binarios en la Release
`libmpv-lgpl-r2` de este fork.

- Fuera, por patentes, los decoders `eac3` (E-AC-3, Dolby Digital Plus) y `dca`
  (DTS, DTS-HD), como ya lo estaban `truehd`, `mlp` y `vvc`.
- Siguen `ac3` y `ac3_fixed` (la patente de AC-3 venció en 2017), los parsers `ac3`
  (que también cubre E-AC-3) y `dca`, los demuxers `ac3`, `eac3`, `dts`, `dtshd`,
  `truehd` y `spdif`, y el muxer `spdif`: DTS, DTS-HD, E-AC-3 y TrueHD siguen
  saliendo sin decodificar por `audio-spdif` hacia un amplificador.
- En Apple, E-AC-3 lo decodifica el sistema (`eac3_at` de AudioToolbox), y AC-3
  `ac3_at` o `ac3`. DTS no tiene decoder en ninguna plataforma.
- `verify*.sh` exige `CONFIG_EAC3_DECODER=0` y `CONFIG_DCA_DECODER=0`, y
  `package-apple.sh` escribe también `dist/configure-apple-<segmento>.txt`.
