import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Low-cost defaults can be overridden as provider catalogs change.
enum AiProvider {
  openai('OPENAI_API_KEY', 'gpt-6-luna'),
  claude('ANTHROPIC_API_KEY', 'claude-haiku-5-5'),
  gemini('GEMINI_API_KEY', 'gemini-3.5-flash-lite');

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

/// Calls only the selected provider's HTTPS API. No redirects or retries.
class AiClient {
  AiClient({
    required this.provider,
    required String apiKey,
    String? model,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _apiKey = apiKey.trim(),
       model = model ?? provider.defaultModel,
       _http = httpClient ?? HttpClient(),
       _ownsClient = httpClient == null {
    if (_apiKey.isEmpty || !RegExp(r'^[\x21-\x7e]+$').hasMatch(_apiKey)) {
      throw ArgumentError(
        'Set a valid ${provider.environmentKey} environment variable.',
      );
    }
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$').hasMatch(this.model)) {
      throw ArgumentError('Invalid AI model ID.');
    }
    if (timeout <= Duration.zero)
      throw ArgumentError('AI timeout must be positive.');
  }

  final AiProvider provider;
  final String model;
  final String _apiKey;
  final HttpClient _http;
  final bool _ownsClient;
  final Duration timeout;

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
      } else {
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
        if (response['status'] != 'completed')
          throw AiException('OpenAI response was incomplete or refused.');
        for (final item in response['output'] as List) {
          if (item['type'] != 'message') continue;
          for (final content in item['content'] as List) {
            if (content['type'] == 'refusal')
              throw AiException('OpenAI refused the request.');
            if (content['type'] == 'output_text')
              parts.add(content['text'] as String);
          }
        }
      case AiProvider.claude:
        if (response['stop_reason'] != 'end_turn')
          throw AiException('Claude response was incomplete or refused.');
        for (final content in response['content'] as List) {
          if (content['type'] == 'text') parts.add(content['text'] as String);
        }
      case AiProvider.gemini:
        final candidates = response['candidates'] as List;
        if (candidates.length != 1 ||
            candidates.first['finishReason'] != 'STOP')
          throw AiException('Gemini response was incomplete or blocked.');
        for (final part in candidates.first['content']['parts'] as List) {
          if (part['text'] is String && part['thought'] != true)
            parts.add(part['text'] as String);
        }
    }
    if (parts.isEmpty) throw AiException('Provider returned no text.');
    return parts.join();
  }

  void close() {
    if (_ownsClient) _http.close(force: true);
  }
}
