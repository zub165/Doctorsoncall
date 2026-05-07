import 'package:flutter_test/flutter_test.dart';

import 'package:emergency_time/main.dart';

void main() {
  testWidgets('App loads with Doctor On Call branding', (WidgetTester tester) async {
    await tester.pumpWidget(const DoctorOnCallApp());
    await tester.pump();
    expect(find.textContaining('Doctor On Call'), findsWidgets);
  });
}
