import 'package:flutter_test/flutter_test.dart';

import '../lib/models/schedule.dart';

void main() {
  test('active schedule follows IST cutoff windows and resets at midnight', () {
    expect(
      Schedule.activeTripAtIst(DateTime.utc(2026, 11, 14, 6, 29)),
      'incoming',
    );
    expect(
      Schedule.activeTripAtIst(DateTime.utc(2026, 11, 14, 6, 30)),
      'outgoing',
    );
    expect(
      Schedule.activeTripAtIst(DateTime.utc(2026, 11, 14, 15, 29)),
      'outgoing',
    );
    expect(
      Schedule.activeTripAtIst(DateTime.utc(2026, 11, 14, 15, 30)),
      isNull,
    );
    expect(
      Schedule.activeTripAtIst(DateTime.utc(2026, 11, 14, 18, 30)),
      'incoming',
    );
  });

  test('next IST transition is the next cutoff, including day reset', () {
    expect(
      Schedule.nextTransitionIstUtc(DateTime.utc(2026, 11, 14, 6, 29)),
      DateTime.utc(2026, 11, 14, 6, 30),
    );
    expect(
      Schedule.nextTransitionIstUtc(DateTime.utc(2026, 11, 14, 15, 29)),
      DateTime.utc(2026, 11, 14, 15, 30),
    );
    expect(
      Schedule.nextTransitionIstUtc(DateTime.utc(2026, 11, 14, 15, 30)),
      DateTime.utc(2026, 11, 14, 18, 30),
    );
  });
}
