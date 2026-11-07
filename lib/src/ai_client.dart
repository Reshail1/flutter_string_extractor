import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Low-cost defaults can be overridden as provider catalogs change.
enum AiProvider {
  openai('OPENAI_API_KEY', 'gpt-6-luna'),
  claude('ANTHROPIC_API_KEY', 'claude-haiku-5-5'),
  gemini('GEMINI_API_KEY', 'gemini-3.5-flash-lite'),
  local('LOCAL_AI_API_KEY', '');

  const AiProvider(this.environmentKey, this.defaultModel);
  final String environmentKey;
  final String defaultModel;
}

/// A sanitized failure: provider bodies may contain private source text or keys.
class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => 'AI error: $message';
}

/// Uses fixed cloud APIs or a loopback chat API. No redirects or retries.
class AiClient {
  AiClient({
    required this.provider,
    String apiKey = '',
    String? model,
    String? baseUrl,
    HttpClient? httpClient,
    Duration? timeout,
  }) : _apiKey = apiKey.trim(),
       model = model ?? provider.defaultModel,
       _localUri = _localEndpoint(provider, baseUrl),
       timeout =
           timeout ??
           Duration(seconds: provider == AiProvider.local ? 180 : 60),
       _http = httpClient ?? HttpClient(),
       _ownsClient = httpClient == null {
    if ((_apiKey.isEmpty && provider != AiProvider.local) ||
        (_apiKey.isNotEmpty && !RegExp(r'^[\x21-\x7e]+$').hasMatch(_apiKey))) {
      throw ArgumentError(
        'Set a valid ${provider.environmentKey} environment variable.',
      );
    }
    if (provider == AiProvider.local && this.model.isEmpty) {
      throw ArgumentError(
        'Local AI requires --model with an installed model ID.',
      );
    }
    final modelPattern = provider == AiProvider.local
        ? r'^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,255}$'
        : r'^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$';
    if (!RegExp(modelPattern).hasMatch(this.model)) {
      throw ArgumentError('Invalid AI model ID.');
    }
    if (this.timeout <= Duration.zero) {
      throw ArgumentError('AI timeout must be positive.');
    }
  }

  final AiProvider provider;
  final String model;
  final String _apiKey;
  final HttpClient _http;
  final bool _ownsClient;
  final Duration timeout;
  final Uri? _localUri;

  static Uri? _localEndpoint(AiProvider provider, String? baseUrl) {
    if (provider != AiProvider.local) {
      if (baseUrl != null) {
        throw ArgumentError(
          '--ai-base-url is only supported with --ai-provider local.',
        );
      }
      return null;
    }
    final uri = Uri.tryParse(baseUrl ?? 'http://127.0.0.1:11434/v1');
    final host = uri?.host
        .replaceAll('[', '')
        .replaceAll(']', '')
        .toLowerCase();
    final loopback =
        host == 'localhost' ||
        (host != null && InternetAddress.tryParse(host)?.isLoopback == true);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        !loopback ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
        'Local AI base URL must use HTTP(S) on localhost or a loopback IP, without credentials, query parameters, or fragments.',
      );
    }
    final prefix = uri.path.isEmpty || uri.path == '/'
        ? '/v1'
        : uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: '$prefix/chat/completions');
  }

  Future<Map<String, dynamic>> complete(
    String instructions,
    Map<String, dynamic> input,
  ) async {
    final payload = jsonEncode(input);
    final uri = switch (provider) {
      AiProvider.openai => Uri.https('api.openai.com', '/v1/responses'),
      AiProvider.claude => Uri.https('api.anthropic.com', '/v1/messages'),
      AiProvider.gemini => Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$model:generateContent',
      ),
      AiProvider.local => _localUri!,
    };
    final body = switch (provider) {
      AiProvider.openai => {
        'model': model,
        'store': false,
        'instructions': instructions,
        'input': payload,
        'max_output_tokens': 8192,
        'text': {
          'format': {'type': 'json_object'},
        },
      },
      AiProvider.claude => {
        'model': model,
        'max_tokens': 8192,
        'system': instructions,
        'messages': [
          {'role': 'user', 'content': payload},
        ],
      },
      AiProvider.gemini => {
        'systemInstruction': {
          'parts': [
            {'text': instructions},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': payload},
            ],
          },
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'maxOutputTokens': 8192,
        },
      },
      AiProvider.local => {
        'model': model,
        'messages': [
          {'role': 'system', 'content': instructions},
          {'role': 'user', 'content': payload},
        ],
        'response_format': {'type': 'json_object'},
        'temperature': 0,
        'max_tokens': 4096,
        'stream': false,
      },
    };
    HttpClientRequest? request;
    var expired = false;
    Future<Map<String, dynamic>> send() async {
      final outgoing = await _http.postUrl(uri);
      request = outgoing;
      if (expired) {
        outgoing.abort();
        throw AiException('Request timed out.');
      }
      outgoing.followRedirects = false;
      outgoing.headers.contentType = ContentType.json;
      if (provider == AiProvider.gemini) {
        outgoing.headers.set('x-goog-api-key', _apiKey);
      } else if (_apiKey.isNotEmpty) {
        outgoing.headers.set('authorization', 'Bearer $_apiKey');
      }
      if (provider == AiProvider.claude) {
        outgoing.headers.set('anthropic-version', '2026-10-21');
      }
      outgoing.write(jsonEncode(body));
      final response = await outgoing.close();
      if (response.statusCode != 200) {
        throw AiException(
          '${provider.name} returned HTTP ${response.statusCode}. Check the key, model access, quota, and provider status. No automatic retry was made.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw AiException('Provider response exceeded the 1 MiB limit.');
        }
        bytes.addAll(chunk);
      }
      final envelope = jsonDecode(utf8.decode(bytes));
      if (envelope is! Map<String, dynamic>) throw const FormatException();
      final text = _responseText(envelope);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    }

    try {
      return await send().timeout(
        timeout,
        onTimeout: () {
          expired = true;
          request?.abort();
          throw AiException(
            '${provider.name} request timed out; no automatic retry was made.',
          );
        },
      );
    } on AiException {
      rethrow;
    } on IOException {
      throw AiException(
        'Could not reach ${provider.name}. Check your network connection.',
      );
    } catch (_) {
      throw AiException(
        '${provider.name} returned an invalid JSON response. No response content was logged.',
      );
    } finally {
      request?.abort();
    }
  }

  String _responseText(Map<String, dynamic> response) {
    final parts = <String>[];
    switch (provider) {
      case AiProvider.openai:
        if (response['status'] != 'completed') {
          throw AiException('OpenAI response was incomplete or refused.');
        }
        for (final item in response['output'] as List) {
          if (item['type'] != 'message') continue;
          for (final content in item['content'] as List) {
            if (content['type'] == 'refusal') {
              throw AiException('OpenAI refused the request.');
            }
            if (content['type'] == 'output_text') {
              parts.add(content['text'] as String);
            }
          }
        }
      case AiProvider.claude:
        if (response['stop_reason'] != 'end_turn') {
          throw AiException('Claude response was incomplete or refused.');
        }
        for (final content in response['content'] as List) {
          if (content['type'] == 'text') parts.add(content['text'] as String);
        }
      case AiProvider.gemini:
        final candidates = response['candidates'] as List;
        if (candidates.length != 1 ||
            candidates.first['finishReason'] != 'STOP') {
          throw AiException('Gemini response was incomplete or blocked.');
        }
        for (final part in candidates.first['content']['parts'] as List) {
          if (part['text'] is String && part['thought'] != true) {
            parts.add(part['text'] as String);
          }
        }
      case AiProvider.local:
        final choices = response['choices'] as List;
        if (choices.length != 1 || choices.first['finish_reason'] != 'stop') {
          throw AiException(
            'Local model response was incomplete or refused. Try a JSON-capable model with a larger context window.',
          );
        }
        final message = choices.first['message'];
        if (message['refusal'] != null || message['content'] is! String) {
          throw AiException('Local model returned no usable translation text.');
        }
        parts.add(message['content'] as String);
    }
    if (parts.isEmpty) throw AiException('Provider returned no text.');
    return parts.join();
  }

  void close() {
    if (_ownsClient) _http.close(force: true);
  }
}
