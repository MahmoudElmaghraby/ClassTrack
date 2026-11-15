import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BackendConfig {
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'classtrack-b9bb8',
  );
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const emulators = bool.fromEnvironment('USE_EMULATORS');
  static const emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  static bool get configured =>
      emulators ||
      (apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty);

  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        projectId: emulators ? 'demo-classtrack' : projectId,
        apiKey: emulators ? 'AIzaSyDemoClassTrackEmulatorOnly00000000' : apiKey,
        appId: emulators ? '1:123456789:android:demo' : appId,
        messagingSenderId: emulators ? '123456789' : senderId,
      ),
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    if (emulators) {
      FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8180);
      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9199);
    }
  }
}
