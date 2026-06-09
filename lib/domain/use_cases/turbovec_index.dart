import '../models/turbovec_result.dart';
import '../../data/implementations/turbovec_index_impl.dart';

abstract class TurboVecIndex {
  factory TurboVecIndex.load(String path) = TurboVecIndexImpl.load;
  factory TurboVecIndex.createLazy({int bitWidth}) = TurboVecIndexImpl.createLazy;
  factory TurboVecIndex.create(int dim, {int bitWidth}) = TurboVecIndexImpl.create;

  int get len;
  int get dim;
  void add(int id, List<double> vector);
  void addBatch(List<int> ids, List<List<double>> vectors);
  List<TurboVecResult> search(List<double> query, int k, {List<int>? allowlist});
  bool remove(int id);
  void write(String path);
  void close();
}
