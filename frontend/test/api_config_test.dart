import 'package:flutter_test/flutter_test.dart';

import '../lib/config/app_config.dart';
import '../lib/services/api_service.dart';

void main() {
  test('native debug builds require an explicit backend URL', () async {
    if (AppConfig.apiBaseUrl.isNotEmpty) {
      expect(Uri.tryParse(AppConfig.apiBaseUrl)?.hasAuthority, isTrue);
      return;
    }

    await expectLater(
      ApiService.get('/health'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('physical phone'),
        ),
      ),
    );
  });
}
