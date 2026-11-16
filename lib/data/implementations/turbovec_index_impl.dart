import 'dart:ffi' as ffi;
import 'dart:io' show File, FileSystemEntity, FileSystemEntityType;
import 'package:ffi/ffi.dart';
import '../../domain/models/turbovec_result.dart';
import '../../domain/use_cases/turbovec_index.dart';
import 'turbovec_bindings.dart';

/// A concrete implementation of TurboVecIndex using FFI bindings.
class TurboVecIndexImpl implements TurboVecIndex {
  static const int maxDimension = TurboVecSecurityPolicy.maxDimension;
  static const int maxSearchK = TurboVecSecurityPolicy.maxSearchK;
  static const int maxBatchVectors = TurboVecSecurityPolicy.maxBatchVectors;
  static const int maxAllowlistSize = TurboVecSecurityPolicy.maxAllowlistSize;
  static const Set<int> supportedBitWidths =
      TurboVecSecurityPolicy.supportedBitWidths;

  ffi.Pointer<IdMapIndexOpaque> _ptr;
  bool _closed = false;

  TurboVecIndexImpl._(this._ptr);

  static void _validateBitWidth(int bitWidth) =>
      TurboVecSecurityPolicy.validateBitWidth(bitWidth);

  static bool _hasSymlinkAncestorSync(String rawPath) {
    var current = File(rawPath).parent.path;
    for (var depth = 0; depth < 64; depth++) {
      if (current.isEmpty ||
          current == '.' ||
          current == '/' ||
          current == '/tmp' ||
          current == '/var' ||
          current == '/etc' ||
          RegExp(r'^[A-Za-z]:[\\/]?$').hasMatch(current)) {
        break;
      }
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        return true;
      }
      final next = File(current).parent.path;
      if (next == current) break;
      current = next;
    }
    return false;
  }

  static String _validateIoPath(String path, {required bool mustExistFile}) {
    final cleanPath = TurboVecSecurityPolicy.validatePath(path);
    final entityType = FileSystemEntity.typeSync(cleanPath, followLinks: false);
    if (entityType == FileSystemEntityType.link ||
        entityType == FileSystemEntityType.directory ||
        _hasSymlinkAncestorSync(cleanPath)) {
      throw ArgumentError.value(
        path,
        'path',
        'Symlink and directory index paths are forbidden',
      );
    }
    if (mustExistFile && entityType != FileSystemEntityType.file) {
      throw StateError('Failed to load turbovec index from path: $cleanPath');
    }
    return cleanPath;
  }

  static void _validateId(int id) => TurboVecSecurityPolicy.validateId(id);

  static void _validateFiniteVector(List<double> vector, String paramName) =>
      TurboVecSecurityPolicy.validateFiniteVector(vector, paramName);

  /// Load a previously saved index from [path].
  factory TurboVecIndexImpl.load(String path) {
    final cleanPath = _validateIoPath(path, mustExistFile: true);
    final bindings = TurboVecBindings.instance;
    final pathPtr = cleanPath.toNativeUtf8();
    try {
      final ptr = bindings.loadIndex(pathPtr);
      if (ptr.address == 0) {
        throw StateError('Failed to load turbovec index from path: $cleanPath');
      }
      return TurboVecIndexImpl._(ptr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Create an empty index that infers its dimension on the first add call.
  factory TurboVecIndexImpl.createLazy({int bitWidth = 4}) {
    _validateBitWidth(bitWidth);
    final bindings = TurboVecBindings.instance;
    final ptr = bindings.createLazyIndex(bitWidth);
    if (ptr.address == 0) {
      throw StateError('Failed to create lazy turbovec index');
    }
    return TurboVecIndexImpl._(ptr);
  }

  /// Create an empty index with a fixed dimensionality (must be a multiple of 8).
  factory TurboVecIndexImpl.create(int dim, {int bitWidth = 4}) {
    TurboVecSecurityPolicy.validateDim(dim);
    _validateBitWidth(bitWidth);
    final bindings = TurboVecBindings.instance;
    final ptr = bindings.createIndex(dim, bitWidth);
    if (ptr.address == 0) {
      throw StateError('Failed to create turbovec index with dim $dim');
    }
    return TurboVecIndexImpl._(ptr);
  }

  void _checkNotClosed() {
    if (_closed) {
      throw StateError('Cannot operate on a closed TurboVecIndex');
    }
  }

  @override
  int get len {
    _checkNotClosed();
    return TurboVecBindings.instance.getLen(_ptr);
  }

  @override
  int get dim {
    _checkNotClosed();
    return TurboVecBindings.instance.getDim(_ptr);
  }

  @override
  void add(int id, List<double> vector) {
    _checkNotClosed();
    if (vector.isEmpty) return;
    _validateId(id);
    _validateFiniteVector(vector, 'vector');
    final expectedDim = dim;
    if (expectedDim == 0 && vector.length % 8 != 0) {
      throw ArgumentError.value(
        vector.length,
        'vector.length',
        'TurboVec requires vector dimension to be a multiple of 8',
      );
    }
    if (expectedDim > 0 && vector.length != expectedDim) {
      throw ArgumentError(
        'Vector dimension (${vector.length}) does not match index dimension ($expectedDim)',
      );
    }

    final bindings = TurboVecBindings.instance;
    final vectorsPtr = malloc.allocate<ffi.Float>(
      ffi.sizeOf<ffi.Float>() * vector.length,
    );
    final idsPtr = malloc.allocate<ffi.Uint64>(ffi.sizeOf<ffi.Uint64>());

    try {
      idsPtr[0] = id;
      for (var i = 0; i < vector.length; i++) {
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

  @override
  void addBatch(List<int> ids, List<List<double>> vectors) {
    _checkNotClosed();
    if (ids.isEmpty || vectors.isEmpty) return;
    if (ids.length != vectors.length) {
      throw ArgumentError('ids and vectors lists must have the same length');
    }

    final count = ids.length;
    final vectorDim = vectors.first.length;
    if (vectorDim == 0) return;
    final expectedDim = dim;
    TurboVecSecurityPolicy.validateBatchDimensions(
      idsLength: count,
      vectorsLength: vectors.length,
      vectorDim: vectorDim,
      expectedDim: expectedDim,
    );

    for (var i = 0; i < count; i++) {
      _validateId(ids[i]);
      final vec = vectors[i];
      if (vec.length != vectorDim) {
        throw ArgumentError(
          'All vectors in the batch must have the same dimension ($vectorDim)',
        );
      }
      _validateFiniteVector(vec, 'vectors[$i]');
    }

    final bindings = TurboVecBindings.instance;
    final vectorsPtr = malloc.allocate<ffi.Float>(
      ffi.sizeOf<ffi.Float>() * count * vectorDim,
    );
    final idsPtr = malloc.allocate<ffi.Uint64>(
      ffi.sizeOf<ffi.Uint64>() * count,
    );

    try {
      for (var i = 0; i < count; i++) {
        idsPtr[i] = ids[i];
        final vec = vectors[i];
        for (var j = 0; j < vectorDim; j++) {
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

  @override
  List<TurboVecResult> search(
    List<double> query,
    int k, {
    List<int>? allowlist,
  }) {
    _checkNotClosed();
    if (query.isEmpty || k <= 0 || len == 0) return [];
    _validateFiniteVector(query, 'query');

    final expectedDim = dim;
    if (expectedDim > 0 && query.length != expectedDim) {
      throw ArgumentError(
        'Query dimension (${query.length}) does not match index dimension ($expectedDim)',
      );
    }

    final boundedK = k.clamp(1, maxSearchK);
    final bindings = TurboVecBindings.instance;
    final queryPtr = malloc.allocate<ffi.Float>(
      ffi.sizeOf<ffi.Float>() * query.length,
    );

    ffi.Pointer<ffi.Uint64> allowlistPtr = ffi.nullptr;
    var allowlistLen = 0;
    if (allowlist != null && allowlist.isNotEmpty) {
      TurboVecSecurityPolicy.validateAllowlist(allowlist);
      allowlistLen = allowlist.length;
      allowlistPtr = malloc.allocate<ffi.Uint64>(
        ffi.sizeOf<ffi.Uint64>() * allowlistLen,
      );
      for (var i = 0; i < allowlistLen; i++) {
        allowlistPtr[i] = allowlist[i];
      }
    }

    final scoresOut = malloc.allocate<ffi.Float>(
      ffi.sizeOf<ffi.Float>() * boundedK,
    );
    final idsOut = malloc.allocate<ffi.Uint64>(
      ffi.sizeOf<ffi.Uint64>() * boundedK,
    );

    try {
      for (var i = 0; i < query.length; i++) {
        queryPtr[i] = query[i];
      }

      final rawCount = bindings.search(
        _ptr,
        queryPtr,
        boundedK,
        allowlistPtr,
        allowlistLen,
        scoresOut,
        idsOut,
      );
      final resultsCount = rawCount.clamp(0, boundedK);

      final results = <TurboVecResult>[];
      for (var i = 0; i < resultsCount; i++) {
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

  @override
  bool remove(int id) {
    _checkNotClosed();
    _validateId(id);
    return TurboVecBindings.instance.remove(_ptr, id);
  }

  @override
  void write(String path) {
    _checkNotClosed();
    final cleanPath = _validateIoPath(path, mustExistFile: false);
    final bindings = TurboVecBindings.instance;
    final pathPtr = cleanPath.toNativeUtf8();
    try {
      final ok = bindings.writeIndex(_ptr, pathPtr);
      if (!ok) {
        throw StateError(
          'Failed to write turbovec index to path: $cleanPath',
        );
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  @override
  void close() {
    if (_closed) return;
    TurboVecBindings.instance.freeIndex(_ptr);
    _ptr = ffi.nullptr;
    _closed = true;
  }
}
