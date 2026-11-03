import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_string_extractor/flutter_string_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory source;
  late File output;

  setUp(() {
    final temporary = Directory.systemTemp.createTempSync('extractor_edges_');
    root = Directory(temporary.resolveSymbolicLinksSync());
    source = Directory(p.join(root.path, 'application with spaces', 'lib'))
      ..createSync(recursive: true);
    output = File(p.join(root.path, 'strings.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  void writeSource(String code, [String name = 'app.dart']) {
    final file = File(p.join(source.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(code);
  }

  ExtractionResult extract({bool dryRun = true, bool allStrings = false}) =>
      FlutterStringExtractor.extractStrings(
        source.path,
        output.path,
        dryRun: dryRun,
        allStrings: allStrings,
      );

  // Literal expectations catch a wrong argument index or receiver classification.
  const calls = <(String, String, Map<String, String>)>[
    ('GetX getter', "'title'.tr", {'title': 'title'}),
    ('GetX arguments', "'title'.trArgs(['Ignore'])", {'title': 'title'}),
    (
      'GetX parameters',
      "'title'.trParams({'name': 'Ignore'})",
      {'title': 'title'},
    ),
    (
      'GetX plural',
      "'one'.trPlural('many', 2)",
      {'one': 'one', 'many': 'many'},
    ),
    (
      'GetX plural parameters',
      "'one'.trPluralParams('many', 2, {'x': 'Ignore'})",
      {'one': 'one', 'many': 'many'},
    ),
    (
      'Easy Localization function',
      "tr('title', args: ['Ignore'])",
      {'title': 'title'},
    ),
    (
      'Easy Localization extension',
      "'title'.tr(namedArgs: {'x': 'Ignore'})",
      {'title': 'title'},
    ),
    ('Easy Localization context', "context.tr('title')", {'title': 'title'}),
    (
      'Easy Localization Text',
      "Text('title', key: Key('Ignore')).tr()",
      {'title': 'title'},
    ),
    (
      'Easy Localization const Text',
      "const Text('title').tr()",
      {'title': 'title'},
    ),
    (
      'Easy Localization prefixed Text',
      "widgets.Text('title').tr()",
      {'title': 'title'},
    ),
    (
      'Easy Localization prefixed const Text',
      "const widgets.Text('title').tr()",
      {'title': 'title'},
    ),
    (
      'Easy Localization parenthesized Text',
      "(Text('title')).tr()",
      {'title': 'title'},
    ),
    (
      'Easy Localization plural function',
      "plural('items', 2)",
      {'items': 'items'},
    ),
    (
      'Easy Localization plural context',
      "context.plural('items', 2)",
      {'items': 'items'},
    ),
    (
      'Easy Localization plural Text',
      "Text('items').plural(2)",
      {'items': 'items'},
    ),
    (
      'Flutter Translate',
      "translate('title', args: {'x': 'Ignore'})",
      {'title': 'title'},
    ),
    (
      'Flutter Translate plural',
      "translatePlural('items', 2)",
      {'items': 'items'},
    ),
    (
      'FlutterI18n translation',
      "FlutterI18n.translate(context, 'title')",
      {'title': 'title'},
    ),
    (
      'FlutterI18n fallback',
      "FlutterI18n.translate(context, 'title', fallbackKey: 'fallback')",
      {'title': 'title', 'fallback': 'fallback'},
    ),
    (
      'FlutterI18n prefixed translation',
      "i18n.FlutterI18n.translate(context, 'title')",
      {'title': 'title'},
    ),
    (
      'FlutterI18n plural',
      "FlutterI18n.plural(context, 'items', 2)",
      {'items': 'items'},
    ),
    ('i18n_extension getter', "'Hello'.i18n", {'Hello': 'Hello'}),
    ('i18n_extension plural', "'items'.plural(2)", {'items': 'items'}),
    (
      'Intl named message',
      "Intl.message('Hello', name: 'hello', desc: 'Ignore')",
      {'hello': 'Hello'},
    ),
    ('Intl unnamed message', "Intl.message('Hello')", {'Hello': 'Hello'}),
    (
      'Intl prefixed message',
      "intl.Intl.message('Hello', name: 'hello')",
      {'hello': 'Hello'},
    ),
    ('parenthesized literal', "(('title')).tr", {'title': 'title'}),
    ('null-aware getter', "'title'?.tr", {'title': 'title'}),
    ('null-aware method', "context?.tr('title')", {'title': 'title'}),
    ('cascade getter', "'title'..tr", {'title': 'title'}),
    ('cascade method', "context..tr('title')", {'title': 'title'}),
    ('empty key', "''.tr", {}),
    ('similar method name', "translateOther('Ignore')", {}),
    ('no positional key', "tr(args: ['Ignore'])", {}),
  ];
  for (final (name, expression, expected) in calls) {
    test('recognizes $name without collecting translation arguments', () {
      writeSource('void f(context) { $expression; }');
      final result = extract();
      expect(result.translations, expected);
      expect(result.extractedCount, expected.length);
      expect(result.warnings, isEmpty);
      expect(output.existsSync(), isFalse);
    });
  }

  for (final expression in [
    'key.tr',
    'key.trParams({"name": "Ignore"})',
    'tr(key)',
    r'"Hello $key".tr',
    'tr("Hello" + key)',
    'Intl.message("Hello", name: key)',
    'Intl.message(key, name: "hello")',
    'Intl.plural(2, one: "Ignore", other: "Ignore")',
    'Intl.gender(key, male: "Ignore", female: "Ignore", other: "Ignore")',
    'Intl.select(key, {"x": "Ignore"})',
  ]) {
    test('reports unresolved expression $expression without guessing', () {
      writeSource('void f(String key) { $expression; }');
      final result = extract();
      expect(result.translations, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('app.dart:1:'));
    });
  }

  test('round trips 500 seeded Unicode and escaped literals across files', () {
    final random = Random(7462);
    const alphabet = [
      'a',
      'Z',
      ' ',
      "'",
      '"',
      r'\',
      r'$',
      '\n',
      '\t',
      '\r',
      '\b',
      '\f',
      '\u0000',
      'é',
      'e\u0301',
      'مرحبا',
      '你好',
      'नमस्ते',
      '😀',
      '👩🏽‍💻',
    ];
    final expected = <String, String>{};
    for (var file = 0; file < 20; file++) {
      final expressions = <String>[];
      for (var message = 0; message < 25; message++) {
        final text =
            '$file:$message ' +
            List.generate(
              12,
              (_) => alphabet[random.nextInt(alphabet.length)],
            ).join();
        expected[text] = text;
        // JSON escaping is valid Dart escaping except for interpolation dollars.
        final literal = jsonEncode(text).replaceAll(r'$', r'\$');
        expressions.add('tr($literal);');
      }
      writeSource('void f() { ${expressions.join('\n')} }', 'pages/$file.dart');
    }
    final result = extract(dryRun: false);
    expect(result.translations, expected);
    expect(jsonDecode(output.readAsStringSync()), expected);
    expect(result.filesScanned, 20);
    expect(result.addedCount, 500);
    final original = output.readAsBytesSync();
    for (var repeat = 0; repeat < 10; repeat++) {
      final next = extract(dryRun: false);
      expect(next.addedCount, 0, reason: 'repeat $repeat');
      expect(output.readAsBytesSync(), original, reason: 'repeat $repeat');
    }
  });

  test(
    'empty source preserves an existing catalog without inventing entries',
    () {
      output.writeAsStringSync('{"Keep":"Translated"}');
      final result = extract();
      expect(result.translations, {'Keep': 'Translated'});
      expect(result.filesScanned, 0);
      expect(result.extractedCount, 0);
      expect(result.addedCount, 0);
      expect(output.readAsStringSync(), '{"Keep":"Translated"}');
    },
  );

  test('empty source can create a valid empty JSON object', () {
    final result = extract(dryRun: false);
    expect(result.translations, isEmpty);
    expect(jsonDecode(output.readAsStringSync()), <String, dynamic>{});
  });

  test('discovery skips import, export, and part directives', () {
    writeSource('''
import 'ignored.dart';
export 'also_ignored.dart';
part 'generated.dart';
void f() { Text('Visible'); }
''');
    expect(extract(allStrings: true).translations, {'Visible': 'Visible'});
  });

  test('finds translations inside records, collections, and closures', () {
    writeSource('''
void f(bool visible) {
  final record = (tr('Record'), title: 'Named'.tr);
  final list = [if (visible) 'Conditional'.tr, ...['Spread'.tr]];
  final callback = () => tr('Closure');
}
''');
    expect(extract().translations, {
      'Record': 'Record',
      'Named': 'Named',
      'Conditional': 'Conditional',
      'Spread': 'Spread',
      'Closure': 'Closure',
    });
  });

  test(
    'preserves distinct Unicode normalization forms and surrounding whitespace',
    () {
      writeSource(
        "void f() { 'é'.tr; 'e\\u0301'.tr; ' padded '.tr; '  '.tr; }",
      );
      expect(extract().translations, {
        'é': 'é',
        'e\u0301': 'e\u0301',
        ' padded ': ' padded ',
        '  ': '  ',
      });
    },
  );

  test('named Intl values win over placeholder keys in either file order', () {
    for (final namedFirst in [true, false]) {
      writeSource(
        "void f() { Intl.message('Welcome', name: 'title'); }",
        namedFirst ? 'a.dart' : 'z.dart',
      );
      writeSource("void f() { 'title'.tr; }", namedFirst ? 'z.dart' : 'a.dart');
      expect(extract().translations, {'title': 'Welcome'});
    }
  });

  test(
    'imports ARB values over source placeholders and can replace translations',
    () {
      writeSource("void f() { 'hello'.tr; }");
      final arb = File(p.join(root.path, 'en.arb'))
        ..writeAsStringSync(
          '{"hello":"Hello!","@hello":{"description":"Ignore"}}',
        );
      output.writeAsStringSync('{"hello":"Hallo","old":"Alt"}');
      final result = FlutterStringExtractor.extractStrings(
        source.path,
        output.path,
        sourceArb: arb.path,
        replace: true,
      );
      expect(result.translations, {'hello': 'Hello!'});
      expect(jsonDecode(output.readAsStringSync()), {'hello': 'Hello!'});
      expect(jsonDecode(arb.readAsStringSync())['hello'], 'Hello!');
    },
  );

  test('rejects importing the output itself as a catalog', () {
    output.writeAsStringSync('{"Keep":"Safe"}');
    expect(
      () => FlutterStringExtractor.extractStrings(
        source.path,
        output.path,
        sourceArb: output.path,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(output.readAsStringSync(), '{"Keep":"Safe"}');
  });

  test('failed scans never create output parents or staging directories', () {
    writeSource('void f( {');
    final destination = p.join(root.path, 'missing', 'strings.json');
    expect(
      () => FlutterStringExtractor.extractStrings(source.path, destination),
      throwsA(isA<FormatException>()),
    );
    expect(Directory(p.dirname(destination)).existsSync(), isFalse);
  });

  test('rejects a file where the source directory is required', () {
    final file = File(p.join(root.path, 'source.dart'))
      ..writeAsStringSync("void f() { 'Keep'.tr; }");
    expect(
      () => FlutterStringExtractor.extractStrings(file.path, output.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(output.existsSync(), isFalse);
  });

  test('skips symlinked source directories and their outside content', () {
    final external = Directory(p.join(root.path, 'external'))..createSync();
    File(
      p.join(external.path, 'private.dart'),
    ).writeAsStringSync("void f() { 'Outside'.tr; }");
    Link(p.join(source.path, 'linked')).createSync(external.path);
    writeSource("void f() { 'Inside'.tr; }");
    expect(extract().translations, {'Inside': 'Inside'});
  });

  test(
    'adds deeply nested keys while preserving flat keys and non-string values',
    () {
      writeSource(
        "void f() { 'home.menu.new'.tr; 'home.menu.old'.tr; 'flat.key'.tr; }",
      );
      output.writeAsStringSync('''
{"home":{"menu":{"old":"Translated"}},"flat.key":"Flat translated","metadata":null}
''');
      expect(extract().translations, {
        'home': {
          'menu': {'old': 'Translated', 'new': 'home.menu.new'},
        },
        'flat.key': 'Flat translated',
        'metadata': null,
      });
    },
  );

  test(
    'retains shared POSIX permissions across repeated replacements',
    () {
      writeSource("void f() { 'Hello'.tr; }");
      output.writeAsStringSync('{}');
      final chmod = Process.runSync('/bin/chmod', ['640', output.path]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
      for (var repeat = 0; repeat < 3; repeat++) {
        extract(dryRun: false);
        expect(output.statSync().mode & 0x1ff, 0x1a0);
      }
    },
    skip: Platform.isWindows,
  );
}
