import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';

import '../core/domain.dart';
import '../core/store.dart';
import 'common.dart';

class SessionEditor extends StatefulWidget {
  const SessionEditor(this.store, this.classId, {super.key});
  final Store store;
  final String classId;
  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  final form = GlobalKey<FormState>();
  final radius = TextEditingController(text: '50');
  final texts = List.generate(5, (_) => TextEditingController());
  final options = List.generate(
    5,
    (_) => List.generate(4, (_) => TextEditingController()),
  );
  final correct = List<int>.filled(5, 0);
  String mode = 'punch_in';
  @override
  void dispose() {
    radius.dispose();
    for (final c in texts) {
      c.dispose();
    }
    for (final row in options) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعداد جلسة حضور')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'مدة الجلسة دقيقتان من وقت بدء السيرفر. جهّز الأسئلة قبل البدء.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'طريقة الحضور'),
              items: const [
                DropdownMenuItem(
                  value: 'punch_in',
                  child: Text('ضغطة حضور بالموقع'),
                ),
                DropdownMenuItem(value: 'quiz', child: Text('كويز الحضور')),
              ],
              onChanged: (v) => setState(() => mode = v!),
            ),
            const SizedBox(height: 16),
            field(
              radius,
              'النطاق المسموح بالمتر',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              validator: (s) {
                final v = double.tryParse(s ?? '');
                return v == null || !v.isFinite || v <= 0
                    ? 'اكتب نطاقًا موجبًا بالمتر'
                    : null;
              },
            ),
            if (mode == 'quiz')
              for (var i = 0; i < 5; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'السؤال ${i + 1}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        field(texts[i], 'نص السؤال', lines: 2),
                        for (var j = 0; j < 4; j++)
                          field(options[i][j], 'الاختيار ${j + 1}'),
                        DropdownButtonFormField<int>(
                          initialValue: correct[i],
                          decoration: const InputDecoration(
                            labelText: 'الإجابة الصحيحة',
                          ),
                          items: List.generate(
                            4,
                            (j) => DropdownMenuItem(
                              value: j,
                              child: Text('الاختيار ${j + 1}'),
                            ),
                          ),
                          onChanged: (v) => setState(() => correct[i] = v!),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            ActionButton(
              label: 'بدء الجلسة الآن',
              icon: Icons.play_arrow,
              action: () async {
                if (!form.currentState!.validate()) return;
                final questions = mode == 'quiz'
                    ? List.generate(
                        5,
                        (i) => QuizQuestion(
                          texts[i].text,
                          options[i].map((c) => c.text).toList(),
                          correct[i],
                        ),
                      )
                    : <QuizQuestion>[];
                final id = await widget.store.startSession(
                  widget.classId,
                  mode,
                  double.parse(radius.text),
                  questions,
                );
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ResultsScreen(widget.store, id),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class CountdownView extends StatefulWidget {
  const CountdownView(this.store, this.expiry, {super.key, this.onExpired});
  final Store store;
  final DateTime expiry;
  final VoidCallback? onExpired;
  @override
  State<CountdownView> createState() => _CountdownViewState();
}

class _CountdownViewState extends State<CountdownView>
    with WidgetsBindingObserver {
  Timer? timer;
  bool notified = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (!notified && !widget.store.now.isBefore(widget.expiry)) {
        notified = true;
        widget.onExpired?.call();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.syncClock().catchError((Object e) {
        if (mounted) showError(context, e);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(
      widget.store.now.isBefore(widget.expiry)
          ? 'الوقت المتبقي: ${countdown(widget.expiry, widget.store.now)}'
          : 'انتهت الجلسة',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );
}

class StudentSession extends StatefulWidget {
  const StudentSession(this.store, this.id, {super.key});
  final Store store;
  final String id;
  @override
  State<StudentSession> createState() => _StudentSessionState();
}

class _StudentSessionState extends State<StudentSession> {
  late final session = widget.store.db
      .doc('attendance_sessions/${widget.id}')
      .snapshots();
  late final record = widget.store.myRecord(widget.id);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('جلسة الحضور')),
    body: StreamBuilder<DocumentSnapshot<Data>>(
      stream: session,
      builder: (context, s) {
        if (s.hasError) return ProblemView(friendlyError(s.error!));
        if (!s.hasData) return const LoadingView();
        final data = s.data!.data()!;
        final expiry = dateOf(data['expiryTime'])!;
        return StreamBuilder<DocumentSnapshot<Data>>(
          stream: record,
          builder: (context, r) {
            if (r.hasError) return ProblemView(friendlyError(r.error!));
            final pending = r.data?.metadata.hasPendingWrites ?? false;
            final result = pending ? null : r.data?.data();
            final quiz = data['mode'] == 'quiz';
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Icon(
                  quiz ? Icons.quiz_outlined : Icons.location_on_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                Text(
                  quiz ? 'كويز الحضور • ٥ أسئلة' : 'تسجيل الحضور بالموقع',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                CountdownView(
                  widget.store,
                  expiry,
                  onExpired: () {
                    if (mounted) setState(() {});
                  },
                ),
                Text(
                  'النطاق المسموح: ${data['radius']} متر',
                  textAlign: TextAlign.center,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'الجلسة ظاهرة لكل أعضاء الفصل. قبول الحضور يتطلب وجودك داخل النطاق المسموح.',
                  ),
                ),
                ConfirmedResultCard(
                  r.data?.data(),
                  pending: pending,
                  quiz: quiz,
                ),
                if (result?['status'] != 'present')
                  ActionButton(
                    label: quiz ? 'فتح الكويز' : 'تسجيل حضوري',
                    icon: quiz ? Icons.quiz : Icons.check_circle,
                    enabled: !pending && widget.store.now.isBefore(expiry),
                    action: () async {
                      final receipt = await widget.store.attempt(
                        widget.id,
                        opening: quiz,
                      );
                      if (!context.mounted) return;
                      if (quiz && receipt['opened'] == true) {
                        final questions = await widget.store.questions(
                          widget.id,
                        );
                        if (context.mounted) {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => QuizScreen(
                                widget.store,
                                widget.id,
                                expiry,
                                questions,
                              ),
                            ),
                          );
                        }
                      } else {
                        await outcome(context, receipt, quiz: quiz);
                      }
                    },
                  ),
                TextButton.icon(
                  onPressed: Geolocator.openLocationSettings,
                  icon: const Icon(Icons.location_on),
                  label: const Text('إعدادات الموقع'),
                ),
                TextButton(
                  onPressed: Geolocator.openAppSettings,
                  child: const Text('إعدادات إذن التطبيق'),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class ConfirmedResultCard extends StatelessWidget {
  const ConfirmedResultCard(
    this.data, {
    super.key,
    required this.quiz,
    this.pending = false,
  });
  final Data? data;
  final bool pending;
  final bool quiz;
  @override
  Widget build(BuildContext context) {
    if (pending) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('جارٍ تأكيد الحضور…'),
        ),
      );
    }
    return data == null
        ? const SizedBox.shrink()
        : ResultCard(data!, quiz: quiz);
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard(this.data, {super.key, required this.quiz});
  final Data data;
  final bool quiz;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الحالة: ${displayStatus(data['status'])}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (data['rejectionReason'] != null)
            Text(reasonText(data['rejectionReason'])),
          if (data['distance'] != null)
            Text(
              'المسافة: ${(data['distance'] as num).toStringAsFixed(1)} متر',
            ),
          if (quiz && data['quizSubmitted'] == true)
            Text(
              data['quizScore'] == null
                  ? 'الدرجة: في انتظار حساب النتائج'
                  : 'الدرجة: ${data['quizScore']}/5',
            ),
          if (quiz)
            Text(
              data['quizSubmitted'] == true
                  ? 'تم تسليم الكويز'
                  : 'لم يتم تسليم الكويز',
            ),
          Text('وقت المحاولة: ${readableTime(data['timestamp'])}'),
          if (data['submissionTime'] != null)
            Text('وقت التسليم: ${readableTime(data['submissionTime'])}'),
        ],
      ),
    ),
  );
}

class QuizScreen extends StatefulWidget {
  const QuizScreen(
    this.store,
    this.id,
    this.expiry,
    this.questions, {
    super.key,
  });
  final Store store;
  final String id;
  final DateTime expiry;
  final List<Data> questions;
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final answers = List<int?>.filled(5, null);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('كويز الحضور')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CountdownView(
          widget.store,
          widget.expiry,
          onExpired: () {
            if (mounted) setState(() {});
          },
        ),
        for (var i = 0; i < 5; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${i + 1}. ${widget.questions[i]['text']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  RadioGroup<int>(
                    groupValue: answers[i],
                    onChanged: (v) => setState(() => answers[i] = v),
                    child: Column(
                      children: [
                        for (var j = 0; j < 4; j++)
                          RadioListTile<int>(
                            value: j,
                            title: Text(widget.questions[i]['options'][j]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        ActionButton(
          label: 'تسليم الإجابات',
          enabled: widget.store.now.isBefore(widget.expiry),
          action: () async {
            if (answers.any((a) => a == null)) {
              throw const AppFailure('أجب عن الأسئلة الخمسة قبل التسليم');
            }
            final result = await widget.store.attempt(
              widget.id,
              answers: answers.cast<int>(),
            );
            if (!context.mounted) return;
            await outcome(context, result, quiz: true);
            if (context.mounted && result['status'] == 'present') {
              Navigator.pop(context);
            }
          },
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen(this.store, this.id, {super.key});
  final Store store;
  final String id;
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final session = widget.store.db
      .doc('attendance_sessions/${widget.id}')
      .snapshots();
  late final records = widget.store.records(widget.id);
  Stream<QuerySnapshot<Data>>? members, events;
  String? processingError;
  bool finishAttempted = false;
  String? gradedVersion;
  Future<void> process({bool finish = false}) async {
    try {
      if (finish) {
        await widget.store.finalize(widget.id);
      } else {
        await widget.store.grade(widget.id);
      }
      if (mounted && processingError != null) {
        setState(() => processingError = null);
      }
    } catch (e) {
      if (mounted) setState(() => processingError = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('متابعة ونتائج الجلسة')),
    body: StreamBuilder<DocumentSnapshot<Data>>(
      stream: session,
      builder: (context, s) {
        if (s.hasError) return ProblemView(friendlyError(s.error!));
        if (!s.hasData) return const LoadingView();
        final data = s.data!.data()!, expiry = dateOf(data['expiryTime'])!;
        final quiz = data['mode'] == 'quiz';
        members ??= widget.store.members(data['classID']);
        events ??= widget.store.db
            .collectionGroup('attempts')
            .where('sessionID', isEqualTo: widget.id)
            .where('classID', isEqualTo: data['classID'])
            .snapshots();
        final expired = !widget.store.now.isBefore(expiry);
        if (expired && !finishAttempted) {
          finishAttempted = true;
          scheduleMicrotask(() => process(finish: true));
        }
        return StreamBuilder<QuerySnapshot<Data>>(
          stream: members,
          builder: (context, m) {
            if (m.hasError) return ProblemView(friendlyError(m.error!));
            if (!m.hasData) return const LoadingView();
            return StreamBuilder<QuerySnapshot<Data>>(
              stream: records,
              builder: (context, r) {
                if (r.hasError) return ProblemView(friendlyError(r.error!));
                if (!r.hasData) return const LoadingView();
                return StreamBuilder<QuerySnapshot<Data>>(
                  stream: events,
                  builder: (context, e) {
                    if (e.hasError) return ProblemView(friendlyError(e.error!));
                    if (!e.hasData) return const LoadingView();
                    final pending = e.data!.docs
                        .where(
                          (d) =>
                              d.data()['quizSubmitted'] == true &&
                              d.data()['quizScore'] == null,
                        )
                        .map((d) => d.id)
                        .join(',');
                    if (quiz &&
                        pending.isNotEmpty &&
                        pending != gradedVersion) {
                      gradedVersion = pending;
                      scheduleMicrotask(() => process());
                    }
                    final rows = m.data!.docs
                        .where(
                          (d) =>
                              !dateOf(d.data()['createdAt'])!.isAfter(expiry),
                        )
                        .toList();
                    final byStudent = {
                      for (final d in r.data!.docs)
                        d.data()['studentID']: d.data(),
                    };
                    var present = 0, rejected = 0, absent = 0;
                    for (final student in rows) {
                      final status =
                          byStudent[student.data()['studentID']]?['status'];
                      if (status == 'present') {
                        present++;
                      } else if (status == 'rejected') {
                        rejected++;
                      } else if (expired) {
                        absent++;
                      }
                    }
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          quiz ? 'نتائج كويز الحضور' : 'نتائج تسجيل الحضور',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        CountdownView(
                          widget.store,
                          expiry,
                          onExpired: () {
                            if (mounted) setState(() {});
                          },
                        ),
                        Text(
                          'حاضر: $present • مرفوض: $rejected • غائب: $absent',
                          textAlign: TextAlign.center,
                        ),
                        if (!expired)
                          Text(
                            'لم يسجل بعد: ${rows.length - present - rejected}',
                            textAlign: TextAlign.center,
                          ),
                        if (processingError != null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  Text(processingError!),
                                  ActionButton(
                                    label: 'إعادة تحديث النتائج',
                                    action: () async {
                                      await process(finish: expired);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (rows.isEmpty)
                          const ProblemView(
                            'لا يوجد طلاب منضمون خلال فترة هذه الجلسة.',
                          ),
                        for (final student in rows)
                          Builder(
                            builder: (context) {
                              final id = student.data()['studentID'];
                              final record = byStudent[id];
                              final attempts =
                                  e.data!.docs
                                      .where((d) => d.data()['studentID'] == id)
                                      .toList()
                                    ..sort(
                                      (a, b) =>
                                          (dateOf(a.data()['timestamp']) ??
                                                  DateTime(1970))
                                              .compareTo(
                                                dateOf(b.data()['timestamp']) ??
                                                    DateTime(1970),
                                              ),
                                    );
                              final label = record != null
                                  ? displayStatus(record['status'])
                                  : expired
                                  ? 'غائب'
                                  : attempts.any(
                                      (a) =>
                                          a.data()['eventType'] == 'quiz_open',
                                    )
                                  ? 'بدأ الكويز'
                                  : 'لم يسجل بعد';
                              return Card(
                                child: ExpansionTile(
                                  title: Text(
                                    '${student.data()['studentName']} • $label',
                                  ),
                                  subtitle: Text(
                                    student.data()['universityStudentID'],
                                  ),
                                  children: [
                                    if (record != null)
                                      ResultCard(record, quiz: quiz),
                                    if (attempts.isEmpty)
                                      const ListTile(
                                        title: Text('لا توجد محاولات مسجلة'),
                                      ),
                                    for (final a in attempts)
                                      ListTile(
                                        title: Text(
                                          '${a.data()['eventType'] == 'quiz_open'
                                              ? 'فتح الكويز'
                                              : a.data()['quizSubmitted'] == true
                                              ? 'تسليم الكويز'
                                              : 'محاولة الحضور'} • ${a.data()['eventType'] == 'quiz_open' && a.data()['rejectionReason'] == null ? 'تم الفتح' : displayStatus(a.data()['status'])}',
                                        ),
                                        subtitle: Text(
                                          '${readableTime(a.data()['timestamp'])}${a.data()['rejectionReason'] == null ? '' : '\n${reasonText(a.data()['rejectionReason'])}'}${a.data()['quizScore'] == null ? '' : '\nالدرجة: ${a.data()['quizScore']}/5'}',
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    ),
  );
}
