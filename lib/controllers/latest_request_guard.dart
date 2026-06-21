class LatestRequestGuard {
  int _generation = 0;

  int begin() => ++_generation;

  bool isCurrent(int generation) => generation == _generation;

  void invalidate() {
    _generation++;
  }
}
