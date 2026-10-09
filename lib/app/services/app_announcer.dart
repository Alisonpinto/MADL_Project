import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AppAnnouncer {
  AppAnnouncer._();

  static final AppAnnouncer instance = AppAnnouncer._();
  static const _preferredLanguages = ['en-US', 'en-AU', 'en_AU', 'en_US'];

  final FlutterTts _flutterTts = FlutterTts();
  bool _initialized = false;
  bool _enabled = true;
  String? _lastTtsError;
  List<String> _engineNames = <String>[];
  int _engineCursor = 0;
  final ValueNotifier<bool> _enabledNotifier = ValueNotifier<bool>(true);

  ValueListenable<bool> get enabledListenable => _enabledNotifier;
  bool get isEnabled => _enabled;

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) {
      return;
    }
    _enabled = enabled;
    _enabledNotifier.value = enabled;
    if (!enabled) {
      try {
        await _flutterTts.stop();
      } catch (_) {
        // Ignore stop errors from unavailable engines.
      }
    }
  }

  Future<void> toggleEnabled() => setEnabled(!_enabled);

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    _flutterTts.setErrorHandler((message) {
      _lastTtsError = '$message';
    });

    await _loadAndSelectEngine();

    final languages = _asStringList(await _flutterTts.getLanguages);
    final selectedLanguage = _selectLanguage(languages);
    if (selectedLanguage != null) {
      await _flutterTts.setLanguage(selectedLanguage);
    }

    try {
      await _flutterTts.setAudioAttributesForNavigation();
    } catch (_) {
      // Not supported on some platforms.
    }

    await _flutterTts.setSpeechRate(0.47);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _initialized = true;
  }

  Future<void> _loadAndSelectEngine() async {
    try {
      final enginesDynamic = await _flutterTts.getEngines;
      final engines = _asEngineNames(enginesDynamic);

      if (engines.isEmpty) {
        return;
      }

      _engineNames = engines;
      final preferred = engines.firstWhere(
        (engine) => engine == 'com.google.android.tts',
        orElse: () => engines.first,
      );
      _engineCursor = engines.indexOf(preferred);
      await _flutterTts.setEngine(preferred);
    } catch (_) {
      // Ignore engine selection failure.
    }
  }

  List<String> _asStringList(dynamic values) {
    if (values is! List) {
      return <String>[];
    }
    return values.map((e) => '$e').toList();
  }

  List<String> _asEngineNames(dynamic values) {
    if (values is! List) {
      return <String>[];
    }
    return values
        .map((entry) {
          if (entry is Map && entry['name'] != null) {
            return entry['name'].toString();
          }
          return entry.toString();
        })
        .where((name) => name.trim().isNotEmpty)
        .toList();
  }

  String? _selectLanguage(List<String> languages) {
    for (final candidate in _preferredLanguages) {
      final hasCandidate = languages.any(
        (lang) => lang.toLowerCase() == candidate.toLowerCase(),
      );
      if (hasCandidate) {
        return candidate;
      }
    }

    for (final language in languages) {
      if (language.toLowerCase().startsWith('en')) {
        return language;
      }
    }

    return languages.isNotEmpty ? languages.first : null;
  }

  Future<void> speak(String text, {bool interrupt = true}) async {
    if (!_enabled || text.trim().isEmpty) {
      return;
    }

    await _ensureInitialized();

    if (interrupt) {
      await _flutterTts.stop();
    }

    _lastTtsError = null;
    final result = await _flutterTts.speak(text);
    final isOkResult = result == 1 || result == 0;
    if (!isOkResult || _lastTtsError != null) {
      await _retryWithNextEngine(text, interrupt: interrupt);
    }
  }

  Future<void> _retryWithNextEngine(
    String text, {
    required bool interrupt,
  }) async {
    if (_engineNames.length > 1) {
      _engineCursor = (_engineCursor + 1) % _engineNames.length;
      final nextEngine = _engineNames[_engineCursor];
      try {
        await _flutterTts.setEngine(nextEngine);
      } catch (_) {
        // Ignore engine switch failure.
      }
    } else {
      _initialized = false;
      await _ensureInitialized();
    }

    if (interrupt) {
      await _flutterTts.stop();
    }

    _lastTtsError = null;
    final retryResult = await _flutterTts.speak(text);
    final retryOk =
        (retryResult == 1 || retryResult == 0) && _lastTtsError == null;
    if (!retryOk) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

}
