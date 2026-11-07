import 'dart:convert';
import 'dart:io';

import 'package:flutter_string_extractor/src/ai_client.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late AiClient client;
  late Object response;
  late int status;
  late String? authorization;
  late Map<String, dynamic> requestBody;
  late String path;
  var requests = 0;

  setUp(() async {
    requests = 0;
    status = 200;
    response = {
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {
            'role': 'assistant',
            'content': '{"translations":{"0":"Buchen"}}',
          },
        },
      ],
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      authorization = request.headers.value('authorization');
      path = request.uri.path;
      requestBody = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      request.response.statusCode = status;
      if (status == 307) {
        request.response.headers.set('location', 'https://example.com/steal');
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = AiClient(
      provider: AiProvider.local,
      model: 'organization/small-model:latest',
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
    );
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('uses local chat completions and requires no API key', () async {
    final result = await client.complete('Translate UI text to JSON.', {
      'messages': {'0': 'Book'},
    });
    expect(result, {
      'translations': {'0': 'Buchen'},
    });
    expect(path, '/v1/chat/completions');
    expect(authorization, isNull);
    expect(requestBody['model'], 'organization/small-model:latest');
    expect(requestBody['messages'], [
      {'role': 'system', 'content': 'Translate UI text to JSON.'},
      {'role': 'user', 'content': '{"messages":{"0":"Book"}}'},
    ]);
    expect(requestBody['response_format'], {'type': 'json_object'});
    expect(requestBody['stream'], isFalse);
    expect(requestBody['temperature'], 0);
    expect(client.timeout, greaterThan(const Duration(seconds: 60)));
    expect(requests, 1);
  });

  test('supports localhost, a custom API prefix, and explicit local authentication', () async {
    client.close();
    client = AiClient(
      provider: AiProvider.local,
      model: 'small',
      apiKey: 'local-only-key',
      baseUrl: 'http://localhost:${server.port}/api/v1/',
    );
    await client.complete('JSON', {});
    expect(path, '/api/v1/chat/completions');
    expect(authorization, 'Bearer local-only-key');
  });

  test('requires a local model instead of choosing or downloading one', () {
    expect(() => AiClient(provider: AiProvider.local), throwsArgumentError);
    expect(requests, 0);
  });

  test('keeps custom endpoints exclusive to local mode', () {
    expect(
      () => AiClient(
        provider: AiProvider.openai,
        apiKey: 'cloud-key',
        baseUrl: 'http://localhost:1234/v1',
      ),
      throwsArgumentError,
    );
    expect(requests, 0);
  });

  test(
    'rejects remote endpoints and URLs containing credentials or parameters',
    () {
      for (final url in [
        'https://example.com/v1',
        'http://192.168.1.2:1234/v1',
        'http://localhost.example.com/v1',
        'http://user:secret@localhost:1234/v1',
        'http://localhost:1234/v1?key=secret',
        'http://localhost:1234/v1#fragment',
        'file:///tmp/model',
        'not a URL',
      ]) {
        expect(
          () => AiClient(
            provider: AiProvider.local,
            model: 'small',
            baseUrl: url,
          ),
          throwsArgumentError,
        );
      }
      expect(requests, 0);
    },
  );

  test('allows IPv6 loopback URLs', () async {
    final HttpServer ipv6;
    try {
      ipv6 = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
    } on SocketException {
      markTestSkipped('IPv6 loopback unavailable');
      return;
    }
    ipv6.listen((request) async {
      await request.drain<void>();
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client.close();
    client = AiClient(
      provider: AiProvider.local,
      model: 'small',
      baseUrl: 'http://[::1]:${ipv6.port}/v1',
    );
    try {
      expect(await client.complete('JSON', {}), {
        'translations': {'0': 'Buchen'},
      });
    } finally {
      await ipv6.close(force: true);
    }
  });

  for (final finish in ['length', 'tool_calls', 'content_filter']) {
    test(
      'rejects local $finish responses before consuming translations',
      () async {
        response = {
          'choices': [
            {
              'finish_reason': finish,
              'message': {'content': '{"translations":{"0":"Buchen"}}'},
            },
          ],
        };
        await expectLater(
          client.complete('JSON', {}),
          throwsA(isA<AiException>()),
        );
        expect(requests, 1);
      },
    );
  }

  test('does not follow local redirects or try a cloud fallback', () async {
    status = 307;
    await expectLater(client.complete('JSON', {}), throwsA(isA<AiException>()));
    expect(requests, 1);
  });

  test(
    'local errors hide response content and authentication values',
    () async {
      status = 500;
      response = {'error': 'local-only-key private project text'};
      await expectLater(
        client.complete('JSON', {}),
        throwsA(
          predicate(
            (error) =>
                error is AiException &&
                !error.toString().contains('local-only-key') &&
                !error.toString().contains('private project text'),
          ),
        ),
      );
      expect(requests, 1);
    },
  );
}
