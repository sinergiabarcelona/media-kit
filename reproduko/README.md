# Rama `reproduko` del fork de media-kit

Fork de https://github.com/media-kit/media-kit usado por reproduko (sinergiabarcelona/reproduko).

- Base: upstream `c533e446755f51cf53c7e57aea873f2aa5355f81` (media_kit 1.2.6), sin cambios en el código de media_kit (MIT).
- `reproduko/libmpv-lgpl/` + `.github/workflows/libmpv-lgpl.yml`: recetas para compilar libmpv/FFmpeg **solo LGPL**
  (`-Dgpl=false`, sin `--enable-gpl` ni `--enable-nonfree`) para Windows, Linux, tvOS y visionOS. Solo se lanzan a mano
  (`workflow_dispatch`). libmpv y FFmpeg conservan su licencia LGPL-2.1+; estas recetas son MPL-2.0.
- reproduko fija esta rama con la etiqueta `reproduko-2026.11.05`.
