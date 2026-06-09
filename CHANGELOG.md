## 1.0.1

* Fix package logo rendering on pub.dev by using absolute raw GitHub URL.

## 1.0.0

* Initial release of `saia_turbovec`.
* Fully functional bindings for Google Research's `turbovec` (TurboQuant algorithm).
* Support for lazy initialization, quantized 4-bit vector search, batch insertion, allowed filters (allowlists), record deletion, index persistence, and native memory release.
* Platform compilation configurations and bundled precompiled binaries for macOS (`libturbovec.dylib`), iOS (`turbovec.xcframework` simulator + device), and Android (`libturbovec.so` ARM64/x86_64).
* Decoupled architecture under **Open Neom** standards (`domain/models`, `domain/use_cases`, and `data/implementations` separation).
