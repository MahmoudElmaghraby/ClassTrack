import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../core/domain.dart';
import '../core/store.dart';
import 'common.dart';
import 'classes.dart';

class ClassTrackApp extends StatelessWidget {
  const ClassTrackApp({super.key, this.store, this.startupError});
  final Store? store;
  final String? startupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ClassTrack',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff11676c)),
      scaffoldBackgroundColor: const Color(0xfff4f7f8),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
      ),
    ),
    home: store == null
        ? Scaffold(
            appBar: AppBar(title: const Text('ClassTrack')),
            body: ProblemView(startupError ?? 'تعذر بدء التطبيق'),
          )
        : AuthGate(store!),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate(this.store, {super.key});
  final Store store;
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: store.auth.authStateChanges(),
    builder: (context, auth) {
      if (auth.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: LoadingView());
      }
      if (!auth.hasData) return LoginScreen(store);
      return StreamBuilder<DocumentSnapshot<Data>>(
        stream: store.profile,
        builder: (context, profile) {
          if (profile.hasError) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('ClassTrack'),
                actions: [
                  IconButton(
                    onPressed: store.auth.signOut,
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
              body: ProblemView(friendlyError(profile.error!)),
            );
          }
          if (!profile.hasData) return const Scaffold(body: LoadingView());
          if (profile.data!.metadata.hasPendingWrites) {
            return const Scaffold(body: LoadingView());
          }
          if (!profile.data!.exists) return ProfileScreen(store);
          if (store.requestedRole != null &&
              store.requestedRole != profile.data!.data()!['role']) {
            return Scaffold(
              appBar: AppBar(title: const Text('الدور غير مطابق')),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'الدور المختار لا يطابق دور الحساب. ارجع واختر الدور الصحيح.',
                      ),
                    ),
                    ActionButton(
                      label: 'الرجوع لتسجيل الدخول',
                      action: store.auth.signOut,
                    ),
                  ],
                ),
              ),
            );
          }
          return ClassesScreen(store, profile.data!.data()!);
        },
      );
    },
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen(this.store, {super.key});
  final Store store;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  String role = 'student';
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.school_outlined,
                  size: 64,
                  color: Color(0xff11676c),
                ),
                const SizedBox(height: 16),
                Text(
                  'ClassTrack',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const Text(
                  'الحضور والكويز في مكان واحد',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: const [
                    DropdownMenuItem(value: 'student', child: Text('طالب')),
                    DropdownMenuItem(value: 'teacher', child: Text('مدرس')),
                  ],
                  onChanged: (v) => setState(() => role = v!),
                ),
                const SizedBox(height: 16),
                field(
                  email,
                  'البريد الإلكتروني',
                  validator: emailError,
                  keyboard: TextInputType.emailAddress,
                ),
                field(
                  password,
                  'كلمة المرور',
                  validator: passwordError,
                  password: true,
                ),
                ActionButton(
                  label: 'تسجيل الدخول',
                  icon: Icons.login,
                  action: () async {
                    if (!form.currentState!.validate()) return;
                    widget.store.requestedRole = role;
                    await widget.store.auth.signInWithEmailAndPassword(
                      email: email.text.trim(),
                      password: password.text,
                    );
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => RegisterScreen(widget.store),
                    ),
                  ),
                  child: const Text('إنشاء حساب جديد'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen(this.store, {super.key});
  final Store store;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      university = TextEditingController();
  String role = 'student';
  @override
  void dispose() {
    for (final c in [name, email, password, university]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إنشاء حساب')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: form,
        child: Column(
          children: [
            field(name, 'الاسم الكامل'),
            field(
              email,
              'البريد الإلكتروني',
              validator: emailError,
              keyboard: TextInputType.emailAddress,
            ),
            field(
              password,
              'كلمة المرور',
              validator: passwordError,
              password: true,
            ),
            DropdownButtonFormField<String>(
              initialValue: role,
              items: const [
                DropdownMenuItem(value: 'student', child: Text('طالب')),
                DropdownMenuItem(value: 'teacher', child: Text('مدرس')),
              ],
              onChanged: (v) => setState(() => role = v!),
              decoration: const InputDecoration(labelText: 'الدور'),
            ),
            const SizedBox(height: 16),
            if (role == 'student') field(university, 'الرقم الجامعي'),
            ActionButton(
              label: 'إنشاء الحساب',
              action: () async {
                if (!form.currentState!.validate()) return;
                widget.store.requestedRole = role;
                if (widget.store.auth.currentUser == null) {
                  await widget.store.auth.createUserWithEmailAndPassword(
                    email: email.text.trim(),
                    password: password.text,
                  );
                } else if (widget.store.auth.currentUser!.email !=
                    email.text.trim()) {
                  throw const AppFailure(
                    'يوجد حساب مسجل الدخول بالفعل. ارجع لتسجيل الخروج أولًا.',
                  );
                }
                await widget.store.saveProfile(
                  name.text,
                  role,
                  university.text,
                );
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen(this.store, {super.key});
  final Store store;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), university = TextEditingController();
  String role = 'student';
  @override
  void dispose() {
    name.dispose();
    university.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('استكمال بيانات الحساب'),
      actions: [
        IconButton(
          onPressed: widget.store.auth.signOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: form,
        child: Column(
          children: [
            const Text('أكمل بيانات الحساب لإتاحة الفصول والحضور.'),
            const SizedBox(height: 20),
            field(name, 'الاسم الكامل'),
            DropdownButtonFormField<String>(
              initialValue: role,
              items: const [
                DropdownMenuItem(value: 'student', child: Text('طالب')),
                DropdownMenuItem(value: 'teacher', child: Text('مدرس')),
              ],
              onChanged: (v) => setState(() => role = v!),
            ),
            const SizedBox(height: 16),
            if (role == 'student') field(university, 'الرقم الجامعي'),
            ActionButton(
              label: 'حفظ',
              action: () async {
                if (form.currentState!.validate()) {
                  widget.store.requestedRole = role;
                  await widget.store.saveProfile(
                    name.text,
                    role,
                    university.text,
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
