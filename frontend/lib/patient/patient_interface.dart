import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/api_config.dart';
import 'condition_detail_page.dart';
import '../services/language_service.dart';
import '../services/condition_service.dart';
import '../services/location_service.dart';
import 'patient_caregivers_page.dart';
import '../services/background_location_service.dart';
import '../services/signal_service.dart';

class PatientInterface extends StatefulWidget {
  const PatientInterface({super.key});

  @override
  State<PatientInterface> createState() => _PatientInterfaceState();
}

class _PatientInterfaceState extends State<PatientInterface> {
  bool _isLoading                  = true;
  bool _isLoggingOut               = false;
  Map<String, dynamic>? _userData;
  String? _errorMessage;
  int _selectedIndex               = 0;
  int _unreadNotificationsCount    = 0;

  // adherence from history/stats
  int _weeklyAdherence             = 0;
  int _todayTaken                  = 0;
  int _todayTotal                  = 0;
  int _todayMissed                 = 0;

  List<Map<String, dynamic>> _patientConditions = [];
  bool _loadingConditions          = false;
  Map<String, dynamic>? _nextMedication;

  // location
  final LocationService _locationService                     = LocationService();
  final BackgroundLocationService _backgroundLocationService = BackgroundLocationService();
  bool _backgroundTrackingEnabled    = false;
  bool _hasAskedLocationPermission   = false;
  bool _hasAskedBackgroundPermission = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      _loadUserData(),
      _loadPatientConditions(),
      _loadAdherenceData(),
      _loadTodayStats(),
      _loadNextMedication(),
      _loadUnreadNotificationsCount(),
    ]).then((_) {
      _startLocationTracking();
      _setupBackgroundTracking();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUnreadNotificationsCount());
  }

  @override
  void dispose() {
    _locationService.stopLocationTracking();
    SignalService.instance.clearCache();
    super.dispose();
  }

  // ── greeting helpers ───────────────────────────────────────────────────────

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return '🌅 Good morning';
    if (h < 17) return '☀️ Good afternoon';
    if (h < 21) return '🌆 Good evening';
    return '🌙 Good night';
  }

  String _firstName() {
    final name = _userData?['name']?.toString() ?? '';
    return name.split(' ').first;
  }

  // ── condition helpers (same as conditions_list_page) ──────────────────────

  String _iconForCondition(String name) {
    final n = name.toLowerCase();
    if (n.contains('diabetes'))    return '🩸';
    if (n.contains('hypertension') || n.contains('heart failure')) return '❤️';
    if (n.contains('heart') || n.contains('cardio')) return '🫀';
    if (n.contains('asthma') || n.contains('copd') || n.contains('bronch')) return '🫁';
    if (n.contains('thyroid'))     return '🦋';
    if (n.contains('arthritis') || n.contains('arthrose')) return '🦵';
    if (n.contains('osteoporosis') || n.contains('bone')) return '🦴';
    if (n.contains('kidney') || n.contains('renal')) return '🫘';
    if (n.contains('alzheimer') || n.contains('parkinson')) return '🧠';
    if (n.contains('depression') || n.contains('anxiety')) return '🌧️';
    if (n.contains('insomnia')) return '🌙';
    if (n.contains('cholesterol')) return '🫀';
    if (n.contains('epilep')) return '⚡';
    if (n.contains('migraine')) return '🤕';
    if (n.contains('cancer')) return '🎗️';
    if (n.contains('glaucoma') || n.contains('cataract')) return '👁️';
    return '💊';
  }

  Color _bgColorForCondition(String name) {
    final n = name.toLowerCase();
    if (n.contains('diabetes'))    return const Color(0xFFFAEEDA);
    if (n.contains('hypertension') || n.contains('heart')) return const Color(0xFFE6F1FB);
    if (n.contains('asthma') || n.contains('copd')) return const Color(0xFFEAF3DE);
    if (n.contains('thyroid'))     return const Color(0xFFEEEDFE);
    if (n.contains('arthritis') || n.contains('osteo')) return const Color(0xFFF1EFE8);
    if (n.contains('kidney'))      return const Color(0xFFE1F5EE);
    if (n.contains('cancer'))      return const Color(0xFFFCEBEB);
    return const Color(0xFFEEEDFE);
  }

  Color _adherenceColor(int pct) {
    if (pct >= 80) return const Color(0xFF639922);
    if (pct >= 50) return const Color(0xFFBA7517);
    return const Color(0xFFE24B4A);
  }

  String _translateConditionName(String name, LanguageService lang) {
    // Keep this for condition names that might come from backend as English keys
    // but we'll still use hardcoded English names for UI.
    switch (name) {
      case 'Diabetes Type 1':  return 'Type 1 Diabetes';
      case 'Diabetes Type 2':  return 'Type 2 Diabetes';
      case 'Hypertension':     return 'Hypertension';
      case 'Asthma':           return 'Asthma';
      case 'Heart Disease':    return 'Heart Disease';
      case 'High Cholesterol': return 'High Cholesterol';
      case 'COPD':             return 'COPD';
      case 'Arthritis':        return 'Arthritis';
      case 'Thyroid Disorder': return 'Thyroid Disorder';
      default: return name;
    }
  }

  Color _getColorForCondition(String name) {
    if (name.isEmpty) return Colors.blue;
    const colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.teal];
    return colors[name.hashCode.abs() % colors.length];
  }

  // ── data loading ───────────────────────────────────────────────────────────

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) { _redirectToSignIn(); return; }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/auth/me'),
        headers: ApiConfig.getAuthHeaders(token),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) setState(() { _userData = data['user']; _isLoading = false; });
        await prefs.setString('user_name', data['user']['name']?.toString() ?? '');
        await prefs.setInt('user_id', data['user']['id'] as int? ?? 0);
      } else {
        await prefs.remove('auth_token');
        _redirectToSignIn();
      }
    } catch (e) {
      if (mounted) setState(() { _errorMessage = 'Cannot load data. Check your connection.'; _isLoading = false; });
    }
  }

  Future<void> _loadAdherenceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/history/stats?days=7'),
        headers: ApiConfig.getAuthHeaders(token),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final stats = data['data'];
        if (mounted) {
          setState(() {
            _weeklyAdherence = double.tryParse(stats?['adherence_rate']?.toString() ?? '0')?.round() ?? 0;
          });
        }
      }
    } catch (e) { debugPrint('adherence error: $e'); }
  }

  Future<void> _loadTodayStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/treatments/schedule?date=$today'),
        headers: ApiConfig.getAuthHeaders(token),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (mounted) {
          setState(() {
            _todayTotal  = int.tryParse(data['stats']?['total']?.toString() ?? '0') ?? 0;
            _todayTaken  = int.tryParse(data['stats']?['completed']?.toString() ?? '0') ?? 0;
            _todayMissed = int.tryParse(data['stats']?['missed']?.toString() ?? '0') ?? 0;
          });
        }
      }
    } catch (e) { debugPrint('today stats error: $e'); }
  }

  Future<void> _loadNextMedication() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/treatments/next-medication'),
        headers: ApiConfig.getAuthHeaders(token),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (mounted) setState(() => _nextMedication = data['success'] == true ? data['medication'] : null);
      }
    } catch (e) { debugPrint('next med error: $e'); }
  }

  Future<void> _loadUnreadNotificationsCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications/unread'),
        headers: ApiConfig.getAuthHeaders(token),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (mounted) setState(() => _unreadNotificationsCount = data['data']['count'] ?? 0);
        debugPrint('🔔 Unread notifications: $_unreadNotificationsCount');
      }
    } catch (e) { debugPrint('unread error: $e'); }
  }

  Future<void> _loadPatientConditions() async {
    setState(() => _loadingConditions = true);
    try {
      final conditions = await ConditionService.getPatientConditions();
      if (mounted) {
        setState(() {
          _patientConditions = conditions.map<Map<String, dynamic>>((c) {
            final name = c['name']?.toString() ?? 'Unknown';
            return {
              'id':         c['id'] ?? 0,
              'name':       name,
              'percentage': int.tryParse(c['adherence_rate']?.toString() ?? '0') ?? 0,
              'color':      _getColorForCondition(name),
            };
          }).toList();
          _loadingConditions = false;
        });
      }
    } catch (e) {
      debugPrint('conditions error: $e');
      if (mounted) setState(() => _loadingConditions = false);
    }
  }

  // ── mark taken / snooze (actually calls backend) ──────────────────────────

  Future<void> _markTaken(int scheduleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final resp = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/schedule/take/$scheduleId'),
        headers: ApiConfig.getAuthHeaders(token),
      );

      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Medication marked as taken!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        _loadNextMedication();
        _loadTodayStats();
      }
    } catch (e) { debugPrint('markTaken error: $e'); }
  }

  Future<void> _snoozeNext(int scheduleId, int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/notifications/snooze/$scheduleId'),
        headers: ApiConfig.getAuthHeaders(token),
        body: jsonEncode({'minutes': minutes}),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('😴 Snoozed for $minutes minutes'),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) { debugPrint('snooze error: $e'); }
  }

  // ── location ───────────────────────────────────────────────────────────────

  Future<void> _startLocationTracking() async {
    if (kIsWeb || _hasAskedLocationPermission) return;
    _hasAskedLocationPermission = true;

    final prefs     = await SharedPreferences.getInstance();
    int? patientId  = prefs.getInt('user_id') ?? (_userData?['id'] as int?);
    if (patientId == null) return;

    final optedOut  = prefs.getBool('location_sharing_opted_out') ?? false;
    if (!optedOut) {
      await _locationService.startLocationTracking(patientId);
    }
  }

  Future<void> _setupBackgroundTracking() async {
    if (kIsWeb) return;
    final prefs    = await SharedPreferences.getInstance();
    int? patientId = prefs.getInt('user_id') ?? (_userData?['id'] as int?);
    final token    = prefs.getString('auth_token');
    if (patientId == null || _userData == null || token == null) return;
    final agreed   = prefs.getBool('background_tracking_agreed') ?? false;
    if (!agreed && !_hasAskedBackgroundPermission) {
      _hasAskedBackgroundPermission = true;
      final ok = await _askForBackgroundTrackingPermission();
      if (ok) {
        final started = await _backgroundLocationService.startTracking(patientId, token);
        if (mounted) setState(() => _backgroundTrackingEnabled = started);
        await prefs.setBool('background_tracking_agreed', true);
      }
    } else if (agreed) {
      await _backgroundLocationService.restoreTrackingIfNeeded();
      final isTracking = await _backgroundLocationService.isTracking();
      if (mounted) setState(() => _backgroundTrackingEnabled = isTracking);
    }
  }

  Future<bool> _askForLocationPermission() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.location_on, color: Colors.blue, size: 24), SizedBox(width: 8),
          Flexible(child: Text('24/7 Location Sharing', style: TextStyle(fontSize: 16))),
        ]),
        content: const Text(
          'Your caregiver can track your location to ensure your safety. '
          'You can turn this off anytime in settings.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not Now')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _askForBackgroundTrackingPermission() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.location_on, color: Colors.blue, size: 28), SizedBox(width: 8),
          Flexible(child: Text('24/7 Location Sharing')),
        ]),
        content: const Text(
          'To ensure your safety, MediCare can share your location with your caregiver '
          'even when the app is closed.\n\n'
          '• Works in the background\n• Uses minimal battery\n• Can be turned off anytime',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not Now')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _redirectToSignIn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pushReplacementNamed(context, '/signin');
    });
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      _locationService.stopLocationTracking(); // stop foreground only
      final prefs     = await SharedPreferences.getInstance();
      final token     = prefs.getString('auth_token');

      // Background tracking uses its own dedicated credential keys (separate
      // from the login session) so it can keep running after logout — preserve
      // them across the prefs wipe below.
      final bgTracking  = prefs.getBool('background_tracking_active') ?? false;
      final bgToken     = prefs.getString('bg_auth_token');
      final bgPatientId = prefs.getInt('bg_patient_id');

      if (token != null) {
        await http.post(
          Uri.parse('${ApiConfig.baseUrl}/auth/logout'),
          headers: ApiConfig.getAuthHeaders(token),
        ).timeout(const Duration(seconds: 10));
      }
      await prefs.clear();
      if (bgTracking && bgToken != null && bgPatientId != null) {
        await prefs.setBool('background_tracking_active', true);
        await prefs.setString('bg_auth_token', bgToken);
        await prefs.setInt('bg_patient_id', bgPatientId);
      }
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/signin');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('👋 Logged out successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error logging out'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Language service is kept only for condition name translation; UI text is hardcoded.
    final lang = Provider.of<LanguageService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: _buildAppBar(),
      drawer: _buildDrawer(context, lang),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: () async {
                    await Future.wait([
                      _loadUserData(),
                      _loadPatientConditions(),
                      _loadAdherenceData(),
                      _loadTodayStats(),
                      _loadNextMedication(),
                      _loadUnreadNotificationsCount(),
                    ]);
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildGreetingCard(),
                      const SizedBox(height: 16),
                      _buildTodaySummaryCard(),
                      const SizedBox(height: 16),
                      _buildWeeklyAdherenceCard(),
                      const SizedBox(height: 20),
                      if (_nextMedication != null) ...[
                        _buildNextMedicationCard(lang),
                        const SizedBox(height: 20),
                      ],
                      if (_patientConditions.isNotEmpty) ...[
                        _buildConditionsSection(lang),
                        const SizedBox(height: 20),
                      ],
                      _buildQuickActionsGrid(),
                    ]),
                  ),
                ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── APP BAR ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Builder(builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu, color: Colors.black54),
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      )),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
          child: const Icon(Icons.favorite, color: Colors.blue, size: 18),
        ),
        const SizedBox(width: 8),
        const Text('MediCare', style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 18)),
      ]),
      actions: [
        Stack(children: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.blue, size: 26),
            onPressed: () => Navigator.pushNamed(context, '/notifications').then((_) => _loadUnreadNotificationsCount()),
          ),
          if (_unreadNotificationsCount > 0)
            Positioned(
              right: 8, top: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  _unreadNotificationsCount > 9 ? '9+' : '$_unreadNotificationsCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ]),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── GREETING CARD ──────────────────────────────────────────────────────────

  Widget _buildGreetingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting(), style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
          const SizedBox(height: 4),
          Text(_firstName().isNotEmpty ? _firstName() : 'Patient',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _isLoading
                ? 'Loading your schedule...'
                : _todayTotal > 0
                    ? '$_todayTaken of $_todayTotal medications taken today'
                    : 'No medications scheduled today',
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
          ),
        ])),
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
          child: Center(child: Text(
            _todayTotal > 0 ? '${((_todayTaken / _todayTotal) * 100).round()}%' : '—',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          )),
        ),
      ]),
    );
  }

  // ── TODAY SUMMARY ──────────────────────────────────────────────────────────

  Widget _buildTodaySummaryCard() {
    final pct   = _todayTotal > 0 ? (_todayTaken / _todayTotal) : 0.0;
    final color = _adherenceColor(_todayTotal > 0 ? (pct * 100).round() : 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.today_outlined, size: 18, color: Color(0xFF1A237E)),
          const SizedBox(width: 8),
          const Text("Today's progress", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const Spacer(),
          Text('$_todayTaken/$_todayTotal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _summaryChip(Icons.check_circle_outline, '$_todayTaken', 'Taken', const Color(0xFF639922), const Color(0xFFEAF3DE)),
          const SizedBox(width: 8),
          _summaryChip(Icons.cancel_outlined, '$_todayMissed', 'Missed', const Color(0xFFE24B4A), const Color(0xFFFCEBEB)),
          const SizedBox(width: 8),
          _summaryChip(Icons.access_time, '${_todayTotal - _todayTaken - _todayMissed}', 'Remaining', const Color(0xFFBA7517), const Color(0xFFFAEEDA)),
        ]),
      ]),
    );
  }

  Widget _summaryChip(IconData icon, String value, String label, Color color, Color bg) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text('$value $label', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis)),
      ]),
    ));
  }

  // ── WEEKLY ADHERENCE ───────────────────────────────────────────────────────

  Widget _buildWeeklyAdherenceCard() {
    final color = _adherenceColor(_weeklyAdherence);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Overall Adherence',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 2),
          const Text('Last 7 days', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _weeklyAdherence / 100,
              minHeight: 7,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ])),
        const SizedBox(width: 16),
        Column(children: [
          Text('$_weeklyAdherence%',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          Text(
            _weeklyAdherence >= 80 ? 'Excellent' : _weeklyAdherence >= 50 ? 'Fair' : 'Low',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ]),
      ]),
    );
  }

  // ── NEXT MEDICATION ────────────────────────────────────────────────────────

  Widget _buildNextMedicationCard(LanguageService lang) {
    final med      = _nextMedication!;
    final name     = med['name']?.toString() ?? 'Medication';
    final cond     = med['condition']?.toString() ?? '';
    final time     = med['time']?.toString() ?? '--:--';
    final dose     = med['dosage']?.toString() ?? '';
    final priority = med['priority']?.toString() ?? '';
    final meal     = med['meal_timing']?.toString() ?? '';

    // countdown
    String countdown = '';
    try {
      final parts   = time.split(':');
      final now     = DateTime.now();
      final scheduled = DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));
      final diff = scheduled.difference(now);
      if (diff.isNegative) {
        countdown = 'Overdue';
      } else if (diff.inMinutes < 60) {
        countdown = 'in ${diff.inMinutes} min';
      } else {
        final h = diff.inHours;
        final m = diff.inMinutes % 60;
        countdown = m > 0 ? 'in ${h}h ${m}m' : 'in ${h}h';
      }
    } catch (_) {}

    final isUrgent  = countdown == 'Overdue' ||
        (countdown.contains('min') && int.tryParse(countdown.split(' ')[1]) != null
            && int.parse(countdown.split(' ')[1]) <= 30);
    final cardColor = isUrgent
        ? const LinearGradient(colors: [Color(0xFFB91C1C), Color(0xFFDC2626)],
            begin: Alignment.topLeft, end: Alignment.bottomRight)
        : const LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
            begin: Alignment.topLeft, end: Alignment.bottomRight);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.alarm_outlined, size: 18, color: Color(0xFF1A237E)),
        const SizedBox(width: 8),
        const Text('Next Medication',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E))),
        const Spacer(),
        if (countdown.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isUrgent ? const Color(0xFFFEE2E2) : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(countdown, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold,
              color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF1565C0),
            )),
          ),
      ]),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: () => _showMedicationDetail(context, lang, med),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
              color: (isUrgent ? Colors.red : Colors.blue).withOpacity(0.3),
              blurRadius: 14, offset: const Offset(0, 6),
            )],
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 20,
                  fontWeight: FontWeight.bold, color: Colors.white)),
              if (dose.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(dose, style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 14)),
              ],
              if (cond.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(_translateConditionName(cond, lang), style: TextStyle(
                    color: Colors.white.withOpacity(0.7), fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(time, style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (priority == 'HIGH') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('⚠️ HIGH', style: TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ])),
            Column(children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.medication_outlined, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 8),
              const Text('Tap for\ndetails', style: TextStyle(
                  color: Colors.white, fontSize: 10,
                  height: 1.4), textAlign: TextAlign.center),
            ]),
          ]),
        ),
      ),
    ]);
  }

  void _showMedicationDetail(BuildContext context, LanguageService lang,
      Map<String, dynamic> med) {
    final name     = med['name']?.toString() ?? 'Medication';
    final dose     = med['dosage']?.toString() ?? '';
    final cond     = med['condition']?.toString() ?? '';
    final time     = med['time']?.toString() ?? '--:--';
    final priority = med['priority']?.toString() ?? '';
    final meal     = med['meal_timing']?.toString() ?? '';

    // recompute countdown inside sheet
    String countdown = '';
    try {
      final parts     = time.split(':');
      final now       = DateTime.now();
      final scheduled = DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]));
      final diff = scheduled.difference(now);
      if (diff.isNegative) {
        countdown = 'Overdue';
      } else if (diff.inMinutes < 60) {
        countdown = '${diff.inMinutes} minutes';
      } else {
        final h = diff.inHours;
        final m = diff.inMinutes % 60;
        countdown = m > 0 ? '${h}h ${m}m' : '${h} hours';
      }
    } catch (_) {}

    String mealLabel = '';
    if (meal == 'BEFORE_MEAL') mealLabel = '🍽️ Take before meal';
    else if (meal == 'AFTER_MEAL') mealLabel = '🍽️ Take after meal';
    else if (meal == 'WITH_MEAL') mealLabel = '🍽️ Take with meal';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 8, 24,
            MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // handle
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 20),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),

          // icon + name
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.medication_outlined,
                  color: Color(0xFF1565C0), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(name, style: const TextStyle(fontSize: 20,
                  fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              if (dose.isNotEmpty)
                Text(dose, style: TextStyle(fontSize: 14,
                    color: Colors.grey.shade500)),
            ])),
            if (priority == 'HIGH')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('⚠️ HIGH', style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626))),
              ),
          ]),
          const SizedBox(height: 24),

          // info tiles
          Row(children: [
            _infoTile(Icons.access_time_rounded, 'Scheduled', time,
                const Color(0xFF1565C0), const Color(0xFFE3F2FD)),
            const SizedBox(width: 10),
            _infoTile(Icons.hourglass_top_rounded, 'Time left', countdown,
                const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
          ]),
          if (cond.isNotEmpty || mealLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (cond.isNotEmpty)
                Expanded(child: _infoTile(Icons.medical_information_outlined,
                    'Condition', _translateConditionName(cond, lang),
                    const Color(0xFF7C3AED), const Color(0xFFF5F3FF))),
              if (cond.isNotEmpty && mealLabel.isNotEmpty)
                const SizedBox(width: 10),
              if (mealLabel.isNotEmpty)
                Expanded(child: _infoTile(Icons.restaurant_outlined,
                    'Meal timing', mealLabel,
                    const Color(0xFFD97706), const Color(0xFFFEF3C7))),
            ]),
          ],
          const SizedBox(height: 28),

          // reminder note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF16A34A), size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'You will receive a notification when it\'s time to take this medication.',
                style: TextStyle(fontSize: 13, color: Color(0xFF16A34A), height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 20),

          // Go to Planning button
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/planning');
              },
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: const Text('View Full Schedule',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // dismiss
          SizedBox(
            width: double.infinity, height: 48,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss',
                  style: TextStyle(fontSize: 15, color: Colors.grey)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value,
      Color color, Color bg) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7),
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
            color: color), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    ));
  }

  // ── CONDITIONS ─────────────────────────────────────────────────────────────

  Widget _buildConditionsSection(LanguageService lang) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.medical_information_outlined, size: 18, color: Color(0xFF1A237E)),
        const SizedBox(width: 8),
        const Text('Your Conditions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/conditions'),
          child: const Text('View All', style: TextStyle(color: Colors.blue, fontSize: 13)),
        ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 150,
        child: _loadingConditions
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _patientConditions.length,
                itemBuilder: (_, i) => _buildConditionCard(_patientConditions[i], lang),
              ),
      ),
    ]);
  }

  Widget _buildConditionCard(Map<String, dynamic> condition, LanguageService lang) {
    final name  = condition['name']?.toString() ?? 'Unknown';
    final pct   = int.tryParse(condition['percentage']?.toString() ?? '0') ?? 0;
    final icon  = _iconForCondition(name);
    final bg    = _bgColorForCondition(name);
    final color = _adherenceColor(pct);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ConditionDetailPage(condition: condition),
      )),
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
          ),
          const Spacer(),
          Text(_translateConditionName(name, lang),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Text('$pct%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const Spacer(),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
          ]),
        ]),
      ),
    );
  }

  // ── QUICK ACTIONS ──────────────────────────────────────────────────────────

  Widget _buildQuickActionsGrid() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.grid_view_outlined, size: 18, color: Color(0xFF1A237E)),
        const SizedBox(width: 8),
        const Text('Quick Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _quickCard('My Planning', Icons.calendar_month_outlined, Colors.blue,
            () => Navigator.pushNamed(context, '/planning'))),
        const SizedBox(width: 12),
        Expanded(child: _quickCard('Notifications', Icons.notifications_outlined, Colors.purple,
            () => Navigator.pushNamed(context, '/notifications').then((_) => _loadUnreadNotificationsCount()),
            badge: _unreadNotificationsCount)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _quickCard('History', Icons.history_outlined, Colors.teal,
            () => Navigator.pushNamed(context, '/history'))),
        const SizedBox(width: 12),
        Expanded(child: _quickCard('Health Overview', Icons.favorite_border_outlined, Colors.orange,
            () => Navigator.pushNamed(context, '/healthoverview'))),
      ]),
    ]);
  }

  Widget _quickCard(String title, IconData icon, Color color, VoidCallback onTap, {int badge = 0}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Stack(children: [
              Center(child: Icon(icon, color: color, size: 20)),
              if (badge > 0)
                Positioned(
                  right: 4, top: 4,
                  child: Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  // ── BOTTOM NAV ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (i) {
        if (i == 0) setState(() => _selectedIndex = 0);
        else if (i == 1) Navigator.pushNamed(context, '/conditions');
        else if (i == 2) Navigator.pushNamed(context, '/history');
        else if (i == 3) Navigator.pushNamed(context, '/healthoverview');
      },
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: Colors.blue,
      unselectedItemColor: Colors.grey,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      elevation: 20,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Conditions'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Health'),
      ],
    );
  }

  // ── ERROR VIEW ─────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.cloud_off_rounded, size: 80, color: Colors.grey),
        const SizedBox(height: 24),
        Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _loadUserData,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
          child: const Text('Retry'),
        ),
      ]),
    ));
  }

  // ── DRAWER ─────────────────────────────────────────────────────────────────

  Widget _buildDrawer(BuildContext context, LanguageService lang) {
    return Drawer(
      child: Column(children: [
        _buildDrawerHeader(),
        Expanded(child: ListView(padding: EdgeInsets.zero, children: [
          _drawerItem(Icons.home_outlined, 'Dashboard', _selectedIndex == 0, () {
            Navigator.pop(context); setState(() => _selectedIndex = 0);
          }),
          _drawerItem(Icons.timeline, 'Conditions', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/conditions');
          }),
          _drawerItem(Icons.access_time, 'My Planning', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/planning');
          }),
          _drawerItemBadge(Icons.notifications_none, 'Notifications', false, _unreadNotificationsCount, () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/notifications').then((_) => _loadUnreadNotificationsCount());
          }),
          _drawerItem(Icons.favorite_border, 'Health Overview', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/healthoverview');
          }),
          const Divider(indent: 20, endIndent: 20, height: 32),
          _drawerItem(Icons.chat_bubble_outline, 'AI Health Assistant', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/ai-chatbot');
          }),
          _drawerItem(Icons.people_outline_rounded, 'Caregivers', false, () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => const PatientCaregiversPage()));
          }),
          _drawerItem(Icons.menu_book_outlined, 'Medication Dictionary', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/med-dictionary');
          }),
          _drawerItem(Icons.workspace_premium_outlined, 'Rewards & Achievements', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/rewards');
          }),
          const Divider(indent: 20, endIndent: 20, height: 32),
          _drawerItem(Icons.history_outlined, 'History', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/history');
          }),
          _drawerItem(Icons.person_outline, 'Profile', false, () async {
            Navigator.pop(context);
            await Navigator.pushNamed(context, '/profile');
            // Reload user data after returning from profile (name may have changed)
            await _loadUserData();
            // Also reload other data to stay consistent
            _loadPatientConditions();
            _loadAdherenceData();
            _loadTodayStats();
            _loadNextMedication();
            _loadUnreadNotificationsCount();
          }),
          _drawerItem(Icons.settings_outlined, 'Settings', false, () {
            Navigator.pop(context); Navigator.pushNamed(context, '/settings');
          }),
          const Divider(indent: 20, endIndent: 20, height: 32),
        ])),
        _buildLogoutItem(),
      ]),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 40, bottom: 24, left: 20, right: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 26),
            onPressed: () => Navigator.pop(context),
          )),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.favorite, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MediCare', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(_userData?['name']?.toString() ?? 'Patient',
                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
          ]),
        ]),
      ]),
    );
  }

  Widget _drawerItem(IconData icon, String title, bool selected, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: selected ? Colors.blue : Colors.grey.shade600, size: 22),
      title: Text(title, style: TextStyle(
        color: selected ? Colors.blue : const Color(0xFF1A237E),
        fontSize: 15, fontWeight: selected ? FontWeight.bold : FontWeight.w500,
      )),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  Widget _drawerItemBadge(IconData icon, String title, bool selected, int badge, VoidCallback onTap) {
    return ListTile(
      leading: Stack(children: [
        Icon(icon, color: selected ? Colors.blue : Colors.grey.shade600, size: 22),
        if (badge > 0)
          Positioned(right: 0, top: 0,
            child: Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle))),
      ]),
      title: Row(children: [
        Text(title, style: TextStyle(
          color: selected ? Colors.blue : const Color(0xFF1A237E),
          fontSize: 15, fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        )),
        if (badge > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
            child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ]),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  Widget _buildLogoutItem() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: ListTile(
        leading: _isLoggingOut
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
            : const Icon(Icons.logout, color: Colors.red, size: 22),
        title: const Text('Logout',
            style: TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold)),
        onTap: _isLoggingOut ? null : _logout,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}