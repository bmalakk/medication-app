import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/accessibility_service.dart';
import '../services/shake_confirm_service.dart';
import '../services/voice_confirm_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ACCESSIBLE NOTIFICATION CARDS  v5
//
// Shake fix: the card REGISTERS FOR SHAKE WHEN TAPPED (inside _speak), not in
// initState. Because every card in the list builds at once, registering in
// initState meant the last-built card became the shake target — so a shake
// confirmed the wrong card. Now: tap a card → it reads aloud AND becomes the
// active shake target → shake confirms exactly that card.
// ─────────────────────────────────────────────────────────────────────────────

class _StageCfg {
  final Color   color;
  final Color   bgColor;
  final String  emoji;
  final IconData icon;
  final String  label;
  final bool    isCritical;
  const _StageCfg({
    required this.color, required this.bgColor,
    required this.emoji, required this.icon,
    required this.label, this.isCritical = false,
  });
}

_StageCfg _cfgForStage(String stage) {
  switch (stage) {
    case 'PREP':
      return const _StageCfg(color: Color(0xFFB45309), bgColor: Color(0xFFFFFDE7),
          emoji: '⏰', icon: Icons.access_time_rounded, label: 'Coming soon');
    case 'MAIN':
      return const _StageCfg(color: Color(0xFF1565C0), bgColor: Color(0xFFE3F2FD),
          emoji: '💊', icon: Icons.medication_rounded, label: 'Take now');
    case 'MAIN_HIGH':
      return const _StageCfg(color: Color(0xFFE53935), bgColor: Color(0xFFFFEBEE),
          emoji: '⚠️', icon: Icons.medication_rounded,
          label: 'Take now — important', isCritical: true);
    case 'FOLLOW_UP':
      return const _StageCfg(color: Color(0xFFF57C00), bgColor: Color(0xFFFFF3E0),
          emoji: '⏳', icon: Icons.hourglass_bottom_rounded, label: 'Still waiting');
    case 'MISSED':
      return const _StageCfg(color: Color(0xFFD84315), bgColor: Color(0xFFFBE9E7),
          emoji: '❌', icon: Icons.error_outline_rounded, label: 'Missed dose');
    case 'ESCALATION':
      return const _StageCfg(color: Color(0xFFB71C1C), bgColor: Color(0xFFFFEBEE),
          emoji: '🚨', icon: Icons.crisis_alert_rounded,
          label: 'URGENT', isCritical: true);
    case 'SNOOZE':
      return const _StageCfg(color: Color(0xFF546E7A), bgColor: Color(0xFFECEFF1),
          emoji: '😴', icon: Icons.snooze_rounded, label: 'Snoozed reminder');
    case 'BEFORE_MEAL_EARLY':
      return const _StageCfg(color: Color(0xFFAF6C00), bgColor: Color(0xFFFFF8E1),
          emoji: '🍽️', icon: Icons.restaurant_menu_rounded, label: 'Before meal — soon');
    case 'BEFORE_MEAL_MAIN':
      return const _StageCfg(color: Color(0xFFEF6C00), bgColor: Color(0xFFFFF3E0),
          emoji: '🍽️', icon: Icons.restaurant_menu_rounded, label: 'Before meal — now');
    case 'BEFORE_MEAL_MAIN_HIGH':
      return const _StageCfg(color: Color(0xFFD32F2F), bgColor: Color(0xFFFFEBEE),
          emoji: '🍽️', icon: Icons.restaurant_menu_rounded,
          label: 'Before meal — urgent', isCritical: true);
    case 'BEFORE_MEAL_FOLLOWUP':
      return const _StageCfg(color: Color(0xFFBF360C), bgColor: Color(0xFFFBE9E7),
          emoji: '🍽️', icon: Icons.warning_amber_rounded, label: 'Last chance');
    case 'INFORM_LATE':
      return const _StageCfg(color: Color(0xFF546E7A), bgColor: Color(0xFFECEFF1),
          emoji: '🙅', icon: Icons.block_rounded, label: 'Too late — do not take');
    case 'BEDTIME_PREP':
      return const _StageCfg(color: Color(0xFF3949AB), bgColor: Color(0xFFE8EAF6),
          emoji: '🌙', icon: Icons.bedtime_outlined, label: 'Sleep soon');
    case 'BEDTIME_MAIN':
      return const _StageCfg(color: Color(0xFF283593), bgColor: Color(0xFFE8EAF6),
          emoji: '💤', icon: Icons.bedtime_rounded, label: 'Bedtime');
    case 'BEDTIME_LATE':
      return const _StageCfg(color: Color(0xFF1A237E), bgColor: Color(0xFFE8EAF6),
          emoji: '🌛', icon: Icons.nightlight_round, label: 'Still awake?');
    case 'EMPTY_STOMACH_PREP':
      return const _StageCfg(color: Color(0xFF00695C), bgColor: Color(0xFFE0F2F1),
          emoji: '🥛', icon: Icons.no_meals_outlined, label: 'Empty stomach — soon');
    case 'SAFE_TO_EAT':
      return const _StageCfg(color: Color(0xFF2E7D32), bgColor: Color(0xFFE8F5E9),
          emoji: '🥗', icon: Icons.restaurant_rounded, label: 'You can eat now');
    default:
      return const _StageCfg(color: Color(0xFF1565C0), bgColor: Color(0xFFE3F2FD),
          emoji: '💊', icon: Icons.medication_rounded, label: 'Medication');
  }
}

Map<String, dynamic> _parseNotifData(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String && raw.isNotEmpty) {
    try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
  }
  return {};
}

// ─────────────────────────────────────────────────────────────────────────────
// ILLITERACY CARD
// ─────────────────────────────────────────────────────────────────────────────

class IlliteracyNotificationCard extends StatefulWidget {
  final Map<String, dynamic> notification;
  final bool isFr;
  final VoidCallback onTaken;
  final VoidCallback onSnooze;
  final VoidCallback onSkip;
  final VoidCallback onDismiss;
  final dynamic Function(Map<String, dynamic>) getStyle;

  const IlliteracyNotificationCard({
    super.key,
    required this.notification, required this.isFr,
    required this.onTaken, required this.onSnooze,
    required this.onSkip, required this.onDismiss,
    required this.getStyle,
  });

  @override
  State<IlliteracyNotificationCard> createState() =>
      _IlliteracyNotificationCardState();
}

class _IlliteracyNotificationCardState
    extends State<IlliteracyNotificationCard>
    with TickerProviderStateMixin {

  late AnimationController _pulse;
  late AnimationController _successCtrl;
  late Animation<double>   _successScale;
  late Animation<double>   _successOpacity;

  bool   _showSuccess = false;
  int    _shakeCount  = 0;
  bool   _isListening = false;
  String _heardText   = '';

  final _a11y  = AccessibilityService.instance;
  // ── no local _shake instance — use singleton, registered on tap ───────────
  final _voice = VoiceConfirmService();

  int get _notifId => widget.notification['id'] as int;

  @override
  void initState() {
    super.initState();

    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    final data  = _parseNotifData(widget.notification['data']);
    final stage = (data['stage'] ?? '').toString();
    if (stage == 'ESCALATION' || stage == 'MAIN_HIGH' ||
        stage == 'BEFORE_MEAL_MAIN_HIGH') {
      _pulse.repeat(reverse: true);
    }

    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _successScale = Tween<double>(begin: 0.5, end: 1.2).animate(
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
    _successOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _successCtrl,
            curve: const Interval(0.0, 0.5, curve: Curves.easeIn)));

    // ── NOTE: shake registration happens in _speak() (on tap), NOT here.
    //    Registering here would make every card register on build and the
    //    last one would win — confirming the wrong card on shake.
  }

  @override
  void dispose() {
    _pulse.dispose();
    _successCtrl.dispose();
    // Unregister by id — only stops the sensor if THIS card was the active one
    ShakeConfirmService.instance.unregister(_notifId);
    _voice.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _voice.stop();
      if (mounted) setState(() { _isListening = false; _heardText = ''; });
      return;
    }
    // Wait for TTS to fully finish before starting the mic — otherwise the
    // TTS audio ("Say: I took it") is picked up by the recognizer and triggers
    // a false keyword match, or the audio session conflict prevents recognition.
    await _a11y.speakAndWait('Say: I took it');
    if (!mounted) return;
    await _voice.startListening(
      onConfirmed: () {
        if (mounted) setState(() { _isListening = false; _heardText = ''; });
        _handleTaken();
      },
      onListeningChanged: (v) {
        if (mounted) setState(() => _isListening = v);
      },
      onPartialResult: (text) {
        if (mounted) setState(() => _heardText = text);
      },
    );
  }

  Future<void> _speak() async {
    final data    = _parseNotifData(widget.notification['data']);
    final stage   = (data['stage'] ?? 'MAIN').toString();
    final message = (widget.notification['message'] ?? '').toString();

    // ── Make THIS card the active shake target ──────────────────────────────
    // Only the card the patient just tapped will receive the shake confirmation.
    final style  = widget.getStyle(widget.notification);
    final isRead = widget.notification['is_read'] == 1 ||
                   widget.notification['is_read'] == true;
    if (style.showTaken && !isRead && !_showSuccess) {
      ShakeConfirmService.instance.register(
        notificationId: _notifId,
        onConfirmed: _handleTaken,
        onProgress: (count) {
          if (mounted) setState(() => _shakeCount = count);
        },
      );
    }

    await _a11y.vibrateForStage(stage);
    await _a11y.speakNotification(message, stage: stage, lang: 'en');
  }

  Future<void> _handleTaken() async {
    // Stop listening for shakes on this card immediately
    ShakeConfirmService.instance.unregister(_notifId);
    setState(() => _showSuccess = true);
    _successCtrl.forward();
    await _a11y.speakConfirmation();
    await Future.delayed(const Duration(milliseconds: 900));
    widget.onTaken();
  }

  String _medName() {
    final title = (widget.notification['title'] ?? '').toString();
    final idx   = title.indexOf(':');
    return idx != -1 ? title.substring(idx + 1).trim() : title;
  }

  String _time() {
    final data = _parseNotifData(widget.notification['data']);
    final raw  = data['scheduled_date_time']?.toString();
    if (raw == null || raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final data  = _parseNotifData(widget.notification['data']);
    final stage = (data['stage'] ?? 'MAIN').toString();
    final cfg   = _cfgForStage(stage);
    final style = widget.getStyle(widget.notification);
    final isRead = widget.notification['is_read'] == 1 ||
                   widget.notification['is_read'] == true;
    final name  = _medName();
    final time  = _time();
    final fs    = _a11y.textScaleFactor;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final pulseScale = cfg.isCritical ? 1.0 + _pulse.value * 0.012 : 1.0;
        return Transform.scale(
          scale: pulseScale,
          child: GestureDetector(
            onTap: _speak,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: cfg.isCritical
                    ? Border.all(color: cfg.color, width: 3)
                    : Border.all(color: cfg.color.withOpacity(0.3), width: 1.5),
                boxShadow: [BoxShadow(
                  color: cfg.color.withOpacity(cfg.isCritical ? 0.3 : 0.1),
                  blurRadius: cfg.isCritical ? 24 : 12,
                  offset: const Offset(0, 6),
                )],
              ),
              child: Column(children: [
                Stack(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    decoration: BoxDecoration(
                      color: cfg.color,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24)),
                    ),
                    child: Column(children: [
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Stack(alignment: Alignment.center, children: [
                          Icon(Icons.medication_rounded,
                              color: Colors.white.withOpacity(0.3), size: 72),
                          Text(cfg.emoji,
                              style: const TextStyle(fontSize: 42)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(cfg.label.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11 * fs,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            )),
                      ),
                    ]),
                  ),
                  if (_showSuccess)
                    AnimatedBuilder(
                      animation: _successCtrl,
                      builder: (_, __) => Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(
                              _successOpacity.value * 0.92),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                        ),
                        child: Column(children: [
                          Transform.scale(
                            scale: _successScale.value,
                            child: const Text('✅',
                                style: TextStyle(fontSize: 64)),
                          ),
                          const SizedBox(height: 8),
                          Text('Well done!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20 * fs,
                                fontWeight: FontWeight.bold,
                              )),
                        ]),
                      ),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(name,
                            style: TextStyle(
                              fontSize: 20 * fs,
                              fontWeight: FontWeight.bold,
                              color: cfg.color,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                        if (time.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cfg.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('🕐 $time',
                                style: TextStyle(
                                  fontSize: 16 * fs,
                                  fontWeight: FontWeight.bold,
                                  color: cfg.color,
                                )),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.touch_app_outlined,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('Tap card to hear message',
                          style: TextStyle(
                              fontSize: 10 * fs,
                              color: Colors.grey.shade400)),
                      const Spacer(),
                      GestureDetector(
                        onTap: _speak,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cfg.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.volume_up_rounded,
                              color: cfg.color, size: 18),
                        ),
                      ),
                    ]),
                    if (_shakeCount > 0 && !_showSuccess) ...[
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.vibration,
                            size: 14, color: Colors.orange.shade600),
                        const SizedBox(width: 6),
                        Text('Shake to confirm ',
                            style: TextStyle(
                                fontSize: 11 * fs,
                                color: Colors.orange.shade600)),
                        ...List.generate(3, (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _shakeCount
                                ? Colors.orange.shade600
                                : Colors.grey.shade300,
                          ),
                        )),
                      ]),
                    ],
                    if (_isListening) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(children: [
                          const _PulsingMic(),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Listening...',
                                style: TextStyle(
                                    fontSize: 13 * fs,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold)),
                            if (_heardText.isNotEmpty)
                              Text('"$_heardText"',
                                  style: TextStyle(
                                      fontSize: 11 * fs,
                                      color: Colors.blue.shade500,
                                      fontStyle: FontStyle.italic)),
                          ])),
                          GestureDetector(
                            onTap: _toggleVoice,
                            child: Icon(Icons.close,
                                color: Colors.blue.shade400, size: 18),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!isRead && !_showSuccess)
                      _buildButtons(style, cfg, fs)
                    else if (isRead && !_showSuccess)
                      Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.green.shade400, size: 20),
                        const SizedBox(width: 6),
                        Text('Done', style: TextStyle(
                            color: Colors.green.shade400,
                            fontWeight: FontWeight.w600,
                            fontSize: 14 * fs)),
                      ]),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildButtons(dynamic style, _StageCfg cfg, double fs) {
    return Column(children: [
      if (style.showTaken) ...[
        _btn(emoji: '✅', label: 'I took it',
            color: const Color(0xFF2E7D32), fs: fs,
            onTap: _handleTaken),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Icon(Icons.vibration, size: 16, color: Colors.orange.shade600),
              const SizedBox(width: 6),
              Text('Or shake phone',
                  style: TextStyle(
                      fontSize: 12 * fs,
                      color: Colors.orange.shade600,
                      fontWeight: FontWeight.w600)),
            ]),
          )),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _toggleVoice,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isListening
                    ? Colors.blue.shade600
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _isListening ? Icons.mic : Icons.mic_none_outlined,
                  size: 18,
                  color: _isListening ? Colors.white : Colors.blue.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  _isListening ? 'Listening...' : 'Say it',
                  style: TextStyle(
                    fontSize: 12 * fs,
                    color: _isListening ? Colors.white : Colors.blue.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
      ],
      if (style.showSnooze) ...[
        _btn(emoji: '⏰', label: 'Remind me later',
            color: const Color(0xFF1565C0), fs: fs,
            onTap: widget.onSnooze),
        const SizedBox(height: 10),
      ],
      if (style.showDismiss) ...[
        _btn(emoji: '👍', label: 'Got it',
            color: const Color(0xFF546E7A), fs: fs,
            onTap: widget.onDismiss),
        const SizedBox(height: 10),
      ],
      if (style.showSkip)
        GestureDetector(
          onTap: widget.onSkip,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Skip this dose',
                style: TextStyle(
                  fontSize: 13 * fs,
                  color: Colors.grey.shade500,
                  decoration: TextDecoration.underline,
                )),
          ),
        ),
    ]);
  }

  Widget _btn({
    required String emoji, required String label,
    required Color color, required double fs,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8, offset: const Offset(0, 4),
          )],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
            color: Colors.white,
            fontSize: 17 * fs,
            fontWeight: FontWeight.bold,
          )),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VISUAL IMPAIRMENT CARD
// ─────────────────────────────────────────────────────────────────────────────

class VisualImpairmentNotificationCard extends StatefulWidget {
  final Map<String, dynamic> notification;
  final bool isFr;
  final VoidCallback onTaken;
  final VoidCallback onSnooze;
  final VoidCallback onSkip;
  final VoidCallback onDismiss;
  final dynamic Function(Map<String, dynamic>) getStyle;

  const VisualImpairmentNotificationCard({
    super.key,
    required this.notification, required this.isFr,
    required this.onTaken, required this.onSnooze,
    required this.onSkip, required this.onDismiss,
    required this.getStyle,
  });

  @override
  State<VisualImpairmentNotificationCard> createState() =>
      _VisualImpairmentNotificationCardState();
}

class _VisualImpairmentNotificationCardState
    extends State<VisualImpairmentNotificationCard>
    with SingleTickerProviderStateMixin {

  late AnimationController _successCtrl;
  late Animation<double>   _successScale;
  bool   _showSuccess = false;
  int    _shakeCount  = 0;
  bool   _isListening = false;
  String _heardText   = '';

  final _a11y  = AccessibilityService.instance;
  // ── no local _shake instance — use singleton, registered on tap ───────────
  final _voice = VoiceConfirmService();

  int get _notifId => widget.notification['id'] as int;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));

    // ── NOTE: shake registration happens in _speak() (on tap), NOT here.
  }

  @override
  void dispose() {
    _successCtrl.dispose();
    // Unregister by id — only stops the sensor if THIS card was the active one
    ShakeConfirmService.instance.unregister(_notifId);
    _voice.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    final data    = _parseNotifData(widget.notification['data']);
    final stage   = (data['stage'] ?? 'MAIN').toString();
    final message = (widget.notification['message'] ?? '').toString();

    // ── Make THIS card the active shake target ──────────────────────────────
    final style  = widget.getStyle(widget.notification);
    final isRead = widget.notification['is_read'] == 1 ||
                   widget.notification['is_read'] == true;
    if (style.showTaken && !isRead && !_showSuccess) {
      ShakeConfirmService.instance.register(
        notificationId: _notifId,
        onConfirmed: _handleTaken,
        onProgress: (count) {
          if (mounted) setState(() => _shakeCount = count);
        },
      );
    }

    await _a11y.vibrateForStage(stage);
    await _a11y.speakNotification(message, stage: stage, lang: 'en');
  }

  Future<void> _handleTaken() async {
    ShakeConfirmService.instance.unregister(_notifId);
    setState(() => _showSuccess = true);
    _successCtrl.forward();
    await _a11y.speakConfirmation();
    await Future.delayed(const Duration(milliseconds: 900));
    widget.onTaken();
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _voice.stop();
      if (mounted) setState(() { _isListening = false; _heardText = ''; });
      return;
    }
    // Wait for TTS to fully finish before starting the mic — otherwise the
    // TTS audio ("Say: I took it") is picked up by the recognizer and triggers
    // a false keyword match, or the audio session conflict prevents recognition.
    await _a11y.speakAndWait('Say: I took it');
    if (!mounted) return;
    await _voice.startListening(
      onConfirmed: () {
        if (mounted) setState(() { _isListening = false; _heardText = ''; });
        _handleTaken();
      },
      onListeningChanged: (v) {
        if (mounted) setState(() => _isListening = v);
      },
      onPartialResult: (text) {
        if (mounted) setState(() => _heardText = text);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data    = _parseNotifData(widget.notification['data']);
    final stage   = (data['stage'] ?? 'MAIN').toString();
    final cfg     = _cfgForStage(stage);
    final style   = widget.getStyle(widget.notification);
    final isRead  = widget.notification['is_read'] == 1 ||
                    widget.notification['is_read'] == true;
    final title   = (widget.notification['title']   ?? '').toString();
    final message = (widget.notification['message'] ?? '').toString();
    final fs      = _a11y.textScaleFactor;

    return Semantics(
      label: '$title. $message',
      child: GestureDetector(
        onTap: _speak,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(20),
            border: cfg.isCritical
                ? Border.all(color: cfg.color, width: 3)
                : Border.all(color: cfg.color.withOpacity(0.5), width: 2),
            boxShadow: [BoxShadow(
              color: cfg.color.withOpacity(0.25),
              blurRadius: 16, offset: const Offset(0, 6),
            )],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 5,
                decoration: BoxDecoration(color: cfg.color,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20)))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (_showSuccess)
                  AnimatedBuilder(
                    animation: _successCtrl,
                    builder: (_, __) => Transform.scale(
                      scale: _successScale.value,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          const Text('✅', style: TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Text('Well done!', style: TextStyle(
                            color: Colors.green,
                            fontSize: 20 * fs,
                            fontWeight: FontWeight.bold,
                          )),
                        ]),
                      ),
                    ),
                  ),
                Row(children: [
                  Text(cfg.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title,
                      style: TextStyle(fontSize: 17 * fs,
                          fontWeight: FontWeight.bold, color: cfg.color))),
                  Semantics(
                    button: true, label: 'Replay audio',
                    child: GestureDetector(
                      onTap: _speak,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.volume_up_rounded,
                            color: cfg.color, size: 22),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(message, style: TextStyle(
                    fontSize: 16 * fs, color: Colors.white, height: 1.6)),
                const SizedBox(height: 6),
                Text('Tap card to hear this message',
                    style: TextStyle(fontSize: 10 * fs,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 20),
                if (!isRead && !_showSuccess)
                  _buildActions(style, fs)
                else if (isRead && !_showSuccess)
                  Row(children: [
                    Icon(Icons.check_circle,
                        color: Colors.green.shade400, size: 18),
                    const SizedBox(width: 6),
                    Text('Read', style: TextStyle(
                        color: Colors.green.shade400,
                        fontSize: 14 * fs)),
                  ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildActions(dynamic style, double fs) {
    return Column(children: [
      if (style.showTaken) ...[
        Semantics(button: true, label: 'Mark as taken',
            child: _btn('✅  I took it', Colors.green.shade700, fs, _handleTaken)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Icon(Icons.vibration, size: 16, color: Colors.orange.shade400),
              const SizedBox(width: 6),
              Text('Or shake phone',
                  style: TextStyle(
                      fontSize: 12 * fs,
                      color: Colors.orange.shade400,
                      fontWeight: FontWeight.w600)),
            ]),
          )),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: _isListening ? 'Stop listening' : 'Say I took it',
            child: GestureDetector(
              onTap: _toggleVoice,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isListening
                      ? Colors.blue.shade600
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    _isListening ? Icons.mic : Icons.mic_none_outlined,
                    size: 18,
                    color: _isListening ? Colors.white : Colors.blue.shade400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isListening ? 'Listening...' : 'Say it',
                    style: TextStyle(
                      fontSize: 12 * fs,
                      color: _isListening ? Colors.white : Colors.blue.shade400,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
      ],
      if (_shakeCount > 0 && !_showSuccess) ...[
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.vibration, size: 13, color: Colors.orange.shade400),
          const SizedBox(width: 6),
          Text('Shake to confirm ',
              style: TextStyle(fontSize: 11 * fs, color: Colors.orange.shade400)),
          ...List.generate(3, (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _shakeCount
                  ? Colors.orange.shade400
                  : Colors.grey.shade700,
            ),
          )),
        ]),
        const SizedBox(height: 8),
      ],
      if (_isListening) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(children: [
            const _PulsingMic(),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Listening...',
                  style: TextStyle(
                      fontSize: 13 * fs,
                      color: Colors.blue.shade300,
                      fontWeight: FontWeight.bold)),
              if (_heardText.isNotEmpty)
                Text('"$_heardText"',
                    style: TextStyle(
                        fontSize: 11 * fs,
                        color: Colors.blue.shade400,
                        fontStyle: FontStyle.italic)),
            ])),
            GestureDetector(
              onTap: _toggleVoice,
              child: Icon(Icons.close, color: Colors.blue.shade400, size: 18),
            ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (style.showSnooze) ...[
        Semantics(button: true, label: 'Snooze',
            child: _btn('⏰  Remind me later',
                const Color(0xFF1565C0), fs, widget.onSnooze)),
        const SizedBox(height: 10),
      ],
      if (style.showDismiss) ...[
        Semantics(button: true, label: 'Got it',
            child: _btn('👍  Got it',
                const Color(0xFF546E7A), fs, widget.onDismiss)),
        const SizedBox(height: 10),
      ],
      if (style.showSkip)
        Semantics(button: true, label: 'Skip dose',
            child: GestureDetector(
              onTap: widget.onSkip,
              child: Text('Skip this dose', style: TextStyle(
                fontSize: 14 * fs, color: Colors.grey.shade500,
                decoration: TextDecoration.underline,
              )),
            )),
    ]);
  }

  Widget _btn(String label, Color color, double fs, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, height: 64,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(14)),
        child: Center(child: Text(label, style: TextStyle(
          color: Colors.white, fontSize: 18 * fs,
          fontWeight: FontWeight.bold,
        ))),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULSING MIC ICON
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingMic extends StatefulWidget {
  const _PulsingMic();
  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween<double>(begin: 1.0, end: 1.4).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.blue.shade600, shape: BoxShape.circle),
          child: const Icon(Icons.mic, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}