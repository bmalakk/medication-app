import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/settings_service.dart';
import '../services/background_location_service.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'about_medicare_page.dart';
import '../services/location_service.dart';
import '../config/api_config.dart';
import 'accessibility_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _backgroundTracking = false;

  @override
  void initState() {
    super.initState();
    _loadBackgroundStatus();
  }

  Future<void> _loadBackgroundStatus() async {
    final isEnabled = await BackgroundLocationService().isTracking();
    if (mounted) setState(() => _backgroundTracking = isEnabled);
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
  ////////export pdf method 
Future<void> _exportPdf() async {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Row(children: [
      SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
      SizedBox(width: 12),
      Text('Generating your PDF report...'),
    ]),
    backgroundColor: Colors.blue,
    duration: Duration(seconds: 30),
    behavior: SnackBarBehavior.floating,
  ));

  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/history/export-pdf?months=3'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/pdf',
      },
    ).timeout(const Duration(seconds: 30));

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (response.statusCode == 200) {
      // Save directly to Downloads folder
      final fileName = 'medication-report-${DateTime.now().toIso8601String().split('T')[0]}.pdf';
      final filePath = '/storage/emulated/0/Download/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      // Open the PDF immediately with the device's PDF reader
      final result = await OpenFile.open(filePath);
      debugPrint('OpenFile result: ${result.message}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Report saved to Downloads: $fileName'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OPEN',
            textColor: Colors.white,
            onPressed: () => OpenFile.open(filePath),
          ),
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Failed to generate report'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  } catch (e) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Error: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings  = Provider.of<SettingsService>(context);
    final isDark    = false;
    final textColor = isDark ? Colors.white : const Color(0xFF1A237E);
    final subColor  = isDark ? Colors.white70 : Colors.grey.shade600;
    final bg        = isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FC);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(settings.translate('settings'),
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // subtitle
          Text('Customize your app experience',
              style: TextStyle(fontSize: 13, color: subColor)),
          const SizedBox(height: 24),

          // ── NOTIFICATIONS ───────────────────────────────────────────────
          _section('Notifications', Icons.notifications_outlined, Colors.blue, isDark),
          _card(isDark, [
            _switchTile(
              icon: Icons.notifications_active_outlined, iconColor: Colors.blue,
              title: 'All Notifications', subtitle: 'Master toggle for all alerts',
              value: settings.allNotifications,
              onChanged: (v) => settings.setAllNotifications(v),
              isDark: isDark,
            ),
            _divider(isDark),
            _switchTile(
              icon: Icons.medication_outlined, iconColor: Colors.blue,
              title: 'Medication Reminders', subtitle: 'Get reminded to take your medications',
              value: settings.medReminders,
              onChanged: settings.allNotifications ? (v) => settings.setMedReminders(v) : null,
              isDark: isDark,
            ),
            _divider(isDark),
            _switchTile(
              icon: Icons.crisis_alert_outlined, iconColor: Colors.red,
              title: 'Critical Alerts', subtitle: 'HIGH priority alerts bypass quiet hours',
              value: settings.criticalAlertsEnabled,
              onChanged: settings.allNotifications ? (v) => settings.setCriticalAlertsEnabled(v) : null,
              isDark: isDark,
            ),
            _divider(isDark),
            _switchTile(
              icon: Icons.trending_up_outlined, iconColor: Colors.blue,
              title: 'Adherence Alerts', subtitle: 'Track your daily progress',
              value: settings.adherenceAlerts,
              onChanged: settings.allNotifications ? (v) => settings.setAdherenceAlerts(v) : null,
              isDark: isDark,
            ),
            _divider(isDark),
            _switchTile(
              icon: Icons.psychology_outlined, iconColor: Colors.blue,
              title: 'Smart Insights', subtitle: 'AI-powered health recommendations',
              value: settings.smartInsights,
              onChanged: settings.allNotifications ? (v) => settings.setSmartInsights(v) : null,
              isDark: isDark,
            ),
            _divider(isDark),
            _navTile(
              icon: Icons.bedtime_outlined, iconColor: Colors.indigo,
              title: 'Quiet Hours',
              badge: '${settings.quietHoursStart} – ${settings.quietHoursEnd}',
              badgeColor: Colors.indigo,
              onTap: () => Navigator.pushNamed(context, '/quiet-hours'),
              isDark: isDark,
            ),
          ]),
          const SizedBox(height: 20),

// ── MEDICATION ──────────────────────────────────────────────────
          _section('Medication', Icons.medication_outlined, Colors.purple, isDark),
          _card(isDark, [

            _switchTile(
              icon: Icons.autorenew_outlined, iconColor: Colors.purple,
              title: 'Auto Refill Reminders',
              subtitle: 'Get notified before a treatment runs out, so you can refill in time',
              value: settings.autoRefillReminders,
              onChanged: (v) => settings.setAutoRefillReminders(v),
              isDark: isDark,
            ),
            _divider(isDark),
            _navTile(
              icon: Icons.schedule_outlined, iconColor: Colors.purple,
              title: 'Daily Schedule',
              subtitle: 'Sleep, wake & meal times',
              onTap: () => Navigator.pushNamed(context, '/daily-schedule'),
              isDark: isDark,
            ),
            _divider(isDark),
            _navTile(
              icon: Icons.file_download_outlined, iconColor: Colors.purple,
              title: 'Export Data',
              subtitle: 'Download your medication history',
              onTap: _exportPdf,
              isDark: isDark,
              showChevron:true
            ),
          ]),
          const SizedBox(height: 20),

          // ── FAMILY & CARE ───────────────────────────────────────────────
         _section('Family & Care', Icons.people_outline, Colors.teal, isDark),
          _card(isDark, [
            _switchTile(
              icon: Icons.location_on_outlined, iconColor: Colors.teal,
              title: '24/7 Location Sharing',
              subtitle: 'Share location with caregiver even when app is closed',
              value: _backgroundTracking,
              onChanged: (v) => _toggleBackgroundTracking(v),
              isDark: isDark,
            ),
          ]),
          const SizedBox(height: 20),
          // ── ACCESSIBILITY ───────────────────────────────────────────────
_section('Accessibility', Icons.accessibility_new_outlined, Colors.orange, isDark),
_card(isDark, [
  _navTile(
    icon: Icons.auto_awesome_outlined,
    iconColor: Colors.orange,
    title: 'Easy Read Mode',
    subtitle: 'Icons, audio, clear text',
    onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AccessibilitySettingsPage())),
    isDark: isDark,
    showChevron: true,
  ),
]),
const SizedBox(height: 20),

          // ── SUPPORT ─────────────────────────────────────────────────────
       _section('Support & Legal', Icons.help_outline, Colors.grey, isDark),
          _card(isDark, [
            _navTile(
              icon: Icons.info_outline, iconColor: Colors.grey,
              title: 'About MediCare',
              badge: 'v1.0.0',
              badgeColor: Colors.grey,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AboutMediCarePage())),
              isDark: isDark, showChevron: true,
            ),
          ]),
          const SizedBox(height: 32),

          // ── DANGER ZONE ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.red.withOpacity(0.08) : Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.red.shade100, shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              ),
              title: const Text('Delete Account',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('Permanently delete your account and all data',
                  style: TextStyle(color: Colors.red, fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, color: Colors.red, size: 18),
              onTap: () => _confirmDeleteAccount(settings),
            ),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  Widget _section(String title, IconData icon, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : const Color(0xFF1A237E),
        )),
      ]),
    );
  }

  Widget _card(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(bool isDark) {
    return Divider(
      height: 1, indent: 56, endIndent: 16,
      color: isDark ? Colors.white12 : Colors.grey.shade100,
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required bool isDark,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: onChanged != null ? iconColor.withOpacity(0.1) : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
          color: onChanged != null ? iconColor : Colors.grey.shade400,
          size: 18),
      ),
      title: Text(title, style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600,
        color: onChanged != null
            ? (isDark ? Colors.white : const Color(0xFF1A237E))
            : Colors.grey.shade400,
      )),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(
              fontSize: 11,
              color: onChanged != null
                  ? (isDark ? Colors.white54 : Colors.grey.shade500)
                  : Colors.grey.shade300))
          : null,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: iconColor,
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    String? badge,
    Color? badgeColor,
    required VoidCallback onTap,
    required bool isDark,
    bool showChevron = true,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : const Color(0xFF1A237E),
      )),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade500))
          : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (badgeColor ?? Colors.grey).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: badgeColor ?? Colors.grey,
            )),
          ),
        if (showChevron) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
        ],
      ]),
      onTap: onTap,
    );
  }

  // ── BACKGROUND TRACKING ────────────────────────────────────────────────────

Future<void> _toggleBackgroundTracking(bool value) async {
  final prefs     = await SharedPreferences.getInstance();
  final patientId = prefs.getInt('user_id') ?? prefs.getInt('patient_id');
  final token     = prefs.getString('auth_token');
  if (value && patientId != null && token != null) {
    await prefs.setBool('location_sharing_opted_out', false);
    final started = await BackgroundLocationService().startTracking(patientId, token);
    if (mounted) {
      setState(() => _backgroundTracking = started);
      _snack(started ? '✅ 24/7 location sharing enabled' : '❌ Failed to enable', 
             started ? Colors.green : Colors.red);
    }
  } else {
    await prefs.setBool('location_sharing_opted_out', true);
    await BackgroundLocationService().stopTracking();
    LocationService().stopLocationTracking();
    if (mounted) {
      setState(() => _backgroundTracking = false);
      _snack('🛑 24/7 location sharing disabled', Colors.orange);
    }
  }
}

  // ── DELETE ACCOUNT ─────────────────────────────────────────────────────────

  Future<void> _confirmDeleteAccount(SettingsService settings) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Delete Account', style: TextStyle(color: Colors.red, fontSize: 18)),
        ]),
        content: const Text(
          'Are you sure you want to permanently delete your account?\n\n'
          'All your medication history, conditions, and data will be lost. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await settings.deleteAccount();
      if (success && mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/signin', (route) => false);
      }
    }
  }

  // ── LANGUAGE DIALOG ────────────────────────────────────────────────────────

  Future<void> _showLanguageDialog(BuildContext context, SettingsService settings) async {
    final current = settings.getCurrentLanguage();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: settings.isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(settings.translate('language'),
            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioListTile<String>(
            value: 'en',
            groupValue: current,
            title: Text('🇬🇧  English',
                style: TextStyle(color: settings.isDarkMode ? Colors.white : Colors.black)),
            onChanged: (v) { Navigator.pop(context); settings.setLanguage('en'); },
          ),
          RadioListTile<String>(
            value: 'fr',
            groupValue: current,
            title: Text('🇫🇷  Français',
                style: TextStyle(color: settings.isDarkMode ? Colors.white : Colors.black)),
            onChanged: (v) { Navigator.pop(context); settings.setLanguage('fr'); },
          ),
        ]),
      ),
    );
  }
}