import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'src/turbovec_bindings.dart';
export 'src/turbovec_bindings.dart' show TurboVecBindings;


/// Represents a result match from a vector query search.
class TurboVecResult {
  final int id;
  final double score;

  const TurboVecResult({required this.id, required this.score});

  @override
  String toString() =>
      'TurboVecResult(id: $id, score: ${score.toStringAsFixed(4)})';
}

/// A TurboQuant quantized vector index with stable external uint64 IDs.
class TurboVecIndex {
  ffi.Pointer<IdMapIndexOpaque> _ptr;
  bool _closed = false;

  TurboVecIndex._(this._ptr);

  /// Load a previously saved index from [path].
  factory TurboVecIndex.load(String path) {
    final bindings = TurboVecBindings.instance;
    final pathPtr = path.toNativeUtf8();
    try {
      final ptr = bindings.loadIndex(pathPtr);
      if (ptr.address == 0) {
        throw StateError('Failed to load turbovec index from path: $path');
      }
      return TurboVecIndex._(ptr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Create an empty index that infers its dimension on the first add call.
  factory TurboVecIndex.createLazy({int bitWidth = 4}) {
    final bindings = TurboVecBindings.instance;
    final ptr = bindings.createLazyIndex(bitWidth);
    if (ptr.address == 0) {
      throw StateError('Failed to create lazy turbovec index');
    }
    return TurboVecIndex._(ptr);
  }

  /// Create an empty index with a fixed dimensionality.
  factory TurboVecIndex.create(int dim, {int bitWidth = 4}) {
    final bindings = TurboVecBindings.instance;
    final ptr = bindings.createIndex(dim, bitWidth);
    if (ptr.address == 0) {
      throw StateError('Failed to create turbovec index with dim $dim');
    }
    return TurboVecIndex._(ptr);
  }

  /// Ensure the index is not closed before operating on it.
  void _checkNotClosed() {
    if (_closed) {
      throw StateError('Cannot operate on a closed TurboVecIndex');
    }
  }

  /// Get the number of vectors in the index.
  int get len {
    _checkNotClosed();
    return TurboVecBindings.instance.getLen(_ptr);
  }

  /// Get the vector dimension, or 0 if not yet inferred.
  int get dim {
    _checkNotClosed();
    return TurboVecBindings.instance.getDim(_ptr);
  }

  /// Add a single vector to the index.
  void add(int id, List<double> vector) {
    _checkNotClosed();
    if (vector.isEmpty) return;

    final bindings = TurboVecBindings.instance;
    final vectorsPtr = malloc.allocate<ffi.Float>(
      ffi.sizeOf<ffi.Float>() * vector.length,
    );
    final idsPtr = malloc.allocate<ffi.Uint64>(ffi.sizeOf<ffi.Uint64>());

    try {
      idsPtr[0] = id;
      for (int i = 0; i < vector.length; i++) {
        vectorsPtr[i] = vector[i];
      }

      final ok = bindings.addWithIds2d(
        _ptr,
        vectorsPtr,
        vector.length,
        idsPtr,
        1,
      );
      if (!ok) {
        throw StateError('Failed to add vector with id $id to turbovec index');
      }
    } finally {
      malloc.free(vectorsPtr);
      malloc.free(idsPtr);
    }
  }

  /// Add a batch of vectors with stable 64-bit integer IDs.
  void addBatch(List<int> ids, List<List<double>> vectors) {
    _checkNotClosed();
    if (ids.isEmpty || vectors.isEmpty) return;
    if (ids.length != vectors.length) {
      throw ArgumentError('ids and vectors lists must have the same length');
    }

    final count = ids.length;
    final vectorDim = vectors.first.length;
    if (vectorDim == 0) return;

    final bindings = TurboVecBindings.instance;
    final vectorsPtr = malloc.allocate<ffi.Float>(
      ffi.sizeOf<ffi.Float>() * count * vectorDim,
    );
    final idsPtr = malloc.allocate<ffi.Uint64>(
      ffi.sizeOf<ffi.Uint64>() * count,
    );

    try {
      for (int i = 0; i < count; i++) {
        idsPtr[i] = ids[i];
        final vec = vectors[i];
        if (vec.length != vectorDim) {
          throw ArgumentError(
            'All vectors in the batch must have the same dimension ($vectorDim)',
          );
        }
        for (int j = 0; j < vectorDim; j++) {
          vectorsPtr[i * vectorDim + j] = vec[j];
        }
      }

      final ok = bindings.addWithIds2d(
        _ptr,
        vectorsPtr,
        vectorDim,
        idsPtr,
        count,
      );
      if (!ok) {
        throw StateError(
          'Failed to add batch of $count vectors to turbovec index',
        );
      }
    } finally {
      malloc.free(vectorsPtr);
      malloc.free(idsPtr);
    }
  }

  /// Search the index for the top-[k] most similar matches to [query].
  ///
  /// Optionally restricts results to candidates in [allowlist].
  List<TurboVecResult> search(
    List<double> query,
    int k, {
    List<int>? allowlist,
  }) {
    _checkNotClosed();
    if (query.isEmpty || k <= 0 || len == 0) return [];

    final bindings = TurboVecBindings.instance;
    final queryPtr = malloc.allocate<ffi.Float>(
      ffi.sizeOf<ffi.Float>() * query.length,
    );
    for (int i = 0; i < query.length; i++) {
      queryPtr[i] = query[i];
    }

    ffi.Pointer<ffi.Uint64> allowlistPtr = ffi.nullptr;
    int allowlistLen = 0;
    if (allowlist != null && allowlist.isNotEmpty) {
      allowlistLen = allowlist.length;
      allowlistPtr = malloc.allocate<ffi.Uint64>(
        ffi.sizeOf<ffi.Uint64>() * allowlistLen,
      );
      for (int i = 0; i < allowlistLen; i++) {
        allowlistPtr[i] = allowlist[i];
      }
    }

    // Allocate output buffers
    final scoresOut = malloc.allocate<ffi.Float>(ffi.sizeOf<ffi.Float>() * k);
    final idsOut = malloc.allocate<ffi.Uint64>(ffi.sizeOf<ffi.Uint64>() * k);

    try {
      final resultsCount = bindings.search(
        _ptr,
        queryPtr,
        k,
        allowlistPtr,
        allowlistLen,
        scoresOut,
        idsOut,
      );

      final results = <TurboVecResult>[];
      for (int i = 0; i < resultsCount; i++) {
        results.add(TurboVecResult(id: idsOut[i], score: scoresOut[i]));
      }
      return results;
    } finally {
      malloc.free(queryPtr);
      if (allowlistPtr != ffi.nullptr) {
        malloc.free(allowlistPtr);
      }
      malloc.free(scoresOut);
      malloc.free(idsOut);
    }
  }

  /// Remove a vector by [id]. Returns true if found and removed.
  bool remove(int id) {
    _checkNotClosed();
    return TurboVecBindings.instance.remove(_ptr, id);
  }

  /// Write the index file to [path].
  void write(String path) {
    _checkNotClosed();
    final bindings = TurboVecBindings.instance;
    final pathPtr = path.toNativeUtf8();
    try {
      final ok = bindings.writeIndex(_ptr, pathPtr);
      if (!ok) {
        throw StateError('Failed to write turbovec index to path: $path');
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Free native memory allocated for this index.
  void close() {
    if (_closed) return;
    TurboVecBindings.instance.freeIndex(_ptr);
    _ptr = ffi.nullptr;
    _closed = true;
  }
}
