/// Represents a result match from a vector query search.
class TurboVecResult {
  final int id;
  final double score;

  const TurboVecResult({required this.id, required this.score});

  @override
  String toString() =>
      'TurboVecResult(id: $id, score: ${score.toStringAsFixed(4)})';
}
