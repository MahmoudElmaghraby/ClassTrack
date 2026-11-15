# ClassTrack

تطبيق Android لمشروع **Mobile Programming – Level 2**: حضور بالموقع أو كويز من خمسة أسئلة، باستخدام Flutter وFirebase Spark دون حساب فوترة.

المشروع: `classtrack-b9bb8` — اسم حزمة Android: `com.classtrack.classtrack`.

## الوظائف

تطبيق واحد للمدرس والطالب، حسابات بالأدوار، إنشاء فصل وتعديل بياناته، كود انضمام وعضويات، جلسة حضور 120 ثانية، نطاق يحدده المدرس، Punch-In، محرر خمسة أسئلة وحلها وتسليمها، متابعة مباشرة وسجل داخلي ونتائج بسيطة. لا توجد ميزات Bonus أو تصدير أو Push أو تتبع بالخلفية.

## متطلبات التشغيل

- Flutter **3.50.0** وDart **3.14.0**؛ إصدارات الحزم محفوظة في `pubspec.lock`.
- JDK 21 كاملًا، Android SDK Platforms 34 و36 وBuild Tools 36.0.0، وNDK الذي يطلبه Flutter/Gradle. يلزم قبول رخصة Android SDK في بيئة البناء.
- جهاز Android 7.0 أو أحدث (API 24+) لاختبار GPS الفعلي. نسخة Release الشاملة تستهدف armeabi-v7a وarm64-v8a وx86_64.
- لاختبار القواعد: Node.js 22 أو أحدث وJava 21.

## إعداد Firebase

1. مشروع Spark المذكور دون ربط فوترة؛ إضافة تطبيق Android باسم الحزمة أعلاه.
2. تفعيل **Authentication → Email/Password**.
3. إنشاء **Cloud Firestore Standard** الافتراضي `(default)` في Production mode.
4. نسخ محتوى `firestore.rules` كاملًا إلى تبويب Rules والضغط على Publish.
5. إنشاء Structured index من تبويب Indexes/Manual للمجموعة `attempts`، الحقلان `classID` و`sessionID` بترتيب Ascending، وQuery scope = Collection group، ثم انتظار Enabled.

بديل نشر القواعد والفهرس من جهاز مالك الحساب:

```sh
firebase login
firebase deploy --project classtrack-b9bb8 --only firestore:rules,firestore:indexes
```

## تشغيل وبناء

بعد تثبيت Flutter:

```sh
flutter pub get
python tool/import_firebase_config.py /path/to/google-services.json
flutter run --dart-define-from-file=config/firebase.android.json
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 --dart-define-from-file=config/firebase.android.json
```

يتحقق سكربت الإعداد من Project ID واسم الحزمة قبل إنشاء `config/firebase.android.json`. يستخدم التطبيق FirebaseOptions صريحة، فلا يحتاج Google Services Gradle plugin. لا يحتوي على مفاتيح حساب خدمة أو Admin SDK.

ناتج البناء: `build/app/outputs/flutter-apk/app-release.apk`. هو بناء Release للعرض الجامعي، موقّع بمفتاح debug للتثبيت التجريبي، وليس إصدار متجر. يشمل معماريات Android الثلاث المذكورة. تصغير Java والموارد معطّل في إعداد Release لتبسيط بناء وتسليم المشروع؛ Dart يعمل بوضع Release.

`tool/flutter.sh` مساعد لبيئة `/workspace` الحالية. على جهاز آخر استخدم أوامر flutter العادية أو اضبط مساراته بمتغيرات البيئة. إعدادات proxy الخاصة بالبيئة ليست ضمن كود المشروع.

## الاختبارات

```sh
flutter analyze
flutter test
npm ci
npm run test:rules
```

اختبارات القواعد تعمل على `demo-classtrack` داخل محاكي محلي، وليس على بيانات المشروع الحقيقي. رسائل PERMISSION_DENIED متوقعة في اختبارات الرفض المتعمد.

لتشغيل Android Emulator على Backend محلي:

```sh
npx firebase emulators:start --project demo-classtrack --only auth,firestore
flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=10.0.2.2
```

المنافذ: Firestore 8180 وAuth 9199. اتصالات HTTP المحلية مسموحة في Android debug فقط. النسخة الحقيقية لا تستخدم المحاكيات أو بيانات حضور مصطنعة.

## الوقت والأمان والنتائج على Spark

- الجلسة ظاهرة لكل الأعضاء حتى خارج النطاق؛ القبول فقط مرتبط بالموقع.
- قواعد السيرفر تتحقق من الهوية والعضوية والوقت والمسافة والتكرار. القرار يستخدم `request.time < expiryTime` و`latlng.distance <= radius`.
- تُجهز الجلسة والأسئلة أولًا، ثم تُكتب ساعة بدء موثوقة مرة واحدة وتُفعّل الجلسة بفارق 120 ثانية بالضبط. تأخير الشبكة لا يزيد المدة، وإعادة فتح الشاشة لا تمنح دقيقتين جديدتين.
- سجل واحد لكل طالب/جلسة بمعرف حتمي، مع أحداث تدقيق منفصلة للمحاولات. الطالب لا يستبدل حضورًا مقبولًا.
- الكويز خمسة أسئلة، أربع اختيارات للسؤال وإجابة صحيحة واحدة. يجب إجابة الخمسة والتسليم داخل الوقت والنطاق. الدرجة ليست حد قبول الحضور؛ 0/5 قد تكون مع حضور صحيح.
- يُعاد أخذ الموقع عند التسليم؛ الوجود داخل النطاق عند فتح الكويز وحده لا يكفي.
- مفاتيح الإجابات خاصة بالمدرس. يحسب تطبيق المدرس الدرجات تلقائيًا عند مراجعة النتائج، وتراجع القواعد صحتها دون السماح بتغيير الحضور. إذا كان المدرس غير متصل تبقى الدرجة معلقة حتى المراجعة، دون إظهار صفر زائف.
- إغلاق status وتثبيت الغياب يحدثان أثناء مراجعة المدرس. ومع ذلك يُرفض الحضور فور انتهاء expiryTime حتى لو كانت التطبيقات مغلقة وبقي status المخزن active مؤقتًا.
- التحقق يعيد حساب المسافة من الإحداثيات المقدمة؛ لا يثبت أن هاتفًا معدلًا لم يزوّر GPS. الحماية المتقدمة من التزييف خارج نطاق التكليف.

لا يُستخدم Storage: لا توجد وظيفة رفع ملفات مطلوبة، والبند الإلزامي يحدد Auth وFirestore، بينما Storage يتطلب Blaze حاليًا. لا تُفعل فوترة أو Functions.

## حالة التحقق والتسليم

نجح محليًا: **34 اختبار Security Rules و9 اختبارات Flutter وتحليل الكود**. ونجح اختبار Firebase الحقيقي في **11 تحققًا** موثقة في `docs/LIVE_BACKEND_TEST.md`، بحسابات وبيانات تجريبية وإحداثيات مصطنعة. نجح بناء APK Release الشامل وفحص توقيعه وسلامة ملفاته. تجربة GPS على جهازين ما زالت تحتاج الفريق؛ لا يُستنتج نجاحها من اختبارات Backend. التفاصيل في `docs/IMPLEMENTATION_STATUS.md`.

- بنية البيانات: `docs/schema.md`.
- سيناريو العرض وتجربة جهازين: `docs/DEMO.md`.
- الموعد النهائي وتفاصيل التقييم تعلنها د. أماني، وفق التكليف.

## الفريق

الأدوار والمساهمات تُوزع وتُعدل لاحقًا بمعرفة الفريق، حسب طلب صاحبه. الأرقام الجامعية تضاف قبل التسليم.

| الاسم | الرقم الجامعي | الدور/المساهمة |
|---|---|---|
| Mahmoud Ibrahem Ahmed | | |
| Mohamed Ahmed Saied | | |
| Ibrahem Wael Ibrahem | | |
| Youssef Walid Awad | | |
| Zyad Saudi | | |
