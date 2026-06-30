import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/signal_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EARLY WARNING CARD — Enhanced
//
// Enhancements:
//   #1 — 7-day trend chart (mini sparkline)
//   #3 — Risk trend badge (↑ Getting worse / ↓ Improving / → Stable)
//   Tips — personalised actionable tip per active signal
// ─────────────────────────────────────────────────────────────────────────────

class EarlyWarningCard extends StatefulWidget {
  final bool showWhenLow;
  const EarlyWarningCard({super.key, this.showWhenLow = false});

  @override
  State<EarlyWarningCard> createState() => _EarlyWarningCardState();
}

class _EarlyWarningCardState extends State<EarlyWarningCard>
    with SingleTickerProviderStateMixin {

  AdherenceForecast?          _forecast;
  List<ForecastHistoryPoint>  _history  = [];
  bool _isLoading    = true;
  bool _isRefreshing = false;
  bool _expanded     = false;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _load();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      SignalService.instance.getLatestForecast(),
      SignalService.instance.getForecastHistory(),
    ]);
    final forecast = results[0] as AdherenceForecast?;
    final history  = results[1] as List<ForecastHistoryPoint>;
    if (mounted) {
      setState(() {
        _forecast  = forecast;
        _history   = history;
        _isLoading = false;
      });
      if (forecast?.riskLevel == 'critical' || forecast?.riskLevel == 'high') {
        _pulseCtrl.repeat(reverse: true);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    _pulseCtrl.stop();
    final results = await Future.wait([
      SignalService.instance.generateForecast(),
      SignalService.instance.getForecastHistory(),
    ]);
    final forecast = results[0] as AdherenceForecast?;
    final history  = results[1] as List<ForecastHistoryPoint>;
    if (mounted) {
      setState(() {
        _forecast    = forecast;
        _history     = history;
        _isRefreshing = false;
      });
      if (forecast?.riskLevel == 'critical' || forecast?.riskLevel == 'high') {
        _pulseCtrl.repeat(reverse: true);
      }
    }
  }

  // ── #3 Trend badge logic ─────────────────────────────────────────────────

  /// Compares current score to the previous forecast score.
  /// Returns: 'up' | 'down' | 'stable' | 'new'
  String _trend() {
    if (_history.length < 2) return 'new';
    final current  = _history.last.score;
    final previous = _history[_history.length - 2].score;
    final delta    = current - previous;
    if (delta >  0.05) return 'up';
    if (delta < -0.05) return 'down';
    return 'stable';
  }

  Widget _buildTrendBadge(Color riskColor) {
    final trend = _trend();
    if (trend == 'new') return const SizedBox.shrink();

    String label;
    IconData icon;
    Color color;

    switch (trend) {
      case 'up':
        label = 'Getting worse';
        icon  = Icons.trending_up_rounded;
        color = const Color(0xFFE53935);
        break;
      case 'down':
        label = 'Improving';
        icon  = Icons.trending_down_rounded;
        color = const Color(0xFF2E7D32);
        break;
      default:
        label = 'Stable';
        icon  = Icons.trending_flat_rounded;
        color = const Color(0xFFF57C00);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  // ── #1 Sparkline chart ───────────────────────────────────────────────────

  Widget _buildSparkline(Color riskColor) {
    if (_history.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('7-day risk trend',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        _buildTrendBadge(riskColor),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 64,
        child: CustomPaint(
          painter: _SparklinePainter(
            points:    _history.map((h) => h.score).toList(),
            color:     riskColor,
            bgColor:   riskColor.withOpacity(0.08),
          ),
          size: const Size(double.infinity, 64),
        ),
      ),
      const SizedBox(height: 4),
      // Day labels
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: _history.map((h) => Text(
          h.dayLabel,
          style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
        )).toList(),
      ),
    ]);
  }

  // ── Tips per signal ──────────────────────────────────────────────────────

  String _tipForSignal(String signal) {
    switch (signal) {
      case 'responseTimeDegradation':
        return '💡 Try taking your medication the moment the reminder appears — don\'t put it down for later.';
      case 'partialDayAdherence':
        return '💡 Set a dedicated alarm on your phone for your evening doses — separate from other notifications.';
      case 'weekendCliff':
        return '💡 Your weekend routine differs from weekdays. Try preparing your medications on Thursday night.';
      case 'postIllnessRecovery':
        return '💡 When recovering, start with your most important medications first and build back your routine gradually.';
      case 'specificMedDrift':
        return '💡 Place this medication somewhere very visible — next to your toothbrush or beside your plate.';
      case 'lowOverallAdherence':
        return '💡 Try using a weekly pill organizer to make it easier to track which doses you\'ve taken.';
      default:
        return '';
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_forecast == null) return const SizedBox.shrink();
    if (_forecast!.riskLevel == 'low' && !widget.showWhenLow) {
      return _buildLowRiskBadge();
    }
    return _buildForecastCard(_forecast!);
  }

  Widget _buildForecastCard(AdherenceForecast f) {
    final isCritical = f.riskLevel == 'critical';

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Transform.scale(
        scale: isCritical ? _pulseAnim.value : 1.0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: f.riskColor.withOpacity(isCritical ? 0.6 : 0.3),
              width: isCritical ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: f.riskColor.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(children: [

            // top stripe
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: f.riskColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                // ── header ──────────────────────────────────────────────
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: f.riskBgColor,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(f.riskIcon, color: f.riskColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('🤖 AI Health Insight',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.5)),
                      Text(f.riskLabel,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: f.riskColor)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: f.riskBgColor,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${f.scorePercent}%',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: f.riskColor)),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isRefreshing ? null : _refresh,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10)),
                      child: _isRefreshing
                          ? SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: f.riskColor))
                          : Icon(Icons.refresh_rounded,
                              size: 18, color: Colors.grey.shade500),
                    ),
                  ),
                ]),

                const SizedBox(height: 12),

                // ── score bar ────────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Text('Adherence risk score',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  Text('${f.scorePercent}/100',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: f.riskColor)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: f.forecastScore,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(f.riskColor),
                  ),
                ),

                // ── #1 Sparkline ─────────────────────────────────────────
                if (_history.length >= 2) ...[
                  const SizedBox(height: 16),
                  _buildSparkline(f.riskColor),
                ],

                // ── active signals ───────────────────────────────────────
                if (f.activeSignals.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(children: [
                      Text(
                        '${f.activeSignals.length} risk factor${f.activeSignals.length > 1 ? 's' : ''} detected',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700),
                      ),
                      const Spacer(),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    ]),
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 10),
                    ...f.activeSignals.map((s) => _buildSignalRow(s, f.riskColor)),
                  ],
                ],

                if (f.activeSignals.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text('No specific risk factors identified.',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500)),
                ],

                // ── timestamp ────────────────────────────────────────────
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.access_time_rounded,
                      size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Updated ${_timeAgo(f.createdAt)}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSignalRow(ActiveSignal signal, Color riskColor) {
    final tip = _tipForSignal(signal.signal);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: riskColor.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(signal.icon, size: 16, color: riskColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(signal.label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800)),
              const SizedBox(height: 2),
              Text(signal.detail,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.4)),
            ]),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
                color: riskColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text('${(signal.score * 100).round()}%',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: riskColor)),
          ),
        ]),
        // ── Tip ───────────────────────────────────────────────────────────
        if (tip.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: riskColor.withOpacity(0.15)),
            ),
            child: Text(tip,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    height: 1.4)),
          ),
        ],
      ]),
    );
  }

  Widget _buildLowRiskBadge() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_outline_rounded,
            color: Colors.green.shade600, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('AI health analysis: adherence looks good! Keep it up.',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500)),
            // Show trend badge even when low risk
            if (_history.length >= 2) ...[
              const SizedBox(height: 6),
              _buildTrendBadge(Colors.green.shade600),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildSkeleton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 120,
      decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20)),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPARKLINE PAINTER
// Draws a smooth filled area chart from a list of 0.0–1.0 score values.
// ─────────────────────────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color        color;
  final Color        bgColor;

  const _SparklinePainter({
    required this.points,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final n      = points.length;
    final maxVal = points.reduce(math.max).clamp(0.01, 1.0);
    final minVal = points.reduce(math.min);
    final range  = (maxVal - minVal).clamp(0.05, 1.0);

    // x positions
    double xOf(int i) => n == 1 ? size.width / 2 : i * size.width / (n - 1);

    // y position — inverted (higher score = higher on canvas = worse)
    double yOf(double v) =>
        size.height - ((v - minVal) / range) * size.height * 0.85 - size.height * 0.075;

    final linePath = Path();
    final fillPath = Path();

    linePath.moveTo(xOf(0), yOf(points[0]));
    fillPath.moveTo(xOf(0), size.height);
    fillPath.lineTo(xOf(0), yOf(points[0]));

    for (int i = 1; i < n; i++) {
      final x0 = xOf(i - 1);
      final y0 = yOf(points[i - 1]);
      final x1 = xOf(i);
      final y1 = yOf(points[i]);
      final cx = (x0 + x1) / 2;
      linePath.cubicTo(cx, y0, cx, y1, x1, y1);
      fillPath.cubicTo(cx, y0, cx, y1, x1, y1);
    }

    fillPath.lineTo(xOf(n - 1), size.height);
    fillPath.close();

    // filled area
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.fill,
    );

    // line
    canvas.drawPath(
      linePath,
      Paint()
        ..color       = color
        ..strokeWidth = 2.5
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round,
    );

    // dots at each data point
    for (int i = 0; i < n; i++) {
      canvas.drawCircle(
        Offset(xOf(i), yOf(points[i])),
        3.5,
        Paint()..color = color,
      );
      canvas.drawCircle(
        Offset(xOf(i), yOf(points[i])),
        2.0,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points != points || old.color != color;
}