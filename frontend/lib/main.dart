import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/schedule_service.dart';
import 'services/bus_service.dart';
import 'services/gps_service.dart';
import 'screens/splash_screen.dart';
import 'config/app_config.dart';
import 'config/firebase_options.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is non-blocking — the app works even if Firebase is unavailable.
  // Login uses our own JWT auth (email + password via backend).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Firebase init warning (non-fatal): $e');
  }

  // Load saved JWT token so returning users are auto-logged in.
  try {
    await ApiService.loadToken();
  } catch (e) {
    debugPrint('Token load warning: $e');
  }

  try {
    await AppConfig.initialize();
  } catch (e) {
    debugPrint('AppConfig init warning: $e');
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const KlnceTransportApp());
}

// ── Design Tokens ─────────────────────────────────────────────────────────────
class AppColors {
  static const navy = Color(0xFF18324B);
  static const navyMid = Color(0xFF244966);
  static const emerald = Color(0xFF147D75);
  static const emeraldDark = Color(0xFF0F665F);
  static const amber = Color(0xFF9A5E12);
  static const surface = Color(0xFFF4F6F8);
  static const card = Colors.white;
  static const textPrimary = Color(0xFF172A3B);
  static const textSecondary = Color(0xFF68798A);
  static const arts = Color(0xFF3B5C78);
  static const artsBg = Color(0xFFEAF0F5);
  static const engBg = Color(0xFFEAF4F2);
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

class KlnceBrandMark extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;

  const KlnceBrandMark({super.key, this.size = 48, this.onTap});

  @override
  Widget build(BuildContext context) {
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/images/klnce_transport_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    return Semantics(
      label: 'KLNCE Transport logo',
      button: onTap != null,
      child: onTap == null
          ? mark
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(size * 0.28),
              child: mark,
            ),
    );
  }
}

class KlnceBrandLockup extends StatelessWidget {
  final bool onDark;
  final double markSize;
  final VoidCallback? onTap;

  const KlnceBrandLockup({
    super.key,
    this.onDark = false,
    this.markSize = 48,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : AppColors.textPrimary;
    final subtitleColor =
        onDark ? Colors.white.withValues(alpha: 0.68) : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Row(
        children: [
          KlnceBrandMark(size: markSize),
          SizedBox(width: AppSpacing.sm + 2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'KLNCE Transport',
                style: TextStyle(
                  color: titleColor,
                  fontSize: markSize * 0.34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'College bus information',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: markSize * 0.23,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void navigateToDashboard(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class KlnceTransportApp extends StatelessWidget {
  const KlnceTransportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ScheduleService()),
        ChangeNotifierProvider(create: (_) => BusService()),
        ChangeNotifierProvider(create: (_) => GpsService()),
      ],
      child: MaterialApp(
        title: 'KLNCE Smart Transport',
        scaffoldMessengerKey: NotificationService.scaffoldMessengerKey,
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const SplashScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.emerald,
        primary: AppColors.emerald,
        secondary: AppColors.navyMid,
        surface: AppColors.card,
        error: const Color(0xFFB33A3A),
      ),
      scaffoldBackgroundColor: AppColors.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        color: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.emerald,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.emerald,
          side: const BorderSide(color: AppColors.emerald, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.emerald, width: 2),
        ),
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFFADB5BD), fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }
}
