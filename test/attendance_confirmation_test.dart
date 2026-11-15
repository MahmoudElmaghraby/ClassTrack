import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:classtrack/ui/sessions.dart';

void main() {
  testWidgets(
    'optimistic presence waits for server acknowledgement and rolls back visibly',
    (tester) async {
      Future<void> display(String status, {bool pending = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ConfirmedResultCard(
                {
                  'status': status,
                  'distance': 0.0,
                  'timestamp': null,
                  'rejectionReason': status == 'rejected' ? 'expired' : null,
                },
                quiz: false,
                pending: pending,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await display('present', pending: true);
      expect(find.text('جارٍ تأكيد الحضور…'), findsOneWidget);
      expect(find.text('الحالة: حاضر'), findsNothing);
      await display('present');
      expect(find.text('جارٍ تأكيد الحضور…'), findsNothing);
      expect(find.text('الحالة: حاضر'), findsOneWidget);
      await display('present', pending: true);
      expect(find.text('الحالة: حاضر'), findsNothing);
      await display('rejected');
      expect(find.text('الحالة: مرفوض'), findsOneWidget);
      expect(find.text('الحالة: حاضر'), findsNothing);
    },
  );
}
