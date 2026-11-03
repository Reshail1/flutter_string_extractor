import 'package:flutter_string_extractor/src/ai_client.dart';
import 'package:test/test.dart';

import 'support/ai_server.dart';

void main() {
  late AiServer server;
  tearDown(() => server.close());

  for (final provider in AiProvider.values) {
    test(
      '$provider sends JSON with the selected model and authenticates',
      () async {
        server = await AiServer.start((request) {
          expect(request.input, {
            'messages': {'0': 'Hello'},
          });
          expect(request.uri.scheme, 'https');
          expect(request.uri.query, isEmpty);
          if (provider == AiProvider.gemini) {
            expect(
              request.uri.path,
              '/v1beta/models/custom-small:generateContent',
            );
            expect(request.headers.value('x-goog-api-key'), 'test-secret-key');
            expect(
              request.body['generationConfig']['responseMimeType'],
              'application/json',
            );
          } else {
            expect(request.body['model'], 'custom-small');
            expect(
              request.headers.value('authorization'),
              'Bearer test-secret-key',
            );
            expect(
              request.uri.path,
              provider == AiProvider.openai ? '/v1/responses' : '/v1/messages',
            );
          }
          if (provider == AiProvider.openai)
            expect(request.body['store'], isFalse);
          return {
            'translations': {'0': 'Hallo'},
          };
        });
        final client = server.client(provider, model: 'custom-small');
        expect(
          await client.complete('Translate and return JSON.', {
            'messages': {'0': 'Hello'},
          }),
          {
            'translations': {'0': 'Hallo'},
          },
        );
      },
    );

    test('$provider hides error response bodies and keys', () async {
      server = await AiServer.start((_) => 'test-secret-key private message');
      server.statusCode = 401;
      server.rawResponse = true;
      await expectLater(
        server.client(provider).complete('JSON', {}),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('401') &&
                !e.toString().contains('test-secret-key') &&
                !e.toString().contains('private message'),
          ),
        ),
      );
    });

    test('$provider rejects incomplete or blocked output', () async {
      server = await AiServer.start(
        (_) => switch (provider) {
          AiProvider.openai => '{"status":"incomplete","output":[]}',
          AiProvider.claude =>
            '{"stop_reason":"max_tokens","content":[{"type":"text","text":"{}"}]}',
          AiProvider.gemini =>
            '{"candidates":[{"finishReason":"SAFETY","content":{"parts":[{"text":"{}"}]}}]}',
        },
      );
      server.rawResponse = true;
      await expectLater(
        server.client(provider).complete('JSON', {}),
        throwsA(isA<AiException>()),
      );
    });
  }

  test('does not follow redirects or forward credentials', () async {
    server = await AiServer.start((_) => {});
    server.statusCode = 307;
    server.redirect = 'http://127.0.0.1:${server.server.port}/stolen';
    await expectLater(
      server.client(AiProvider.openai).complete('JSON', {}),
      throwsA(isA<AiException>()),
    );
    expect(server.requests, hasLength(1));
  });

  test('bounds response size before decoding', () async {
    server = await AiServer.start((_) => 'x' * (1024 * 1024 + 1));
    server.rawResponse = true;
    await expectLater(
      server.client(AiProvider.openai).complete('JSON', {}),
      throwsA(isA<AiException>()),
    );
  });

  test('times out a slow response without retries', () async {
    server = await AiServer.start((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return {};
    });
    await expectLater(
      server
          .client(AiProvider.openai, timeout: const Duration(milliseconds: 40))
          .complete('JSON', {}),
      throwsA(isA<AiException>()),
    );
    expect(server.requests, hasLength(1));
  });

  test('rejects invalid JSON without echoing provider content', () async {
    server = await AiServer.start((_) => 'sensitive invalid JSON');
    server.rawResponse = true;
    await expectLater(
      server.client(AiProvider.openai).complete('JSON', {}),
      throwsA(
        predicate(
          (e) => e is AiException && !e.toString().contains('sensitive'),
        ),
      ),
    );
  });
}
