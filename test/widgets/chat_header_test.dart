import 'package:cozy_sidekick/widgets/chat_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in <double>[320, 375]) {
    for (final scale in <double>[1, 2]) {
      testWidgets('buttons work at $width px wide with ${scale}x text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var chatsTaps = 0;
        var settingsTaps = 0;
        await tester.pumpWidget(
          _header(
            onChatsTap: () => chatsTaps++,
            onSettingsTap: () => settingsTaps++,
          ),
        );

        expect(tester.takeException(), isNull);
        final chats = find.byKey(const Key('chatsButton'));
        final settings = find.byKey(const Key('settingsButton'));
        final title = tester.getRect(find.text('Cozy Sidekick'));
        expect(title.overlaps(tester.getRect(chats)), isFalse);
        expect(title.overlaps(tester.getRect(settings)), isFalse);
        await tester.tapAt(tester.getCenter(chats));
        await tester.tapAt(tester.getCenter(settings));
        await tester.pump();
        expect(chatsTaps, 1);
        expect(settingsTaps, 1);
      });
    }
  }

  testWidgets('the title stays in the middle at normal text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_header(onChatsTap: () {}, onSettingsTap: () {}));

    final avatar = tester.getRect(find.byType(CircleAvatar));
    final title = tester.getRect(find.text('Cozy Sidekick'));
    expect((avatar.left + title.right) / 2, 400);
    expect(tester.getRect(find.byKey(const Key('chatsButton'))).left, 8);
    expect(tester.getRect(find.byKey(const Key('settingsButton'))).right, 792);
    expect(tester.getSize(find.byType(ChatHeader)).height, 72);
  });
}

/// The header at the top of a column, as on the chat screen.
Widget _header({
  required VoidCallback onChatsTap,
  required VoidCallback onSettingsTap,
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: <Widget>[
        ChatHeader(onChatsTap: onChatsTap, onSettingsTap: onSettingsTap),
      ],
    ),
  ),
);
