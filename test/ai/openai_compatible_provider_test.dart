import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

  group('streaming', () {
    late String sentBody;
    var requests = 0;

    /// A provider whose API sends [body] in pieces of [pieceSize] bytes, then
    /// fails with [error] if there is one.
    Future<OpenAiCompatibleProvider> streamingProvider(
      String body, {
      int statusCode = 200,
      int pieceSize = 1024,
      Object? error,
      bool withKey = true,
    }) async {
      final keys = InMemoryApiKeyStore();
      if (withKey) await keys.save(AiProviderType.openRouter, 'key');
      return OpenAiCompatibleProvider(
        type: AiProviderType.openRouter,
        baseUrl: 'https://example.com/v1',
        model: 'test-model',
        keyStore: keys,
        client: MockClient.streaming((request, bodyStream) async {
          requests++;
          sentBody = await bodyStream.bytesToString();
          return http.StreamedResponse(
            _inPieces(utf8.encode(body), pieceSize, error),
            statusCode,
          );
        }),
      );
    }

    Stream<AiReply> ask(
      OpenAiCompatibleProvider provider, {
      List<ChatMessage>? conversation,
    }) => provider.streamChat(
      systemPrompt: 'system',
      messages:
          conversation ?? <ChatMessage>[ChatMessage.user('Is 1001 prime?')],
    );

    /// Every reply the provider streams for [body].
    Future<List<AiReply>> repliesFor(String body) async =>
        ask(await streamingProvider(body)).toList();

    test('streams the answer as it arrives', () async {
      final provider = await streamingProvider(
        _sse(<Map<String, Object?>>[
          <String, Object?>{'role': 'assistant', 'content': ''},
          <String, Object?>{'content': 'No, '},
          <String, Object?>{'content': '1001 = 7 * 11 * 13. '},
        ]),
      );
      expect(
        await ask(
          provider,
          conversation: <ChatMessage>[
            ChatMessage.user('Is 1001 prime?'),
            ChatMessage.assistant('No.', reasoning: 'Try dividing by 7.'),
            ChatMessage.user('Why?'),
          ],
        ).toList(),
        const <AiReply>[
          AiReply(text: 'No,'),
          AiReply(text: 'No, 1001 = 7 * 11 * 13.'),
        ],
      );
      final body = jsonDecode(sentBody) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['model'], 'test-model');
      expect(sentBody, isNot(contains('Try dividing by 7.')));
      expect((body['messages'] as List).map((m) => m['content']), <String>[
        'system',
        'Is 1001 prime?',
        'No.',
        'Why?',
      ]);
    });

    test('streams reasoning from reasoning and reasoning_content', () async {
      for (final field in <String>['reasoning', 'reasoning_content']) {
        expect(
          await repliesFor(
            _sse(<Map<String, Object?>>[
              <String, Object?>{field: 'Try dividing '},
              <String, Object?>{field: 'by 7.'},
              <String, Object?>{'content': 'No.'},
            ]),
          ),
          const <AiReply>[
            AiReply(text: '', reasoning: 'Try dividing'),
            AiReply(text: '', reasoning: 'Try dividing by 7.'),
            AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
          ],
          reason: field,
        );
      }
    });

    test('streams the text and summaries in reasoning_details', () async {
      expect(
        await repliesFor(
          _sse(<Map<String, Object?>>[
            <String, Object?>{
              'reasoning_details': <Object?>[
                <String, Object?>{
                  'type': 'reasoning.summary',
                  'summary': 'Try dividing ',
                  'format': 'unknown',
                  'index': 0,
                },
              ],
            },
            <String, Object?>{
              'reasoning_details': <Object?>[
                <String, Object?>{
                  'type': 'reasoning.encrypted',
                  'data': 'c2VjcmV0',
                  'index': 1,
                },
                <String, Object?>{
                  'type': 'reasoning.text',
                  'text': 'by 7.',
                  'index': 2,
                },
              ],
            },
            <String, Object?>{'content': 'No.'},
          ]),
        ),
        const <AiReply>[
          AiReply(text: '', reasoning: 'Try dividing'),
          AiReply(text: '', reasoning: 'Try dividing by 7.'),
          AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
        ],
      );
    });

    test('reasoning sent in two fields is not counted twice', () async {
      Map<String, Object?> both(String text) => <String, Object?>{
        'reasoning': text,
        'reasoning_details': <Object?>[
          <String, Object?>{'type': 'reasoning.text', 'text': text},
        ],
      };
      final replies = await repliesFor(
        _sse(<Map<String, Object?>>[
          both('Try dividing '),
          both('by 7.'),
          <String, Object?>{'content': 'No.'},
        ]),
      );
      expect(
        replies.last,
        const AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
      );
    });

    test('uses the first reasoning field that is not blank', () async {
      final replies = await repliesFor(
        _sse(<Map<String, Object?>>[
          <String, Object?>{
            'reasoning': '  ',
            'reasoning_content': 'From reasoning_content',
          },
          <String, Object?>{'content': 'No.'},
        ]),
      );
      expect(
        replies.last,
        const AiReply(text: 'No.', reasoning: 'From reasoning_content'),
      );
    });

    test('a <think> block streams as reasoning until it closes', () async {
      expect(
        await repliesFor(
          _sse(<Map<String, Object?>>[
            <String, Object?>{'content': '<think>'},
            <String, Object?>{'content': '\nTry dividing'},
            <String, Object?>{'content': ' by 7.\n'},
            <String, Object?>{'content': '</think>'},
            <String, Object?>{'content': '\n\nNo.'},
          ]),
        ),
        const <AiReply>[
          AiReply(text: '', reasoning: 'Try dividing'),
          AiReply(text: '', reasoning: 'Try dividing by 7.'),
          AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
        ],
      );
    });

    test('a <think> block that never closes ends up in the answer', () async {
      // Like sendChat, the finished reply only splits at a </think>.
      expect(
        await repliesFor(
          _sse(<Map<String, Object?>>[
            <String, Object?>{'content': '<think>'},
            <String, Object?>{'content': 'Hmm.'},
          ]),
        ),
        const <AiReply>[
          AiReply(text: '', reasoning: 'Hmm.'),
          AiReply(text: '<think>Hmm.'),
        ],
      );
    });

    test('the finished reply is the one sendChat returns', () async {
      final provider = await streamingProvider('');
      for (final message in <Map<String, String>>[
        <String, String>{'content': ' No, 1001 = 7 * 11 * 13. '},
        <String, String>{
          'content': '<think>\nTry dividing by 7.\n</think>\n\nNo.',
        },
        <String, String>{'content': 'Try dividing by 7.\n</think>\n\nNo.'},
        <String, String>{
          'content': '<think>Is </think> a tag? Yes.</think>No.',
        },
        <String, String>{'content': '<think>\n\n</think>\n\nNo.'},
        <String, String>{
          'content': ' No. ',
          'reasoning': '\nTry dividing by 7.\n',
        },
        <String, String>{
          'content': 'No.',
          'reasoning': ' ',
          'reasoning_content': 'Try dividing by 7.',
        },
      ]) {
        // Every character arrives in its own piece.
        final replies = await repliesFor(
          _sse(<Map<String, Object?>>[
            for (final MapEntry(:key, :value) in message.entries)
              for (final character in value.split(''))
                <String, Object?>{key: character},
          ]),
        );
        expect(
          replies.last,
          provider.parseReply(<String, dynamic>{
            'choices': <Object?>[
              <String, Object?>{'message': message},
            ],
          }),
          reason: '$message',
        );
      }
    });

    test(
      'skips keep-alive lines, joins split pieces, stops at [DONE]',
      () async {
        const keepAlive = ': OPENROUTER PROCESSING\n\n';
        final body =
            '$keepAlive${_event(<String, Object?>{'content': 'Hi 👋'})}'
            '$keepAlive${_event(<String, Object?>{'content': ' there'})}'
            '$_done${_event(<String, Object?>{'content': ' never read'})}';
        for (final lines in <String>[body, body.replaceAll('\n', '\r\n')]) {
          // One-byte pieces split every line, and the emoji's four bytes.
          for (final size in <int>[1, 2, 3, 5, 64]) {
            final provider = await streamingProvider(lines, pieceSize: size);
            expect(await ask(provider).toList(), const <AiReply>[
              AiReply(text: 'Hi 👋'),
              AiReply(text: 'Hi 👋 there'),
            ], reason: '$size-byte pieces');
          }
        }
      },
    );

    test('a piece that reports an error fails the reply', () async {
      for (final error in <String>[
        '{"error":{"code":502,"message":"Provider disconnected"},'
            '"choices":[{"index":0,"delta":{"content":""},'
            '"finish_reason":"error"}]}',
        '{"choices":[{"index":0,"delta":{},"finish_reason":"error"}]}',
        '{"error":{"message":"Internal error"}}',
      ]) {
        final provider = await streamingProvider(
          '${_event(<String, Object?>{'content': 'No'})}data: $error\n\n',
        );
        await expectLater(
          ask(provider),
          emitsInOrder(<Object>[
            const AiReply(text: 'No'),
            emitsError(isA<ProviderUnavailableException>()),
          ]),
          reason: error,
        );
      }
    });

    test('an HTTP error before the stream keeps its usual meaning', () async {
      for (final (code, body, matcher) in <(int, String, Matcher)>[
        (401, '{"error":{"message":"No auth"}}', isA<InvalidApiKeyException>()),
        (
          403,
          '{"error":{"code":"model_not_found"}}',
          isA<ModelNotAvailableException>(),
        ),
        (429, '{}', isA<RateLimitException>()),
        (503, '', isA<ProviderUnavailableException>()),
      ]) {
        final provider = await streamingProvider(body, statusCode: code);
        await expectLater(ask(provider), emitsError(matcher), reason: '$code');
      }
    });

    test('a connection that drops mid-reply is a network error', () async {
      for (final error in <Object>[
        http.ClientException('Connection closed while receiving data'),
        const SocketException('Software caused connection abort'),
      ]) {
        final provider = await streamingProvider(
          _event(<String, Object?>{'content': 'No'}),
          error: error,
        );
        await expectLater(
          ask(provider),
          emitsInOrder(<Object>[
            const AiReply(text: 'No'),
            emitsError(isA<NetworkException>()),
          ]),
          reason: '$error',
        );
      }
    });

    test('a stream that ends without an answer is a bad response', () async {
      for (final body in <String>[
        '',
        _done,
        _sse(<Map<String, Object?>>[
          <String, Object?>{'reasoning': 'Try dividing by 7.'},
        ]),
        _sse(<Map<String, Object?>>[
          <String, Object?>{'content': '<think>Try dividing by 7.</think>\n'},
        ]),
      ]) {
        final provider = await streamingProvider(body);
        await expectLater(
          ask(provider).last,
          throwsA(isA<BadResponseException>()),
          reason: body,
        );
      }
    });

    test('a missing key fails before any request', () async {
      requests = 0;
      final provider = await streamingProvider(_done, withKey: false);
      await expectLater(
        ask(provider),
        emitsError(isA<MissingApiKeyException>()),
      );
      expect(requests, 0);
    });
  });
}

/// [bytes] in pieces of [size] bytes, then [error] if there is one.
Stream<List<int>> _inPieces(List<int> bytes, int size, Object? error) async* {
  for (var start = 0; start < bytes.length; start += size) {
    yield bytes.sublist(start, math.min(start + size, bytes.length));
  }
  if (error != null) throw error;
}

/// A server-sent event with one piece of a reply.
String _event(Map<String, Object?> delta) =>
    'data: ${jsonEncode(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{'index': 0, 'delta': delta},
      ],
    })}\n\n';

const String _done = 'data: [DONE]\n\n';

/// A streamed reply made of [deltas].
String _sse(List<Map<String, Object?>> deltas) =>
    '${deltas.map(_event).join()}$_done';
