import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'admin/admin_home.dart';
import 'login_screen.dart';
import 'student/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Bus route animation: smooth continuous forward drive along the curved road
  late final AnimationController _routeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  late final CurvedAnimation _routeAnimation = CurvedAnimation(
    parent: _routeController,
    curve: Curves.linear,
  );

  // Pulse animation for campus hub rings
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  late final CurvedAnimation _pulseAnimation = CurvedAnimation(
    parent: _pulseController,
    curve: Curves.easeInOutSine,
  );

  @override
  void initState() {
    super.initState();
    // 1. Full-screen Immersive Mode: Completely hides status bar (time, battery, Wi-Fi)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _init();
  }

  Future<void> _init() async {
    final minimumDisplayTime = Future<void>.delayed(
      const Duration(milliseconds: 3200),
    );
    final auth = Provider.of<AuthService>(context, listen: false);
    final loggedIn = await auth.tryAutoLogin();
    await minimumDisplayTime;
    if (!mounted) return;

    // Restore standard edge-to-edge system overlays before navigating
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    final Widget dest = loggedIn
        ? (auth.isAdmin ? const AdminHomeScreen() : const StudentHomeScreen())
        : const LoginScreen();

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => dest,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _routeAnimation.dispose();
    _pulseAnimation.dispose();
    _routeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F3),
      // Full screen edge-to-edge layout without SafeArea to eliminate any top blank bar
      body: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background subtle grid / transit map dots
            Positioned.fill(
              child: CustomPaint(
                painter: const _MapBackgroundPainter(),
              ),
            ),

            // Main route canvas and active moving bus
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final route = _RouteGeometry(constraints.biggest);
                  return Stack(
                    children: [
                      // Curved Black Asphalt Road
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _CurvedBlackRoadPainter(route),
                          ),
                        ),
                      ),

                      // Transit stop pins along the route
                      const _MapPin(
                        left: 0.14,
                        top: 0.70,
                        label: 'Main Gate',
                        color: Color(0xFF10B981),
                      ),
                      const _MapPin(
                        left: 0.28,
                        top: 0.17,
                        label: 'North Arch',
                        color: Color(0xFF0EA5E9),
                      ),
                      const _MapPin(
                        left: 0.78,
                        top: 0.17,
                        label: 'East Terminal',
                        color: Color(0xFF0EA5E9),
                      ),
                      const _MapPin(
                        left: 0.92,
                        top: 0.68,
                        label: 'Ring Road',
                        color: Color(0xFF10B981),
                      ),

                      // Pulsing campus radar rings
                      Positioned.fill(
                        child: Align(
                          alignment: const Alignment(0, -0.06),
                          child: _PulseRing(animation: _pulseAnimation),
                        ),
                      ),

                      // Center College Campus Gate Logo Card
                      Positioned.fill(
                        child: Align(
                          alignment: const Alignment(0, -0.06),
                          child: _CenterBusCard(animation: _pulseAnimation),
                        ),
                      ),

                      // Yellow Bus actively traveling along the curved green road
                      AnimatedBuilder(
                        animation: _routeAnimation,
                        builder: (context, _) {
                          final loc = route.location(_routeAnimation.value);
                          return Positioned(
                            left: loc.point.dx - 26,
                            top: loc.point.dy - 13,
                            child: Transform.rotate(
                              angle: loc.angle,
                              alignment: Alignment.center,
                              child: const _MovingYellowBus(),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),

            // Bottom Brand Branding & Clean Route Progress
            Positioned(
              left: 24,
              right: 24,
              bottom: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'CAMPUS TRANSIT',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      color: Color(0xFF143048),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'KLNCE SMART TRANSPORTATION',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Sleek route loading progress bar (clean, no duplicate bus)
                  SizedBox(
                    width: 240,
                    child: AnimatedBuilder(
                      animation: _routeAnimation,
                      builder: (context, _) {
                        return _RouteProgressBar(
                          progress: _routeAnimation.value,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Fetching live routes...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pulsing Concentric Rings around Campus Hub ────────────────────────────────
class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final scale = 0.95 + animation.value * 0.12;
        final opacity = (0.65 + animation.value * 0.35).clamp(0.0, 1.0);
        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: SizedBox(
              width: 210,
              height: 210,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        width: 1.8,
                      ),
                    ),
                  ),
                  Container(
                    width: 175,
                    height: 175,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.30),
                        width: 2.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Center Card: KLNCE Main Gate Photo Logo ───────────────────────────────────
class _CenterBusCard extends StatelessWidget {
  const _CenterBusCard({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.98 + animation.value * 0.03,
          child: Container(
            width: 146,
            height: 146,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/klnce_transport_logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Yellow Bus: Oriented in Travel Direction (+X Forward) ────────────────────
class _MovingYellowBus extends StatelessWidget {
  const _MovingYellowBus();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 26,
      decoration: BoxDecoration(
        color: const Color(0xFFFFB800), // Vibrant School Bus Yellow
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFD97706),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFFFB800).withValues(alpha: 0.50),
            blurRadius: 8,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Roof / Hood panel with "KLNCE"
          Positioned(
            left: 10,
            right: 14,
            top: 4,
            bottom: 4,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: const Text(
                'KLNCE',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // Front Windshield (Right side = direction of forward travel)
          Positioned(
            right: 4,
            top: 4,
            bottom: 4,
            child: Container(
              width: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Dual Headlights at Front
          Positioned(
            right: 1,
            top: 4,
            child: Container(
              width: 3,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFFFEF08A),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 1,
            bottom: 4,
            child: Container(
              width: 3,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFFFEF08A),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),

          // Rear Tail Lights (Left side)
          Positioned(
            left: 1,
            top: 4,
            child: Container(
              width: 2.5,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Positioned(
            left: 1,
            bottom: 4,
            child: Container(
              width: 2.5,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          // Forward Headlight Glow Beam onto the black road
          Positioned(
            right: -24,
            top: 3,
            bottom: 3,
            child: IgnorePointer(
              child: Container(
                width: 24,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x60FEF08A),
                      Colors.transparent,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Curved Black Road Painter ────────────────────────────────────────────────
class _CurvedBlackRoadPainter extends CustomPainter {
  const _CurvedBlackRoadPainter(this.route);

  final _RouteGeometry route;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Soft Road Base Shadow / Verge
    final vergePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(route.path, vergePaint);

    // 2. Dark Slate Curb Edge
    final curbPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(route.path, curbPaint);

    // 3. Deep Black Asphalt Highway Surface
    final asphaltPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(route.path, asphaltPaint);

    // 4. Crisp White Dashed Road Markings along center
    final centerDashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(route.dashedPath, centerDashPaint);
  }

  @override
  bool shouldRepaint(covariant _CurvedBlackRoadPainter oldDelegate) {
    return oldDelegate.route != route;
  }
}

// ── Route Geometry & Tangent Heading Calculator ──────────────────────────────
class _RouteGeometry {
  factory _RouteGeometry(Size size) {
    final path = _buildRoute(size);
    return _RouteGeometry._(
      path,
      _dashedPath(path, 12, 10),
      path.computeMetrics().first,
    );
  }

  const _RouteGeometry._(this.path, this.dashedPath, this.metric);

  final Path path;
  final Path dashedPath;
  final PathMetric metric;

  ({Offset point, double angle}) location(double progress) {
    final distance = (metric.length * progress).clamp(0.0, metric.length);
    final tangent = metric.getTangentForOffset(distance);
    if (tangent == null) return (point: Offset.zero, angle: 0);
    return (
      point: tangent.position,
      angle: math.atan2(tangent.vector.dy, tangent.vector.dx),
    );
  }
}

// ── Builds the curved road path matching the user's sketch ───────────────────
Path _buildRoute(Size size) {
  final w = size.width;
  final h = size.height;

  // Graceful twin-arch transit loop around the campus gate
  return Path()
    ..moveTo(w * 0.08, h * 0.72)
    ..cubicTo(
      w * 0.16,
      h * 0.14,
      w * 0.40,
      h * 0.16,
      w * 0.50,
      h * 0.62,
    )
    ..cubicTo(
      w * 0.60,
      h * 0.92,
      w * 0.76,
      h * 0.14,
      w * 0.88,
      h * 0.52,
    )
    ..cubicTo(
      w * 0.92,
      h * 0.64,
      w * 0.95,
      h * 0.70,
      w * 0.98,
      h * 0.74,
    );
}

Path _dashedPath(Path source, double dashLength, double gapLength) {
  final dashed = Path();

  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final end = math.min(distance + dashLength, metric.length);
      dashed.addPath(metric.extractPath(distance, end), Offset.zero);
      distance += dashLength + gapLength;
    }
  }

  return dashed;
}

// ── Map Pin (Stop Points) ────────────────────────────────────────────────────
class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.left,
    required this.top,
    required this.label,
    required this.color,
  });

  final double left;
  final double top;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment((left * 2) - 1, (top * 2) - 1),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sleek Synchronized Route Progress Bar ────────────────────────────────────
class _RouteProgressBar extends StatelessWidget {
  const _RouteProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fillWidth = (constraints.maxWidth * progress).clamp(0.0, constraints.maxWidth);
          return Stack(
            children: [
              Container(
                width: fillWidth,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF047857)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Background Subtle Map Grid Dots ──────────────────────────────────────────
class _MapBackgroundPainter extends CustomPainter {
  const _MapBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = const Color(0xFFD6D3CD).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    const spacing = 36.0;
    for (double x = 18; x < size.width; x += spacing) {
      for (double y = 18; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapBackgroundPainter oldDelegate) => false;
}
