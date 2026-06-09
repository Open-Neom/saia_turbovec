import '../models/turbovec_result.dart';
import '../../data/implementations/turbovec_index_impl.dart';

/// An on-device vector index that provides ultra-fast, 4-bit quantized
/// similarity search.
abstract class TurboVecIndex {
  /// Loads an existing index from the specified file [path].
  factory TurboVecIndex.load(String path) = TurboVecIndexImpl.load;

  /// Creates a lazy index that infers the dimensions from the first added vector.
  /// The [bitWidth] specifies the quantization bit width (default is 4).
  factory TurboVecIndex.createLazy({int bitWidth}) =
      TurboVecIndexImpl.createLazy;

  /// Creates an index with a pre-defined vector dimension [dim].
  /// The [bitWidth] specifies the quantization bit width (default is 4).
  factory TurboVecIndex.create(int dim, {int bitWidth}) =
      TurboVecIndexImpl.create;

  /// Returns the number of vectors stored in the index.
  int get len;

  /// Returns the dimension of the vectors in this index.
  int get dim;

  /// Adds a single [vector] associated with the given [id] to the index.
  void add(int id, List<double> vector);

  /// Adds a batch of [vectors] associated with their respective [ids] to the index.
  void addBatch(List<int> ids, List<List<double>> vectors);

  /// Searches the index for the top [k] most similar vectors to [query].
  ///
  /// Optionally, you can pass an [allowlist] of IDs to restrict the search space,
  /// enabling isolation boundaries (e.g., workspace-specific or user-specific filters).
  List<TurboVecResult> search(
    List<double> query,
    int k, {
    List<int>? allowlist,
  });

  /// Removes a vector by its [id] from the index. Returns `true` if successful.
  bool remove(int id);

  /// Saves the current index state to a file at [path].
  void write(String path);

  /// Closes the index and releases all associated native FFI memory.
  void close();
}
