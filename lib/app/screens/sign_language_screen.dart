import 'dart:async';

import 'package:flutter/material.dart';

import '../feature/auslan_scripts/sign_language_camera_card.dart';
import '../services/app_announcer.dart';
import '../services/translation_history_service.dart';
import '../widgets/module_bottom_sheet.dart';
import '../widgets/module_header.dart';

class SignLanguageScreen extends StatefulWidget {
  const SignLanguageScreen({super.key});

  @override
  State<SignLanguageScreen> createState() => _SignLanguageScreenState();
}

class _SignLanguageScreenState extends State<SignLanguageScreen> {
  final TranslationHistoryService _historyService = TranslationHistoryService();
  final List<TranslationHistoryEntry> _history = <TranslationHistoryEntry>[];
  String _allLetters = '';
  String _meaning = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final loaded = await _historyService.load();
    if (!mounted) {
      return;
    }
    setState(() => _history
      ..clear()
      ..addAll(loaded));
  }

  Future<void> _saveTranslation({
    required String capturedLetters,
    required String? guessedText,
  }) async {
    final trimmedLetters = capturedLetters.trim();
    if (trimmedLetters.isEmpty) {
      return;
    }

    final persisted = await _historyService.saveEntry(
      text: trimmedLetters,
      meaning: guessedText?.trim() ?? '',
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _history
        ..clear()
        ..addAll(persisted);
      _allLetters = '';
      _meaning = guessedText?.trim() ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                const ModuleHeader(
                  title: 'Sign Language Translation',
                  accent: Color(0xFF9333EA),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: SignLanguageCameraCard(
                      label: 'Show hand signs to camera',
                      accent: const Color(0xFF3B82F6),
                      onPrediction: (rawLabel, confidence, allLetters) {
                        final isNewCaptureStart =
                            _allLetters.isEmpty && allLetters.isNotEmpty;
                        setState(() {
                          _allLetters = allLetters;
                          if (isNewCaptureStart) {
                            _meaning = '';
                          }
                        });
                        debugPrint(
                          'RAW: $rawLabel ${confidence.toStringAsFixed(1)}% | RESULT: $allLetters',
                        );
                      },
                      onFinalized: (capturedLetters, guessedText, trigger) async {
                        if (guessedText != null && guessedText.isNotEmpty) {
                          AppAnnouncer.instance.speak(guessedText);
                        }

                        await _saveTranslation(
                          capturedLetters: capturedLetters,
                          guessedText: guessedText,
                        );

                        debugPrint(
                          'FINALIZE($trigger): "$capturedLetters" -> "${guessedText ?? '(no result)'}"',
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: ModuleBottomSheet.collapsedHeight),
              ],
            ),
            ModuleBottomSheet(
              title: 'Translation History',
              accent: const Color(0xFFE9D5FF),
              hasData: _history.isNotEmpty || _allLetters.isNotEmpty || _meaning.isNotEmpty,
              child: _history.isEmpty && _allLetters.isEmpty && _meaning.isEmpty
                  ? const Text(
                      'Waiting for hand signs...',
                      style: TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 14,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _history.isEmpty ? 1 : _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (_history.isEmpty) {
                          final currentText = _allLetters.isNotEmpty ? _allLetters : _meaning;
                          return Text(
                            _allLetters.isNotEmpty
                                ? '$_allLetters${_meaning.isEmpty ? '' : '\nMeaning: $_meaning'}'
                                : 'Meaning: $_meaning',
                            style: const TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 14,
                            ),
                          );
                        }

                        final entry = _history[index];
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF5FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE9D5FF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.text,
                                style: const TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                entry.meaning.isNotEmpty
                                    ? entry.meaning
                                    : 'Pending translation',
                                style: const TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontSize: 14,
                                ),
                              ),
                            ],
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
