import 'package:flutter_test/flutter_test.dart';

import 'package:doctersoncall/main.dart';

void main() {
  testWidgets('App loads with Doctor On Call branding', (WidgetTester tester) async {
    // Disable offline DB in widget tests (Drift can spawn background timers/isolate).
    await tester.pumpWidget(const DoctorOnCallApp(offlineDbFactory: null));
    await tester.pump();
    expect(find.textContaining('Doctor On Call'), findsWidgets);
  });
}
