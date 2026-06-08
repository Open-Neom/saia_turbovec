import 'dart:math';
import 'package:flutter/material.dart';
import 'package:saia_turbovec/saia_turbovec.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurboVec Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6200EE),
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFBB86FC),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E1E),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TurboVecIndex? _index;
  final int _dimensions = 1536;
  bool _isIndexing = false;
  String _indexStatus = 'Index is uninitialized';
  String _timingInfo = '';
  List<TurboVecResult> _searchResults = [];
  bool _useAllowlist = false;
  
  // Keep track of generated IDs to display in allowlist toggle options
  final List<int> _allIds = [];
  final List<List<double>> _allVectors = [];

  @override
  void initState() {
    super.initState();
    _initializeIndex();
  }

  void _initializeIndex() {
    try {
      _index = TurboVecIndex.createLazy(bitWidth: 4);
      setState(() {
        _indexStatus = 'Empty 4-bit Quantized Index Initialized';
      });
    } catch (e) {
      setState(() {
        _indexStatus = 'Failed to initialize native index: $e';
      });
    }
  }

  void _generateAndIndex() async {
    if (_index == null) return;
    setState(() {
      _isIndexing = true;
      _timingInfo = 'Generating vectors...';
    });

    // Run computation asynchronously
    await Future.delayed(const Duration(milliseconds: 100));

    final stopwatch = Stopwatch()..start();
    final random = Random();
    final ids = <int>[];
    final vectors = <List<double>>[];

    _allIds.clear();
    _allVectors.clear();

    for (int i = 0; i < 500; i++) {
      final v = List<double>.generate(_dimensions, (_) => random.nextDouble() * 2 - 1);
      // Normalize
      double norm = 0;
      for (int j = 0; j < _dimensions; j++) norm += v[j] * v[j];
      norm = sqrt(norm);
      for (int j = 0; j < _dimensions; j++) v[j] /= norm;

      final id = 2000 + i;
      ids.add(id);
      vectors.add(v);
      _allIds.add(id);
      _allVectors.add(v);
    }

    try {
      _index!.addBatch(ids, vectors);
      stopwatch.stop();
      setState(() {
        _isIndexing = false;
        _indexStatus = 'Index holds ${_index!.len} vectors of D=${_index!.dim}';
        _timingInfo = 'Indexed 500 vectors in ${stopwatch.elapsedMilliseconds} ms';
        _searchResults.clear();
      });
    } catch (e) {
      setState(() {
        _isIndexing = false;
        _indexStatus = 'Error adding vectors: $e';
      });
    }
  }

  void _performSearch() {
    if (_index == null || _allVectors.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    final query = _allVectors.first; // Search using first vector (should match ID 2000 perfectly)
    
    List<int>? allowlist;
    if (_useAllowlist) {
      // Limit search to even IDs only
      allowlist = _allIds.where((id) => id % 2 == 0).toList();
    }

    final results = _index!.search(query, 5, allowlist: allowlist);
    stopwatch.stop();

    setState(() {
      _searchResults = results;
      _timingInfo = 'Found ${results.length} neighbors in ${stopwatch.elapsed.inMicroseconds} μs (${(stopwatch.elapsed.inMicroseconds / 1000.0).toStringAsFixed(3)} ms)';
    });
  }

  @override
  void dispose() {
    _index?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TurboVec Vector Search Demo'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _indexStatus,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    if (_timingInfo.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _timingInfo,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.secondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isIndexing ? null : _generateAndIndex,
                    icon: _isIndexing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt),
                    label: const Text('Index 500 Vectors'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _allVectors.isEmpty ? null : _performSearch,
                    icon: const Icon(Icons.search),
                    label: const Text('Query Top-5'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search filters
            SwitchListTile(
              title: const Text('Filter with Allowlist (Even IDs only)'),
              subtitle: const Text('Restricts nearest neighbors to IDs 2000, 2002, 2004...'),
              value: _useAllowlist,
              onChanged: _allVectors.isEmpty
                  ? null
                  : (val) {
                      setState(() {
                        _useAllowlist = val;
                      });
                      _performSearch();
                    },
            ),
            const SizedBox(height: 16),

            // Results Title
            Text(
              'Search Results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            // Results List
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        _allVectors.isEmpty
                            ? 'Index some vectors first!'
                            : 'Click "Query Top-5" to see similarity matches.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final res = _searchResults[index];
                        final isPerfectMatch = res.score >= 0.9999;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          color: isPerfectMatch
                              ? const Color(0xFF1E3A1E)
                              : Theme.of(context).colorScheme.surface,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPerfectMatch
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.primary,
                              child: Text('${index + 1}'),
                            ),
                            title: Text('Vector ID: ${res.id}'),
                            subtitle: Text(
                              isPerfectMatch
                                  ? 'Exact Match (Score: ${res.score.toStringAsFixed(6)})'
                                  : 'Similarity Score: ${res.score.toStringAsFixed(6)}',
                            ),
                            trailing: isPerfectMatch
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
