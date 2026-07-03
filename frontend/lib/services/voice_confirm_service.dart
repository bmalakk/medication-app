import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VOICE CONFIRM SERVICE
//
// Listens for confirmation keywords after patient takes medication.
// Patient taps the mic button → speaks → app detects keyword → confirms.
//
// Recognised keywords (English + French):
//   "took", "taken", "done", "yes", "ok", "confirm",
//   "pris", "oui", "fait", "terminé"
//
// Usage:
//   final voice = VoiceConfirmService();
//   await voice.initialize();
//   await voice.startListening(
//     onConfirmed: () => markAsTaken(),
//     onListeningChanged: (isListening) => setState(...),
//     onPartialResult: (text) => setState(...),
//   );
//   voice.stop();
// ─────────────────────────────────────────────────────────────────────────────

class VoiceConfirmService {

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _isListening = false;
  ValueChanged<bool>? _onListeningChanged;

  bool get isListening  => _isListening;
  bool get isAvailable  => _initialized;

  static const List<String> _keywords = [
    // English
    'took', 'taken', 'done', 'yes', 'ok', 'okay',
    'confirm', 'confirmed', 'i took it', 'taken it',
    // French
    'pris', 'oui', 'fait', 'terminé', 'termine', 'je l ai pris',
  ];

  // ── Initialize ───────────────────────────────────────────────────────────────
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (e) {
        debugPrint('[Voice] Error: ${e.errorMsg}');
        // If recognition errors out (e.g. no match, timeout, network) the
        // native side stops listening on its own — without this, the UI is
        // left stuck showing "Listening..." with no feedback until the
        // 8-second fallback timer fires.
        if (_isListening) {
          _isListening = false;
          _onListeningChanged?.call(false);
        }
      },
      onStatus: (s) {
        debugPrint('[Voice] Status: $s');
        if ((s == 'notListening' || s == 'done') && _isListening) {
          _isListening = false;
          _onListeningChanged?.call(false);
        }
      },
    );
    return _initialized;
  }

  // ── Start listening ──────────────────────────────────────────────────────────
  Future<void> startListening({
    required VoidCallback onConfirmed,
    required ValueChanged<bool> onListeningChanged,
    ValueChanged<String>? onPartialResult,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    if (_isListening) {
      await stop();
      return;
    }

    _onListeningChanged = onListeningChanged;
    _isListening = true;
    onListeningChanged(true);

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 8),
        pauseFor:  const Duration(seconds: 3),
        // No localeId: forcing 'en_US' meant the recognizer would listen but
        // never return a result on devices where that language pack isn't
        // installed. Omitting it lets speech_to_text use the device's own
        // default locale, which is guaranteed to be supported.
        partialResults: true,
        onResult: (result) {
          final text = result.recognizedWords.toLowerCase().trim();
          debugPrint('[Voice] Heard: "$text"');

          onPartialResult?.call(text);

          // Check for any confirmation keyword
          final confirmed = _keywords.any((kw) => text.contains(kw));
          if (confirmed) {
            debugPrint('[Voice] Keyword detected — confirming');
            _isListening = false;
            stop();
            onListeningChanged(false);
            onConfirmed();
          }
        },
        listenMode: ListenMode.confirmation,
      );
    } catch (e) {
      debugPrint('[Voice] listen() failed: $e');
      _isListening = false;
      onListeningChanged(false);
      return;
    }

    // Auto-stop after listen duration
    Future.delayed(const Duration(seconds: 8), () {
      if (_isListening) {
        stop();
        onListeningChanged(false);
      }
    });
  }

  // ── Stop ─────────────────────────────────────────────────────────────────────
  Future<void> stop() async {
    _isListening = false;
    await _speech.stop();
  }

  void dispose() {
    _onListeningChanged = null;
    _speech.cancel();
  }
}