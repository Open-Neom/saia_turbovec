# saia_turbovec

![TurboVec Logo](assets/turbovec_logo.png)

High-performance, 4-bit quantized vector similarity search for Flutter and Dart. Encapsulates Google Research's **TurboQuant** algorithm via native FFI bindings, optimizing memory footprint and query speed for AI-powered long-term memory.

## Features

- **⚡ Blazing Fast SIMD Execution**: Queries run in **~1.1 ms** for 10,000 high-dimensional vectors (D=1536) on modern mobile/desktop CPUs using NEON (ARM64) or AVX (x86_64) instructions via Rust/C FFI (up to **15.5x faster** than pure Dart loops).
- **📉 8x Memory Reduction**: Compresses Float32 vectors down to 4-bit quantized codes, reducing index RAM consumption by 8x (critical for mobile apps and low-memory environments).
- **🔒 Granular Search Filters**: Built-in support for `allowlist` filters to restrict query search to specific IDs (perfect for multi-workspace, multi-user, or catalog-specific searches).
- **💾 Easy Persistence**: Direct save-to-disk and load-from-disk methods for fast serialisation and deserialisation of index states.
- **🛠️ Self-Contained & Isolated**: Safe wrapper around native pointers, automating allocation/deallocation and ensuring no memory leaks in Dart's garbage collector.

---

## Performance Benchmark

Tested on a macOS ARM64 machine searching for the nearest neighbors among **10,000 vectors** of **1536 dimensions** (e.g. standard Gemini embeddings):

| Implementation | Average Query Time | Speedup vs Dart Loop | Memory Footprint |
|---|---|---|---|
| **Pure Dart Linear Loop** | 17.43 ms | 1.0x (Baseline) | High (Raw Float32) |
| **Pure Dart TurboQuant** | 66.84 ms | 0.26x (Bit-unpack overhead) | **Low (4-bit)** |
| **C/Rust FFI (`saia_turbovec`)** | **1.12 ms** | **15.5x** | **Low (4-bit)** |

---

## Getting Started

### 1. Installation

Add `saia_turbovec` to your `pubspec.yaml`:

```yaml
dependencies:
  saia_turbovec:
    path: path/to/neom_modules/ai/saia_turbovec
```

### 2. Bundling Native Libraries

Because this package relies on native FFI bindings, you must compile and bundle the `turbovec` C-shared library:

#### macOS
Place the compiled `libturbovec.dylib` in your macOS app bundle. When creating a Flutter plugin package, place it at `macos/libturbovec.dylib` and add `s.vendored_libraries = 'libturbovec.dylib'` inside `saia_turbovec.podspec`.

#### Android
Compile the `.so` binaries for the target architectures (`arm64-v8a`, `armeabi-v7a`, `x86_64`) and place them in:
`android/src/main/jniLibs/<architecture>/libturbovec.so`.

#### iOS
Compile a universal iOS framework or `libturbovec.a` static library and configure the CocoaPods podspec to vendor it.

---

## Usage Example

```dart
import 'dart:typed_data';
import 'package:saia_turbovec/saia_turbovec.dart';

void main() {
  // 1. Create a lazy index (it infers the dimension from the first added vector)
  final index = TurboVecIndex.createLazy(bitWidth: 4);

  // 2. Add vectors
  final vector1 = List<double>.generate(1536, (i) => i / 1536.0);
  final vector2 = List<double>.generate(1536, (i) => (1536 - i) / 1536.0);

  index.add(101, vector1);
  index.add(102, vector2);

  print('Index length: ${index.len}'); // Prints: 2
  print('Vector dimension: ${index.dim}'); // Prints: 1536

  // 3. Search nearest neighbors
  final query = List<double>.generate(1536, (i) => i / 1536.0);
  final results = index.search(query, 5);

  for (final res in results) {
    print('Found ID: ${res.id}, similarity score: ${res.score.toStringAsFixed(4)}');
  }

  // 4. Search with an allowlist (filtering query targets)
  final filteredResults = index.search(query, 5, allowlist: [102]);
  // Only ID 102 will be considered in the search

  // 5. Save the index state
  index.write('path/to/my_index.tvim');

  // 6. Close the index to free native memory
  index.close();
}
```

## License

This project is licensed under the MIT License.
