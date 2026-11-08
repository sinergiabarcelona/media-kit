# libmpv LGPL para Apple (receta reproduko, r1)

Orden: `./setup-tools.sh && ./fetch.sh`, después por segmento
`./build-apple.sh <seg>` y `./verify.sh <seg>` (macos-arm64 macos-amd64 ios-arm64
iossimulator-arm64 iossimulator-amd64), y al final `./package-apple.sh macos` y
`./package-apple.sh ios`. Salida en dist/. Ver MANIFEST.txt.

tvOS (prueba de viabilidad, rama libmpv-lgpl-r2-tvos): segmentos tvos-arm64,
tvossimulator-arm64 y tvossimulator-amd64 con las mismas opciones que iOS
(OpenGL ES por EAGL, AudioUnit, decoders `*_at`), y `./package-apple.sh tvos`.
