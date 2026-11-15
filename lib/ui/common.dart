import 'package:material_ui/material_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/domain.dart';

String friendlyError(Object e) {
  if (e is AppFailure) return e.message;
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'email-already-in-use' =>
        'البريد مستخدم بالفعل؛ سجّل الدخول بدل إنشاء حساب جديد.',
      'invalid-email' => 'البريد الإلكتروني غير صحيح.',
      'weak-password' => 'كلمة المرور ضعيفة؛ استخدم ستة أحرف على الأقل.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'البريد أو كلمة المرور غير صحيحين.',
      'network-request-failed' =>
        'تعذر الاتصال. تحقق من الإنترنت وحاول مجددًا.',
      'too-many-requests' => 'محاولات كثيرة. انتظر قليلًا وحاول مجددًا.',
      'operation-not-allowed' =>
        'تسجيل الدخول غير متاح حاليًا. راجع إعدادات الخدمة مع مسؤول المشروع.',
      _ => 'تعذر إتمام تسجيل الدخول. حاول مجددًا.',
    };
  }
  if (e is FirebaseException) {
    return e.code == 'permission-denied'
        ? reasonText(null)
        : 'تعذر حفظ العملية أو تحميلها. تحقق من اتصالك وحاول مجددًا.';
  }
  return 'تعذر إتمام العملية. تحقق من اتصالك وحاول مجددًا.';
}

void showError(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(e))));

class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.action,
    this.enabled = true,
    this.icon,
  });
  final String label;
  final Future<void> Function() action;
  final bool enabled;
  final IconData? icon;
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: !widget.enabled || busy
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await widget.action();
            } catch (e) {
              if (context.mounted) showError(context, e);
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.check),
    label: Text(busy ? 'جارٍ التنفيذ…' : widget.label),
  );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class ProblemView extends StatelessWidget {
  const ProblemView(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

Widget field(
  TextEditingController controller,
  String label, {
  String? Function(String?)? validator,
  bool password = false,
  TextInputType? keyboard,
  int lines = 1,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextFormField(
    controller: controller,
    obscureText: password,
    keyboardType: keyboard,
    maxLines: lines,
    validator: validator ?? requiredText,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);
String readableTime(dynamic timestamp) {
  final date = dateOf(timestamp)?.toLocal();
  if (date == null) return '—';
  return '${date.year}/${date.month}/${date.day} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
}

Future<void> outcome(BuildContext context, Data result, {bool quiz = false}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          result['status'] == 'present' ? 'تم تسجيل حضورك' : 'لم يُقبل الحضور',
        ),
        content: Text(
          result['status'] == 'present'
              ? (quiz
                    ? 'تم تأكيد التسليم وحفظه. ستظهر الدرجة بعد حساب النتائج.'
                    : 'تم تأكيد الحضور وحفظه.')
              : reasonText(result['rejectionReason']),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
