import 'package:flutter_test/flutter_test.dart';
import 'package:planner/core/updates/update_service.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('detects newer versions at each position', () {
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
    });

    test('rejects equal and older versions', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('compares numerically, not lexically', () {
      expect(UpdateService.isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.9.0', '1.10.0'), isFalse);
    });

    test('ignores build number suffixes', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0+42'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0+2', '1.0.0+1'), isFalse);
    });

    test('tolerates short and malformed versions', () {
      expect(UpdateService.isNewerVersion('1.1', '1.0.5'), isTrue);
      expect(UpdateService.isNewerVersion('', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('abc', '1.0.0'), isFalse);
    });
  });
}
