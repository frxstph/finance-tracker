import 'package:finance_tracker/data/lock_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isValidPin', () {
    expect(isValidPin('1234', 4), isTrue);
    expect(isValidPin('123456', 6), isTrue);
    expect(isValidPin('12345', 4), isFalse);
    expect(isValidPin('12a4', 4), isFalse);
    expect(isValidPin('1234', 5), isFalse);
  });

  test('hashPin is salted and repeatable', () {
    final a = hashPin('1234', 'salt-a');
    expect(hashPin('1234', 'salt-a'), a);
    expect(hashPin('1234', 'salt-b'), isNot(a));
    expect(hashPin('4321', 'salt-a'), isNot(a));
    expect(a, isNot(contains('1234')));
  });

  test('settings round trip', () {
    const s = LockSettings(
        pinHash: 'h', salt: 's', digits: 6, biometrics: true);
    final back = LockSettings.fromJson(s.toJson());
    expect(back.enabled, isTrue);
    expect(back.digits, 6);
    expect(back.biometrics, isTrue);
    expect(const LockSettings().enabled, isFalse);
  });
}
