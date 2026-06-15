import '../../domain/models/turbovec_result.dart';
import '../../domain/use_cases/turbovec_index.dart';

/// A stub/mock implementation of TurboVecIndex for platforms where FFI is not supported.
class TurboVecIndexImpl implements TurboVecIndex {
  @override
  int get len => 0;

  @override
  int get dim => 0;

  TurboVecIndexImpl._();

  /// Loads an existing index from the specified file [path].
  factory TurboVecIndexImpl.load(String path) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  /// Creates a lazy index that infers the dimensions from the first added vector.
  factory TurboVecIndexImpl.createLazy({int bitWidth = 4}) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  /// Creates an index with a pre-defined vector dimension [dim].
  factory TurboVecIndexImpl.create(int dim, {int bitWidth = 4}) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  @override
  void add(int id, List<double> vector) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  @override
  void addBatch(List<int> ids, List<List<double>> vectors) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  @override
  List<TurboVecResult> search(
    List<double> query,
    int k, {
    List<int>? allowlist,
  }) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  @override
  bool remove(int id) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  @override
  void write(String path) {
    throw UnsupportedError('TurboVecIndex is not supported on this platform.');
  }

  @override
  void close() {
    // No-op on stub
  }
}
