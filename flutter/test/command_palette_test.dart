import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/command_palette.dart';

void main() {
  testWidgets('command palette filters and runs the first matching command', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showXuCommandPalette(context);
              },
              child: const Text('打开命令面板'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开命令面板'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '纪念日');
    await tester.pumpAndSettle();
    expect(find.text('打开纪念日'), findsOneWidget);
    expect(find.text('打开今日'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selected, 'anniversaries');
  });
}
