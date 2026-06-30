import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ACCESSIBILITY SERVICE
//
// Centralises all accessibility state and TTS behaviour.
// Usage:
//   final a11y = AccessibilityService.instance;
//   await a11y.load();                        // call once at app start
//   a11y.illiteracyMode                       // bool
//   a11y.visualImpairmentMode                 // bool
//   await a11y.speak('text', lang: 'fr-FR');  // TTS
//   await a11y.speakStage('MAIN', 'Doliprane', priority: 'HIGH', lang: 'fr');
// ─────────────────────────────────────────────────────────────────────────────

class AccessibilityService extends ChangeNotifier {

  AccessibilityService._();
  static final AccessibilityService instance = AccessibilityService._();

  // ── state ──────────────────────────────────────────────────────────────────
  bool   _illiteracyMode       = false;
  bool   _visualImpairmentMode = false;
  bool   _highContrastMode     = false;
  bool   _largeTextMode        = false;
  double _textScaleFactor      = 1.2; // 1.0 – 1.6, controlled by slider
  String _ttsLanguage          = 'en-US';

  bool   get illiteracyMode       => _illiteracyMode;
  bool   get visualImpairmentMode => _visualImpairmentMode;
  bool   get highContrastMode     => _highContrastMode || _visualImpairmentMode;
  bool   get largeTextMode        => _largeTextMode    || _visualImpairmentMode;
  bool   get ttsEnabled           => _illiteracyMode   || _visualImpairmentMode;
  String get ttsLanguage          => _ttsLanguage;
  double get textScale            => largeTextMode ? _textScaleFactor : 1.0;
  double get textScaleFactor      => _textScaleFactor;

  // ── TTS engine ─────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;

  // ── persist keys ───────────────────────────────────────────────────────────
  static const _kIlliteracy  = 'a11y_illiteracy';
  static const _kVisual      = 'a11y_visual';
  static const _kContrast    = 'a11y_contrast';
  static const _kLargeText   = 'a11y_large_text';
  static const _kLang        = 'a11y_tts_lang';
  static const _kTextScale   = 'a11y_text_scale';

  // ── load from prefs ────────────────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _illiteracyMode       = prefs.getBool(_kIlliteracy) ?? false;
    _visualImpairmentMode = prefs.getBool(_kVisual)     ?? false;
    _highContrastMode     = prefs.getBool(_kContrast)   ?? false;
    _largeTextMode        = prefs.getBool(_kLargeText)  ?? false;
    _textScaleFactor      = prefs.getDouble(_kTextScale) ?? 1.2;
    _ttsLanguage          = prefs.getString(_kLang)     ?? 'en-US';
    await _initTts();
    notifyListeners();
  }

  Future<void> _initTts() async {
    // Force Google TTS engine — avoids device default which may be French
    await _tts.setEngine('com.google.android.tts');
    await _tts.setLanguage('en-US');
    // Explicitly set an English voice if available
    final voices = await _tts.getVoices as List?;
    if (voices != null) {
      final enVoice = voices.firstWhere(
        (v) => v is Map &&
               (v['locale'] == 'en-US' || v['locale'] == 'en-GB') &&
               (v['name'] as String? ?? '').toLowerCase().contains('english'),
        orElse: () => null,
      );
      if (enVoice != null && enVoice is Map) {
        await _tts.setVoice({
          'name':   enVoice['name'] as String,
          'locale': enVoice['locale'] as String,
        });
      }
    }
    await _tts.setSpeechRate(0.38);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ttsReady = true;
  }

  // ── setters ────────────────────────────────────────────────────────────────
  Future<void> setIlliteracyMode(bool v) async {
    _illiteracyMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIlliteracy, v);
    notifyListeners();
  }

  Future<void> setVisualImpairmentMode(bool v) async {
    _visualImpairmentMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVisual, v);
    notifyListeners();
  }

  Future<void> setHighContrastMode(bool v) async {
    _highContrastMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kContrast, v);
    notifyListeners();
  }

  Future<void> setLargeTextMode(bool v) async {
    _largeTextMode = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLargeText, v);
    notifyListeners();
  }

  Future<void> setTextScaleFactor(double v) async {
    _textScaleFactor = v.clamp(1.0, 1.6);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTextScale, _textScaleFactor);
    notifyListeners();
  }

  Future<void> setTtsLanguage(String lang) async {
    _ttsLanguage = lang;
    await _tts.setLanguage(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLang, lang);
    notifyListeners();
  }

  // ── TEXT CLEANING ───────────────────────────────────────────────────────────
  //
  // Strips emojis and punctuation symbols that TTS engines read literally.
  // Also normalises medication names — removes dosage suffixes and converts
  // ALL-CAPS brand names to Title Case so they are pronounced as words.
  //
  // Examples:
  //   "💊 IMPORTANT. Prenez..."  → "Attention. Prenez..."
  //   "ACUILIX"                  → "Acuilix"
  //   "Doliprane 500mg"          → "Doliprane"
  // ──────────────────────────────────────────────────────────────────────────

  String _cleanForTts(String text) {
    return text
        .replaceAll(RegExp(
            r'[\u{1F000}-\u{1FFFF}]|[\u{2600}-\u{27FF}]|[\u{2B00}-\u{2BFF}]'
            r'|[\u{FE00}-\u{FEFF}]|[\u{1F900}-\u{1F9FF}]',
            unicode: true), '')
        .replaceAll(RegExp(r'[!?*#@%^&+=|<>~`{}[\]\\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanMedName(String name) {
    return name
        .replaceAll(RegExp(r'\s*\d+\s*(mg|g|ml|mcg|µg|ui|iu)\b',
            caseSensitive: false), '')
        .splitMapJoin(RegExp(r'\b[A-Z]{3,}\b'), onMatch: (m) {
          final w = m.group(0)!;
          return w[0] + w.substring(1).toLowerCase();
        })
        .trim();
  }

  // ── TTS ────────────────────────────────────────────────────────────────────

  Future<void> speak(String text, {String? lang}) async {
    if (!ttsEnabled) return;
    if (!_ttsReady) await _initTts();
    final cleaned = _cleanForTts(text);
    if (cleaned.isEmpty) return;
    if (lang != null && lang != _ttsLanguage) await _tts.setLanguage(lang);
    await _tts.stop();
    await _tts.speak(cleaned);
    if (lang != null && lang != _ttsLanguage) await _tts.setLanguage(_ttsLanguage);
  }

  /// Like [speak] but waits for TTS to fully finish before returning.
  /// Use this before starting the microphone to avoid audio-session conflicts
  /// where TTS audio is still playing when speech recognition starts.
  Future<void> speakAndWait(String text, {String? lang}) async {
    if (!ttsEnabled) return;
    if (!_ttsReady) await _initTts();
    final cleaned = _cleanForTts(text);
    if (cleaned.isEmpty) return;
    if (lang != null && lang != _ttsLanguage) await _tts.setLanguage(lang);
    await _tts.stop();
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(cleaned);
    await _tts.awaitSpeakCompletion(false);
    if (lang != null && lang != _ttsLanguage) await _tts.setLanguage(_ttsLanguage);
  }

  Future<void> stop() async => _tts.stop();

  // ── CONFIRMATION SOUND ─────────────────────────────────────────────────────
  // Called after patient taps "I took it". Positive reinforcement.
  Future<void> speakConfirmation() async {
    if (!ttsEnabled) return;
    await speak('Well done. Medication taken.');
  }

  // ── SPEAK NOTIFICATION ─────────────────────────────────────────────────────
  //
  // Reads the actual notification message from the DB directly.
  // This is the single source of truth — no duplicate text templates.
  // The message already contains the right content for each stage,
  // we just clean it before speaking.
  //
  // Also adjusts TTS speed per stage:
  //   ESCALATION / MAIN_HIGH  → faster (0.45) — urgency
  //   PREP / BEDTIME_PREP     → slower (0.32) — heads-up, no rush
  //   everything else         → normal (0.38)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> speakNotification(
    String message, {
    String stage = 'MAIN',
    String lang  = 'fr',
  }) async {
    if (!ttsEnabled) return;
    if (!_ttsReady) await _initTts();

    final ttsLang = lang == 'ar' ? 'ar-SA' : 'en-US';

    // Adjust speed per stage urgency
    final double rate;
    if (stage == 'ESCALATION' || stage == 'MAIN_HIGH' ||
        stage == 'BEFORE_MEAL_MAIN_HIGH') {
      rate = 0.45; // slightly faster — urgent
    } else if (stage == 'PREP' || stage == 'BEDTIME_PREP' ||
               stage == 'EMPTY_STOMACH_PREP' || stage == 'BEFORE_MEAL_EARLY') {
      rate = 0.32; // slower — just a heads-up
    } else {
      rate = 0.38; // normal
    }

    await _tts.setSpeechRate(rate);

    // Clean the message then speak it
    final cleaned = _cleanForTts(message);
    if (cleaned.isEmpty) return;

    if (ttsLang != _ttsLanguage) await _tts.setLanguage(ttsLang);
    await _tts.stop();
    await _tts.speak(cleaned);
    if (ttsLang != _ttsLanguage) await _tts.setLanguage(_ttsLanguage);
  }

  // Keep speakStage as a fallback in case message is not available
  Future<void> speakStage(
    String stage,
    String medicationName, {
    String priority = 'MEDIUM',
    String lang     = 'fr',
  }) async {
    if (!ttsEnabled) return;
    final name    = _cleanMedName(medicationName);
    final isFr    = lang == 'fr';
    final ttsLang = lang == 'ar' ? 'ar-SA' : 'en-US';
    final text    = isFr
        ? 'Il est l heure de prendre $name.'
        : 'حان وقت تناول $name.';
    await speak(text, lang: ttsLang);
  }

  // ── VIBRATION ──────────────────────────────────────────────────────────────

  Future<void> vibrateForStage(String stage) async {
    if (stage == 'ESCALATION' || stage == 'MAIN_HIGH') {
      // Triple strong pulse for critical
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 300));
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 300));
      HapticFeedback.heavyImpact();
    } else if (stage.contains('MAIN') || stage.contains('BEDTIME_MAIN')) {
      // Double pulse for normal main
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 400));
      HapticFeedback.mediumImpact();
    } else {
      // Single light for prep/info
      HapticFeedback.lightImpact();
    }
  }
}