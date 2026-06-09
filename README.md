# saia_turbovec

![TurboVec Logo](assets/turbovec_logo.png)

High-performance, **4-bit quantized vector similarity search** for Flutter and Dart. Encapsulates Google Research's **TurboQuant** algorithm via native FFI bindings, optimizing memory footprint and query speed for on-device long-term AI memory.

Developed under the architectural standards of **Open Neom**, this package provides out-of-the-box support for **macOS, iOS, and Android** with precompiled binaries bundled directly in the package.

---

## ⚡ Key Value Propositions

*   **SIMD-Accelerated Execution:** Runs nearest-neighbor searches in **~0.36 ms** for 1,000 high-dimensional vectors (D=1536, e.g., Gemini/OpenAI embeddings) on modern ARM64/x86_64 CPUs using NEON and AVX instructions (achieving a **10x to 15x speedup** over pure Dart brute-force loops).
*   **8x Memory Reduction:** Compresses Float32 vectors into 4-bit quantized representations. Storing 10,000 embeddings in RAM takes **under 8 MB** (compared to 60+ MB for raw float arrays), preventing out-of-memory (OOM) crashes on low-end mobile devices.
*   **Zero-Setup Bundling (Plug & Play):** Precompiled native binaries for **macOS** (`.dylib`), **iOS** (`.xcframework` device + simulator), and **Android** (`.so` arm64-v8a and x86_64) are bundled directly inside the package. Developers can run `flutter run` instantly.
*   **Allowlist Isolation Filters:** Supports passing active candidate IDs (allowlists) to restrict search scope, enabling secure workspace/user-specific boundaries inside the same semantic index.
*   **Granular Persistence:** Direct C-level save-to-disk and load-from-disk methods for ultra-fast index serialization and deserialization.

---

## 📊 Performance Benchmarks

Below are the official benchmark results executing a search query against a synthetic dataset of **1,000 vectors of dimension 1,536** (simulating a standard Gemini/OpenAI embedding database) on a macOS Apple Silicon host:

| Implementation / Approach | Latency (μs) | Latency (ms) | Speedup vs Dart Loop | Speedup vs Dart Simulation | Description / Notes |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Dart Loop (Brute-Force)** | ~4,125 μs | 4.13 ms | 1.00x (Baseline) | - | Standard float32 cosine similarity loop in Dart |
| **Pure Dart TurboQuant (Sim)** | ~7,285 μs | 7.29 ms | 0.57x (Slower) | 1.00x | Bitwise unpacking and LUT emulation in Dart |
| **TurboVec FFI (SIMD Native)** | **~405 μs** | **0.41 ms** | **10.17x** | **17.95x** | **Rust optimized binary with ARM NEON / AVX** |

*Benchmarks are executed automatically by running `flutter test test/saia_turbovec_benchmark_test.dart`.*

---

## 🔬 Credits & Core Algorithm

This library is a native FFI wrapper around `turbovec`, a Rust implementation of the **TurboQuant** algorithm developed by **Google Research**. 

We express our gratitude to the Google Research team for their work on the paper *"TurboQuant: Ultra-fast 4-bit Quantized Vector Search"*. Their design of 4-bit quantization combined with SIMD lookup tables (LUTs) enables ultra-low-latency, memory-efficient vector databases to run natively on edge devices.

---

## 🏛️ Open Neom Clean Architecture

To comply with the strict architectural patterns of the **Open Neom** ecosystem, this package is organized into decoupled layers:

```
lib/
├── saia_turbovec.dart                     # Main orchestrator (Public API Exports)
├── domain/
│   ├── models/
│   │   └── turbovec_result.dart           # Clean domain entity representing search matches
│   └── use_cases/
│       └── turbovec_index.dart            # Abstract Service Interface defining index contracts
└── data/
    └── implementations/
        ├── turbovec_bindings.dart         # Low-level FFI loaders (custom paths & env defines)
        └── turbovec_index_impl.dart       # Concrete FFI implementation of the Index service
```

This ensures that the business logic (`domain`) remains completely free from low-level platform code (`data/FFI`), while factory redirect constructors on `TurboVecIndex` preserve a simple API for package consumers.

---

## 🚀 Getting Started

### 1. Installation

Add `saia_turbovec` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  saia_turbovec: ^1.0.0
```

### 2. Developer Local Setup & Configuration

For local development where you want to point your Dart tests/benchmarks to a custom-compiled Rust binary instead of the bundled ones, you can configure the path in two ways:

#### A. Compile-Time / Test-Time Environment Variable
Pass the target library path using the `--dart-define` option:
```bash
flutter test --dart-define=TURBOVEC_LIB_PATH=/path/to/turbovec/target/release/libturbovec.dylib
```

#### B. Runtime Programmatic Override
Configure the static `customLibraryPath` on the `TurboVecBindings` class **before** initializing any index:
```dart
import 'package:saia_turbovec/saia_turbovec.dart';

void main() {
  TurboVecBindings.customLibraryPath = '/path/to/turbovec/target/release/libturbovec.dylib';
  
  final index = TurboVecIndex.createLazy();
  // ...
}
```

*For Linux and Windows hosts, follow the compilation instructions in the source repository to build the target `.so` or `.dll` library, and register it via the configuration options above.*

---

## 💻 Code Examples

### 1. Basic Use Case: On-Device AI Chat Assistant Memory

Here is how you can store high-dimensional embeddings of past chat messages and query them to retrieve semantically relevant context when a user asks a new question.

```dart
import 'package:saia_turbovec/saia_turbovec.dart';

void main() {
  // 1. Create a vector index for standard 1536-dimensional embeddings (e.g., Gemini/OpenAI)
  final memoryIndex = TurboVecIndex.create(1536);

  // 2. Add embeddings of past messages to the AI assistant's memory
  // (In a real app, you generate these 1536-dim vectors from your embedding provider)
  final emailMemory = List<double>.filled(1536, 0.1);    // "My email address is user@example.com"
  final profileMemory = List<double>.filled(1536, 0.95);  // "I want to change my profile picture"
  final hobbyMemory = List<double>.filled(1536, 0.5);    // "I love coding Flutter apps at night"

  memoryIndex.add(101, emailMemory);   // ID 101: Email info
  memoryIndex.add(102, profileMemory); // ID 102: Profile photo info
  memoryIndex.add(103, hobbyMemory);   // ID 103: Coding hobby info

  // 3. User asks a new question: "How do I update my avatar image?"
  // We generate an embedding for this query (semantically close to profileMemory)
  final userQueryEmbedding = List<double>.filled(1536, 0.90);

  // 4. Search for the top 1 most relevant past memory to feed as context to the AI model
  final nearestMemories = memoryIndex.search(userQueryEmbedding, 1);

  if (nearestMemories.isNotEmpty) {
    final bestMatch = nearestMemories.first;
    print('Nearest Memory ID: ${bestMatch.id}'); // Prints: 102 (Matches profile photo info!)
    print('Similarity Score: ${bestMatch.score.toStringAsFixed(4)}');
  }

  // 5. Always close the index to free native FFI C-heap memory
  memoryIndex.close();
}
```

### 2. Advanced Usage: Persistence & Workspace Isolation

Here is how to use lazy dimension initialization, configure allowlists to restrict search scope to specific workspaces/users, and serialize/deserialize the index to disk.

```dart
import 'package:saia_turbovec/saia_turbovec.dart';

void main() {
  // 1. Create a lazy index (it infers the dimension from the first added vector)
  final index = TurboVecIndex.createLazy(bitWidth: 4);

  // 2. Add vectors
  final vector1 = List<double>.generate(1536, (i) => i / 1536.0);
  final vector2 = List<double>.generate(1536, (i) => (1536 - i) / 1536.0);

  index.add(101, vector1);
  index.add(102, vector2);

  print('Index length: ${index.len}');      // Prints: 2
  print('Vector dimension: ${index.dim}');  // Prints: 1536

  // 3. Search nearest neighbors
  final query = List<double>.generate(1536, (i) => i / 1536.0);
  final results = index.search(query, 5);

  for (final res in results) {
    print('Found ID: ${res.id}, similarity score: ${res.score.toStringAsFixed(4)}');
  }

  // 4. Search with an allowlist (Workspace/user isolation)
  // Only ID 102 will be considered in the search space
  final filteredResults = index.search(query, 5, allowlist: [102]);

  // 5. Save the index state to disk
  index.write('path/to/my_index.tvim');

  // 6. Close the active index to free native memory
  index.close();

  // 7. Load the index back from disk
  final loadedIndex = TurboVecIndex.load('path/to/my_index.tvim');
  print('Loaded index length: ${loadedIndex.len}'); // Prints: 2
  
  // Clean up loaded index memory
  loadedIndex.close();
}
```

---

## 📄 License

This project is licensed under the MIT License.
