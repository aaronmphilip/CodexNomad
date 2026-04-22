// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:codex_nomad/app.dart';

void main() {
  testWidgets('Codex Nomad app builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CodexNomadApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Your phone becomes the control room.'), findsOneWidget);
  });
}
