// Copyright (c) 2026 Open Neom / SAIA. All rights reserved.

import 'dart:io';

import 'package:ffigen/ffigen.dart';

const Set<String> _includedFunctions = <String>{
  'turbovec_create_index',
  'turbovec_create_lazy_index',
  'turbovec_add_with_ids_2d',
  'turbovec_search',
  'turbovec_remove',
  'turbovec_write',
  'turbovec_load',
  'turbovec_free_index',
  'turbovec_len',
  'turbovec_dim',
};

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  final entryHeader = packageRoot.resolve('src/turbovec.h');
  final bindingsOutput =
      packageRoot.resolve('lib/src/native/turbovec_ffi.g.dart');

  await FfiGenerator(
    input: Input(
      entryPoints: [entryHeader],
      include: (header) => header.path.endsWith('turbovec.h'),
    ),
    visitors: [
      Visitor(
        struct: (node) {
          if (node.originalName == 'IdMapIndexOpaque') {
            node.isIncluded = true;
          }
        },
        func: (node) {
          if (_includedFunctions.contains(node.originalName)) {
            node.isIncluded = true;
            node.isLeaf = true;
          }
        },
      ),
    ],
    output: Output(
      dart: DartOutput(path: bindingsOutput),
      style: const DynamicLibraryBindings(
        wrapperName: 'TurboVecFfiBindings',
        wrapperDocComment:
            'Generated FFI bindings (`isLeaf: true`) for the Rust TurboQuant vector index.',
      ),
      format: true,
      preamble: '''
// Copyright (c) 2026 Open Neom / SAIA. All rights reserved.
// AUTO-GENERATED FILE - DO NOT MODIFY.
// Generated via `dart run tool/ffigen.dart` (`ffigen ^23.0.0`).

// ignore_for_file: type=lint, unused_import, unused_element, camel_case_types, non_constant_identifier_names
''',
    ),
  ).generate();
}
