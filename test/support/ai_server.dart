import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_string_extractor/src/ai_client.dart';

class AiRequest {
  AiRequest(this.uri, this.body, this.headers);
  final Uri uri;
  final Map<String, dynamic> body;
  final HttpHeaders headers;

  Map<String, dynamic> get input {
    final String text;
    if (uri.host == 'api.openai.com') {
      text = body['input'] as String;
    } else if (uri.host == 'api.anthropic.com') {
      text = body['messages'][0]['content'] as String;
    } else {
      text = body['contents'][0]['parts'][0]['text'] as String;
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }
}

/// Real HTTP and provider envelopes; only the remote destination is substituted.
class AiServer {
  AiServer._(this.server, this.handler);
  final HttpServer server;
  final FutureOr<Object> Function(AiRequest) handler;
  final requests = <AiRequest>[];
  final clients = <HttpClient>[];
  int statusCode = 200;
  String? redirect;
  bool rawResponse = false;

  static Future<AiServer> start(
    FutureOr<Object> Function(AiRequest) handler,
  ) async {
    final fixture = AiServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      handler,
    );
    fixture.server.listen(fixture._respond);
    return fixture;
  }

  AiClient client(
    AiProvider provider, {
    String? model,
    Duration timeout = const Duration(seconds: 5),
  }) {
    final transport = _LocalClient(this);
    clients.add(transport);
    return AiClient(
      provider: provider,
      apiKey: 'test-secret-key',
      model: model,
      httpClient: transport,
      timeout: timeout,
    );
  }

  Future<void> _respond(HttpRequest request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join());
    final observed = AiRequest(
      Uri.parse(request.headers.value('x-test-destination')!),
      body as Map<String, dynamic>,
      request.headers,
    );
    requests.add(observed);
    final result = await handler(observed);
    request.response.statusCode = statusCode;
    if (redirect != null) request.response.headers.set('location', redirect!);
    request.response.headers.contentType = ContentType.json;
    if (rawResponse) {
      request.response.write(result);
    } else {
      final text = jsonEncode(result);
      request.response.write(
        jsonEncode(switch (observed.uri.host) {
          'api.openai.com' => {
            'id': 'resp_test',
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {'type': 'output_text', 'text': text},
                ],
              },
            ],
          },
          'api.anthropic.com' => {
            'id': 'msg_test',
            'type': 'message',
            'role': 'assistant',
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': text},
            ],
          },
          _ => {
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'role': 'model',
                  'parts': [
                    {'text': text},
                  ],
                },
              },
            ],
          },
        }),
      );
    }
    await request.response.close();
  }

  Future<void> close() async {
    for (final client in clients) {
      client.close(force: true);
    }
    await server.close(force: true);
  }
}

class _LocalClient implements HttpClient {
  _LocalClient(this.fixture);
  final AiServer fixture;
  final HttpClient _client = HttpClient();

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    final request = await _client.postUrl(
      url.replace(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: fixture.server.port,
      ),
    );
    request.headers.set('x-test-destination', url.toString());
    return request;
  }

  @override
  void close({bool force = false}) => _client.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
