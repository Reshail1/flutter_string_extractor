import 'dart:convert';
import 'dart:io';

import 'package:flutter_string_extractor/ai_string_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/ai_server.dart';

void main() {
  late Directory root;
  late Directory source;
  late Directory output;
  late AiServer server;

  setUp(() async {
    final temp = Directory.systemTemp.createTempSync('ai_extractor_');
    root = Directory(temp.resolveSymbolicLinksSync());
    source = Directory(p.join(root.path, 'lib'))..createSync();
    output = Directory(p.join(root.path, 'translations'));
    server = await AiServer.start((request) {
      final input = request.input;
      final messages = input['messages'] as Map<String, dynamic>;
      if (input['task'] == 'classify') {
        return {
          'selected_ids': [
            for (final e in messages.entries)
              if (!e.value.toString().startsWith('https:')) e.key,
          ],
        };
      }
      return {
        'translations': {
          for (final e in messages.entries)
            e.key: '${input['target_language']}: ${e.value}',
        },
      };
    });
  });
  tearDown(() async {
    await server.close();
    root.deleteSync(recursive: true);
  });

  void writeSource(String code, [String name = 'app.dart']) {
    final file = File(p.join(source.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(code);
  }

  void catalog(String locale, Map<String, dynamic> contents) {
    output.createSync(recursive: true);
    File(p.join(output.path, '$locale.json'))
        .writeAsStringSync(jsonEncode(contents));
  }

  Map<String, dynamic> read(String locale) =>
      jsonDecode(File(p.join(output.path, '$locale.json')).readAsStringSync())
          as Map<String, dynamic>;

  Future<AiExtractionResult> run({
    List<String> languages = const ['de', 'fr'],
    bool dryRun = false,
    bool acceptAi = true,
    int maxRequests = 100,
    List<String> exclude = const [],
    String? sourceArb,
  }) => AiStringExtractor.extract(
    source.path,
    output.path,
    provider: AiProvider.openai,
    languages: languages,
    apiKey: 'test-secret-key',
    client: server.client(AiProvider.openai),
    dryRun: dryRun,
    acceptAi: acceptAi,
    maxRequests: maxRequests,
    exclude: exclude,
    sourceArb: sourceArb,
  );

  test('selects unmarked text, keeps marked keys, and translates every locale', () async {
    const code =
        "void f() { Text('Welcome'); 'settings.title'.tr; final url = 'https://example.com'; }";
    writeSource(code);
    final result = await run();
    expect(read('en'), {
      'Welcome': 'Welcome',
      'settings.title': 'settings.title',
    });
    expect(read('de'), {
      'Welcome': 'de: Welcome',
      'settings.title': 'de: settings.title',
    });
    expect(read('fr'), {
      'Welcome': 'fr: Welcome',
      'settings.title': 'fr: settings.title',
    });
    expect(result.translatedCount, 4);
    expect(File(p.join(source.path, 'app.dart')).readAsStringSync(), code);
    expect(server.requests, hasLength(3));
  });

  test(
    'retains human edits, nested values, and stale keys on reruns',
    () async {
      writeSource(
        "void f() { Text('Welcome'); 'settings.title'.tr; 'settings.subtitle'.tr; }",
      );
      catalog('en', {
        'settings': {'title': 'Settings', 'subtitle': 'Preferences'},
      });
      catalog('de', {
        'Welcome': 'Willkommen',
        'settings': {'title': 'Einstellungen'},
        'old': 'Alt',
      });
      final result = await run(languages: ['de']);
      expect(read('de'), {
        'Welcome': 'Willkommen',
        'settings': {'title': 'Einstellungen', 'subtitle': 'de: Preferences'},
        'old': 'Alt',
      });
      expect(result.translatedCount, 1);
      server.requests.clear();
      await run(languages: ['de']);
      expect(server.requests, isEmpty);
    },
  );

  test('dry run scans without consent, keys, network, or writes', () async {
    writeSource("void f() { Text('Welcome'); }");
    final result = await AiStringExtractor.extract(
      source.path,
      output.path,
      provider: AiProvider.gemini,
      languages: ['pt_BR'],
      dryRun: true,
    );
    expect(result.messages, {'Welcome': 'Welcome'});
    expect(jsonDecode(result.previewJson)['languages'], ['pt-br']);
    expect(result.requestCount, 0);
    expect(output.existsSync(), isFalse);
  });

  test('requires informed opt-in before calling a provider', () async {
    writeSource("void f() { Text('Welcome'); }");
    await expectLater(run(acceptAi: false), throwsArgumentError);
    expect(server.requests, isEmpty);
    expect(output.existsSync(), isFalse);
  });

  test('filters obvious credentials without printing their values', () async {
    writeSource(
      "void f() { Text('Welcome'); final token = 'sk-abcdefghijklmnopqrstuvwxyz123456'; final active = 'test-secret-key'; }",
    );
    final result = await run(languages: ['de']);
    expect(read('en'), {'Welcome': 'Welcome'});
    expect(
      server.requests.every(
        (r) =>
            !jsonEncode(r.body)
                .contains('sk-abcdefghijklmnopqrstuvwxyz123456') &&
            !jsonEncode(r.body).contains('test-secret-key'),
      ),
      isTrue,
    );
    expect(
      result.warnings.join(),
      isNot(contains('abcdefghijklmnopqrstuvwxyz')),
    );
    expect(result.warnings.join(), contains('credential'));
  });

  test(
    'rejects unsafe locales before requests or directory creation',
    () async {
      writeSource("void f() { Text('Welcome'); }");
      for (final locale in ['../outside', 'de/fr', '', 'en', 'EN', 'de.json']) {
        await expectLater(run(languages: [locale]), throwsArgumentError);
      }
      expect(server.requests, isEmpty);
      expect(output.existsSync(), isFalse);
    },
  );

  test('validates every destination catalog before making requests', () async {
    writeSource("void f() { Text('Welcome'); }");
    catalog('de', {'Keep': 'Sicher'});
    File(p.join(output.path, 'fr.json')).writeAsStringSync('[]');
    await expectLater(run(), throwsFormatException);
    expect(server.requests, isEmpty);
    expect(read('de'), {'Keep': 'Sicher'});
    expect(File(p.join(output.path, 'en.json')).existsSync(), isFalse);
  });

  test('rejects symlink destinations before making requests', () async {
    writeSource("void f() { Text('Welcome'); }");
    output.createSync();
    final other = File(p.join(root.path, 'private.json'))
      ..writeAsStringSync('{}');
    try {
      Link(p.join(output.path, 'de.json')).createSync(other.path);
    } on FileSystemException {
      markTestSkipped('Symlink creation unavailable');
      return;
    }
    await expectLater(
      run(languages: ['de']),
      throwsA(isA<FileSystemException>()),
    );
    expect(server.requests, isEmpty);
    expect(other.readAsStringSync(), '{}');
  });

  test(
    'rejects existing files used as output parents before requests',
    () async {
      writeSource("void f() { Text('Welcome'); }");
      File(output.path).writeAsStringSync('Keep this file');
      await expectLater(
        run(languages: ['de']),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        run(languages: ['de'], dryRun: true),
        throwsA(isA<FileSystemException>()),
      );
      expect(server.requests, isEmpty);
      expect(File(output.path).readAsStringSync(), 'Keep this file');
    },
  );

  test(
    'never overwrites an imported catalog used as a target output',
    () async {
      writeSource('void f() {}');
      catalog('de', {'hello': 'Hello', '@@locale': 'en'});
      await expectLater(
        run(languages: ['de'], sourceArb: p.join(output.path, 'de.json')),
        throwsArgumentError,
      );
      expect(server.requests, isEmpty);
      expect(read('de')['@@locale'], 'en');
    },
  );

  test('batches large scans and respects explicit exclusions', () async {
    writeSource(
      "void f() { ${List.generate(45, (i) => "Text('Message $i');").join()} }",
    );
    writeSource("void f() { Text('Excluded'); }", 'ignored/a.dart');
    writeSource("void f() { Text('Generated'); }", 'model.g.dart');
    final result = await run(languages: ['de'], exclude: ['ignored/**']);
    expect(result.filesScanned, 1);
    expect(read('de'), hasLength(45));
    expect(server.requests, hasLength(6));
    expect(
      server.requests.every((r) => (r.input['messages'] as Map).length <= 20),
      isTrue,
    );
  });

  test(
    'project-root scanning skips vendored SDKs and dependency caches',
    () async {
      writeSource("void f() { Text('Welcome'); }");
      for (final directory in [
        '.fvm',
        '.gradle',
        '.symlinks',
        'node_modules',
        'Pods',
      ]) {
        writeSource(
          'This is invalid Dart and must never be parsed',
          '$directory/vendor.dart',
        );
      }
      final result = await run(dryRun: true);
      expect(result.filesScanned, 1);
      expect(result.messages, {'Welcome': 'Welcome'});
    },
  );

  test(
    'preserves a catalog edited while provider requests are running',
    () async {
      writeSource("void f() { 'Welcome'.tr; }");
      catalog('de', {'Keep': 'Sicher'});
      await server.close();
      server = await AiServer.start((_) {
        catalog('de', {'Keep': 'Edited during translation'});
        return {
          'translations': {'0': 'Willkommen'},
        };
      });
      await expectLater(
        run(languages: ['de']),
        throwsA(isA<FileSystemException>()),
      );
      expect(read('de'), {'Keep': 'Edited during translation'});
      expect(File(p.join(output.path, 'en.json')).existsSync(), isFalse);
    },
  );

  test(
    'request limit prevents further charges and leaves catalogs unchanged',
    () async {
      writeSource("void f() { Text('Welcome'); }");
      catalog('de', {'Keep': 'Sicher'});
      await expectLater(
        run(languages: ['de'], maxRequests: 1),
        throwsA(isA<AiException>()),
      );
      expect(server.requests, hasLength(1));
      expect(read('de'), {'Keep': 'Sicher'});
      expect(File(p.join(output.path, 'en.json')).existsSync(), isFalse);
    },
  );

  test('unknown model-selected IDs abort before writing files', () async {
    writeSource("void f() { Text('Welcome'); }");
    await server.close();
    server = await AiServer.start(
      (_) => {
        'selected_ids': ['../../outside'],
      },
    );
    await expectLater(run(), throwsA(isA<AiException>()));
    expect(output.existsSync(), isFalse);
  });

  test(
    'a provider error during a later language leaves all files unchanged',
    () async {
      writeSource("void f() { 'Welcome'.tr; }");
      catalog('de', {'Keep': 'Sicher'});
      await server.close();
      server = await AiServer.start((request) {
        if (request.input['target_language'] == 'fr') {
          server.statusCode = 429;
          return {'error': 'quota'};
        }
        return {
          'translations': {'0': 'Willkommen'},
        };
      });
      await expectLater(run(), throwsA(isA<AiException>()));
      expect(read('de'), {'Keep': 'Sicher'});
      expect(File(p.join(output.path, 'en.json')).existsSync(), isFalse);
    },
  );

  for (final invalid in [
    {'translations': <String, dynamic>{}},
    {
      'translations': {'0': 'Hallo', 'extra': 'Unexpected'},
    },
    {
      'translations': {'0': 42},
    },
    {
      'translations': {'0': ''},
    },
    {
      'translations': {'0': 'Hallo {person}'},
    },
  ]) {
    test(
      'rejects missing, extra, non-string or broken-placeholder translations $invalid',
      () async {
        writeSource("void f() { 'Hello {name}'.tr; }");
        await server.close();
        server = await AiServer.start((_) => invalid);
        await expectLater(run(languages: ['de']), throwsA(isA<AiException>()));
        expect(output.existsSync(), isFalse);
      },
    );
  }

  test('preserves common placeholder syntaxes and Unicode', () async {
    writeSource(
      r"void f() { r'Hello {name}, @count, %1$s, %d, ${price}'.tr; Text('مرحبا 👋'); }",
    );
    await run(languages: ['ar']);
    expect(
      read('ar')[r'Hello {name}, @count, %1$s, %d, ${price}'],
      r'ar: Hello {name}, @count, %1$s, %d, ${price}',
    );
    expect(read('ar')['مرحبا 👋'], 'ar: مرحبا 👋');
  });

  test('ordinary percentages are not treated as format placeholders', () async {
    writeSource("void f() { 'Save 20% today'.tr; }");
    await server.close();
    server = await AiServer.start(
      (_) => {
        'translations': {'0': 'Heute 20% sparen'},
      },
    );
    await run(languages: ['de']);
    expect(read('de'), {'Save 20% today': 'Heute 20% sparen'});
  });

  for (final corrupted in [
    'Preis: {preis, number, currency}',
    'Preis: kostenlos',
    'Preis: {price, number}',
    'Preis: {price, number, currency} {price, number, currency}',
  ]) {
    test('rejects changed typed ICU placeholders: $corrupted', () async {
      writeSource("void f() { 'Price: {price, number, currency}'.tr; }");
      await server.close();
      server = await AiServer.start(
        (_) => {
          'translations': {'0': corrupted},
        },
      );
      await expectLater(run(languages: ['de']), throwsA(isA<AiException>()));
      expect(output.existsSync(), isFalse);
    });
  }

  test('keeps typed ICU and real printf placeholders in valid translations', () async {
    writeSource(
      r"void f() { r'Price: {price, number}; {price, number, currency}; %s; %1$s; %02d; %.2f'.tr; }",
    );
    await server.close();
    server = await AiServer.start(
      (_) => {
        'translations': {
          '0': r'Preis: {price, number}; {price, number, currency}; %s; %1$s; %02d; %.2f',
        },
      },
    );
    await run(languages: ['de']);
    expect(
      read(
        'de',
      )[r'Price: {price, number}; {price, number, currency}; %s; %1$s; %02d; %.2f'],
      r'Preis: {price, number}; {price, number, currency}; %s; %1$s; %02d; %.2f',
    );
  });

  test('rejects removed real printf placeholders', () async {
    writeSource(r"void f() { r'Hello %s, count %1$d'.tr; }");
    await server.close();
    server = await AiServer.start(
      (_) => {
        'translations': {'0': 'Hallo, Anzahl'},
      },
    );
    await expectLater(run(languages: ['de']), throwsA(isA<AiException>()));
    expect(output.existsSync(), isFalse);
  });

  test(
    'imports source values, diagnoses ICU, and skips dynamic expressions',
    () async {
      writeSource(r"void f(String name) { Text('Hi $name'); 'welcome'.tr; }");
      final arb = File(p.join(root.path, 'app_en.arb'))
        ..writeAsStringSync(
          jsonEncode({
            '@@locale': 'en',
            'welcome': 'Hello {name}',
            'items': '{count, plural, one{One item} other{{count} items}}',
          }),
        );
      final result = await run(languages: ['de'], sourceArb: arb.path);
      expect(
        read('en')['items'],
        '{count, plural, one{One item} other{{count} items}}',
      );
      expect(read('de'), {'welcome': 'de: Hello {name}'});
      expect(result.warnings.join(), contains('ICU'));
      expect(result.warnings.join(), contains('dynamic'));
    },
  );
}
