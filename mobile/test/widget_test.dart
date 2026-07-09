import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('AttendLens app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AttendLensApp());
    expect(find.text('AttendLens 🎥'), findsOneWidget);
  });
}
