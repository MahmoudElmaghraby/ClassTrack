import 'package:flutter/widgets.dart';

import 'core/firebase_config.dart';
import 'core/store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Store? store;
  String? startupError;
  if (!BackendConfig.configured) {
    startupError = 'لم تُضف إعدادات Firebase لهذه النسخة بعد.';
  } else {
    try {
      await BackendConfig.initialize();
      store = Store();
    } catch (_) {
      startupError = 'تعذر الاتصال بالخدمة. تحقق من الاتصال وأعد فتح التطبيق.';
    }
  }
  runApp(ClassTrackApp(store: store, startupError: startupError));
}
