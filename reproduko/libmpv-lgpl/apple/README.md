# libmpv LGPL para Apple (receta reproduko, r1)

Orden: `./setup-tools.sh && ./fetch.sh`, después por segmento
`./build-apple.sh <seg>` y `./verify.sh <seg>` (macos-arm64 macos-amd64 ios-arm64
iossimulator-arm64 iossimulator-amd64), y al final `./package-apple.sh macos` y
`./package-apple.sh ios`. Salida en dist/. Ver MANIFEST.txt.
