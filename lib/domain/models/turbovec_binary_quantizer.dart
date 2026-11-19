import 'dart:math' as math;
import 'dart:typed_data';

import '../use_cases/turbovec_index.dart';
import 'turbovec_result.dart';

/// Pure-Dart / WebAssembly-ready 1-bit Binary Quantization (`BQ`) and
/// Matryoshka Representation Learning (`MRL`) utilities for `saia_turbovec`.
///
/// Compresses a `768`-dim `float32` vector (`3,072` bytes) into `24` `uint32`
/// words (`96` bytes — **96.875 %** RAM reduction) and evaluates Hamming
/// similarity via branchless SWAR 32-bit `popcount`.
class TurboVecBinaryQuantizer {
  TurboVecBinaryQuantizer._();

  /// Packs the sign bits (`v[i] > 0.0 -> 1`, else `0`) into 32-bit words.
  static Uint32List quantize1Bit(List<double> vector) {
    final n = vector.length;
    final wordCount = (n + 31) >> 5;
    final words = Uint32List(wordCount);
    for (var i = 0; i < n; i++) {
      if (vector[i] > 0.0) {
        words[i >> 5] |= (1 << (i & 31));
      }
    }
    return words;
  }

  /// Branchless SWAR 32-bit population count (`O(1)` operations per 32 dims).
  static int popcount32(int x) {
    var v = x & 0xFFFFFFFF;
    v = v - ((v >>> 1) & 0x55555555);
    v = (v & 0x33333333) + ((v >>> 2) & 0x33333333);
    return (((v + (v >>> 4)) & 0x0F0F0F0F) * 0x01010101 >>> 24) & 0xFF;
  }

  /// Computes normalized Hamming similarity in `[0.0, 1.0]` (`1 - d_H / dim`).
  static double hammingSimilarity(Uint32List a, Uint32List b, int dim) {
    if (dim <= 0 || a.isEmpty || b.isEmpty) return 0.0;
    final len = math.min(a.length, b.length);
    var diffBits = 0;
    for (var i = 0; i < len; i++) {
      diffBits += popcount32(a[i] ^ b[i]);
    }
    final clamped = diffBits.clamp(0, dim);
    return 1.0 - (clamped / dim);
  }

  /// Truncates a Matryoshka-trained embedding (e.g. Qwen3-Embedding / Nomic v1.5)
  /// to [targetDim] and L2-renormalizes it so inner product == cosine similarity.
  static Float32List truncateMatryoshka(
    List<double> vector,
    int targetDim, {
    bool l2Normalize = true,
  }) {
    if (targetDim <= 0) {
      throw RangeError.value(targetDim, 'targetDim', 'Must be positive');
    }
    final sliceLen = math.min(vector.length, targetDim);
    final out = Float32List(sliceLen);
    var normSq = 0.0;
    for (var i = 0; i < sliceLen; i++) {
      final v = vector[i];
      out[i] = v;
      normSq += v * v;
    }
    if (l2Normalize && normSq > 0.0) {
      final invNorm = 1.0 / math.sqrt(normSq);
      for (var i = 0; i < sliceLen; i++) {
        out[i] = out[i] * invNorm;
      }
    }
    return out;
  }
}

/// Pure-Dart / WebAssembly two-stage vector index (`1-bit BQ` Hamming shortlist
/// + `int8` scalar-quantized cosine rescoring) for Web and FFI-less runtimes.
class TurboVecBinaryIndex implements TurboVecIndex {
  int _dim;
  final int overfetchFactor;
  bool _closed = false;

  final Map<int, Uint32List> _codes = <int, Uint32List>{};
  final Map<int, Int8List> _int8Vectors = <int, Int8List>{};

  TurboVecBinaryIndex({int dim = 0, this.overfetchFactor = 4}) : _dim = dim;

  void _ensureOpen() {
    if (_closed) {
      throw StateError('Cannot operate on a closed TurboVecIndex');
    }
  }

  static Int8List _quantizeInt8Unit(List<double> vec) {
    var normSq = 0.0;
    for (var i = 0; i < vec.length; i++) {
      normSq += vec[i] * vec[i];
    }
    final scale = normSq > 0.0 ? (127.0 / math.sqrt(normSq)) : 0.0;
    final out = Int8List(vec.length);
    for (var i = 0; i < vec.length; i++) {
      out[i] = (vec[i] * scale).round().clamp(-127, 127);
    }
    return out;
  }

  static double _cosineInt8(Int8List a, Int8List b) {
    var dot = 0;
    var normA = 0;
    var normB = 0;
    for (var i = 0; i < a.length; i++) {
      final va = a[i];
      final vb = b[i];
      dot += va * vb;
      normA += va * va;
      normB += vb * vb;
    }
    if (normA <= 0 || normB <= 0) return 0.0;
    return dot / math.sqrt(normA.toDouble() * normB.toDouble());
  }

  @override
  int get len {
    _ensureOpen();
    return _codes.length;
  }

  @override
  int get dim {
    _ensureOpen();
    return _dim;
  }

  @override
  void add(int id, List<double> vector) {
    _ensureOpen();
    if (vector.isEmpty) return;
    TurboVecSecurityPolicy.validateId(id);
    TurboVecSecurityPolicy.validateFiniteVector(vector, 'vector');
    if (_dim == 0) {
      TurboVecSecurityPolicy.validateDim(vector.length);
      _dim = vector.length;
    } else if (vector.length != _dim) {
      throw ArgumentError(
        'Vector dimension (${vector.length}) does not match index dimension ($_dim)',
      );
    }
    _codes[id] = TurboVecBinaryQuantizer.quantize1Bit(vector);
    _int8Vectors[id] = _quantizeInt8Unit(vector);
  }

  @override
  void addBatch(List<int> ids, List<List<double>> vectors) {
    _ensureOpen();
    if (ids.isEmpty || vectors.isEmpty) return;
    final vectorDim = vectors.first.length;
    if (vectorDim == 0) return;
    TurboVecSecurityPolicy.validateBatchDimensions(
      idsLength: ids.length,
      vectorsLength: vectors.length,
      vectorDim: vectorDim,
      expectedDim: _dim,
    );
    for (var i = 0; i < ids.length; i++) {
      if (vectors[i].length != vectorDim) {
        throw ArgumentError(
          'All vectors in the batch must have the same dimension ($vectorDim)',
        );
      }
      add(ids[i], vectors[i]);
    }
  }

  @override
  List<TurboVecResult> search(
    List<double> query,
    int k, {
    List<int>? allowlist,
  }) {
    _ensureOpen();
    if (query.isEmpty || k <= 0 || _codes.isEmpty) return const [];
    if (k > TurboVecSecurityPolicy.maxSearchK) {
      throw RangeError.range(k, 1, TurboVecSecurityPolicy.maxSearchK, 'k');
    }
    TurboVecSecurityPolicy.validateFiniteVector(query, 'query');
    if (query.length != _dim) {
      throw ArgumentError(
        'Query dimension (${query.length}) does not match index dimension ($_dim)',
      );
    }
    Set<int>? allowedSet;
    if (allowlist != null) {
      TurboVecSecurityPolicy.validateAllowlist(allowlist);
      if (allowlist.isEmpty) return const [];
      allowedSet = allowlist.toSet();
    }

    final qBits = TurboVecBinaryQuantizer.quantize1Bit(query);
    final shortlistCap = math.max(k * overfetchFactor, 32);
    final bqCandidates = <({int id, double bq})>[];

    if (allowedSet != null) {
      for (final id in allowedSet) {
        final code = _codes[id];
        if (code == null) continue;
        bqCandidates.add((
          id: id,
          bq: TurboVecBinaryQuantizer.hammingSimilarity(qBits, code, _dim),
        ));
      }
    } else {
      _codes.forEach((id, code) {
        bqCandidates.add((
          id: id,
          bq: TurboVecBinaryQuantizer.hammingSimilarity(qBits, code, _dim),
        ));
      });
    }

    if (bqCandidates.isEmpty) return const [];
    bqCandidates.sort((a, b) => b.bq.compareTo(a.bq));

    final qInt8 = _quantizeInt8Unit(query);
    final rescored = <TurboVecResult>[];
    final inspectCount = math.min(bqCandidates.length, shortlistCap);
    for (var i = 0; i < inspectCount; i++) {
      final id = bqCandidates[i].id;
      final stored = _int8Vectors[id];
      final score = stored != null
          ? _cosineInt8(qInt8, stored)
          : bqCandidates[i].bq;
      rescored.add(TurboVecResult(id: id, score: score));
    }
    rescored.sort((a, b) => b.score.compareTo(a.score));
    return rescored.take(k).toList(growable: false);
  }

  @override
  bool remove(int id) {
    _ensureOpen();
    TurboVecSecurityPolicy.validateId(id);
    _int8Vectors.remove(id);
    return _codes.remove(id) != null;
  }

  @override
  void write(String path) {
    TurboVecSecurityPolicy.validatePath(path);
    throw UnsupportedError('Filesystem index persistence requires native IO.');
  }

  @override
  void close() {
    _closed = true;
    _codes.clear();
    _int8Vectors.clear();
  }
}
