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

    test('is read from reasoning_content (llama.cpp, DeepSeek)', () async {
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

  test('asks the model it is given, or its default', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'key');
    final asked = <Object?>[];
    final provider = OpenAiCompatibleProvider(
      type: AiProviderType.openRouter,
      baseUrl: 'https://example.com/v1',
      model: 'default-model',
      keyStore: keys,
      client: MockClient.streaming((request, bodyStream) async {
        final body = jsonDecode(
          await bodyStream.bytesToString(),
        ) as Map<String, dynamic>;
        asked.add(body['model']);
        return http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(
              body['stream'] == true
                  ? _sse(<Map<String, Object?>>[
                      <String, Object?>{'content': 'Hi'},
                    ])
                  : '{"choices":[{"message":{"content":"Hi"}}]}',
            ),
          ),
          200,
        );
      }),
    );
    final hi = <ChatMessage>[ChatMessage.user('Hi')];

    await provider.sendChat(systemPrompt: 'system', messages: hi);
    await provider.sendChat(
      systemPrompt: 'system',
      messages: hi,
      model: 'chosen-model',
    );
    await provider.streamChat(systemPrompt: 'system', messages: hi).drain();
    await provider
        .streamChat(systemPrompt: 'system', messages: hi, model: 'chosen-model')
        .drain();

    expect(asked, <String>[
      'default-model',
      'chosen-model',
      'default-model',
      'chosen-model',
    ]);
  });

  test('parses total token usage from a completed reply', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'key');
    final provider = OpenAiCompatibleProvider(
      type: AiProviderType.openRouter,
      baseUrl: 'https://example.com/v1',
      model: 'test-model',
      keyStore: keys,
      client: MockClient(
        (_) async => http.Response(
          '{"choices":[{"message":{"content":"Hello"}}],'
          '"usage":{"total_tokens":42}}',
          200,
        ),
      ),
    );

    expect(
      await provider.sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('Hi')],
      ),
      const AiReply(text: 'Hello', totalTokens: 42),
    );
  });

  group('model list', () {
    late http.Request listed;
    var requests = 0;

    /// A provider whose `/models` lists [models].
    Future<OpenAiCompatibleProvider> listing(
      List<Map<String, Object?>> models, {
      int statusCode = 200,
      bool withKey = true,
      bool publicModelList = false,
    }) async {
      final keys = InMemoryApiKeyStore();
      if (withKey) await keys.save(AiProviderType.openAi, 'key');
      return OpenAiCompatibleProvider(
        type: AiProviderType.openAi,
        baseUrl: 'https://example.com/v1/',
        model: 'test-model',
        keyStore: keys,
        publicModelList: publicModelList,
        client: MockClient((request) async {
          requests++;
          listed = request;
          return http.Response(
            jsonEncode(<String, Object?>{'object': 'list', 'data': models}),
            statusCode,
          );
        }),
      );
    }

    List<Map<String, Object?>> ids(List<String> ids) => <Map<String, Object?>>[
      for (final id in ids) <String, Object?>{'id': id, 'object': 'model'},
    ];

    test('lists the chat models at /models, sorted', () async {
      final provider = await listing(
        ids(<String>[
          'gpt-6-sol',
          'gpt-6-luna',
          'gpt-6-luna',
          'gpt-6-astra',
          'text-embedding-3-small',
          'whisper-1',
          'gpt-4o-transcribe',
          'tts-1-hd',
          'gpt-4o-mini-tts',
          'gpt-4o-audio-preview',
          'gpt-realtime-2',
          'gpt-live-1',
          'dall-e-3',
          'gpt-image-2.5-flare',
          'sora-2',
          'omni-moderation-latest',
          'computer-use-preview',
          'gpt-5-codex',
          'babbage-002',
          'davinci-002',
        ]),
      );
      expect(await provider.listModels(), <String>[
        'gpt-6-astra',
        'gpt-6-luna',
        'gpt-6-sol',
      ]);
      expect(listed.method, 'GET');
      expect(listed.url.toString(), 'https://example.com/v1/models');
      expect(listed.headers['authorization'], 'Bearer key');
    });

    test('leaves out the models Groq has turned off', () async {
      final provider = await listing(<Map<String, Object?>>[
        <String, Object?>{'id': 'openai/gpt-oss-20b', 'active': true},
        <String, Object?>{
          'id': 'meta-llama/llama-4-scout-17b-16e-instruct',
          'active': true,
        },
        <String, Object?>{'id': 'llama-3.3-70b-versatile', 'active': false},
        <String, Object?>{'id': 'whisper-large-v3-turbo', 'active': true},
        <String, Object?>{'id': 'canopylabs/orpheus-v1-english'},
        <String, Object?>{'id': 'meta-llama/llama-prompt-guard-2-86m'},
      ]);
      expect(await provider.listModels(), <String>[
        'meta-llama/llama-4-scout-17b-16e-instruct',
        'openai/gpt-oss-20b',
      ]);
    });

    test('goes by what OpenRouter says a model writes', () async {
      Map<String, Object?> model(String id, List<String> outputs) =>
          <String, Object?>{
            'id': id,
            'architecture': <String, Object?>{'output_modalities': outputs},
          };
      final provider = await listing(<Map<String, Object?>>[
        model('openai/gpt-6-luna', <String>['text']),
        model('qwen/qwen3.8-27b:free', <String>['text']),
        // It has "image" in its name, but it writes text too.
        model('google/gemini-3.1-flash-lite-image', <String>['image', 'text']),
        model('example/pictures-only', <String>['image']),
        // Batch entries only work through OpenRouter's Batch API.
        model('openai/gpt-6-luna:batch', <String>['text']),
      ]);
      expect(await provider.listModels(), <String>[
        'google/gemini-3.1-flash-lite-image',
        'openai/gpt-6-luna',
        'qwen/qwen3.8-27b:free',
      ]);
    });

    group('free only', () {
      /// An OpenRouter model that writes [outputs], at [price] for each
      /// part of a request.
      Map<String, Object?> priced(
        String id,
        String price, {
        List<String> outputs = const <String>['text'],
      }) => <String, Object?>{
        'id': id,
        'architecture': <String, Object?>{'output_modalities': outputs},
        'pricing': <String, Object?>{
          'prompt': price,
          'completion': price,
          'request': price,
        },
      };

      // Shaped like OpenRouter's list.
      final openRouterModels = <Map<String, Object?>>[
        priced('qwen/qwen3.8-27b:free', '0'),
        priced('openrouter/free', '0'),
        // The auto router's price of -1 means it varies, not that it's free.
        priced('openrouter/auto', '-1'),
        // Music models are priced at 0 but bill per song.
        priced(
          'google/lyria-3-pro-preview',
          '0',
          outputs: <String>['text', 'audio'],
        ),
        // Stealth models are priced at 0 but aren't in the free quota.
        priced('openrouter/sherlock-alpha', '0'),
        // It only checks text for safety, so it can't chat.
        priced('nvidia/nemotron-3.5-content-safety:free', '0'),
        priced('anthropic/claude-sonnet-5.5', '0.000003'),
      ];

      test(
        "keeps only :free chat models and OpenRouter's free router",
        () async {
          final provider = await listing(openRouterModels);
          expect(await provider.listModels(freeOnly: true), <String>[
            'openrouter/free',
            'qwen/qwen3.8-27b:free',
          ]);
        },
      );

      test('a missing price is free, but a missing pricing is not', () async {
        final provider = await listing(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'z-ai/glm-5:free',
            'pricing': <String, Object?>{'prompt': '0'},
          },
          <String, Object?>{'id': 'deepseek/deepseek-v4-flash:free'},
          <String, Object?>{
            'id': 'meta-llama/llama-5-8b:free',
            'pricing': <String, Object?>{'prompt': '0', 'completion': '0.1'},
          },
        ]);
        expect(await provider.listModels(freeOnly: true), <String>[
          'z-ai/glm-5:free',
        ]);
      });

      test('is off unless asked for', () async {
        final provider = await listing(openRouterModels);
        expect(
          await provider.listModels(),
          containsAll(<String>[
            'anthropic/claude-sonnet-5.5',
            'openrouter/auto',
            'openrouter/free',
            'openrouter/sherlock-alpha',
            'qwen/qwen3.8-27b:free',
          ]),
        );
      });

      test('a list without free chat models is a bad response', () async {
        final provider = await listing(<Map<String, Object?>>[
          priced('anthropic/claude-sonnet-5.5', '0.000003'),
          priced('openrouter/auto', '-1'),
        ]);
        await expectLater(
          provider.listModels(freeOnly: true),
          throwsA(isA<BadResponseException>()),
        );
      });
    });

    test('a public list is read without a key', () async {
      final provider = await listing(
        ids(<String>['openrouter/free']),
        withKey: false,
        publicModelList: true,
      );
      expect(await provider.listModels(), <String>['openrouter/free']);
      expect(listed.headers.containsKey('authorization'), isFalse);
    });

    test('a list that needs a key fails before any request', () async {
      requests = 0;
      final provider = await listing(
        ids(<String>['gpt-6-luna']),
        withKey: false,
      );
      await expectLater(
        provider.listModels(),
        throwsA(isA<MissingApiKeyException>()),
      );
      expect(requests, 0);
    });

    test('a list without chat models is a bad response', () async {
      for (final models in <List<Map<String, Object?>>>[
        <Map<String, Object?>>[],
        ids(<String>['whisper-1', 'text-embedding-3-small']),
        <Map<String, Object?>>[
          <String, Object?>{'id': ''},
          <String, Object?>{'object': 'model'},
        ],
      ]) {
        final provider = await listing(models);
        await expectLater(
          provider.listModels(),
          throwsA(isA<BadResponseException>()),
          reason: '$models',
        );
      }
    });

    test('HTTP errors keep their usual meaning', () async {
      final provider = await listing(ids(<String>[]), statusCode: 401);
      await expectLater(
        provider.listModels(),
        throwsA(isA<InvalidApiKeyException>()),
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

    test('includes usage from the final usage-only event', () async {
      final provider = await streamingProvider(
        '${_event(<String, Object?>{'content': 'Hello'})}'
        'data: ${jsonEncode(<String, Object?>{
          'choices': <Object?>[],
          'usage': <String, Object?>{'total_tokens': 42},
        })}\n\n'
        '$_done',
      );

      expect(await ask(provider).toList(), const <AiReply>[
        AiReply(text: 'Hello'),
        AiReply(text: 'Hello', totalTokens: 42),
      ]);
      expect(
        (jsonDecode(sentBody) as Map<String, dynamic>)['stream_options'],
        <String, bool>{'include_usage': true},
      );
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
