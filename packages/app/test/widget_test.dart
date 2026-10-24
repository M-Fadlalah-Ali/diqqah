import 'package:flutter_test/flutter_test.dart';
import 'package:heseb_app/main.dart';

void main() {
  testWidgets('الإطار يفتح ويعرض حالته الهيكلية (م0)', (tester) async {
    await tester.pumpWidget(const HesebApp());
    expect(find.text('حسيب — الهيكل قيد البناء (م0)'), findsOneWidget);
  });
}
