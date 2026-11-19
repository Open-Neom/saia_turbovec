import '../../domain/models/turbovec_binary_quantizer.dart';
import '../../domain/models/turbovec_result.dart';
import '../../domain/use_cases/turbovec_index.dart';

/// Web / pure-Dart `TurboVecIndex` backed by 1-bit Binary Quantization (`BQ`)
/// Hamming pre-filtering + `int8` cosine rescoring (`dart2wasm` & `dart2js` ready).
class TurboVecIndexImpl implements TurboVecIndex {
  static const int maxDimension = TurboVecSecurityPolicy.maxDimension;
  static const int maxSearchK = TurboVecSecurityPolicy.maxSearchK;
  static const int maxBatchVectors = TurboVecSecurityPolicy.maxBatchVectors;
  static const int maxAllowlistSize = TurboVecSecurityPolicy.maxAllowlistSize;
  static const Set<int> supportedBitWidths =
      TurboVecSecurityPolicy.supportedBitWidths;

  final TurboVecBinaryIndex _delegate;

  TurboVecIndexImpl._(this._delegate);

  @override
  int get len => _delegate.len;

  @override
  int get dim => _delegate.dim;

  /// Loads an existing index from the specified file [path] (native IO only).
  factory TurboVecIndexImpl.load(String path) {
    TurboVecSecurityPolicy.validatePath(path);
    throw UnsupportedError('TurboVecIndex file load is not supported on Web.');
  }

  /// Creates a lazy index that infers dimensions from the first added vector.
  factory TurboVecIndexImpl.createLazy({int bitWidth = 4}) {
    TurboVecSecurityPolicy.validateBitWidth(bitWidth);
    return TurboVecIndexImpl._(TurboVecBinaryIndex());
  }

  /// Creates an index with a pre-defined vector dimension [dim].
  factory TurboVecIndexImpl.create(int dim, {int bitWidth = 4}) {
    TurboVecSecurityPolicy.validateDim(dim);
    TurboVecSecurityPolicy.validateBitWidth(bitWidth);
    return TurboVecIndexImpl._(TurboVecBinaryIndex(dim: dim));
  }

  @override
  void add(int id, List<double> vector) => _delegate.add(id, vector);

  @override
  void addBatch(List<int> ids, List<List<double>> vectors) =>
      _delegate.addBatch(ids, vectors);

  @override
  List<TurboVecResult> search(
    List<double> query,
    int k, {
    List<int>? allowlist,
  }) =>
      _delegate.search(query, k, allowlist: allowlist);

  @override
  bool remove(int id) => _delegate.remove(id);

  @override
  void write(String path) => _delegate.write(path);

  @override
  void close() => _delegate.close();
}
