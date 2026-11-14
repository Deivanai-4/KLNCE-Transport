import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../lib/screens/splash_screen.dart';
import '../lib/services/auth_service.dart';

void main() {
  testWidgets('splash remains visible while the route bus animates',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>(
        create: (_) => _SignedOutAuthService(),
        child: const MaterialApp(home: SplashScreen()),
      ),
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SplashScreen), findsOneWidget);

    final bus = find.byIcon(Icons.directions_bus_rounded).first;
    final initialPosition = tester.getTopLeft(bus);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(SplashScreen), findsOneWidget);
    final displacement = (tester.getTopLeft(bus) - initialPosition).distance;
    expect(displacement, greaterThan(0));
    expect(displacement, lessThan(150));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1000));
  });
}

class _SignedOutAuthService extends AuthService {
  @override
  Future<bool> tryAutoLogin() async => false;
}
