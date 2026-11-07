import 'dart:convert';
import 'dart:io';

import 'package:flutter_string_extractor/ai_string_extractor.dart';
import 'package:flutter_string_extractor/flutter_string_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/ai_server.dart';

void main() {
  late Directory root;
  late Directory source;
  late Directory output;
  late AiServer server;
  setUp(() async {
    final temp = Directory.systemTemp.createTempSync('context_translation_');
    root = Directory(temp.resolveSymbolicLinksSync());
    source = Directory(p.join(root.path, 'lib'))..createSync();
    output = Directory(p.join(root.path, 'translations'));
    server = await AiServer.start(
      (_) => {
        'translations': {'0': 'Buchen'},
      },
    );
  });
  tearDown(() async {
    await server.close();
    root.deleteSync(recursive: true);
  });
  void write(String code, [String name = 'booking.dart']) =>
      File(p.join(source.path, name)).writeAsStringSync(code);
  Future<AiExtractionResult> run({
    String projectContext = '',
    String? sourceArb,
    AiProvider provider = AiProvider.openai,
    bool dryRun = false,
    String apiKey = 'test-secret-key',
  }) => AiStringExtractor.extract(
    source.path,
    output.path,
    provider: provider,
    languages: ['de'],
    acceptAi: true,
    apiKey: apiKey,
    client: server.client(provider),
    projectContext: projectContext,
    sourceArb: sourceArb,
    dryRun: dryRun,
  );

  test(
    'filters the trimmed credential that the client authenticates with',
    () async {
      write("void f() { Text('test-secret-key'); }");
      final result = await run(apiKey: '  test-secret-key  ', dryRun: true);
      expect(result.messages, isEmpty);
      expect(server.requests, isEmpty);
      expect(output.existsSync(), isFalse);
    },
  );

  test(
    'scanner supplies bounded relative UI context without neighboring literals',
    () {
      write('''class BookingScreen {
  void build() {
    const hidden = 'sk-abcdefghijklmnopqrstuvwxyz123456';
    Text('Book');
    IconButton(tooltip: 'Book');
    Text('Book');
  }
}''');
      final scan = FlutterStringExtractor.extractStrings(
        source.path,
        p.join(output.path, 'en.json'),
        allStrings: true,
        dryRun: true,
      );
      final contexts = scan.contexts['Book']!;
      expect(contexts, hasLength(2));
      expect(contexts.first, contains('booking.dart:4'));
      expect(contexts.first, contains('BookingScreen'));
      expect(contexts.first, contains('Text'));
      expect(contexts.last, contains('tooltip'));
      expect(contexts.join(), isNot(contains(root.path)));
      expect(contexts.join(), isNot(contains('abcdefghijklmnopqrstuvwxyz')));
    },
  );

  test('classification and translation receive domain and UI intent', () async {
    write("class FlightBooking { void build() { Text('Book'); } }");
    await server.close();
    server = await AiServer.start((request) {
      final input = request.input;
      final contexts = input['message_context'] as Map<String, dynamic>?;
      final contextual =
          input['project_context'] ==
              'Flight reservations; Book means reserve a seat.' &&
          contexts?['0']['key'] == 'Book' &&
          jsonEncode(contexts).contains('FlightBooking');
      if (input['task'] == 'classify') {
        return {
          'selected_ids': contextual ? ['0'] : [],
        };
      }
      return {
        'translations': {'0': contextual ? 'Buchen' : 'Buch'},
      };
    });
    await run(
      projectContext: 'Flight reservations; Book means reserve a seat.',
    );
    expect(
      jsonDecode(File(p.join(output.path, 'de.json')).readAsStringSync()),
      {'Book': 'Buchen'},
    );
    expect(server.requests, hasLength(2));
  });

  test('catalog descriptions and named IDs disambiguate source text', () async {
    write("void f() { 'booking.action'.tr; }");
    final arb = File(p.join(root.path, 'app_en.arb'))
      ..writeAsStringSync(
        jsonEncode({
          'booking.action': 'Book',
          '@booking.action': {
            'description': 'Action: reserve a flight, not a printed book.',
          },
        }),
      );
    await server.close();
    server = await AiServer.start((request) {
      final context = request.input['message_context']['0'];
      final appropriate =
          context['key'] == 'booking.action' &&
          jsonEncode(context).contains('reserve a flight');
      return {
        'translations': {'0': appropriate ? 'Buchen' : 'Buch'},
      };
    });
    await run(sourceArb: arb.path);
    expect(
      jsonDecode(File(p.join(output.path, 'de.json')).readAsStringSync()),
      {'booking.action': 'Buchen'},
    );
  });

  test('bounds key hints while preserving the full catalog key', () async {
    final longKey = 'booking.${'a' * 900}';
    write("void f() { '$longKey'.tr; }");
    final arb = File(p.join(root.path, 'app_en.arb'))
      ..writeAsStringSync(jsonEncode({longKey: 'Book'}));
    await run(sourceArb: arb.path);
    expect(
      (server.requests.single.input['message_context']['0']['key'] as String)
          .length,
      lessThanOrEqualTo(160),
    );
    expect(
      jsonDecode(File(p.join(output.path, 'de.json')).readAsStringSync()),
      {longKey: 'Buchen'},
    );
  });

  test(
    'distinct named keys preserve different meanings of the same English text',
    () async {
      write('void f() {}');
      final arb = File(p.join(root.path, 'app_en.arb'))
        ..writeAsStringSync(
          jsonEncode({
            'bookFlight': 'Book',
            '@bookFlight': {'description': 'Verb: reserve a flight.'},
            'bookNoun': 'Book',
            '@bookNoun': {'description': 'Noun: a printed book.'},
          }),
        );
      await server.close();
      server = await AiServer.start(
        (request) => {
          'translations': {
            for (final entry
                in (request.input['message_context'] as Map).entries)
              entry.key: entry.value['key'] == 'bookFlight' ? 'Buchen' : 'Buch',
          },
        },
      );
      await run(sourceArb: arb.path);
      expect(
        jsonDecode(File(p.join(output.path, 'de.json')).readAsStringSync()),
        {'bookFlight': 'Buchen', 'bookNoun': 'Buch'},
      );
    },
  );

  test(
    'filters possible credentials in context and catalog descriptions',
    () async {
      write("class sk_abc { void f() { 'book'.tr; } }");
      final arb = File(p.join(root.path, 'app_en.arb'))
        ..writeAsStringSync(
          jsonEncode({
            'book': 'Book',
            '@book': {
              'description': 'api_key=sk-abcdefghijklmnopqrstuvwxyz123456',
            },
          }),
        );
      await run(sourceArb: arb.path);
      expect(server.requests, hasLength(1));
      expect(
        jsonEncode(server.requests.single.body),
        isNot(contains('abcdefghijklmnopqrstuvwxyz')),
      );
    },
  );

  test(
    'rejects secret or oversized project context without requests or writes',
    () async {
      write("void f() { 'Book'.tr; }");
      for (final context in [
        'api_key=sk-abcdefghijklmnopqrstuvwxyz123456',
        'x' * 2001,
      ]) {
        await expectLater(run(projectContext: context), throwsArgumentError);
      }
      expect(server.requests, isEmpty);
      expect(output.existsSync(), isFalse);
    },
  );

  test(
    'local extraction carries context end to end without a cloud key',
    () async {
      write("void f() { 'Book'.tr; }");
      final result = await run(
        provider: AiProvider.local,
        projectContext: 'Flight reservations.',
      );
      expect(result.translatedCount, 1);
      expect(server.requests.single.uri.host, '127.0.0.1');
      expect(
        server.requests.single.input['project_context'],
        'Flight reservations.',
      );
    },
  );

  for (final translated in [
    'Hallo {name}\nWeiter?',
    'Hallo <i>{name}</i>\nWeiter?',
    'Hallo <b>{name}</b> Weiter?',
  ]) {
    test('rejects changed markup or line breaks: $translated', () async {
      write(r"void f() { 'Hello <b>{name}</b>\nContinue?'.tr; }");
      await server.close();
      server = await AiServer.start(
        (_) => {
          'translations': {'0': translated},
        },
      );
      await expectLater(run(), throwsA(isA<AiException>()));
      expect(output.existsSync(), isFalse);
    });
  }

  test(
    'accepts natural translation with intact markup, layout and placeholders',
    () async {
      write(r"void f() { 'Hello <b>{name}</b>\nContinue?'.tr; }");
      await server.close();
      server = await AiServer.start(
        (_) => {
          'translations': {'0': 'Hallo <b>{name}</b>\nWeiter?'},
        },
      );
      await run();
      expect(
        jsonDecode(File(p.join(output.path, 'de.json')).readAsStringSync()),
        {'Hello <b>{name}</b>\nContinue?': 'Hallo <b>{name}</b>\nWeiter?'},
      );
    },
  );
}
