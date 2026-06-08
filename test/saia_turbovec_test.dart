import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:saia_turbovec/saia_turbovec.dart';

void main() {
  setUpAll(() {
    // Ensure the Flutter binding is initialized if needed
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('TurboVecIndex Tests', () {
    test('Create Lazy Index and Add Vectors', () {
      final index = TurboVecIndex.createLazy(bitWidth: 4);
      expect(index.len, equals(0));
      expect(index.dim, equals(0));

      final v1 = [
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
      ]; // Dim = 8 (multiple of 8 required by turbovec)
      final v2 = [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

      index.add(101, v1);
      expect(index.len, equals(1));
      expect(index.dim, equals(8));

      index.add(102, v2);
      expect(index.len, equals(2));

      // Search v1
      final results = index.search(v1, 10);
      expect(results.length, equals(2));
      expect(results.first.id, equals(101));
      expect(results.first.score, greaterThan(results.last.score));

      index.close();
    });

    test('Allowlist Filtered Search', () {
      final index = TurboVecIndex.createLazy(bitWidth: 4);

      final v1 = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final v2 = [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final v3 = [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0];

      index.addBatch([201, 202, 203], [v1, v2, v3]);
      expect(index.len, equals(3));

      // Search allowing only 202 and 203
      final results = index.search(v1, 10, allowlist: [202, 203]);
      expect(results.length, equals(2));
      final ids = results.map((r) => r.id).toList();
      expect(ids, containsAll([202, 203]));
      expect(ids, isNot(contains(201)));

      index.close();
    });

    test('Remove Vector', () {
      final index = TurboVecIndex.createLazy(bitWidth: 4);
      final v1 = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

      index.add(301, v1);
      expect(index.len, equals(1));

      final removed = index.remove(301);
      expect(removed, isTrue);
      expect(index.len, equals(0));

      final removedAgain = index.remove(301);
      expect(removedAgain, isFalse);

      index.close();
    });

    test('Save and Load Index', () {
      final tempDir = Directory.systemTemp.createTempSync();
      final indexFilePath = '${tempDir.path}/test_index.tvim';

      final index = TurboVecIndex.createLazy(bitWidth: 4);
      final v1 = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      final v2 = [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];

      index.addBatch([401, 402], [v1, v2]);
      index.write(indexFilePath);
      index.close();

      expect(File(indexFilePath).existsSync(), isTrue);

      final loadedIndex = TurboVecIndex.load(indexFilePath);
      expect(loadedIndex.len, equals(2));
      expect(loadedIndex.dim, equals(8));

      final results = loadedIndex.search(v1, 10);
      expect(results.first.id, equals(401));

      loadedIndex.close();
      tempDir.deleteSync(recursive: true);
    });
  });
}
