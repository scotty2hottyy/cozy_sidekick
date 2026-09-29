import 'dart:convert';
import 'dart:io';

import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/conversation.dart';
import 'package:cozy_sidekick/services/conversation_store.dart';
import 'package:cozy_sidekick/services/conversation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'failed writes leave in-memory state unchanged and the queue usable',
    () async {
      final store = _FailingStore();
      final service = ConversationService(store);
      await service.initialize();
      final id = service.active.id;
      store.fail = true;
      await expectLater(service.create(), throwsA(isA<FileSystemException>()));
      expect(service.active.id, id);
      expect(service.conversations, hasLength(1));
      store.fail = false;
      await service.create();
      expect(service.conversations, hasLength(2));
    },
  );

  late Directory dir;
  late FileConversationStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('conversations_test');
    store = FileConversationStore(directory: () async => dir);
  });
  tearDown(() async => dir.delete(recursive: true));
  test('corrupt legacy history is preserved for recovery', () async {
    final legacy = File('${dir.path}/chat_history.json');
    await legacy.writeAsString('broken');
    await expectLater(store.read(), throwsFormatException);
    expect(await legacy.readAsString(), 'broken');
    expect(await File('${dir.path}/conversations.json').exists(), isFalse);
  });
  test('fresh storage starts empty', () async {
    expect((await store.read()).conversations, isEmpty);
  });
  test(
    'messages, reasoning, metadata, active ID survive a new instance',
    () async {
      final a = Conversation.empty().withMessages([
        ChatMessage.user('First chat'),
      ]);
      final b = Conversation.empty()
          .withMessages([
            ChatMessage(
              role: MessageRole.assistant,
              text: 'answer',
              reasoning: 'reason',
              createdAt: DateTime.now(),
            ),
          ])
          .renamed('Second chat');
      await store.write(
        ConversationState(conversations: [a, b], activeId: b.id),
      );
      final reopened = await FileConversationStore(directory: () async => dir)
          .read();
      expect(reopened.activeId, b.id);
      expect(reopened.conversations.first.messages, a.messages);
      expect(reopened.conversations.last.messages, b.messages);
      expect(reopened.conversations.last.title, 'Second chat');
      expect(reopened.conversations.last.isTitleCustom, isTrue);
    },
  );
  test(
    'migration retains old messages and never imports again after delete-all',
    () async {
      final old = [
        ChatMessage.user('My old chat'),
        ChatMessage.assistant('Old answer'),
      ];
      final legacy = File('${dir.path}/chat_history.json');
      await legacy.writeAsString(
        jsonEncode(old.map((m) => m.toJson()).toList()),
      );
      final migrated = await store.read();
      expect(migrated.conversations.single.messages, old);
      expect(migrated.conversations.single.title, 'My old chat');
      expect(await legacy.exists(), isFalse);
      final service = ConversationService(store);
      await service.initialize();
      await service.deleteAll();
      final reopened = await FileConversationStore(directory: () async => dir)
          .read();
      expect(reopened.conversations.single.messages, isEmpty);
      expect(reopened.conversations.single.id, isNot(migrated.activeId));
    },
  );
  test('corrupt current storage is not overwritten', () async {
    final file = File('${dir.path}/conversations.json');
    await file.writeAsString('broken');
    await expectLater(store.read(), throwsFormatException);
    expect(await file.readAsString(), 'broken');
  });
  test('500 limit applies independently to each chat and title is from first message', () async {
    final messages = List.generate(505, (i) => ChatMessage.user('Message $i'));
    final a = Conversation.empty().withMessages(messages);
    final b = Conversation.empty().withMessages([ChatMessage.user('Other')]);
    await store.write(ConversationState(conversations: [a, b], activeId: a.id));
    final result = await store.read();
    expect(result.conversations.first.messages, messages.sublist(5));
    expect(result.conversations.first.title, 'Message 0');
    expect(result.conversations.last.messages, b.messages);
  });
  test(
    'serialized creation, selection, rename, deletion restore correctly',
    () async {
      final service = ConversationService(store);
      await service.initialize();
      final first = service.active.id;
      await service.saveMessages(first, [ChatMessage.user('hello')]);
      await service.create();
      final second = service.active.id;
      expect(service.active.messages, isEmpty);
      await Future.wait([
        service.rename(first, 'Renamed'),
        service.saveMessages(second, [ChatMessage.user('second')]),
      ]);
      await service.select(first);
      final reopened = ConversationService(
        FileConversationStore(directory: () async => dir),
      );
      await reopened.initialize();
      expect(reopened.active.id, first);
      expect(reopened.active.title, 'Renamed');
      expect(reopened.active.messages.single.text, 'hello');
      await reopened.delete(second);
      expect(reopened.active.id, first);
      await reopened.delete(first);
      expect(reopened.conversations, hasLength(1));
      expect(reopened.active.messages, isEmpty);
      expect(reopened.active.id, isNot(first));
    },
  );
  test(
    'late saves cannot resurrect deleted or cleared conversations',
    () async {
      final service = ConversationService(store);
      await service.initialize();
      final id = service.active.id;
      final revision = service.revision(id);
      await service.clear(id);
      await service.saveMessages(id, [
        ChatMessage.assistant('late'),
      ], expectedRevision: revision);
      expect(service.active.messages, isEmpty);
      await service.delete(id);
      await service.saveMessages(id, [ChatMessage.assistant('late')]);
      expect(service.conversations.any((c) => c.id == id), isFalse);
    },
  );
  test('invalid active ID falls back to an existing chat', () {
    final c = Conversation.empty();
    final state = ConversationState.fromJson({
      'version': 1,
      'activeId': 'missing',
      'conversations': [c.toJson()],
    });
    expect(state.activeId, c.id);
  });
  test(
    'automatic title normalizes whitespace, truncates and respects rename',
    () {
      final c = Conversation.empty().withMessages([
        ChatMessage.user(' hello \n world '),
      ]);
      expect(c.title, 'hello world');
      expect(Conversation.titleFrom('a' * 100), '${'a' * 60}…');
      expect(
        c.renamed('Mine').withMessages([ChatMessage.user('different')]).title,
        'Mine',
      );
      expect(() => c.renamed('  '), throwsArgumentError);
    },
  );
}

class _FailingStore implements ConversationStore {
  bool fail = false;
  ConversationState state = ConversationState(conversations: []);
  @override
  Future<ConversationState> read() async => state;
  @override
  Future<void> write(ConversationState value) async {
    if (fail) throw const FileSystemException('Test disk failure');
    state = value;
  }
}
