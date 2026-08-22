import 'dart:math';

import '../data/wisdoms.dart';

class WisdomSelectorService {
  final List<String> _recentWisdomIds = [];
  final List<String> _recentTags = [];
  final List<String> _recentTones = [];

  Map<String, dynamic> select() {
    final random = Random();

    if (wisdoms.isEmpty) {
      return {
        "text": "Silence is still available.",
        "id": null,
        "tags": ["silence"],
        "tone": "calm",
      };
    }

    final candidates = wisdoms.where((wisdom) {
      final id = wisdom["id"] as String;
      return !_recentWisdomIds.contains(id);
    }).toList();

    if (candidates.isEmpty) {
      _recentWisdomIds.clear();
      candidates.addAll(wisdoms);
    }

    final scoredCandidates = candidates.map((wisdom) {
      int score = 100;
      final tags = List<String>.from(wisdom["tags"] ?? []);
      final tone = wisdom["tone"] as String? ?? "neutral";
      final id = wisdom["id"] as String;

      for (final tag in tags) {
        if (_recentTags.contains(tag)) score -= 18;
      }
      if (_recentTones.contains(tone)) score -= 25;
      if (_recentWisdomIds.contains(id)) score -= 50;

      score += random.nextInt(35);
      if (score < 5) score = 5;

      return {"wisdom": wisdom, "score": score};
    }).toList();

    scoredCandidates.sort(
      (a, b) => (b["score"] as int).compareTo(a["score"] as int),
    );

    final topPoolSize = min(12, scoredCandidates.length);
    final topPool = scoredCandidates.take(topPoolSize).toList();
    final selected = topPool[random.nextInt(topPool.length)]["wisdom"]
        as Map<String, dynamic>;

    _rememberPattern(selected);
    return selected;
  }

  void _rememberPattern(Map<String, dynamic> selected) {
    final id = selected["id"] as String?;
    final tags = List<String>.from(selected["tags"] ?? []);
    final tone = selected["tone"] as String? ?? "neutral";

    if (id != null) {
      _recentWisdomIds.add(id);
      if (_recentWisdomIds.length > 20) _recentWisdomIds.removeAt(0);
    }

    _recentTags.addAll(tags);
    while (_recentTags.length > 12) {
      _recentTags.removeAt(0);
    }

    _recentTones.add(tone);
    while (_recentTones.length > 5) {
      _recentTones.removeAt(0);
    }
  }
}
