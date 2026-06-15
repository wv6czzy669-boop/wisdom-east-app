import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> playRevealSound() async {
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sounds/reveal.mp3'),
        volume: 0.38,
      );
    } catch (_) {}
  }

  Future<void> playPauseSound() async {
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sounds/pause.mp3'),
        volume: 0.45,
      );
    } catch (_) {}
  }

  Future<void> playFeelSound() async {
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sounds/feel.mp3'),
        volume: 0.45,
      );
    } catch (_) {}
  }

  Future<void> playHeartSound() async {
    try {
      await _player.stop();
      await _player.play(
        AssetSource('sounds/heart.mp3'),
        volume: 0.45,
      );
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }
}
