import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

typedef Data = Map<String, dynamic>;

class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String? requiredText(String? value) =>
    value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;

String? emailError(String? value) =>
    value != null &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
    ? null
    : 'اكتب بريدًا إلكترونيًا صحيحًا';

String? passwordError(String? value) => value != null && value.length >= 6
    ? null
    : 'كلمة المرور يجب أن تكون ٦ أحرف على الأقل';

String enrollmentId(String classId, String uid) => '${classId}__$uid';
String attendanceId(String sessionId, String uid) => '${sessionId}__$uid';

DateTime? dateOf(dynamic value) => value is Timestamp ? value.toDate() : null;

String countdown(DateTime expiry, DateTime now) {
  final seconds = max(0, (expiry.difference(now).inMilliseconds / 1000).ceil());
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}

String displayStatus(String? status) => switch (status) {
  'present' => 'حاضر',
  'rejected' => 'مرفوض',
  'absent' => 'غائب',
  _ => 'لم يسجل بعد',
};

String reasonText(String? reason) => switch (reason) {
  'expired' => 'انتهى وقت الجلسة؛ لم يتم قبول الحضور.',
  'outside_radius' => 'أنت خارج النطاق المسموح؛ لم يتم قبول الحضور.',
  'gps_unavailable' => 'تعذر تحديد موقعك. شغّل خدمة الموقع وحاول مجددًا.',
  'permission_denied' => 'يلزم السماح بالموقع لتسجيل الحضور.',
  'already_present' => 'حضورك مسجل بالفعل في هذه الجلسة.',
  'not_enrolled' => 'يلزم الانضمام إلى الفصل أولًا.',
  _ => 'لم يقبل السيرفر العملية. تحقق من اتصالك ومن صلاحية الجلسة.',
};

class QuizQuestion {
  const QuizQuestion(this.text, this.options, this.correct);
  final String text;
  final List<String> options;
  final int correct;
  Data get publicData => {
    'text': text.trim(),
    'options': options.map((s) => s.trim()).toList(),
  };
  bool get valid =>
      text.trim().isNotEmpty &&
      options.length == 4 &&
      options.every((s) => s.trim().isNotEmpty) &&
      correct >= 0 &&
      correct < 4;
}

int quizScore(List<int> answers, List<int> keys) {
  if (answers.length != 5 ||
      keys.length != 5 ||
      answers.any((a) => a < 0 || a > 3)) {
    throw const AppFailure('يلزم خمس إجابات صالحة');
  }
  return List.generate(
    5,
    (i) => answers[i] == keys[i] ? 1 : 0,
  ).fold(0, (total, item) => total + item);
}

// Same spherical radius as Firebase Rules LatLng.distance (S2 mean radius).
double distanceMeters(double aLat, double aLng, double bLat, double bLng) {
  double rad(double x) => x * pi / 180;
  final a =
      pow(sin(rad(bLat - aLat) / 2), 2) +
      cos(rad(aLat)) * cos(rad(bLat)) * pow(sin(rad(bLng - aLng) / 2), 2);
  return 6371010.0 * 2 * atan2(sqrt(a.clamp(0, 1)), sqrt((1 - a).clamp(0, 1)));
}
