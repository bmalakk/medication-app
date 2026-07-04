import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL background entry point — MUST be top-level, not inside a class
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // On Android set as foreground with a persistent notification
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  // Listen for stop command
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // Show notification channel for Android
  final notifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifications.initialize(const InitializationSettings(
    android: androidSettings,
  ));

  // Update location every 5 minutes
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Update the foreground notification text
        service.setForegroundNotificationInfo(
          title: 'MediCare',
          content: 'Location sharing is active',
        );
      }
    }

    await _sendLocationUpdate();

    // Notify Flutter side that we ran
    service.invoke('update', {'timestamp': DateTime.now().toIso8601String()});
  });
}

/// Sends current GPS position to backend — called from background isolate
Future<void> _sendLocationUpdate() async {
  try {
    final prefs     = await SharedPreferences.getInstance();
    // Uses its own credential keys (set in startTracking), kept separate from
    // the login session so tracking survives logout.
    final token     = prefs.getString('bg_auth_token');
    final patientId = prefs.getInt('bg_patient_id');


    if (token == null || patientId == null) return;

    // Check permission inside background isolate
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    ).timeout(const Duration(seconds: 20));

    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/location/update'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'patient_id': patientId,
        'lat':        position.latitude,
        'lng':        position.longitude,
        'accuracy':   position.accuracy,
        'address':    '',
      }),
    ).timeout(const Duration(seconds: 15));

    print('[BGLocation] ✅ Location updated: ${position.latitude}, ${position.longitude}');
  } catch (e) {
    print('[BGLocation] ❌ Error: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundLocationService — public API used by the app
// ─────────────────────────────────────────────────────────────────────────────
class BackgroundLocationService {
  static final BackgroundLocationService _instance =
      BackgroundLocationService._internal();
  factory BackgroundLocationService() => _instance;
  BackgroundLocationService._internal();

  static const String _prefTrackingKey = 'background_tracking_active';
  static const String _bgTokenKey      = 'bg_auth_token';
  static const String _bgPatientIdKey  = 'bg_patient_id';

  // ── initialize ─────────────────────────────────────────────────────────────
  /// Call once in main() before runApp()
  Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Create notification channel (Android 8+)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'medicare_location',
      'MediCare Location',
      description: 'Location sharing with your caregiver',
      importance: Importance.low, // Low = no sound, just persistent
    );

    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,           // We control start/stop manually
        isForegroundMode: true,     // Required for background location
        notificationChannelId: 'medicare_location',
        initialNotificationTitle: 'MediCare',
        initialNotificationContent: 'Location sharing is active',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: _onIosBackground,
      ),
    );

    print('[BGLocation] ✅ Service configured');
  }

  // ── iOS background handler ─────────────────────────────────────────────────
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await _sendLocationUpdate();
    return true;
  }

  // ── permissions ────────────────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    // Foreground location first
    PermissionStatus loc = await Permission.location.status;
    if (!loc.isGranted) {
      loc = await Permission.location.request();
      if (!loc.isGranted) return false;
    }

    // Background location — user must choose "Allow all the time"
    PermissionStatus bg = await Permission.locationAlways.status;
    if (!bg.isGranted) {
      bg = await Permission.locationAlways.request();
      // Even denied → foreground tracking still works
    }

    await Permission.notification.request();
    return true;
  }

  // ── start ──────────────────────────────────────────────────────────────────
  Future<bool> startTracking(int patientId, String token) async {
    try {
      final hasPerms = await requestPermissions();
      if (!hasPerms) return false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefTrackingKey, true);
      await prefs.setInt('user_id', patientId);
      // Own copy of the credentials, independent of the login session, so
      // tracking keeps working after the user logs out.
      await prefs.setInt(_bgPatientIdKey, patientId);
      await prefs.setString(_bgTokenKey, token);

      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      if (!isRunning) {
        await service.startService();
        print('[BGLocation] ✅ Background service started for patient $patientId');
      }
      return true;
    } catch (e) {
      print('[BGLocation] ❌ Failed to start: $e');
      return false;
    }
  }

  // ── stop ───────────────────────────────────────────────────────────────────
  Future<void> stopTracking() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefTrackingKey, false);
      await prefs.remove(_bgTokenKey);
      await prefs.remove(_bgPatientIdKey);

      final service = FlutterBackgroundService();
      service.invoke('stopService');
      print('[BGLocation] 🛑 Background service stopped');
    } catch (e) {
      print('[BGLocation] Error stopping: $e');
    }
  }

  // ── restore on app launch ──────────────────────────────────────────────────
  /// Call on app start — restarts service if it was active before app closed
  Future<void> restoreTrackingIfNeeded() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final wasActive = prefs.getBool(_prefTrackingKey) ?? false;
      final patientId = prefs.getInt(_bgPatientIdKey);

      if (wasActive && patientId != null) {
        final service   = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (!isRunning) {
          await service.startService();
          print('[BGLocation] 🔄 Tracking restored for patient $patientId');
        }
      }
    } catch (e) {
      print('[BGLocation] Error restoring: $e');
    }
  }

  // ── status ─────────────────────────────────────────────────────────────────
  Future<bool> isTracking() async {
    try {
      final service = FlutterBackgroundService();
      return await service.isRunning();
    } catch (_) {
      return false;
    }
  }
}