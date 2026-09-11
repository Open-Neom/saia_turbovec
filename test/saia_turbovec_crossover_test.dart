import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:saia_turbovec/saia_turbovec.dart';

/// Where does the turbovec index start paying for itself, and what does its
/// quantization cost in accuracy?
///
/// Two questions the existing benchmarks do not answer:
///
///  * `saia_turbovec_benchmark_test.dart` measures a single point (1000
///    vectors × 1536 dims) and reports speed only — no recall.
///  * `neom_memory/test/benchmark_vector_search_test.dart` reports a recall
///    number, but for `TurboQuantIndex` from `neom_codecs` — a pure-Dart
///    reimplementation. It never loads turbovec, so its figures say nothing
///    about this index.
///
/// This sweeps corpus size at **768 dims**, the width of the local GGUF
/// embedding model (`itzli-raiz`, nomic-embed-text v1.5) that
/// `SaiaGgufEmbeddingProvider` produces, and reports both.
///
/// ## Reading the speed column honestly
///
/// The baseline is exact cosine in interpreted Dart, so the ratio mixes two
/// separate effects: native SIMD vs Dart, and 4-bit quantized vs exact. It
/// answers the question the memory store actually faces — "index or the
/// brute-force fallback?" — but it is **not** a measure of quantization
/// speedup on its own. The recall column is the clean number: it isolates
/// exactly what the quantization costs, free of implementation.
///
/// ## Running
///
/// Runs against the committed `macos/libturbovec.dylib` by default. That
/// binary was regenerated from turbovec 1.0 — an earlier one lagged the
/// upstream sync and searched ~2x slower on small corpora, which moved the
/// crossover, so re-measure here after any binary refresh.
///
/// `TURBOVEC_LIB_PATH` points the run at a different build instead:
///
///   cargo build --release -p turbovec        # in codebase_ia/turbovec
///   TURBOVEC_LIB_PATH=<...>/target/release/libturbovec.dylib flutter test \
///     test/saia_turbovec_crossover_test.dart
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final libPath = Platform.environment['TURBOVEC_LIB_PATH'];
    if (libPath != null && File(libPath).existsSync()) {
      TurboVecBindings.customLibraryPath = libPath;
    }
    initSaiaTurbovec();
  });

  test('Crossover: corpus size where the index beats brute force @ 768 dims', () {
    const dim = 768; // nomic-embed-text v1.5, via SaiaGgufEmbeddingProvider
    const k = 10;
    const corpusSizes = [100, 500, 1000, 5000, 10000, 25000];

    final random = Random(1979);

    List<double> unitVector() {
      final v = List<double>.generate(dim, (_) => random.nextDouble() * 2 - 1);
      var norm = 0.0;
      for (final x in v) {
        norm += x * x;
      }
      norm = sqrt(norm);
      for (var i = 0; i < dim; i++) {
        v[i] /= norm;
      }
      return v;
    }

    // Exact top-k by cosine. Vectors are unit-length, so the dot product is
    // the cosine and no per-query normalization is needed.
    List<int> exactTopK(List<List<double>> corpus, List<double> query) {
      final scored = List<({int id, double score})>.generate(corpus.length, (i) {
        final v = corpus[i];
        var dot = 0.0;
        for (var d = 0; d < dim; d++) {
          dot += v[d] * query[d];
        }
        return (id: i, score: dot);
      });
      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.take(k).map((e) => e.id).toList();
    }

    print('\n=== turbovec crossover @ $dim dims, top-$k ===');
    print(
      'lib: ${TurboVecBindings.customLibraryPath ?? "(bundled macos/libturbovec.dylib)"}',
    );
    print('');
    print('      N   fuerza bruta      turbovec    ratio   recall@$k');
    print('  ─────   ────────────   ───────────   ──────   ────────');

    int? crossover;
    final summary = <String>[];

    for (final n in corpusSizes) {
      final corpus = List<List<double>>.generate(n, (_) => unitVector());

      // Fewer queries on big corpora: the exact baseline is O(n) per query
      // in interpreted Dart and would dominate the wall clock.
      final numQueries = n <= 1000 ? 50 : 10;
      final queries = List<List<double>>.generate(numQueries, (_) => unitVector());

      final index = TurboVecIndex.create(dim, bitWidth: 4);
      index.addBatch(List<int>.generate(n, (i) => i), corpus);

      // Warm up both paths so neither pays first-call costs in the timed run.
      index.search(queries.first, k);
      exactTopK(corpus, queries.first);

      final bruteWatch = Stopwatch()..start();
      final exactResults = [
        for (final q in queries) exactTopK(corpus, q),
      ];
      bruteWatch.stop();

      final indexWatch = Stopwatch()..start();
      final indexResults = [
        for (final q in queries) index.search(q, k),
      ];
      indexWatch.stop();

      var hits = 0;
      for (var i = 0; i < numQueries; i++) {
        final expected = exactResults[i].toSet();
        for (final result in indexResults[i]) {
          if (expected.contains(result.id)) hits++;
        }
      }
      final recall = 100.0 * hits / (numQueries * k);

      final bruteUs = bruteWatch.elapsedMicroseconds / numQueries;
      final indexUs = indexWatch.elapsedMicroseconds / numQueries;
      final ratio = bruteUs / indexUs;

      if (crossover == null && ratio > 1.0) crossover = n;

      final line =
          '${n.toString().padLeft(7)}   '
          '${bruteUs.toStringAsFixed(1).padLeft(9)} µs   '
          '${indexUs.toStringAsFixed(1).padLeft(8)} µs   '
          '${ratio.toStringAsFixed(2).padLeft(5)}x   '
          '${recall.toStringAsFixed(1).padLeft(6)}%';
      print('  $line');
      summary.add(line);

      // Recall is the honest cost of 4-bit quantization. A collapse here
      // would mean the index is fast because it stopped finding things.
      expect(
        recall,
        greaterThan(50.0),
        reason: 'recall@$k colapsó a ${recall.toStringAsFixed(1)}% con N=$n',
      );

      index.close();
    }

    print('');
    if (crossover != null) {
      print('  → El índice supera a la fuerza bruta desde N ≈ $crossover.');
    } else {
      print(
        '  → La fuerza bruta ganó en todos los tamaños medidos '
        '(hasta ${corpusSizes.last}).',
      );
    }
    print('');

    expect(summary, hasLength(corpusSizes.length));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('Recall vs bitWidth y distribución del corpus @ 768 dims', () {
    const dim = 768;
    const k = 10;
    // turbovec solo admite {2, 3, 4} (ConstructError::BitWidthOutOfRange).
    // No existe la opción de 8 bits: 4 ya es el techo de precisión, que es
    // lo que SaiaVectorMemoryStore usa por defecto vía createLazy().
    const bitWidths = [2, 3, 4];
    const sizes = [1000, 25000];

    final random = Random(1979);

    List<double> normalize(List<double> v) {
      var norm = 0.0;
      for (final x in v) {
        norm += x * x;
      }
      norm = sqrt(norm);
      for (var i = 0; i < v.length; i++) {
        v[i] /= norm;
      }
      return v;
    }

    List<double> uniformVector() =>
        normalize(List<double>.generate(dim, (_) => random.nextDouble() * 2 - 1));

    /// Corpus agrupado en temas, que es como se distribuyen los embeddings
    /// reales: cada vector es un centroide más ruido. Los vectores uniformes
    /// en dimensión alta son casi ortogonales entre sí — todos los cosenos
    /// se apiñan cerca de 0 y el top-k se decide por márgenes minúsculos,
    /// el peor caso imaginable para un índice cuantizado. Medir solo con
    /// ellos da un recall pesimista que no corresponde a la memoria de
    /// Itzli, donde los recuerdos se agrupan por tema.
    List<List<double>> clusteredCorpus(int n, {int topics = 40}) {
      final centroids =
          List<List<double>>.generate(topics, (_) => uniformVector());
      return List<List<double>>.generate(n, (i) {
        final centroid = centroids[i % topics];
        final v = List<double>.generate(
          dim,
          (d) => centroid[d] + (random.nextDouble() * 2 - 1) * 0.35,
        );
        return normalize(v);
      });
    }

    List<int> exactTopK(List<List<double>> corpus, List<double> query) {
      final scored = List<({int id, double score})>.generate(corpus.length, (i) {
        final v = corpus[i];
        var dot = 0.0;
        for (var d = 0; d < dim; d++) {
          dot += v[d] * query[d];
        }
        return (id: i, score: dot);
      });
      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.take(k).map((e) => e.id).toList();
    }

    double measureRecall(List<List<double>> corpus, int bitWidth) {
      final index = TurboVecIndex.create(dim, bitWidth: bitWidth);
      index.addBatch(List<int>.generate(corpus.length, (i) => i), corpus);

      const numQueries = 20;
      var hits = 0;
      for (var q = 0; q < numQueries; q++) {
        // Consultar con un vector del propio corpus perturbado: se parece a
        // buscar "algo como esto", que es lo que hace la memoria.
        final seed = corpus[random.nextInt(corpus.length)];
        final query = normalize(List<double>.generate(
          dim,
          (d) => seed[d] + (random.nextDouble() * 2 - 1) * 0.15,
        ));

        final expected = exactTopK(corpus, query).toSet();
        for (final r in index.search(query, k)) {
          if (expected.contains(r.id)) hits++;
        }
      }
      index.close();
      return 100.0 * hits / (numQueries * k);
    }

    print('\n=== recall@$k por bitWidth y distribución @ $dim dims ===');
    print('');
    print('       N   bits   uniforme   agrupado');
    print('   ─────   ────   ────────   ────────');

    for (final n in sizes) {
      final uniform = List<List<double>>.generate(n, (_) => uniformVector());
      final clustered = clusteredCorpus(n);

      for (final bits in bitWidths) {
        final recallUniform = measureRecall(uniform, bits);
        final recallClustered = measureRecall(clustered, bits);

        print(
          '${n.toString().padLeft(8)}   '
          '${bits.toString().padLeft(4)}   '
          '${recallUniform.toStringAsFixed(1).padLeft(7)}%   '
          '${recallClustered.toStringAsFixed(1).padLeft(7)}%',
        );

        if (bits == 4) {
          // 4 bits es lo que corre en producción. Un desplome aquí sería
          // el índice devolviendo cosas distintas a las que pidió el store.
          expect(
            recallClustered,
            greaterThan(70.0),
            reason:
                'recall@$k agrupado a 4 bits cayó a '
                '${recallClustered.toStringAsFixed(1)}% con N=$n',
          );
        }
      }
    }
    print('');
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('Sobre-pedir + re-rank exacto recupera el recall perdido', () {
    const dim = 768;
    const k = 10;
    // El mismo factor que usa SaiaVectorMemoryStore._overfetchFactor.
    const overfetch = 3;
    const sizes = [1000, 10000, 25000];

    final random = Random(1979);

    List<double> normalize(List<double> v) {
      var norm = 0.0;
      for (final x in v) {
        norm += x * x;
      }
      norm = sqrt(norm);
      for (var i = 0; i < v.length; i++) {
        v[i] /= norm;
      }
      return v;
    }

    List<double> uniformVector() =>
        normalize(List<double>.generate(dim, (_) => random.nextDouble() * 2 - 1));

    List<List<double>> clusteredCorpus(int n, {int topics = 40}) {
      final centroids =
          List<List<double>>.generate(topics, (_) => uniformVector());
      return List<List<double>>.generate(n, (i) {
        final centroid = centroids[i % topics];
        return normalize(List<double>.generate(
          dim,
          (d) => centroid[d] + (random.nextDouble() * 2 - 1) * 0.35,
        ));
      });
    }

    double cosine(List<double> a, List<double> b) {
      var dot = 0.0;
      for (var i = 0; i < dim; i++) {
        dot += a[i] * b[i];
      }
      return dot;
    }

    List<int> exactTopK(List<List<double>> corpus, List<double> query) {
      final scored = List<({int id, double score})>.generate(
        corpus.length,
        (i) => (id: i, score: cosine(corpus[i], query)),
      );
      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.take(k).map((e) => e.id).toList();
    }

    print('\n=== sobre-pedir ${overfetch}x + re-rank exacto @ $dim dims, top-$k ===');
    print('');
    print('       N   directo   +re-rank   vectores releídos');
    print('   ─────   ───────   ────────   ─────────────────');

    for (final n in sizes) {
      final corpus = clusteredCorpus(n);
      final index = TurboVecIndex.create(dim, bitWidth: 4);
      index.addBatch(List<int>.generate(n, (i) => i), corpus);

      const numQueries = 20;
      var hitsDirect = 0;
      var hitsReranked = 0;

      for (var q = 0; q < numQueries; q++) {
        final seed = corpus[random.nextInt(n)];
        final query = normalize(List<double>.generate(
          dim,
          (d) => seed[d] + (random.nextDouble() * 2 - 1) * 0.15,
        ));
        final expected = exactTopK(corpus, query).toSet();

        // (a) Lo que hacía el store: tomar el orden del índice tal cual.
        for (final r in index.search(query, k)) {
          if (expected.contains(r.id)) hitsDirect++;
        }

        // (b) Lo que hace ahora: pedir 3x y reordenar por coseno exacto
        // sobre esos candidatos — releyendo sólo ellos, no el corpus.
        final candidates = index.search(query, k * overfetch);
        final rescored = candidates
            .map((r) => (id: r.id, score: cosine(corpus[r.id], query)))
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
        for (final r in rescored.take(k)) {
          if (expected.contains(r.id)) hitsReranked++;
        }
      }

      final direct = 100.0 * hitsDirect / (numQueries * k);
      final reranked = 100.0 * hitsReranked / (numQueries * k);

      print(
        '${n.toString().padLeft(8)}   '
        '${direct.toStringAsFixed(1).padLeft(6)}%   '
        '${reranked.toStringAsFixed(1).padLeft(7)}%   '
        '${(k * overfetch).toString().padLeft(6)} de ${n.toString().padLeft(6)}',
      );

      // El punto entero del cambio: reordenar no puede empeorar, y debe
      // cerrar la mayor parte del hueco contra el coseno exacto.
      expect(
        reranked,
        greaterThanOrEqualTo(direct),
        reason: 'el re-rank empeoró el recall con N=$n',
      );

      index.close();
    }
    print('');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
