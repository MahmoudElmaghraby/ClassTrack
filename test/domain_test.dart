import 'package:flutter_test/flutter_test.dart';
import 'package:classtrack/core/domain.dart';

void main() {
  test('quiz grade zero is valid, and five is the maximum', () {
    expect(quizScore([1, 2, 3, 0, 1], [0, 1, 2, 3, 0]), 0);
    expect(quizScore([0, 1, 2, 3, 0], [0, 1, 2, 3, 0]), 5);
  });
  test('incomplete or forged choices cannot be scored', () {
    expect(
      () => quizScore([1, 2], [0, 1, 2, 3, 0]),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => quizScore([1, 2, 3, 4, 9], [0, 1, 2, 3, 0]),
      throwsA(isA<AppFailure>()),
    );
  });
  test('countdown uses remaining session time, not a fresh duration', () {
    final start = DateTime.utc(2026, 11, 15, 9);
    expect(countdown(start.add(const Duration(seconds: 120)), start), '02:00');
    expect(
      countdown(
        start.add(const Duration(seconds: 120)),
        start.add(const Duration(seconds: 65)),
      ),
      '00:55',
    );
    expect(countdown(start, start), '00:00');
    expect(countdown(start, start.add(const Duration(seconds: 1))), '00:00');
  });
  test('geographical distance handles identical and separated points', () {
    expect(distanceMeters(30.0444, 31.2357, 30.0444, 31.2357), 0);
    expect(
      distanceMeters(30.0444, 31.2357, 30.0544, 31.2357),
      closeTo(1111.95, .05),
    );
  });
  test('deterministic record identifiers do not depend on attempt count', () {
    expect(attendanceId('session', 'student'), 'session__student');
    expect(enrollmentId('class', 'student'), 'class__student');
  });
  test('question must have content and a valid single correct choice', () {
    expect(const QuizQuestion('Q', ['A', 'B', 'C', 'D'], 0).valid, true);
    expect(const QuizQuestion('Q', ['A', '', 'C', 'D'], 0).valid, false);
    expect(const QuizQuestion('Q', ['A', 'B', 'C', 'D'], 4).valid, false);
  });
}
