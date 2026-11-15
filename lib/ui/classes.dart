import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/domain.dart';
import '../core/store.dart';
import 'common.dart';
import 'sessions.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen(this.store, this.profile, {super.key});
  final Store store;
  final Data profile;
  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  bool get teacher => widget.profile['role'] == 'teacher';
  late final stream = widget.store.classes(teacher);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('فصولي'),
      actions: [
        IconButton(
          tooltip: 'تسجيل الخروج',
          onPressed: widget.store.auth.signOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => teacher
          ? classForm(context, widget.store)
          : joinForm(context, widget.store),
      icon: Icon(teacher ? Icons.add : Icons.group_add),
      label: Text(teacher ? 'إنشاء فصل' : 'انضمام بكود'),
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'أهلًا ${widget.profile['name']} • ${teacher ? 'مدرس' : 'طالب'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Data>>(
            stream: stream,
            builder: (context, snap) {
              if (snap.hasError) return ProblemView(friendlyError(snap.error!));
              if (!snap.hasData) return const LoadingView();
              if (snap.data!.docs.isEmpty) {
                return const ProblemView(
                  'لا توجد فصول بعد. ابدأ من الزر بالأسفل.',
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: snap.data!.docs.map((doc) {
                  final id = teacher ? doc.id : doc.data()['classID'] as String;
                  return StreamBuilder<DocumentSnapshot<Data>>(
                    stream: widget.store.db.doc('classes/$id').snapshots(),
                    builder: (context, c) {
                      if (c.hasError) {
                        return ProblemView(friendlyError(c.error!));
                      }
                      if (!c.hasData) return const SizedBox.shrink();
                      final data = c.data!.data();
                      if (data == null) return const SizedBox.shrink();
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(data['name']),
                          subtitle: Text(data['semester']),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ClassScreen(widget.store, id, teacher),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    ),
  );
}

Future<void> classForm(
  BuildContext context,
  Store store, {
  String? id,
  Data? current,
}) async {
  final name = TextEditingController(text: current?['name']),
      semester = TextEditingController(text: current?['semester']);
  final form = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(id == null ? 'إنشاء فصل' : 'تعديل بيانات الفصل'),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(name, 'اسم الفصل'),
              field(semester, 'الفصل الدراسي'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ActionButton(
          label: 'حفظ',
          action: () async {
            if (!form.currentState!.validate()) return;
            if (id == null) {
              await store.createClass(name.text, semester.text);
            } else {
              await store.editClass(id, name.text, semester.text);
            }
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  name.dispose();
  semester.dispose();
}

Future<void> joinForm(BuildContext context, Store store) async {
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('انضمام إلى فصل'),
      content: Form(key: form, child: field(code, 'كود الفصل')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ActionButton(
          label: 'انضمام',
          action: () async {
            if (!form.currentState!.validate()) return;
            await store.joinClass(code.text);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  code.dispose();
}

class ClassScreen extends StatefulWidget {
  const ClassScreen(this.store, this.id, this.teacher, {super.key});
  final Store store;
  final String id;
  final bool teacher;
  @override
  State<ClassScreen> createState() => _ClassScreenState();
}

class _ClassScreenState extends State<ClassScreen> {
  bool history = false;
  Timer? timer;
  late final classStream = widget.store.db
      .doc('classes/${widget.id}')
      .snapshots();
  late final sessionStream = widget.store.sessions(widget.id);
  late final memberStream = widget.store.members(widget.id);
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    widget.store.syncClock().catchError((Object e) {
      if (mounted) showError(context, e);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Data>>(
    stream: classStream,
    builder: (context, snap) {
      if (snap.hasError) {
        return Scaffold(body: ProblemView(friendlyError(snap.error!)));
      }
      if (!snap.hasData) return const Scaffold(body: LoadingView());
      final c = snap.data!.data()!;
      return Scaffold(
        appBar: AppBar(
          title: Text(c['name']),
          actions: [
            if (widget.teacher)
              IconButton(
                onPressed: () =>
                    classForm(context, widget.store, id: widget.id, current: c),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.teacher) ...[
              Card(
                child: ListTile(
                  title: const Text('كود الانضمام'),
                  subtitle: SelectableText(c['joinCode']),
                  trailing: IconButton(
                    tooltip: 'نسخ الكود',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: c['joinCode']),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم نسخ الكود')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SessionEditor(widget.store, widget.id),
                  ),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('بدء جلسة حضور'),
              ),
              ExpansionTile(
                title: const Text('الطلاب المنضمون'),
                children: [
                  StreamBuilder<QuerySnapshot<Data>>(
                    stream: memberStream,
                    builder: (context, m) {
                      if (m.hasError) {
                        return ProblemView(friendlyError(m.error!));
                      }
                      if (!m.hasData) return const LoadingView();
                      return Column(
                        children: m.data!.docs
                            .map(
                              (d) => ListTile(
                                title: Text(d.data()['studentName']),
                                subtitle: Text(d.data()['universityStudentID']),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('الجلسات النشطة')),
                ButtonSegment(value: true, label: Text('السجل')),
              ],
              selected: {history},
              onSelectionChanged: (s) => setState(() => history = s.first),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Data>>(
              stream: sessionStream,
              builder: (context, s) {
                if (s.hasError) return ProblemView(friendlyError(s.error!));
                if (!s.hasData) return const LoadingView();
                final docs =
                    s.data!.docs.where((d) {
                      final expired = !widget.store.now.isBefore(
                        dateOf(d.data()['expiryTime'])!,
                      );
                      return history ? expired : !expired;
                    }).toList()..sort(
                      (a, b) =>
                          dateOf(b.data()['startTime'])!
                              .compareTo(dateOf(a.data()['startTime'])!),
                    );
                if (docs.isEmpty) {
                  return ProblemView(
                    history
                        ? 'لا توجد جلسات سابقة'
                        : 'لا توجد جلسات نشطة حاليًا',
                  );
                }
                return Column(
                  children: docs
                      .map(
                        (d) => Card(
                          child: ListTile(
                            leading: Icon(
                              d.data()['mode'] == 'quiz'
                                  ? Icons.quiz_outlined
                                  : Icons.location_on_outlined,
                            ),
                            title: Text(
                              d.data()['mode'] == 'quiz'
                                  ? 'كويز الحضور'
                                  : 'تسجيل الحضور',
                            ),
                            subtitle: Text(readableTime(d.data()['startTime'])),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => widget.teacher
                                    ? ResultsScreen(widget.store, d.id)
                                    : StudentSession(widget.store, d.id),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
