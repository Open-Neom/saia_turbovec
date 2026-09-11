import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guarda la procedencia de los binarios nativos versionados.
///
/// **El fallo que previene.** El `libturbovec.dylib` de macOS estuvo meses
/// compilado desde un turbovec anterior a un sync de 200 commits. Buscaba
/// correctamente, exportaba los símbolos correctos y todos los tests
/// pasaban — solo iba ~2x más lento en corpus pequeños. Nada lo delataba,
/// porque un binario obsoleto no es un binario roto.
///
/// Un checksum por sí solo tampoco lo habría cazado: detecta cambios
/// inesperados, no antigüedad. Lo que faltaba era registrar **de qué fuente
/// salió cada binario** y poder compararlo con la fuente actual.
///
/// Patrón tomado de `runanywhere-sdks`, que documentó la misma recurrencia
/// de "checksum staleness" en sus artefactos nativos.
void main() {
  final manifestFile = File('native_provenance.json');

  group('procedencia de binarios nativos', () {
    late Map<String, dynamic> manifest;

    setUpAll(() {
      manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    });

    test('el manifiesto existe y declara su fuente', () {
      expect(manifestFile.existsSync(), isTrue);
      expect(manifest['upstream_version'], isNotEmpty);
      expect(manifest['upstream_repo'], isNotEmpty);
      expect(manifest['built_on'], isNotEmpty);
    });

    test('cada binario versionado coincide con su checksum', () {
      final binaries = manifest['binaries'] as Map<String, dynamic>;
      expect(binaries, isNotEmpty);

      final drifted = <String>[];
      for (final entry in binaries.entries) {
        final file = File(entry.key);
        if (!file.existsSync()) {
          drifted.add('${entry.key}: FALTA');
          continue;
        }
        final expected = (entry.value as Map)['sha256'] as String;
        final actual = sha256.convert(file.readAsBytesSync()).toString();
        if (actual != expected) {
          drifted.add(
            '${entry.key}: sha ${actual.substring(0, 12)}… '
            '≠ ${expected.substring(0, 12)}…',
          );
        }
      }

      expect(
        drifted,
        isEmpty,
        reason: 'Binarios cambiados sin actualizar native_provenance.json.\n'
            'Si los regeneraste, actualiza el manifiesto (sha256, bytes,\n'
            'upstream_version y built_on) en el mismo commit.\n'
            '${drifted.join('\n')}',
      );
    });

    test('el tamaño declarado coincide', () {
      final binaries = manifest['binaries'] as Map<String, dynamic>;
      for (final entry in binaries.entries) {
        final file = File(entry.key);
        if (!file.existsSync()) continue;
        expect(
          file.lengthSync(),
          (entry.value as Map)['bytes'],
          reason: '${entry.key} cambió de tamaño',
        );
      }
    });

    test('los binarios no están vacíos ni truncados', () {
      final binaries = manifest['binaries'] as Map<String, dynamic>;
      for (final entry in binaries.entries) {
        final file = File(entry.key);
        if (!file.existsSync()) continue;
        // Cualquiera de estas librerías pasa de 100 KB; por debajo de eso
        // es una descarga truncada o un placeholder, no un binario real.
        expect(
          file.lengthSync(),
          greaterThan(100 * 1024),
          reason: '${entry.key} es sospechosamente pequeño',
        );
      }
    });

    test(
      'la versión del manifiesto coincide con la fuente de codebase_ia',
      () {
        // La comprobación que de verdad caza la obsolescencia. Solo corre
        // si la fuente está presente: en CI o en una máquina sin
        // codebase_ia, se salta en vez de fallar por algo ajeno al repo.
        final cargo = File(
          '${Platform.environment['HOME']}/codebase_ia/turbovec/turbovec/Cargo.toml',
        );
        if (!cargo.existsSync()) {
          markTestSkipped('Fuente de turbovec no presente; nada que comparar.');
          return;
        }

        final match = RegExp(r'^version\s*=\s*"([^"]+)"', multiLine: true)
            .firstMatch(cargo.readAsStringSync());
        expect(match, isNotNull, reason: 'No pude leer version del Cargo.toml');

        expect(
          match!.group(1),
          manifest['upstream_version'],
          reason:
              'La fuente de turbovec avanzó respecto a los binarios versionados.\n'
              'Regenéralos (ver build_notes en native_provenance.json) y\n'
              'actualiza el manifiesto. Un binario viejo no falla: solo va\n'
              'más lento, en silencio.',
        );
      },
    );
    test(
      'el dylib de macOS no apunta a una ruta absoluta de compilación',
      () {
        // `cargo build` graba en el dylib la ruta ABSOLUTA de su directorio
        // de compilación. La app sí lo empaqueta en Contents/Frameworks,
        // pero el binario lo referencia por esa ruta, así que dyld lo busca
        // donde ya no está:
        //
        //   dyld: Library not loaded:
        //     /Users/<quien-compiló>/…/target/release/deps/libturbovec.dylib
        //
        // Resultado: la app no arranca en ninguna máquina que no sea la que
        // compiló el binario. Y no falla en Flutter — muere antes, así que
        // no hay traza de Dart que lo explique.
        //
        // El arreglo es `install_name_tool -id @rpath/libturbovec.dylib`
        // después de cada build. Esta prueba existe para que olvidarlo se
        // note aquí y no al distribuir.
        if (!Platform.isMacOS) {
          markTestSkipped('otool solo está en macOS');
          return;
        }

        final dylib = File('macos/libturbovec.dylib');
        if (!dylib.existsSync()) {
          markTestSkipped('sin dylib de macOS en el checkout');
          return;
        }

        final r = Process.runSync('otool', ['-D', dylib.path]);
        final salida = (r.stdout as String).trim().split('\n');
        final installName = salida.isEmpty ? '' : salida.last.trim();

        expect(
          installName.startsWith('@rpath/') ||
              installName.startsWith('@loader_path/'),
          isTrue,
          reason:
              'install_name = "$installName".\n'
              'Debe ser relativo (@rpath/…). Con una ruta absoluta la app '
              'compila pero no arranca fuera de la máquina que la compiló.\n'
              'Corrige con:\n'
              '  install_name_tool -id @rpath/libturbovec.dylib '
              'macos/libturbovec.dylib\n'
              'y actualiza el sha256 en native_provenance.json.',
        );
      },
    );
  });
}
