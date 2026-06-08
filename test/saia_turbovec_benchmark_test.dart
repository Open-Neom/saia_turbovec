import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:saia_turbovec/saia_turbovec.dart';

void main() {
  test('Benchmark: Pure Dart Cosine Similarity vs TurboVec FFI Search', () {
    const int N = 1000; // number of vectors in DB
    const int D = 1536; // dimension of embeddings (Gemini/OpenAI)
    const int K = 10;   // top K results

    print('=== starting saia_turbovec search benchmark ===');
    print('Generating synthetic dataset: $N vectors of dimension $D...');
    final random = Random(42);

    // 1. Generate Float32 vectors in Dart
    final List<List<double>> dbVectors = List.generate(N, (_) {
      final v = List<double>.generate(D, (_) => random.nextDouble() * 2 - 1);
      double norm = 0;
      for (int i = 0; i < D; i++) norm += v[i] * v[i];
      norm = sqrt(norm);
      for (int i = 0; i < D; i++) v[i] /= norm; // normalize
      return v;
    });

    final query = List<double>.generate(D, (_) => random.nextDouble() * 2 - 1);
    double qNorm = 0;
    for (int i = 0; i < D; i++) qNorm += query[i] * query[i];
    qNorm = sqrt(qNorm);
    for (int i = 0; i < D; i++) query[i] /= qNorm;

    // -------------------------------------------------------------
    // BENCHMARK 1: Baseline Brute-Force loop in Dart
    // -------------------------------------------------------------
    print('\n[1/3] Running baseline: Brute-force Cosine Similarity in Dart...');
    final stopwatch1 = Stopwatch()..start();
    final scores1 = Float32List(N);
    for (int iter = 0; iter < 100; iter++) {
      for (int i = 0; i < N; i++) {
        final v = dbVectors[i];
        double dot = 0;
        for (int j = 0; j < D; j++) {
          dot += query[j] * v[j];
        }
        scores1[i] = dot;
      }
      final indices = List.generate(N, (index) => index);
      indices.sort((a, b) => scores1[b].compareTo(scores1[a]));
    }
    stopwatch1.stop();
    final time1 = stopwatch1.elapsedMicroseconds / 100;
    print('  -> Baseline Dart loop latency: ${time1.toStringAsFixed(2)} us (${(time1 / 1000.0).toStringAsFixed(3)} ms)');

    // -------------------------------------------------------------
    // BENCHMARK 2: Pure Dart TurboQuant Simulation (4-bit unpack)
    // -------------------------------------------------------------
    print('\n[2/3] Running simulation: Pure Dart TurboQuant 4-bit (LUT & bitwise unpack)...');
    final List<Uint8List> dbPacked = List.generate(N, (_) {
      final bytes = Uint8List(D ~/ 2);
      for (int i = 0; i < D ~/ 2; i++) {
        bytes[i] = (random.nextInt(16) << 4) | random.nextInt(16);
      }
      return bytes;
    });
    final lut = Float32List(16);
    for (int i = 0; i < 16; i++) lut[i] = random.nextDouble();

    final stopwatch2 = Stopwatch()..start();
    for (int iter = 0; iter < 100; iter++) {
      final scores2 = Float32List(N);
      for (int i = 0; i < N; i++) {
        final packed = dbPacked[i];
        double score = 0;
        final len = D ~/ 2;
        for (int j = 0; j < len; j++) {
          final byte = packed[j];
          score += lut[byte >> 4] + lut[byte & 0x0F];
        }
        scores2[i] = score;
      }
      final indices = List.generate(N, (index) => index);
      indices.sort((a, b) => scores2[b].compareTo(scores2[a]));
    }
    stopwatch2.stop();
    final time2 = stopwatch2.elapsedMicroseconds / 100;
    print('  -> Pure Dart TurboQuant latency: ${time2.toStringAsFixed(2)} us (${(time2 / 1000.0).toStringAsFixed(3)} ms)');

    // -------------------------------------------------------------
    // BENCHMARK 3: TurboVec Index via C/Rust FFI
    // -------------------------------------------------------------
    print('\n[3/3] Running native: TurboVecIndex FFI (Quantized & SIMD)...');
    final index = TurboVecIndex.createLazy(bitWidth: 4);
    final ids = List.generate(N, (i) => i);
    index.addBatch(ids, dbVectors);

    final stopwatch3 = Stopwatch()..start();
    for (int iter = 0; iter < 100; iter++) {
      index.search(query, K);
    }
    stopwatch3.stop();
    final time3 = stopwatch3.elapsedMicroseconds / 100;
    print('  -> TurboVec FFI search latency: ${time3.toStringAsFixed(2)} us (${(time3 / 1000.0).toStringAsFixed(3)} ms)');

    // 4. Verify relative speedup
    final speedupVsDart = time1 / time3;
    final speedupVsSim = time2 / time3;
    print('\n=== benchmark summary ===');
    print('  - Speedup vs Dart Brute-force: ${speedupVsDart.toStringAsFixed(2)}x faster');
    print('  - Speedup vs Dart TurboQuant Simulation: ${speedupVsSim.toStringAsFixed(2)}x faster');

    index.close();
    expect(speedupVsDart, greaterThan(2.0)); // FFI must be significantly faster
  });
}
