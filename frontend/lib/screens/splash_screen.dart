import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
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
  late final AnimationController _routeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 12000),
  )..repeat(reverse: true);
  late final CurvedAnimation _routeAnimation = CurvedAnimation(
    parent: _routeController,
    curve: Curves.easeInOutSine,
  );
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..repeat(reverse: true);
  late final CurvedAnimation _pulseAnimation = CurvedAnimation(
    parent: _pulseController,
    curve: Curves.easeInOutSine,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final minimumDisplayTime = Future<void>.delayed(
      const Duration(milliseconds: 2400),
    );
    final auth = Provider.of<AuthService>(context, listen: false);
    final loggedIn = await auth.tryAutoLogin();
    await minimumDisplayTime;
    if (!mounted) return;
    Widget dest;
    if (loggedIn) {
      dest = auth.isAdmin ? const AdminHomeScreen() : const StudentHomeScreen();
    } else {
      dest = const LoginScreen();
    }
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => dest,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _routeAnimation.dispose();
    _pulseAnimation.dispose();
    _routeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: const Color(0xFFEAE7E3),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: screenWidth > 420 ? 420.0 : screenWidth * 0.94,
            child: Column(
              children: [
                const SizedBox(height: 12),
                const _StatusBar(),
                const SizedBox(height: 4),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final route = _RouteGeometry(constraints.biggest);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: RoutePainter(route),
                              ),
                            ),
                          ),
                          const _MapPin(
                            left: 0.18,
                            top: 0.62,
                            color: Color(0xFF5EB7FF),
                          ),
                          const _MapPin(
                            left: 0.84,
                            top: 0.28,
                            color: Color(0xFF86D9FF),
                          ),
                          const _MapPin(
                            left: 0.15,
                            top: 0.82,
                            color: Color(0xFF8CC6F8),
                          ),
                          const _MapPin(
                            left: 0.74,
                            top: 0.79,
                            color: Color(0xFF8CC6F8),
                          ),
                          _PulseRing(animation: _pulseAnimation),
                          _CenterBusCard(animation: _pulseAnimation),
                          AnimatedBuilder(
                            animation: _routeAnimation,
                            child: const _MovingBus(),
                            builder: (context, bus) {
                              final location =
                                  route.location(_routeAnimation.value);
                              final isReversing = _routeController.status ==
                                  AnimationStatus.reverse;
                              return Positioned(
                                left: location.point.dx - 29,
                                top: location.point.dy - 14,
                                child: RepaintBoundary(
                                  child: Transform.rotate(
                                    angle: location.angle +
                                        (isReversing ? math.pi : 0),
                                    child: bus,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'CAMPUS TRANSIT',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                    color: Color(0xFF1B3557),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Fetching live routes...',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4D7AA1),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 218,
                  child: _RoadProgressBar(animation: _routeAnimation),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '5:35',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF243A49),
            ),
          ),
          Row(
            children: const [
              Icon(Icons.signal_cellular_4_bar_rounded,
                  size: 18, color: Color(0xFF2B2D2D)),
              SizedBox(width: 8),
              Icon(Icons.wifi_rounded, size: 18, color: Color(0xFF2B2D2D)),
              SizedBox(width: 8),
              Icon(Icons.battery_5_bar_rounded,
                  size: 18, color: Color(0xFF2B2D2D)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      child: AnimatedBuilder(
        animation: animation,
        child: const SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0xFFB9D7F9), width: 2),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                height: 140,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0x80B9D7F9), width: 8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        builder: (context, child) => RepaintBoundary(
          child: Transform.scale(
            scale: 0.94 + animation.value * 0.12,
            child:
                Opacity(opacity: 0.72 + animation.value * 0.24, child: child),
          ),
        ),
      ),
    );
  }
}

class _CenterBusCard extends StatelessWidget {
  const _CenterBusCard({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 114,
      child: AnimatedBuilder(
        animation: animation,
        child: RepaintBoundary(
          child: Container(
            width: 150,
            height: 150,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              gradient: const LinearGradient(
                colors: [Color(0xFFF6F3F1), Color(0xFFE9E4E1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.7),
                  blurRadius: 18,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: const Color(0xFFB4CDE8).withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/images/klnce_transport_logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        builder: (context, child) => Transform.scale(
          scale: 0.99 + animation.value * 0.02,
          child: child,
        ),
      ),
    );
  }
}

class _MovingBus extends StatelessWidget {
  const _MovingBus();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFF1C55D),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB68922).withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: const Icon(
        Icons.directions_bus_rounded,
        color: Color(0xFF202E3B),
        size: 18,
      ),
    );
  }
}

class _RoadProgressBar extends StatelessWidget {
  const _RoadProgressBar({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: 32,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: 0,
              right: 0,
              child: CustomPaint(
                size: Size(constraints.maxWidth, 14),
                painter: const _LoadingRoadPainter(),
              ),
            ),
            AnimatedBuilder(
              animation: animation,
              child: const _MovingBus(),
              builder: (context, bus) {
                final travel = constraints.maxWidth - 58;
                return Positioned(
                  left: travel * animation.value,
                  top: 2,
                  child: RepaintBoundary(child: bus!),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.left, required this.top, required this.color});

  final double left;
  final double top;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment((left * 2) - 1, (top * 2) - 1),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoutePainter extends CustomPainter {
  const RoutePainter(this.route);

  final _RouteGeometry route;

  @override
  void paint(Canvas canvas, Size size) {
    final outerStroke = Paint()
      ..color = const Color(0xFFD8D5D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(route.path, outerStroke);

    final dashPaint = Paint()
      ..color = const Color(0xFFF5F4F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(route.dashedPath, dashPaint);
  }

  @override
  bool shouldRepaint(covariant RoutePainter oldDelegate) {
    return oldDelegate.route != route;
  }
}

class _RouteGeometry {
  factory _RouteGeometry(Size size) {
    final path = _buildRoute(size);
    return _RouteGeometry._(
      path,
      _dashedPath(path, 16, 12),
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

class _LoadingRoadPainter extends CustomPainter {
  const _LoadingRoadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final roadRect = Offset.zero & size;
    final road = RRect.fromRectAndRadius(roadRect, const Radius.circular(999));
    final fill = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF57616B), Color(0xFFB8C6D9)],
      ).createShader(roadRect);
    canvas.drawRRect(road, fill);
    canvas.drawRRect(
      road,
      Paint()
        ..color = const Color(0xFFD4DCE7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final dashes = Path();
    const dashWidth = 10.0;
    const gap = 9.0;
    for (var x = 7.0; x < size.width - 4; x += dashWidth + gap) {
      dashes.moveTo(x, size.height / 2);
      dashes.lineTo(math.min(x + dashWidth, size.width - 4), size.height / 2);
    }
    canvas.drawPath(
      dashes,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingRoadPainter oldDelegate) => false;
}

Path _buildRoute(Size size) {
  return Path()
    ..moveTo(size.width * 0.1, size.height * 0.72)
    ..cubicTo(
      size.width * 0.18,
      size.height * 0.18,
      size.width * 0.44,
      size.height * 0.20,
      size.width * 0.55,
      size.height * 0.68,
    )
    ..cubicTo(
      size.width * 0.66,
      size.height * 0.92,
      size.width * 0.78,
      size.height * 0.18,
      size.width * 0.88,
      size.height * 0.58,
    )
    ..cubicTo(
      size.width * 0.92,
      size.height * 0.68,
      size.width * 0.94,
      size.height * 0.72,
      size.width * 0.96,
      size.height * 0.76,
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
