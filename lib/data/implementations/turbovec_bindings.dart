import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../src/native/turbovec_ffi.g.dart';

export '../../src/native/turbovec_ffi.g.dart'
    show IdMapIndexOpaque, TurboVecFfiBindings;

/// Hardened loader + thin facade around `ffigen`-generated [TurboVecFfiBindings].
class TurboVecBindings {
  static final TurboVecBindings instance = TurboVecBindings._();

  /// A custom path to the turbovec dynamic library.
  /// If set, this path will be checked first when loading the library.
  static String? customLibraryPath;

  late final ffi.DynamicLibrary _dylib;
  late final TurboVecFfiBindings _ffi;

  TurboVecBindings._() {
    _dylib = _loadLibrary();
    _ffi = TurboVecFfiBindings(_dylib);
  }

  ffi.Pointer<IdMapIndexOpaque> createIndex(int dim, int bitWidth) =>
      _ffi.turbovec_create_index(dim, bitWidth);

  ffi.Pointer<IdMapIndexOpaque> createLazyIndex(int bitWidth) =>
      _ffi.turbovec_create_lazy_index(bitWidth);

  bool addWithIds2d(
    ffi.Pointer<IdMapIndexOpaque> index,
    ffi.Pointer<ffi.Float> vectors,
    int dim,
    ffi.Pointer<ffi.Uint64> ids,
    int count,
  ) => _ffi.turbovec_add_with_ids_2d(index, vectors, dim, ids, count);

  int search(
    ffi.Pointer<IdMapIndexOpaque> index,
    ffi.Pointer<ffi.Float> query,
    int k,
    ffi.Pointer<ffi.Uint64> allowlist,
    int allowlistLen,
    ffi.Pointer<ffi.Float> scoresOut,
    ffi.Pointer<ffi.Uint64> idsOut,
  ) => _ffi.turbovec_search(
    index,
    query,
    k,
    allowlist,
    allowlistLen,
    scoresOut,
    idsOut,
  );

  bool remove(ffi.Pointer<IdMapIndexOpaque> index, int id) =>
      _ffi.turbovec_remove(index, id);

  bool writeIndex(ffi.Pointer<IdMapIndexOpaque> index, ffi.Pointer<Utf8> path) =>
      _ffi.turbovec_write(index, path.cast<ffi.Char>());

  ffi.Pointer<IdMapIndexOpaque> loadIndex(ffi.Pointer<Utf8> path) =>
      _ffi.turbovec_load(path.cast<ffi.Char>());

  void freeIndex(ffi.Pointer<IdMapIndexOpaque> index) =>
      _ffi.turbovec_free_index(index);

  int getLen(ffi.Pointer<IdMapIndexOpaque> index) => _ffi.turbovec_len(index);

  int getDim(ffi.Pointer<IdMapIndexOpaque> index) => _ffi.turbovec_dim(index);

  static final RegExp _unsafeLibPathRe = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2064\u2066-\u2069\u061C\uFEFF]',
  );

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

  /// Verifies [path] is an existing, non-symlink, non-UNC regular file > 0 bytes.
  static bool isSafeRegularLibraryFile(
    String path, {
    bool disallowParentTraversal = false,
  }) {
    final trimmed = path.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 1024 ||
        trimmed.startsWith('-') ||
        trimmed.startsWith('//') ||
        trimmed.startsWith(r'\\') ||
        trimmed.startsWith(r'\??\') ||
        _unsafeLibPathRe.hasMatch(path)) {
      return false;
    }
    final colonCheck = RegExp(r'^[A-Za-z]:[/\\]').hasMatch(trimmed)
        ? trimmed.substring(2)
        : trimmed;
    if (colonCheck.contains(':')) {
      return false;
    }
    if (disallowParentTraversal &&
        trimmed.split(RegExp(r'[/\\]')).any((seg) => seg == '..')) {
      return false;
    }
    try {
      final type = FileSystemEntity.typeSync(trimmed, followLinks: false);
      if (type != FileSystemEntityType.file) return false;
      if (_hasSymlinkAncestorSync(trimmed)) return false;
      final stat = File(trimmed).statSync();
      return stat.size > 0;
    } catch (_) {
      return false;
    }
  }

  ffi.DynamicLibrary _loadLibrary() {
    // 1. Try custom library path if set (must be a non-symlink regular file)
    final customPath = customLibraryPath;
    if (customPath != null && customPath.isNotEmpty) {
      if (isSafeRegularLibraryFile(
        customPath,
        disallowParentTraversal: true,
      )) {
        return ffi.DynamicLibrary.open(customPath);
      }
      throw ArgumentError(
        'Custom library path does not exist or is an unsafe symlink: $customPath',
      );
    }

    // 2. Try compile-time environment variable
    const envPath = String.fromEnvironment('TURBOVEC_LIB_PATH');
    if (envPath.isNotEmpty) {
      if (isSafeRegularLibraryFile(
        envPath,
        disallowParentTraversal: true,
      )) {
        return ffi.DynamicLibrary.open(envPath);
      }
      throw ArgumentError(
        'Environment library path does not exist or is an unsafe symlink: $envPath',
      );
    }

    // 3. Production fallbacks based on platform (bundle-first, never CWD inside .app)
    if (Platform.isMacOS) {
      final resolvedExe = Platform.resolvedExecutable;
      final insideAppBundle = resolvedExe.contains('.app/Contents/MacOS/');
      if (insideAppBundle) {
        final contentsDir = File(resolvedExe).parent.parent.path;
        final bundleCandidates = <String>[
          '$contentsDir/Frameworks/turbovec.framework/turbovec',
          '$contentsDir/Frameworks/libturbovec.dylib',
        ];
        for (final candidate in bundleCandidates) {
          if (isSafeRegularLibraryFile(candidate)) {
            try {
              return ffi.DynamicLibrary.open(candidate);
            } catch (_) {}
          }
        }
      } else {
        // Only allow dev workspace paths in non-bundled test/CLI runners
        final devPaths = <String>[
          '../neom_modules/ai/saia_turbovec/macos/libturbovec.dylib',
          'macos/libturbovec.dylib',
        ];
        for (final path in devPaths) {
          if (isSafeRegularLibraryFile(path)) {
            try {
              return ffi.DynamicLibrary.open(path);
            } catch (_) {}
          }
        }
      }

      try {
        return ffi.DynamicLibrary.open(
          'Frameworks/turbovec.framework/turbovec',
        );
      } catch (_) {
        return ffi.DynamicLibrary.open('libturbovec.dylib');
      }
    } else if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libturbovec.so');
    } else if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    } else if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundledDll = '$exeDir\\turbovec.dll';
      if (isSafeRegularLibraryFile(bundledDll)) {
        return ffi.DynamicLibrary.open(bundledDll);
      }
      return ffi.DynamicLibrary.open('turbovec.dll');
    } else if (Platform.isLinux) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final rel in ['lib/libturbovec.so', 'libturbovec.so']) {
        final candidate = '$exeDir/$rel';
        if (isSafeRegularLibraryFile(candidate)) {
          return ffi.DynamicLibrary.open(candidate);
        }
      }
      return ffi.DynamicLibrary.open('libturbovec.so');
    }

    throw UnsupportedError(
      'Unsupported platform for turbovec: ${Platform.operatingSystem}',
    );
  }
}
