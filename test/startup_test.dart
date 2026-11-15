import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:classtrack/ui/app.dart';
import 'package:classtrack/ui/common.dart';

void main() {
  testWidgets(
    'missing configuration displays an Arabic error instead of a fake app',
    (tester) async {
      await tester.pumpWidget(
        const ClassTrackApp(startupError: 'الإعداد غير مكتمل'),
      );
      await tester.pumpAndSettle();
      expect(find.text('الإعداد غير مكتمل'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('الإعداد غير مكتمل'))),
        TextDirection.rtl,
      );
    },
  );
  testWidgets('action errors are visible and never reported as success', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionButton(
            label: 'حفظ',
            action: () async {
              throw Exception('test');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(
      find.text('تعذر إتمام العملية. تحقق من اتصالك وحاول مجددًا.'),
      findsOneWidget,
    );
    expect(find.text('حفظ'), findsOneWidget);
  });
}
