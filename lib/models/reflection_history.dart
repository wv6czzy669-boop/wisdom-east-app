import 'dart:convert';

import '../utils/canonical_uuid.dart';
import '../utils/reflection_text_policy.dart';

/// A later thought about an existing reflection. Its identity and writing date
/// survive autosaves, retries and iCloud merges; each thought has its own limit.
final class ReflectionThought {
  ReflectionThought({
    required this.id,
    required this.text,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.mutationId,
  }) {
    if (!isCanonicalUuidV4OrV5(id) ||
        !isCanonicalUuidV4OrV5(mutationId) ||
        text.trim().isEmpty ||
        ReflectionTextPolicy.exceedsMaximum(text) ||
        createdAtMs < 0 ||
        updatedAtMs < createdAtMs ||
        updatedAtMs > 8640000000000000) {
      throw const FormatException('Invalid reflection thought.');
    }
  }

  final String id;
  final String text;
  final int createdAtMs;
  final int updatedAtMs;
  final String mutationId;

  Map<String, Object> toJson() => {
        'id': id,
        'text': text,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'mutationId': mutationId,
      };

  static ReflectionThought decode(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw['id'] is! String ||
        raw['text'] is! String ||
        raw['createdAtMs'] is! int ||
        raw['updatedAtMs'] is! int ||
        raw['mutationId'] is! String) {
      throw const FormatException('Invalid reflection thought.');
    }
    return ReflectionThought(
        id: raw['id'],
        text: raw['text'],
        createdAtMs: raw['createdAtMs'],
        updatedAtMs: raw['updatedAtMs'],
        mutationId: raw['mutationId']);
  }
}

/// Additive to the original reflection fields: old writing needs no migration.
/// A clear watermark prevents a delayed device from resurrecting deleted notes.
final class ReflectionHistory {
  ReflectionHistory({
    Iterable<ReflectionThought> thoughts = const [],
    this.clearedAtMs = 0,
  }) : thoughts = List.unmodifiable(thoughts.toList()
          ..sort((a, b) {
            final date = a.createdAtMs.compareTo(b.createdAtMs);
            return date == 0 ? a.id.compareTo(b.id) : date;
          })) {
    if (clearedAtMs < 0 ||
        clearedAtMs > 8640000000000000 ||
        this.thoughts.map((t) => t.id).toSet().length != this.thoughts.length ||
        this.thoughts.any((t) => t.createdAtMs <= clearedAtMs)) {
      throw const FormatException('Invalid reflection history.');
    }
  }

  // Leave ample space for the other fields in the CloudKit record. Reject an
  // oversized write rather than truncate any of the user's existing writing.
  static const maximumEncodedBytes = 512 * 1024;
  final List<ReflectionThought> thoughts;
  final int clearedAtMs;

  String encode() {
    final value = jsonEncode({
      'version': 1,
      'clearedAtMs': clearedAtMs,
      'thoughts': thoughts.map((t) => t.toJson()).toList()
    });
    if (utf8.encode(value).length > maximumEncodedBytes) {
      throw const FormatException(
          'Reflection history exceeds storage capacity.');
    }
    return value;
  }

  static ReflectionHistory decode(String? value) {
    if (value == null) return ReflectionHistory();
    if (utf8.encode(value).length > maximumEncodedBytes) {
      throw const FormatException(
          'Reflection history exceeds storage capacity.');
    }
    final raw = jsonDecode(value);
    if (raw is! Map<String, dynamic> ||
        raw['version'] != 1 ||
        raw['clearedAtMs'] is! int ||
        raw['thoughts'] is! List) {
      throw const FormatException('Invalid reflection history.');
    }
    return ReflectionHistory(
        clearedAtMs: raw['clearedAtMs'],
        thoughts: (raw['thoughts'] as List).map(ReflectionThought.decode));
  }

  ReflectionHistory upsert(
      {required String id,
      required String text,
      required int timestampMs,
      required String mutationId}) {
    final previous = thoughts.where((t) => t.id == id).firstOrNull;
    if (timestampMs <= clearedAtMs) {
      throw const FormatException('Thought predates reflection deletion.');
    }
    return ReflectionHistory(clearedAtMs: clearedAtMs, thoughts: [
      for (final thought in thoughts)
        if (thought.id != id) thought,
      ReflectionThought(
          id: id,
          text: text,
          createdAtMs: previous?.createdAtMs ?? timestampMs,
          updatedAtMs: timestampMs,
          mutationId: mutationId),
    ]);
  }

  static ReflectionHistory merge(Iterable<ReflectionHistory> histories) {
    var clearedAt = 0;
    final byId = <String, ReflectionThought>{};
    for (final history in histories) {
      if (history.clearedAtMs > clearedAt) clearedAt = history.clearedAtMs;
      for (final thought in history.thoughts) {
        final old = byId[thought.id];
        if (old != null && old.createdAtMs != thought.createdAtMs) {
          throw const FormatException('Thought identity changed.');
        }
        if (old == null ||
            thought.updatedAtMs > old.updatedAtMs ||
            (thought.updatedAtMs == old.updatedAtMs &&
                thought.mutationId.compareTo(old.mutationId) > 0)) {
          byId[thought.id] = thought;
        } else if (thought.updatedAtMs == old.updatedAtMs &&
            thought.mutationId == old.mutationId &&
            thought.text != old.text) {
          throw const FormatException('Thought mutation changed.');
        }
      }
    }
    return ReflectionHistory(
        clearedAtMs: clearedAt,
        thoughts: byId.values.where((t) => t.createdAtMs > clearedAt));
  }
}
