import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../lib/models/schedule.dart';
import '../lib/screens/admin/schedule_list_screen.dart';
import '../lib/services/schedule_service.dart';

void main() {
  test('activity entries expire after seven days without deleting schedules',
      () {
    final now = DateTime.utc(2026, 11, 13, 12);
    final parsed = Schedule.fromJson({
      'created_at': '2026-11-13T12:00:00',
    });
    final recentSchedule = Schedule(
      id: 1,
      title: 'Recent',
      fileUrl: '',
      fileType: 'image',
      tripDirection: 'incoming',
      college: 'both',
      effectiveDate: '2026-11-13',
      status: 'draft',
      createdAt: now.subtract(const Duration(days: 7)),
    );
    final expiredSchedule = Schedule(
      id: 2,
      title: 'Expired',
      fileUrl: '',
      fileType: 'image',
      tripDirection: 'incoming',
      college: 'both',
      effectiveDate: '2026-11-13',
      status: 'published',
      createdAt: now.subtract(const Duration(days: 7, seconds: 1)),
    );

    expect(parsed.createdAt, now);
    expect(recentSchedule.isActivityVisibleAt(now), isTrue);
    expect(expiredSchedule.isActivityVisibleAt(now), isFalse);
    expect(expiredSchedule.status, 'published');
  });

  testWidgets('system Back from schedule history returns to dashboard',
      (tester) async {
    await _openScheduleHistory(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Admin Dashboard'), findsOneWidget);
  });

  testWidgets('schedule history back control returns to dashboard',
      (tester) async {
    await _openScheduleHistory(tester);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Admin Dashboard'), findsOneWidget);
  });

  testWidgets('total schedules filter shows all schedules', (tester) async {
    await _openFilteredScheduleList(
      tester,
      ScheduleListFilter.all,
    );

    expect(find.text('Schedule History'), findsOneWidget);
    expect(find.text('Published timetable'), findsOneWidget);
    expect(find.text('Draft timetable'), findsOneWidget);
  });

  testWidgets('published schedules filter shows only published schedules',
      (tester) async {
    await _openFilteredScheduleList(
      tester,
      ScheduleListFilter.published,
    );

    expect(find.text('Published Schedules'), findsOneWidget);
    expect(find.text('Published timetable'), findsOneWidget);
    expect(find.text('Draft timetable'), findsNothing);
  });

  testWidgets('draft schedules filter shows only drafts', (tester) async {
    await _openFilteredScheduleList(
      tester,
      ScheduleListFilter.drafts,
    );

    expect(find.text('Draft Schedules'), findsOneWidget);
    expect(find.text('Draft timetable'), findsOneWidget);
    expect(find.text('Published timetable'), findsNothing);
  });
}

Future<void> _openScheduleHistory(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ScheduleService>(
          create: (_) => _NoopScheduleService(),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ScheduleListScreen(),
                  ),
                ),
                child: const Text('Admin Dashboard'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Admin Dashboard'));
  await tester.pumpAndSettle();

  expect(find.byType(ScheduleListScreen), findsOneWidget);
}

class _NoopScheduleService extends ScheduleService {
  final List<Schedule> schedules;

  _NoopScheduleService({this.schedules = const []});

  @override
  List<Schedule> get allSchedules => schedules;

  @override
  Future<void> fetchAllSchedules() async {}
}

Future<void> _openFilteredScheduleList(
  WidgetTester tester,
  ScheduleListFilter filter,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<ScheduleService>(
      create: (_) => _NoopScheduleService(
        schedules: [
          _schedule(id: 1, title: 'Published timetable', status: 'published'),
          _schedule(id: 2, title: 'Draft timetable', status: 'draft'),
        ],
      ),
      child: MaterialApp(
        home: ScheduleListScreen(filter: filter),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Schedule _schedule({
  required int id,
  required String title,
  required String status,
}) {
  return Schedule(
    id: id,
    title: title,
    fileUrl: '',
    fileType: 'image',
    tripDirection: 'incoming',
    college: 'both',
    effectiveDate: '2026-11-13',
    status: status,
  );
}
