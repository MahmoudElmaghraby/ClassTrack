import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'domain.dart';

class DeviceLocation {
  const DeviceLocation(this.latitude, this.longitude, {this.error});
  final double? latitude;
  final double? longitude;
  final String? error;
  bool get available => latitude != null && longitude != null;
}

class Store {
  Store({FirebaseAuth? auth, FirebaseFirestore? db})
    : auth = auth ?? FirebaseAuth.instance,
      db = db ?? FirebaseFirestore.instance;
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  String? requestedRole;
  String get uid => auth.currentUser!.uid;
  DateTime? _serverTime;
  final _elapsed = Stopwatch();
  DateTime get now => _serverTime?.add(_elapsed.elapsed) ?? DateTime.now();
  final _grading = <String>{};
  final _finalizing = <String>{};

  Future<void> syncClock() async {
    final ref = db.doc('users/$uid/runtime/clock');
    await ref
        .set({'time': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 15));
    final snap = await ref.get(const GetOptions(source: Source.server));
    _serverTime = dateOf(snap.data()?['time']);
    _elapsed.reset();
    _elapsed.start();
  }

  Stream<DocumentSnapshot<Data>> get profile =>
      db.doc('users/$uid').snapshots(includeMetadataChanges: true);

  Future<void> saveProfile(
    String name,
    String role,
    String universityId,
  ) async {
    if (name.trim().isEmpty ||
        !['teacher', 'student'].contains(role) ||
        (role == 'student' && universityId.trim().isEmpty)) {
      throw const AppFailure('أكمل بيانات الحساب');
    }
    await db.doc('users/$uid').set({
      'name': name.trim(),
      'email': auth.currentUser!.email,
      'role': role,
      if (role == 'student') 'studentID': universityId.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Data>> classes(bool teacher) => teacher
      ? db.collection('classes').where('teacherID', isEqualTo: uid).snapshots()
      : db
            .collection('enrollments')
            .where('studentID', isEqualTo: uid)
            .snapshots();

  Stream<QuerySnapshot<Data>> members(String classId) => db
      .collection('enrollments')
      .where('classID', isEqualTo: classId)
      .snapshots();

  Stream<QuerySnapshot<Data>> sessions(String classId) => db
      .collection('attendance_sessions')
      .where('classID', isEqualTo: classId)
      .where('initialized', isEqualTo: true)
      .snapshots();

  Stream<QuerySnapshot<Data>> records(String sessionId) => db
      .collection('attendance_records')
      .where('sessionID', isEqualTo: sessionId)
      .snapshots();

  Stream<DocumentSnapshot<Data>> myRecord(String sessionId) => db
      .doc('attendance_records/${attendanceId(sessionId, uid)}')
      .snapshots(includeMetadataChanges: true);

  Future<void> createClass(String name, String semester) async {
    final ref = db.collection('classes').doc();
    for (var attempt = 0; attempt < 6; attempt++) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final random = Random.secure();
      final code = List.generate(
        8,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      try {
        await db.runTransaction((tx) async {
          final codeRef = db.doc('class_join_codes/$code');
          if ((await tx.get(codeRef)).exists) {
            throw const AppFailure('code_collision');
          }
          tx.set(ref, {
            'name': name.trim(),
            'semester': semester.trim(),
            'teacherID': uid,
            'joinCode': code,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(codeRef, {
            'classID': ref.id,
            'teacherID': uid,
            'className': name.trim(),
          });
        });
        return;
      } on AppFailure catch (e) {
        if (e.message != 'code_collision') rethrow;
      }
    }
    throw const AppFailure('تعذر توليد كود الفصل؛ حاول مجددًا');
  }

  Future<void> editClass(String classId, String name, String semester) => db
      .doc('classes/$classId')
      .update({'name': name.trim(), 'semester': semester.trim()});

  Future<void> joinClass(String input) async {
    final code = input.trim().toUpperCase();
    if (!RegExp(r'^[A-Z2-9]{8}$').hasMatch(code)) {
      throw const AppFailure('كود الفصل غير صحيح');
    }
    final invitation = await db.doc('class_join_codes/$code').get();
    if (!invitation.exists) throw const AppFailure('كود الفصل غير موجود');
    final classId = invitation.data()!['classID'] as String;
    final ref = db.doc('enrollments/${enrollmentId(classId, uid)}');
    final user = (await db.doc('users/$uid').get()).data()!;
    await db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) {
        throw const AppFailure('أنت منضم إلى الفصل بالفعل');
      }
      tx.set(ref, {
        'classID': classId,
        'studentID': uid,
        'joinCodeUsed': code,
        'studentName': user['name'],
        'universityStudentID': user['studentID'],
        'className': invitation.data()!['className'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<DeviceLocation> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const DeviceLocation(null, null, error: 'gps_unavailable');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const DeviceLocation(null, null, error: 'permission_denied');
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return DeviceLocation(p.latitude, p.longitude);
    } catch (_) {
      return const DeviceLocation(null, null, error: 'gps_unavailable');
    }
  }

  Future<String> startSession(
    String classId,
    String mode,
    double radius,
    List<QuizQuestion> questions,
  ) async {
    if (!radius.isFinite || radius <= 0) {
      throw const AppFailure('النطاق يجب أن يكون رقمًا موجبًا بالمتر');
    }
    if (mode == 'quiz' &&
        (questions.length != 5 || questions.any((q) => !q.valid))) {
      throw const AppFailure('أكمل الأسئلة الخمسة وإجابة كل سؤال الصحيحة');
    }
    final location = await locate();
    if (!location.available) throw AppFailure(reasonText(location.error));
    final ref = db.collection('attendance_sessions').doc();
    final batch = db.batch();
    batch.set(ref, {
      'classID': classId,
      'teacherID': uid,
      'mode': mode,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'radius': radius,
      'startTime': null,
      'expiryTime': null,
      'status': 'closed',
      'initialized': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mode == 'quiz') {
      batch.set(ref.collection('quiz').doc('public'), {
        'questions': questions.map((q) => q.publicData).toList(),
      });
      batch.set(ref.collection('quiz_private').doc('key'), {
        'correctAnswers': questions.map((q) => q.correct).toList(),
      });
    }
    await batch.commit();
    final clockRef = db.doc('session_clocks/${ref.id}');
    await clockRef.set({
      'teacherID': uid,
      'classID': classId,
      'startedAt': FieldValue.serverTimestamp(),
    });
    final clock = await clockRef.get(const GetOptions(source: Source.server));
    final start = dateOf(clock.data()!['startedAt'])!;
    await ref.update({
      'startTime': Timestamp.fromDate(start),
      'expiryTime': Timestamp.fromDate(start.add(const Duration(seconds: 120))),
      'status': 'active',
      'initialized': true,
    });
    await syncClock();
    return ref.id;
  }

  Future<List<Data>> questions(String sessionId) async {
    final doc = await db
        .doc('attendance_sessions/$sessionId/quiz/public')
        .get();
    return List<Data>.from(doc.data()!['questions']);
  }

  Future<Data> attempt(
    String sessionId, {
    List<int>? answers,
    bool opening = false,
  }) async {
    final location = await locate();
    await syncClock();
    try {
      return await _writeAttempt(
        sessionId,
        location,
        answers: answers,
        opening: opening,
      );
    } on FirebaseException catch (error) {
      // A request can cross the exact deadline while it is travelling. Re-check
      // authoritative time and persist a truthful rejection, never a late success.
      if (error.code != 'permission-denied') rethrow;
      await syncClock();
      final session = await db
          .doc('attendance_sessions/$sessionId')
          .get(const GetOptions(source: Source.server));
      final expiry = dateOf(session.data()?['expiryTime']);
      if (expiry == null || now.isBefore(expiry)) rethrow;
      return _writeAttempt(
        sessionId,
        location,
        answers: answers,
        opening: opening,
      );
    }
  }

  Future<Data> _writeAttempt(
    String sessionId,
    DeviceLocation location, {
    List<int>? answers,
    bool opening = false,
  }) async {
    final recordRef = db.doc(
      'attendance_records/${attendanceId(sessionId, uid)}',
    );
    final eventRef = recordRef.collection('attempts').doc();
    return db.runTransaction((tx) async {
      final session = (await tx.get(db.doc('attendance_sessions/$sessionId')))
          .data();
      if (session == null) throw const AppFailure('الجلسة غير موجودة');
      final enrollment = await tx.get(
        db.doc('enrollments/${enrollmentId(session['classID'], uid)}'),
      );
      if (!enrollment.exists) throw AppFailure(reasonText('not_enrolled'));
      final existing = (await tx.get(recordRef)).data();
      final expiry = dateOf(session['expiryTime'])!;
      final withinTime = session['status'] == 'active' && now.isBefore(expiry);
      final duplicate = existing?['status'] == 'present';
      final distance = location.available
          ? distanceMeters(
              location.latitude!,
              location.longitude!,
              (session['latitude'] as num).toDouble(),
              (session['longitude'] as num).toDouble(),
            )
          : null;
      final inRange =
          distance != null && distance <= (session['radius'] as num);
      final reason = duplicate
          ? 'already_present'
          : !withinTime
          ? 'expired'
          : !location.available
          ? location.error!
          : !inRange
          ? 'outside_radius'
          : null;
      final submitted =
          session['mode'] == 'quiz' && !opening && answers != null;
      if (session['mode'] == 'quiz' &&
          !opening &&
          (answers == null ||
              answers.length != 5 ||
              answers.any((a) => a < 0 || a > 3))) {
        throw const AppFailure('أجب عن الأسئلة الخمسة قبل التسليم');
      }
      final status = reason != null
          ? 'rejected'
          : opening
          ? 'absent'
          : 'present';
      final event = <String, dynamic>{
        'studentID': uid,
        'sessionID': sessionId,
        'classID': session['classID'],
        'timestamp': FieldValue.serverTimestamp(),
        'latitude': location.latitude,
        'longitude': location.longitude,
        'distance': distance,
        'locationVerified': inRange,
        'quizOpened': session['mode'] == 'quiz',
        'quizSubmitted': submitted,
        'submissionTime': submitted ? FieldValue.serverTimestamp() : null,
        'answers': submitted ? answers : null,
        'quizScore': null,
        'gradedAt': null,
        'status': status,
        'rejectionReason': reason,
        'eventType': opening
            ? 'quiz_open'
            : session['mode'] == 'quiz'
            ? 'quiz_submit'
            : 'punch_in',
        'finalized': !opening,
      };
      tx.set(eventRef, event);
      if (!opening && !duplicate) {
        tx.set(recordRef, {...event, 'lastAttemptId': eventRef.id});
      }
      return {
        'status': status,
        'rejectionReason': reason,
        'opened': opening && reason == null,
      };
    });
  }

  // Runs only while the owning teacher is viewing results. Rules verify every score.
  Future<void> grade(String sessionId) async {
    if (!_grading.add(sessionId)) return;
    try {
      final sessionRef = db.doc('attendance_sessions/$sessionId');
      final s = (await sessionRef.get()).data()!;
      if (s['teacherID'] != uid || s['mode'] != 'quiz') return;
      final keys = List<int>.from(
        (await sessionRef.collection('quiz_private').doc('key').get())
            .data()!['correctAnswers'],
      );
      final events = await db
          .collectionGroup('attempts')
          .where('sessionID', isEqualTo: sessionId)
          .where('classID', isEqualTo: s['classID'])
          .get();
      for (final event in events.docs) {
        final data = event.data();
        if (data['quizSubmitted'] != true || data['quizScore'] != null) {
          continue;
        }
        final score = quizScore(List<int>.from(data['answers']), keys);
        final recordRef = event.reference.parent.parent!;
        await db.runTransaction((tx) async {
          final record = (await tx.get(recordRef)).data();
          final current = (await tx.get(event.reference)).data();
          if (current?['quizScore'] != null) return;
          final patch = {
            'quizScore': score,
            'gradedAt': FieldValue.serverTimestamp(),
          };
          tx.update(event.reference, patch);
          if (record?['lastAttemptId'] == event.id) tx.update(recordRef, patch);
        });
      }
    } finally {
      _grading.remove(sessionId);
    }
  }

  Future<void> finalize(String sessionId) async {
    if (!_finalizing.add(sessionId)) return;
    try {
      await syncClock();
      final sessionRef = db.doc('attendance_sessions/$sessionId');
      final session = (await sessionRef.get()).data()!;
      final expiry = dateOf(session['expiryTime'])!;
      if (session['teacherID'] != uid || now.isBefore(expiry)) return;
      if (session['status'] != 'closed') {
        await sessionRef.update({'status': 'closed'});
      }
      final members = await db
          .collection('enrollments')
          .where('classID', isEqualTo: session['classID'])
          .get();
      for (final member in members.docs) {
        if (dateOf(member.data()['createdAt'])!.isAfter(expiry)) continue;
        final student = member.data()['studentID'] as String;
        final ref = db.doc(
          'attendance_records/${attendanceId(sessionId, student)}',
        );
        await db.runTransaction((tx) async {
          if ((await tx.get(ref)).exists) return;
          tx.set(ref, {
            'sessionID': sessionId,
            'studentID': student,
            'classID': session['classID'],
            'timestamp': null,
            'latitude': null,
            'longitude': null,
            'distance': null,
            'locationVerified': false,
            'quizOpened': false,
            'quizSubmitted': false,
            'submissionTime': null,
            'answers': null,
            'quizScore': null,
            'gradedAt': null,
            'status': 'absent',
            'rejectionReason': null,
            'finalized': true,
            'finalizedAt': FieldValue.serverTimestamp(),
            'lastAttemptId': null,
          });
        });
      }
      await grade(sessionId);
    } finally {
      _finalizing.remove(sessionId);
    }
  }
}
