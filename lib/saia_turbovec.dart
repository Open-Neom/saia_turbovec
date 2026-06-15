library saia_turbovec;

import 'domain/use_cases/turbovec_index.dart';
import 'data/implementations/turbovec_index_stub.dart'
    if (dart.library.io) 'data/implementations/turbovec_index_impl.dart';

export 'domain/models/turbovec_result.dart';
export 'domain/use_cases/turbovec_index.dart';
export 'data/implementations/turbovec_bindings_web.dart'
    if (dart.library.io) 'data/implementations/turbovec_bindings.dart'
    show TurboVecBindings;

void initSaiaTurbovec() {
  TurboVecIndex.loadBuilder = (path) => TurboVecIndexImpl.load(path);
  TurboVecIndex.createLazyBuilder = ({bitWidth}) => TurboVecIndexImpl.createLazy(bitWidth: bitWidth ?? 4);
  TurboVecIndex.createBuilder = (dim, {bitWidth}) => TurboVecIndexImpl.create(dim, bitWidth: bitWidth ?? 4);
}
