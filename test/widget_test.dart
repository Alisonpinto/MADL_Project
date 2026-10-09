import 'package:flutter_test/flutter_test.dart';

import 'package:handtalk/main.dart';

void main() {
  testWidgets('renders HandTalk home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const HandTalkApp());

    expect(find.text('HandTalk'), findsOneWidget);
    expect(find.text('Sign Language Translation'), findsOneWidget);
    expect(find.text('Obstacles'), findsNothing);
    expect(find.text('Items'), findsNothing);
    expect(find.text('Noise'), findsNothing);
  });
}
