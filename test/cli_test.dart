import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory source;
  late File output;

  setUp(() {
    final temporary = Directory.systemTemp.createTempSync(
      'string_extractor_cli_',
    );
    root = Directory(temporary.resolveSymbolicLinksSync());
    source = Directory(p.join(root.path, 'lib'))..createSync();
    output = File(p.join(root.path, 'strings.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  void writeSource(String code, [String name = 'app.dart']) {
    final file = File(p.join(source.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(code);
  }

  Future<ProcessResult> run(
    List<String> args, {
    Map<String, String>? environment,
  }) => Process.run(Platform.resolvedExecutable, [
    p.absolute('bin/main.dart'),
    '-s',
    source.path,
    if (!args.contains('--ai-provider')) ...['-o', output.path],
    ...args,
  ], environment: environment);

  test(
    'AI preview reports candidates and disclaimer without writing files',
    () async {
      writeSource("void f() { Text('Welcome'); }");
      final folder = p.join(root.path, 'translations');
      final result = await run([
        '--ai-provider',
        'openai',
        '--languages',
        'de,fr',
        '--output-dir',
        folder,
        '--dry-run',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(result.stdout as String)['candidates'], {
        'Welcome': 'Welcome',
      });
      expect(jsonDecode(result.stdout as String)['languages'], ['de', 'fr']);
      expect(result.stderr, contains('AI can'));
      expect(result.stderr, contains('charges'));
      expect(result.stderr, contains('no API calls'));
      expect(Directory(folder).existsSync(), isFalse);
      expect(output.existsSync(), isFalse);
    },
  );

  test(
    'AI defaults to scanning the project root rather than only lib',
    () async {
      writeSource("void f() { Text('Inside lib'); }");
      final screen = File(p.join(root.path, 'features', 'screen.dart'));
      screen.parent.createSync();
      screen.writeAsStringSync("void f() { Text('Outside lib'); }");
      final result = await Process.run(Platform.resolvedExecutable, [
        p.absolute('bin/main.dart'),
        '--ai-provider',
        'gemini',
        '--languages',
        'de',
        '--dry-run',
      ], workingDirectory: root.path);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(result.stdout as String)['candidates'], {
        'Inside lib': 'Inside lib',
        'Outside lib': 'Outside lib',
      });
    },
  );

  test('AI requires consent before network access', () async {
    writeSource("void f() { Text('Welcome'); }");
    final result = await run(['--ai-provider', 'openai', '--languages', 'de']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('--accept-ai'));
    expect(result.stdout, isEmpty);
    expect(output.existsSync(), isFalse);
  });

  test(
    'AI malformed catalogs do not expose credential contents in diagnostics',
    () async {
      writeSource("void f() { Text('Welcome'); }");
      final folder = Directory(p.join(root.path, 'translations'))..createSync();
      File(
        p.join(folder.path, 'en.json'),
      ).writeAsStringSync('test-super-private-credential invalid json');
      final result = await run([
        '--ai-provider',
        'openai',
        '--languages',
        'de',
        '--dry-run',
        '--output-dir',
        folder.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, isNot(contains('test-super-private-credential')));
      expect(result.stdout, isEmpty);
    },
  );

  for (final provider in {
    'openai': 'OPENAI_API_KEY',
    'claude': 'ANTHROPIC_API_KEY',
    'gemini': 'GEMINI_API_KEY',
  }.entries) {
    test(
      'AI explains missing ${provider.value} without leaking credentials',
      () async {
        writeSource("void f() { Text('Welcome'); }");
        final result = await run(
          ['--ai-provider', provider.key, '--languages', 'de', '--accept-ai'],
          environment: {provider.value: ''},
        );
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains(provider.value));
        expect(result.stdout, isEmpty);
      },
    );
  }

  test('rejects AI-only options without provider selection', () async {
    final result = await run(['--languages', 'de', '--dry-run']);
    expect(result.exitCode, 64);
    expect(result.stderr, contains('--ai-provider'));
  });

  test('rejects destructive and ambiguous AI output options', () async {
    writeSource("void f() { Text('Welcome'); }");
    for (final options in [
      ['--replace'],
      ['-o', output.path],
    ]) {
      final result = await run([
        '--ai-provider',
        'openai',
        '--languages',
        'de',
        '--dry-run',
        ...options,
      ]);
      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
    }
  });

  test(
    'dry run previews merged JSON and never writes or creates directories',
    () async {
      writeSource("void f() { 'New'.tr; }");
      output.writeAsStringSync('{"Keep":"Translated"}');
      final result = await run(['--dry-run']);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(result.stdout as String), {
        'Keep': 'Translated',
        'New': 'New',
      });
      expect(output.readAsStringSync(), '{"Keep":"Translated"}');
      final missing = p.join(root.path, 'missing', 'output.json');
      final second = await run(['--dry-run', '-o', missing]);
      expect(second.exitCode, 0, reason: second.stderr.toString());
      expect(Directory(p.dirname(missing)).existsSync(), isFalse);
    },
  );

  test(
    'all-strings discovers unmarked static literals but skips directives and interpolation',
    () async {
      writeSource(r'''
import 'package:flutter/widgets.dart';
void f(String name) {
  Text("Don't forget");
  Text('Adjacent ' 'literal');
  Text("Hi $name");
  tr('Marked');
}
''');
      final result = await run(['--all-strings']);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(output.readAsStringSync()), {
        "Don't forget": "Don't forget",
        'Adjacent literal': 'Adjacent literal',
        'Marked': 'Marked',
      });
    },
  );

  test(
    'exclusions are relative glob patterns and generated files are opt-in',
    () async {
      writeSource("void f() { 'Keep'.tr; }");
      writeSource("void f() { 'Exclude'.tr; }", 'screens/exclude.dart');
      writeSource("void f() { 'Generated'.tr; }", 'model.g.dart');
      final result = await run([
        '--exclude',
        'screens/**',
        '--include-generated',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(output.readAsStringSync()), {
        'Generated': 'Generated',
        'Keep': 'Keep',
      });
    },
  );

  test('replace is explicit and removes stale translations', () async {
    writeSource("void f() { 'Hello'.tr; }");
    output.writeAsStringSync('{"Hello":"Hallo","Old":"Alt"}');
    final result = await run(['--replace']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(output.readAsStringSync()), {'Hello': 'Hello'});
  });

  test(
    'imports ARB messages for gen-l10n without exporting metadata',
    () async {
      writeSource('''
void f(context) {
  Text(AppLocalizations.of(context)!.hello);
  Text(S.of(context).items(3));
}
''');
      final arb = File(p.join(source.path, 'l10n', 'app_en.arb'));
      arb.parent.createSync();
      arb.writeAsStringSync(
        jsonEncode({
          '@@locale': 'en',
          'hello': 'Hello!',
          '@hello': {'description': 'Greeting'},
          'items': '{count, plural, =1{One item} other{{count} items}}',
        }),
      );
      final result = await run(['--from-arb', arb.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(output.readAsStringSync()), {
        'hello': 'Hello!',
        'items': '{count, plural, =1{One item} other{{count} items}}',
      });
      expect(jsonDecode(arb.readAsStringSync())['@@locale'], 'en');
    },
  );

  test('invalid ARB values abort without changing output', () async {
    writeSource('void f() {}');
    final arb = File(p.join(root.path, 'bad.arb'))
      ..writeAsStringSync('{"hello":42}');
    output.writeAsStringSync('{"Keep":"Safe"}');
    final result = await run(['--from-arb', arb.path]);
    expect(result.exitCode, isNot(0));
    expect(output.readAsStringSync(), '{"Keep":"Safe"}');
  });

  test(
    'reports dynamic translation keys and permits custom translation names',
    () async {
      writeSource(r'''
void f(String name) {
  localize('Custom');
  'Getter'.localized;
  'Hi $name'.tr;
  LocaleKeys.title.tr;
}
''');
      final result = await run([
        '--function',
        'localize',
        '--getter',
        'localized',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(output.readAsStringSync()), {
        'Custom': 'Custom',
        'Getter': 'Getter',
      });
      expect(result.stderr.toString().toLowerCase(), contains('dynamic'));
      expect(result.stderr, contains('app.dart:'));
    },
  );

  test(
    'CLI rejects unknown options and unexpected positional arguments',
    () async {
      for (final args in [
        ['--unknown'],
        ['unexpected'],
      ]) {
        final result = await run(args);
        expect(result.exitCode, 64);
        expect(result.stderr, isNotEmpty);
        expect(output.existsSync(), isFalse);
      }
    },
  );

  test(
    'missing source produces a failure on stderr without creating output',
    () async {
      final result = await run(['-s', p.join(root.path, 'missing')]);
      expect(result.exitCode, 1);
      expect(result.stderr, isNotEmpty);
      expect(output.existsSync(), isFalse);
    },
  );

  test('creates output parents and leaves no staging files behind', () async {
    writeSource("void f() { 'Hello'.tr; }");
    final destination = p.join(root.path, 'assets', 'translations', 'en.json');
    final result = await run(['-o', destination]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(File(destination).readAsStringSync()), {
      'Hello': 'Hello',
    });
    expect(
      Directory(
        p.dirname(destination),
      ).listSync().map((f) => p.basename(f.path)),
      ['en.json'],
    );
  });

  test('help succeeds without requiring a source directory', () async {
    source.deleteSync(recursive: true);
    final result = await run(['--help']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('--from-arb'));
    expect(result.stdout, contains('--dry-run'));
    expect(result.stderr, isEmpty);
    expect(output.existsSync(), isFalse);
  });

  test('uses lib and strings.json relative to the application root', () async {
    writeSource("void f() { 'Default'.tr; }");
    final result = await Process.run(Platform.resolvedExecutable, [
      p.absolute('bin/main.dart'),
    ], workingDirectory: root.path);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(output.readAsStringSync()), {'Default': 'Default'});
  });

  test(
    'accepts repeatable custom functions, getters, and exclusions',
    () async {
      writeSource('''
void f() {
  localize('First');
  lookup('Second');
  'Third'.localized;
  'Fourth'.translated();
}
''');
      writeSource("void f() { 'Exclude'.tr; }", 'debug.dart');
      writeSource("void f() { 'Comma'.tr; }", 'a,b.dart');
      final result = await run([
        '--function',
        'localize',
        '--function',
        'lookup',
        '--getter',
        'localized',
        '--getter',
        'translated',
        '--exclude',
        'debug.dart',
        '--exclude',
        'a,b.dart',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(jsonDecode(output.readAsStringSync()), {
        'First': 'First',
        'Second': 'Second',
        'Third': 'Third',
        'Fourth': 'Fourth',
      });
    },
  );

  test(
    'unsafe output paths fail cleanly without modifying the source',
    () async {
      const code = "void f() { 'Hello'.tr; }";
      writeSource(code);
      final destination = p.join(source.path, 'app.dart');
      final result = await run(['-o', destination]);
      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('.json'));
      expect(result.stderr, isNot(contains('Unhandled exception')));
      expect(File(destination).readAsStringSync(), code);
    },
  );

  test(
    'invalid Dart reports a file location and preserves existing output',
    () async {
      writeSource('void f( {');
      output.writeAsStringSync('{"Keep":"Safe"}');
      final result = await run([]);
      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('app.dart:1:'));
      expect(output.readAsStringSync(), '{"Keep":"Safe"}');
    },
  );

  test(
    'a missing ARB reports failure without replacing translations',
    () async {
      writeSource("void f() { 'New'.tr; }");
      output.writeAsStringSync('{"Keep":"Safe"}');
      final result = await run([
        '--from-arb',
        p.join(root.path, 'missing.arb'),
      ]);
      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('missing.arb'));
      expect(output.readAsStringSync(), '{"Keep":"Safe"}');
    },
  );
}
