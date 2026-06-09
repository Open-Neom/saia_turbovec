// ignore_for_file: camel_case_types, non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// Opaque struct representing the Rust IdMapIndex
final class IdMapIndexOpaque extends ffi.Opaque {}

// FFI function signatures (C types)
typedef turbovec_create_index_C =
    ffi.Pointer<IdMapIndexOpaque> Function(ffi.Size dim, ffi.Size bitWidth);
typedef turbovec_create_lazy_index_C =
    ffi.Pointer<IdMapIndexOpaque> Function(ffi.Size bitWidth);
typedef turbovec_add_with_ids_2d_C =
    ffi.Bool Function(
      ffi.Pointer<IdMapIndexOpaque> index,
      ffi.Pointer<ffi.Float> vectors,
      ffi.Size dim,
      ffi.Pointer<ffi.Uint64> ids,
      ffi.Size count,
    );
typedef turbovec_search_C =
    ffi.Size Function(
      ffi.Pointer<IdMapIndexOpaque> index,
      ffi.Pointer<ffi.Float> query,
      ffi.Size k,
      ffi.Pointer<ffi.Uint64> allowlist,
      ffi.Size allowlistLen,
      ffi.Pointer<ffi.Float> scoresOut,
      ffi.Pointer<ffi.Uint64> idsOut,
    );
typedef turbovec_remove_C =
    ffi.Bool Function(ffi.Pointer<IdMapIndexOpaque> index, ffi.Uint64 id);
typedef turbovec_write_C =
    ffi.Bool Function(
      ffi.Pointer<IdMapIndexOpaque> index,
      ffi.Pointer<Utf8> path,
    );
typedef turbovec_load_C =
    ffi.Pointer<IdMapIndexOpaque> Function(ffi.Pointer<Utf8> path);
typedef turbovec_free_index_C =
    ffi.Void Function(ffi.Pointer<IdMapIndexOpaque> index);
typedef turbovec_len_C = ffi.Size Function(ffi.Pointer<IdMapIndexOpaque> index);
typedef turbovec_dim_C = ffi.Size Function(ffi.Pointer<IdMapIndexOpaque> index);

// Dart signatures
typedef turbovec_create_index_Dart =
    ffi.Pointer<IdMapIndexOpaque> Function(int dim, int bitWidth);
typedef turbovec_create_lazy_index_Dart =
    ffi.Pointer<IdMapIndexOpaque> Function(int bitWidth);
typedef turbovec_add_with_ids_2d_Dart =
    bool Function(
      ffi.Pointer<IdMapIndexOpaque> index,
      ffi.Pointer<ffi.Float> vectors,
      int dim,
      ffi.Pointer<ffi.Uint64> ids,
      int count,
    );
typedef turbovec_search_Dart =
    int Function(
      ffi.Pointer<IdMapIndexOpaque> index,
      ffi.Pointer<ffi.Float> query,
      int k,
      ffi.Pointer<ffi.Uint64> allowlist,
      int allowlistLen,
      ffi.Pointer<ffi.Float> scoresOut,
      ffi.Pointer<ffi.Uint64> idsOut,
    );
typedef turbovec_remove_Dart =
    bool Function(ffi.Pointer<IdMapIndexOpaque> index, int id);
typedef turbovec_write_Dart =
    bool Function(ffi.Pointer<IdMapIndexOpaque> index, ffi.Pointer<Utf8> path);
typedef turbovec_load_Dart =
    ffi.Pointer<IdMapIndexOpaque> Function(ffi.Pointer<Utf8> path);
typedef turbovec_free_index_Dart =
    void Function(ffi.Pointer<IdMapIndexOpaque> index);
typedef turbovec_len_Dart = int Function(ffi.Pointer<IdMapIndexOpaque> index);
typedef turbovec_dim_Dart = int Function(ffi.Pointer<IdMapIndexOpaque> index);

class TurboVecBindings {
  static final TurboVecBindings instance = TurboVecBindings._();

  /// A custom path to the turbovec dynamic library.
  /// If set, this path will be checked first when loading the library.
  static String? customLibraryPath;

  late final ffi.DynamicLibrary _dylib;

  // Bindings functions
  late final turbovec_create_index_Dart createIndex;
  late final turbovec_create_lazy_index_Dart createLazyIndex;
  late final turbovec_add_with_ids_2d_Dart addWithIds2d;
  late final turbovec_search_Dart search;
  late final turbovec_remove_Dart remove;
  late final turbovec_write_Dart writeIndex;
  late final turbovec_load_Dart loadIndex;
  late final turbovec_free_index_Dart freeIndex;
  late final turbovec_len_Dart getLen;
  late final turbovec_dim_Dart getDim;

  TurboVecBindings._() {
    _dylib = _loadLibrary();
    _resolveFunctions();
  }

  ffi.DynamicLibrary _loadLibrary() {
    // 1. Try custom library path if set
    final customPath = customLibraryPath;
    if (customPath != null && customPath.isNotEmpty) {
      if (File(customPath).existsSync()) {
        return ffi.DynamicLibrary.open(customPath);
      } else {
        throw ArgumentError('Custom library path does not exist: $customPath');
      }
    }

    // 2. Try compile-time environment variable
    const envPath = String.fromEnvironment('TURBOVEC_LIB_PATH');
    if (envPath.isNotEmpty) {
      if (File(envPath).existsSync()) {
        return ffi.DynamicLibrary.open(envPath);
      } else {
        throw ArgumentError(
          'Environment library path does not exist: $envPath',
        );
      }
    }

    // 3. Production fallbacks based on platform
    if (Platform.isMacOS) {
      // Check package-relative paths for test/CLI runner environments
      final localPaths = [
        'macos/libturbovec.dylib',
        '../neom_modules/ai/saia_turbovec/macos/libturbovec.dylib',
      ];
      for (final path in localPaths) {
        if (File(path).existsSync()) {
          try {
            return ffi.DynamicLibrary.open(path);
          } catch (_) {
            // Keep searching if loading fails
          }
        }
      }

      try {
        return ffi.DynamicLibrary.open('libturbovec.dylib');
      } catch (_) {
        return ffi.DynamicLibrary.open(
          'Frameworks/turbovec.framework/turbovec',
        );
      }
    } else if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libturbovec.so');
    } else if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('turbovec.dll');
    } else if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libturbovec.so');
    }

    throw UnsupportedError(
      'Unsupported platform for turbovec: ${Platform.operatingSystem}',
    );
  }

  void _resolveFunctions() {
    createIndex = _dylib
        .lookup<ffi.NativeFunction<turbovec_create_index_C>>(
          'turbovec_create_index',
        )
        .asFunction<turbovec_create_index_Dart>();

    createLazyIndex = _dylib
        .lookup<ffi.NativeFunction<turbovec_create_lazy_index_C>>(
          'turbovec_create_lazy_index',
        )
        .asFunction<turbovec_create_lazy_index_Dart>();

    addWithIds2d = _dylib
        .lookup<ffi.NativeFunction<turbovec_add_with_ids_2d_C>>(
          'turbovec_add_with_ids_2d',
        )
        .asFunction<turbovec_add_with_ids_2d_Dart>();

    search = _dylib
        .lookup<ffi.NativeFunction<turbovec_search_C>>('turbovec_search')
        .asFunction<turbovec_search_Dart>();

    remove = _dylib
        .lookup<ffi.NativeFunction<turbovec_remove_C>>('turbovec_remove')
        .asFunction<turbovec_remove_Dart>();

    writeIndex = _dylib
        .lookup<ffi.NativeFunction<turbovec_write_C>>('turbovec_write')
        .asFunction<turbovec_write_Dart>();

    loadIndex = _dylib
        .lookup<ffi.NativeFunction<turbovec_load_C>>('turbovec_load')
        .asFunction<turbovec_load_Dart>();

    freeIndex = _dylib
        .lookup<ffi.NativeFunction<turbovec_free_index_C>>(
          'turbovec_free_index',
        )
        .asFunction<turbovec_free_index_Dart>();

    getLen = _dylib
        .lookup<ffi.NativeFunction<turbovec_len_C>>('turbovec_len')
        .asFunction<turbovec_len_Dart>();

    getDim = _dylib
        .lookup<ffi.NativeFunction<turbovec_dim_C>>('turbovec_dim')
        .asFunction<turbovec_dim_Dart>();
  }
}
