import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/error/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ok exposes its value and maps', () {
    const result = Result.ok(2);
    expect(result.isOk, isTrue);
    expect(result.valueOrNull, 2);
    expect(result.failureOrNull, isNull);
    expect(result.map((v) => v * 10).valueOrNull, 20);
    expect(result.fold((v) => 'value $v', (f) => 'failure'), 'value 2');
  });

  test('err exposes its failure and short-circuits map', () {
    const failure = NetworkFailure('offline');
    const result = Result<int>.err(failure);
    expect(result.isOk, isFalse);
    expect(result.valueOrNull, isNull);
    expect(result.failureOrNull, same(failure));
    expect(result.map((v) => v * 10).failureOrNull, same(failure));
    expect(result.fold((v) => 'value', (f) => f.message), 'offline');
  });
}
