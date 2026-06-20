import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  int _operationGeneration = 0;
  bool _latestOperationShouldPlay = false;
  bool _disposed = false;

  Future<void> stop() async {
    if (_disposed) return;

    _latestOperationShouldPlay = false;
    _operationGeneration++;

    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> playRevealSound() => _playSound('sounds/reveal.mp3', 0.38);

  Future<void> playPauseSound() => _playSound('sounds/pause.mp3', 0.45);

  Future<void> playFeelSound() => _playSound('sounds/feel.mp3', 0.45);

  Future<void> playHeartSound() => _playSound('sounds/heart.mp3', 0.45);

  Future<void> _playSound(String assetPath, double volume) async {
    if (_disposed) return;

    _latestOperationShouldPlay = true;
    final operationGeneration = ++_operationGeneration;

    try {
      await _player.stop();
      if (_disposed || operationGeneration != _operationGeneration) return;

      await _player.play(
        AssetSource(assetPath),
        volume: volume,
      );

      if ((_disposed || operationGeneration != _operationGeneration) &&
          !_latestOperationShouldPlay) {
        await _player.stop();
      }
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;

    _disposed = true;
    _latestOperationShouldPlay = false;
    _operationGeneration++;
    unawaited(_shutdownPlayer());
  }

  Future<void> _shutdownPlayer() async {
    try {
      await _player.stop();
    } catch (_) {}

    try {
      await _player.dispose();
    } catch (_) {}
  }
}
