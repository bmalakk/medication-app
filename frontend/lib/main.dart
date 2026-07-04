import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth/sign_up_page.dart';
import 'auth/sign_in_page.dart';
import 'auth/reset_password_page_1.dart';
import 'auth/forgot_password_page.dart';
import 'auth/verify_code_page.dart';
import 'patient/patient_interface.dart';
import 'patient/health_overview_page.dart';
import 'patient/setup_profile_page.dart';
import 'patient/condition_detail_page.dart';
import 'patient/conditions_list_page.dart';
import 'patient/manual_entry_page.dart';
import 'patient/add_medication_page.dart';
import 'patient/daily_planning_page.dart';
import 'patient/notifications_page.dart';
import 'patient/history_page.dart';
import 'patient/settings_page.dart';
import 'patient/quiet_hours_page.dart';
import 'patient/rewards_page.dart';
import 'patient/medication_dictionary_page.dart';
import 'patient/ai_chatbot_page.dart';
import 'patient/daily_schedule_page.dart';
import 'admin/admin_interface.dart';
import 'profile/profile_page.dart';
import 'services/language_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/location_service.dart';
import 'services/background_location_service.dart';
import 'patient/caregiver_access_page.dart';
import 'caregiver/caregiver_login_page.dart';
import 'caregiver/caregiver_dashboard.dart';
import 'caregiver/caregiver_forgot_password_page.dart';
import 'caregiver/caregiver_verify_code_page.dart';
import 'caregiver/caregiver_reset_password_page.dart';
import 'services/accessibility_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
   await AccessibilityService.instance.load();

  // Initialize background location service BEFORE running app.
  // Tracking is independent of the login session, so restore it here
  // regardless of whether the user ends up on the sign-in screen.
  if (!kIsWeb) {
    await BackgroundLocationService().initialize();
    await BackgroundLocationService().restoreTrackingIfNeeded();
  }

  if (kIsWeb) {
    print('✅ Running on web - Firebase ready via HTML');
  } else {
    await Firebase.initializeApp();
    await NotificationService.initialize();
    print('✅ Firebase initialized for mobile');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsService()),
        ChangeNotifierProxyProvider<SettingsService, LanguageService>(
          create: (_) => LanguageService(),
          update: (_, settings, language) => language!..updateFromSettings(settings),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

// Checks stored token on startup and routes to the correct home page.
// The session persists until the user explicitly logs out.
class AppRouter extends StatefulWidget {
  const AppRouter({super.key});
  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final role  = prefs.getString('user_role');

    if (!mounted) return;

    Widget destination;
    if (token != null && token.isNotEmpty) {
      switch (role) {
        case 'admin':
          destination = const AdminInterface();
          break;
        case 'caregiver':
          destination = const CaregiverDashboard();
          break;
        default:
          destination = const PatientInterface();
      }
    } else {
      destination = const SignInPage();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading MediCare...'),
          ],
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final languageService = Provider.of<LanguageService>(context);

return MaterialApp(
  navigatorKey: notificationNavigatorKey,
  title: 'MediCare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      themeMode: settingsService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      locale: languageService.locale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('fr', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppRouter(),
      onGenerateRoute: (settings) {
        // Reset password with token
        if (settings.name == '/resetpassword') {
          final token = settings.arguments as String? ?? '';
          print('🔑 Token reçu dans la route: $token');
          return MaterialPageRoute(
            builder: (context) => ResetPasswordPage(token: token),
          );
        }

        // Verify code with email in URL
        if (settings.name?.startsWith('/verifycode') ?? false) {
          String email = '';
          if (settings.name!.contains('?email=')) {
            email = settings.name!.split('?email=')[1];
            email = Uri.decodeComponent(email);
          }
          print('📧 Email extrait de l\'URL: $email');
          return MaterialPageRoute(
            builder: (context) => VerifyCodePage(email: email),
          );
        }

        // Normal routes
        switch (settings.name) {
          case '/signin':
            return MaterialPageRoute(builder: (context) => const SignInPage());
          case '/signup':
            return MaterialPageRoute(builder: (context) => const SignUpPage());
          case '/forgotpassword':
            return MaterialPageRoute(builder: (context) => const ForgotPasswordPage());
          case '/setupprofile':
            return MaterialPageRoute(builder: (context) => const SetupProfilePage());
          case '/patientinterface':
            return MaterialPageRoute(builder: (context) => const PatientInterface());
          case '/patient':
            return MaterialPageRoute(builder: (context) => const PatientInterface());
          case '/condition-detail':
            final condition = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => ConditionDetailPage(condition: condition),
            );
          case '/conditions':
            return MaterialPageRoute(
              builder: (context) => const ConditionsListPage(),
            );
          case '/manual-entry':
            return MaterialPageRoute(
              builder: (context) => const ManualEntryPage(),
            );
          case '/add-medication':
            return MaterialPageRoute(
              builder: (context) => const AddMedicationPage(),
            );
          case '/planning':
            return MaterialPageRoute(
              builder: (context) => const DailyPlanningPage(),
            );
          case '/admin':
            return MaterialPageRoute(builder: (context) => const AdminInterface());
          case '/profile':
            return MaterialPageRoute(builder: (context) => const ProfilePage());
          case '/healthoverview':
            return MaterialPageRoute(builder: (context) => const HealthOverviewPage());
          case '/notifications':
            return MaterialPageRoute(builder: (context) => const NotificationsPage());
          case '/history':
            return MaterialPageRoute(builder: (context) => const HistoryPage());
          case '/settings':
            return MaterialPageRoute(builder: (context) => const SettingsPage());
          case '/ai-chatbot':
            return MaterialPageRoute(builder: (context) => const AIChatbotPage());
          case '/caregiver-access':
            return MaterialPageRoute(builder: (context) => const CaregiverAccessPage());
          case '/med-dictionary':
            return MaterialPageRoute(builder: (context) => const MedicationDictionaryPage());
          case '/rewards':
            return MaterialPageRoute(builder: (context) => const RewardsPage());
          case '/quiet-hours':
            return MaterialPageRoute(builder: (context) => const QuietHoursPage());
          case '/daily-schedule':
            return MaterialPageRoute(builder: (context) => const DailySchedulePage());
          
          // Caregiver routes
          case '/caregiver-login':
            return MaterialPageRoute(builder: (context) => const CaregiverLoginPage());
          case '/caregiver-dashboard':
            return MaterialPageRoute(builder: (context) => const CaregiverDashboard());
          case '/caregiver-forgot-password':
            return MaterialPageRoute(builder: (context) => const CaregiverForgotPasswordPage());
          case '/caregiver-verify-code':
            final email = settings.arguments as String;
            return MaterialPageRoute(builder: (context) => CaregiverVerifyCodePage(email: email));
          case '/caregiver-reset-password':
            final args = settings.arguments as Map<String, String>;
            return MaterialPageRoute(
              builder: (context) => CaregiverResetPasswordPage(
                resetToken: args['token']!,
                email: args['email']!,
              ),
            );
          
          default:
            return MaterialPageRoute(builder: (context) => const SignInPage());
        }
      },
    );
  }
}