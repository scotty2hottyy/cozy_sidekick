import 'dart:io';

import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/chat_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FileChatHistoryStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('history_test');
    store = FileChatHistoryStore(directory: () async => dir);
  });
  tearDown(() async => dir.delete(recursive: true));
  test('invalid UTF-8 returns empty history', () async {
    await File('${dir.path}/chat_history.json').writeAsBytes([255, 254]);
    expect(await store.load(), isEmpty);
  });
  test('missing file returns empty history', () async {
    expect(await store.load(), isEmpty);
    await store.clear();
  });
  test('save and fresh store load preserve messages and order', () async {
    final messages = [ChatMessage.user('Hello'), ChatMessage.assistant('Hi')];
    await store.save(messages);
    final reopened = FileChatHistoryStore(directory: () async => dir);
    expect(await reopened.load(), messages);
  });
  test('reasoning survives a restart, and older history still loads', () async {
    final messages = [
      ChatMessage.user('Is 1001 prime?'),
      ChatMessage.assistant('No.', reasoning: 'Try dividing by 7.'),
    ];
    await store.save(messages);
    final reopened = FileChatHistoryStore(directory: () async => dir);
    expect(await reopened.load(), messages);

    await File('${dir.path}/chat_history.json').writeAsString(
      '[{"role":"assistant","text":"Hi","createdAt":"2026-01-01T00:00:00.000Z"}]',
    );
    final older = await reopened.load();
    expect(older.single.text, 'Hi');
    expect(older.single.reasoning, isNull);
  });
  test('clear removes the history file', () async {
    await store.save([ChatMessage.user('Hello')]);
    await store.clear();
    expect(await File('${dir.path}/chat_history.json').exists(), isFalse);
    expect(await store.load(), isEmpty);
  });
  test('only newest 500 messages are retained', () async {
    final messages = List.generate(505, (i) => ChatMessage.user('$i'));
    await store.save(messages);
    expect(await store.load(), messages.sublist(5));
    expect(messages, hasLength(505));
  });
  for (final contents in [
    'broken json',
    '{}',
    '[null]',
    '[{"role":"unknown","text":"hi","createdAt":"2026-01-01"}]',
    '[{"role":"user","text":4,"createdAt":"2026-01-01"}]',
    '[{"role":"user","text":"hi","createdAt":"bad"}]',
  ]) {
    test('invalid history returns empty: $contents', () async {
      await File('${dir.path}/chat_history.json').writeAsString(contents);
      expect(await store.load(), isEmpty);
    });
  }
}
