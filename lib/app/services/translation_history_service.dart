import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TranslationHistoryEntry {
  const TranslationHistoryEntry({
    required this.text,
    required this.meaning,
    required this.createdAt,
  });

  final String text;
  final String meaning;
  final DateTime createdAt;

  Map<String, String> toJson() => {
    'text': text,
    'meaning': meaning,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory TranslationHistoryEntry.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['createdAt'] as String? ?? DateTime.now().toUtc().toIso8601String();
    return TranslationHistoryEntry(
      text: (json['text'] ?? '').toString(),
      meaning: (json['meaning'] ?? '').toString(),
      createdAt: DateTime.tryParse(createdAtRaw)?.toLocal() ?? DateTime.now(),
    );
  }
}

class TranslationHistoryService {
  static const _key = 'handtalk_translation_history_v1';
  static const int _maxEntries = 25;

  Future<List<TranslationHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getStringList(_key) ?? const <String>[];
    final parsed = rawItems
        .map((value) {
          try {
            final decoded = jsonDecode(value);
            if (decoded is Map<String, dynamic>) {
              return TranslationHistoryEntry.fromJson(decoded);
            }
          } catch (_) {
            // Ignore corrupt history entries and keep the rest of the list intact.
          }
          return null;
        })
        .whereType<TranslationHistoryEntry>()
        .toList();

    parsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return parsed;
  }

  Future<List<TranslationHistoryEntry>> saveEntry({
    required String text,
    required String meaning,
  }) async {
    final cleanedText = text.trim();
    if (cleanedText.isEmpty) {
      return load();
    }

    final existing = await load();
    final entry = TranslationHistoryEntry(
      text: cleanedText,
      meaning: meaning.trim(),
      createdAt: DateTime.now(),
    );

    final next = [entry, ...existing]
        .where((item) => item.text.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final prefs = await SharedPreferences.getInstance();
    final payload = next.take(_maxEntries).map((item) {
      return jsonEncode(item.toJson());
    }).toList();

    await prefs.setStringList(_key, payload);
    return next.take(_maxEntries).toList();
  }
}
