import 'package:flutter_test/flutter_test.dart';
import 'package:floor_measure/main.dart';

void main() {
  testWidgets('FloorMeasure app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FloorMeasureApp());
    expect(find.byType(FloorMeasureApp), findsOneWidget);
  });
}
