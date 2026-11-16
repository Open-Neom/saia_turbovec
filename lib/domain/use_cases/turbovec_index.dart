import '../models/turbovec_result.dart';

/// Pure-Dart security and memory-bounds policy for [TurboVecIndex] operations.
class TurboVecSecurityPolicy {
  TurboVecSecurityPolicy._();

  static const int maxDimension = 65536;
  static const int maxSearchK = 10000;
  static const int maxBatchVectors = 100000;
  static const int maxAllowlistSize = 100000;
  static const int maxPathLength = 1024;
  static const Set<int> supportedBitWidths = {1, 2, 4, 8};
  static const Set<String> _forbiddenSegments = {
    '..',
    '__proto__',
    'constructor',
    'prototype',
  };

  static final RegExp _controlOrBidi = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
  );
  static final RegExp _encodedTraversalOrBidiRe = RegExp(
    r'%(?:00|2e|2f|5c|25|c2%[89][0-9a-f]|d8%9c|e2%80%(?:8[b-f]|a[8-e])|e2%81%a[0-9]|ef%bb%bf)',
    caseSensitive: false,
  );
  static final RegExp _windowsReservedStemRe = RegExp(
    r'^(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|CLOCK\$|COM[1-9]|LPT[1-9])$',
    caseSensitive: false,
  );

  static const List<String> _forbiddenPathMarkers = [
    '/.ssh/',
    '\\.ssh\\',
    '/.aws/',
    '\\.aws\\',
    '/.gnupg/',
    '\\.gnupg\\',
    '/.kube/',
    '\\.kube\\',
    '/kubeconfig',
    '\\kubeconfig',
    '/.docker/',
    '\\.docker\\',
    '/.config/gcloud/',
    '\\.config\\gcloud\\',
    '/.git/',
    '\\.git\\',
    '/.env',
    '\\.env',
    '/.secret.local',
    '\\.secret.local',
    '/.netrc',
    '\\.netrc',
    '/.git-credentials',
    '\\.git-credentials',
    '/.npmrc',
    '\\.npmrc',
    '/.pypirc',
    '\\.pypirc',
    'terraform.tfstate',
    '.tfvars',
    '/.vault-token',
    '\\.vault-token',
    '/.pgpass',
    '\\.pgpass',
    '/local state/',
    '\\local state\\',
    '/key4.db',
    '\\key4.db',
    '/logins.json',
    '\\logins.json',
    '/cookies.sqlite',
    '\\cookies.sqlite',
    'firebase-adminsdk',
    '/id_rsa',
    '/id_ed25519',
    '/etc/',
    '/private/etc/',
    '/library/keychains/',
    '/proc/',
    '/sys/',
    '/dev/',
  ];

  static void validateBitWidth(int bitWidth) {
    if (!bitWidth.isFinite || !supportedBitWidths.contains(bitWidth)) {
      throw ArgumentError.value(
        bitWidth,
        'bitWidth',
        'Supported bitWidths are $supportedBitWidths',
      );
    }
  }

  static void validateDim(int dim) {
    if (!dim.isFinite || dim <= 0 || dim > maxDimension) {
      throw RangeError.range(dim, 1, maxDimension, 'dim');
    }
    if (dim % 8 != 0) {
      throw ArgumentError.value(
        dim,
        'dim',
        'TurboVec requires vector dimension to be a multiple of 8',
      );
    }
  }

  static String validatePath(String path) {
    if (_controlOrBidi.hasMatch(path)) {
      throw ArgumentError.value(path, 'path', 'Invalid index file path');
    }
    final trimmed = path.trim();
    if (trimmed.isEmpty ||
        trimmed.length > maxPathLength ||
        trimmed.startsWith('-') ||
        trimmed.startsWith('//') ||
        trimmed.startsWith(r'\\') ||
        trimmed.startsWith(r'\??\') ||
        _controlOrBidi.hasMatch(trimmed)) {
      throw ArgumentError.value(path, 'path', 'Invalid index file path');
    }
    // Reject NTFS Alternate Data Streams (`index.tv:ads`), preserving drive `C:/`.
    final colonCheck = RegExp(r'^[A-Za-z]:[/\\]').hasMatch(trimmed)
        ? trimmed.substring(2)
        : trimmed;
    if (colonCheck.contains(':')) {
      throw ArgumentError.value(
        path,
        'path',
        'NTFS Alternate Data Streams (:) are forbidden in index path',
      );
    }
    final lowerRaw = trimmed.toLowerCase();
    if (_encodedTraversalOrBidiRe.hasMatch(lowerRaw)) {
      throw ArgumentError.value(
        path,
        'path',
        'Encoded path traversal, Bidi, or NUL sequences are forbidden',
      );
    }
    final segments = trimmed.split(RegExp(r'[/\\]'));
    for (final s in segments) {
      if (s.isEmpty) continue;
      final lowerSeg = s.toLowerCase();
      if (_forbiddenSegments.contains(lowerSeg) ||
          (s.startsWith('__') && s.endsWith('__') && s.length >= 4)) {
        throw ArgumentError.value(
          path,
          'path',
          'Parent directory traversal (..) or prototype segment is not allowed in index path',
        );
      }
      final stem = s.split('.').first;
      if (_windowsReservedStemRe.hasMatch(stem)) {
        throw ArgumentError.value(
          path,
          'path',
          'Windows reserved device name is forbidden in index path',
        );
      }
    }
    final lower = '$trimmed/'.toLowerCase();
    for (final marker in _forbiddenPathMarkers) {
      if (lower.contains(marker)) {
        throw ArgumentError.value(
          path,
          'path',
          'Sensitive system or credential directory is forbidden',
        );
      }
    }
    return trimmed;
  }

  static void validateId(int id) {
    if (!id.isFinite || id < 0) {
      throw RangeError.value(id, 'id', 'Vector ID must be non-negative');
    }
  }

  static void validateFiniteVector(List<double> vector, String paramName) {
    if (vector.length > maxDimension) {
      throw RangeError.range(
        vector.length,
        1,
        maxDimension,
        paramName,
        'Vector dimension exceeds maxDimension ($maxDimension)',
      );
    }
    for (var i = 0; i < vector.length; i++) {
      if (!vector[i].isFinite) {
        throw ArgumentError.value(
          vector[i],
          '$paramName[$i]',
          'Vector values must be finite numbers (not NaN or Infinity)',
        );
      }
    }
  }

  static void validateBatchDimensions({
    required int idsLength,
    required int vectorsLength,
    required int vectorDim,
    required int expectedDim,
  }) {
    if (idsLength != vectorsLength) {
      throw ArgumentError('ids and vectors lists must have the same length');
    }
    if (idsLength > maxBatchVectors) {
      throw RangeError.range(
        idsLength,
        1,
        maxBatchVectors,
        'ids.length',
        'Batch size exceeds maxBatchVectors ($maxBatchVectors)',
      );
    }
    if (vectorDim > maxDimension) {
      throw RangeError.range(
        vectorDim,
        1,
        maxDimension,
        'vectorDim',
        'Vector dimension exceeds maxDimension ($maxDimension)',
      );
    }
    if (expectedDim == 0 && vectorDim % 8 != 0) {
      throw ArgumentError.value(
        vectorDim,
        'vectorDim',
        'TurboVec requires vector dimension to be a multiple of 8',
      );
    }
    if (expectedDim > 0 && vectorDim != expectedDim) {
      throw ArgumentError(
        'Batch vector dimension ($vectorDim) does not match index dimension ($expectedDim)',
      );
    }
  }

  static void validateAllowlist(List<int> allowlist) {
    if (allowlist.length > maxAllowlistSize) {
      throw RangeError.range(
        allowlist.length,
        0,
        maxAllowlistSize,
        'allowlist.length',
        'Allowlist size exceeds maxAllowlistSize ($maxAllowlistSize)',
      );
    }
    for (final id in allowlist) {
      validateId(id);
    }
  }
}

/// An on-device vector index that provides ultra-fast, 4-bit quantized
/// similarity search.
abstract class TurboVecIndex {
  static TurboVecIndex Function(String path)? loadBuilder;
  static TurboVecIndex Function({int? bitWidth})? createLazyBuilder;
  static TurboVecIndex Function(int dim, {int? bitWidth})? createBuilder;

  /// Loads an existing index from the specified file [path].
  factory TurboVecIndex.load(String path) {
    if (loadBuilder == null) {
      throw StateError(
        'TurboVecIndex.loadBuilder is not registered. '
        'Make sure to call initSaiaTurbovec() during app startup.'
      );
    }
    return loadBuilder!(path);
  }

  /// Creates a lazy index that infers the dimensions from the first added vector.
  /// The [bitWidth] specifies the quantization bit width (default is 4).
  factory TurboVecIndex.createLazy({int? bitWidth}) {
    if (createLazyBuilder == null) {
      throw StateError(
        'TurboVecIndex.createLazyBuilder is not registered. '
        'Make sure to call initSaiaTurbovec() during app startup.'
      );
    }
    return createLazyBuilder!(bitWidth: bitWidth);
  }

  /// Creates an index with a pre-defined vector dimension [dim].
  /// The [bitWidth] specifies the quantization bit width (default is 4).
  factory TurboVecIndex.create(int dim, {int? bitWidth}) {
    if (createBuilder == null) {
      throw StateError(
        'TurboVecIndex.createBuilder is not registered. '
        'Make sure to call initSaiaTurbovec() during app startup.'
      );
    }
    return createBuilder!(dim, bitWidth: bitWidth);
  }

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
