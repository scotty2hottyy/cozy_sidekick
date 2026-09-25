import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/openai_compatible_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  /// Sends [conversation] to an API that answers with [message] as
  /// `choices[0].message`.
  Future<AiReply> replyWith(
    Map<String, Object?> message, {
    List<ChatMessage>? conversation,
  }) async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'key');
    final provider = OpenAiCompatibleProvider(
      type: AiProviderType.openRouter,
      baseUrl: 'https://example.com/v1',
      model: 'test-model',
      keyStore: keys,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{'message': message},
            ],
          }),
          200,
        );
      }),
    );
    return provider.sendChat(
      systemPrompt: 'system',
      messages:
          conversation ?? <ChatMessage>[ChatMessage.user('Is 1001 prime?')],
    );
  }

  group('reasoning', () {
    test('is read from reasoning (OpenRouter, Ollama, vLLM)', () async {
      expect(
        await replyWith(<String, Object?>{
          'content': ' No, 1001 = 7 * 11 * 13. ',
          'reasoning': '\nTry dividing by 7.\n',
        }),
        const AiReply(
          text: 'No, 1001 = 7 * 11 * 13.',
          reasoning: 'Try dividing by 7.',
        ),
      );
    });

    test('is read from reasoning_content (xAI, llama.cpp)', () async {
      expect(
        await replyWith(<String, Object?>{
          'content': 'No.',
          'reasoning_content': 'Try dividing by 7.',
        }),
        const AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
      );
    });

    test('uses the first field that is not blank', () async {
      expect(
        await replyWith(<String, Object?>{
          'content': 'No.',
          'reasoning': 'From reasoning',
          'reasoning_content': 'From reasoning_content',
        }),
        const AiReply(text: 'No.', reasoning: 'From reasoning'),
      );
      expect(
        await replyWith(<String, Object?>{
          'content': 'No.',
          'reasoning': '  ',
          'reasoning_content': 'From reasoning_content',
        }),
        const AiReply(text: 'No.', reasoning: 'From reasoning_content'),
      );
    });

    test('is read from a <think> block in the content', () async {
      expect(
        await replyWith(<String, Object?>{
          'content': '<think>\nTry dividing by 7.\n</think>\n\nNo.',
        }),
        const AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
      );
    });

    test('is read from before a lone </think>', () async {
      // Some Qwen3 models send only the closing tag.
      expect(
        await replyWith(<String, Object?>{
          'content': 'Try dividing by 7.\n</think>\n\nNo.',
        }),
        const AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
      );
    });

    test('runs to the last </think>', () async {
      expect(
        await replyWith(<String, Object?>{
          'content': '<think>Is </think> a tag? Yes.</think>No.',
        }),
        const AiReply(text: 'No.', reasoning: 'Is </think> a tag? Yes.'),
      );
    });

    test('is null when the reply has none', () async {
      for (final message in <Map<String, Object?>>[
        <String, Object?>{'content': 'No.'},
        <String, Object?>{
          'content': 'No.',
          'reasoning': null,
          'reasoning_content': '',
        },
        // Qwen3 sends an empty block when it answers without thinking.
        <String, Object?>{'content': '<think>\n\n</think>\n\nNo.'},
      ]) {
        expect(
          await replyWith(message),
          const AiReply(text: 'No.'),
          reason: '$message',
        );
      }
    });

    test("a reply that's only reasoning is a bad response", () async {
      for (final message in <Map<String, Object?>>[
        <String, Object?>{'content': '<think>Try dividing by 7.</think>\n'},
        <String, Object?>{'content': '', 'reasoning': 'Try dividing by 7.'},
      ]) {
        await expectLater(
          replyWith(message),
          throwsA(isA<BadResponseException>()),
          reason: '$message',
        );
      }
    });

    test('is never sent back to the model', () async {
      await replyWith(
        <String, Object?>{'content': 'Because 7 divides it.'},
        conversation: <ChatMessage>[
          ChatMessage.user('Is 1001 prime?'),
          ChatMessage.assistant('No.', reasoning: 'Try dividing by 7.'),
          ChatMessage.user('Why?'),
        ],
      );
      expect(sent.body, isNot(contains('Try dividing by 7.')));
      expect(
        (jsonDecode(sent.body) as Map<String, dynamic>)['messages'],
        <Map<String, String>>[
          <String, String>{'role': 'system', 'content': 'system'},
          <String, String>{'role': 'user', 'content': 'Is 1001 prime?'},
          <String, String>{'role': 'assistant', 'content': 'No.'},
          <String, String>{'role': 'user', 'content': 'Why?'},
        ],
      );
    });
  });
}
