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
