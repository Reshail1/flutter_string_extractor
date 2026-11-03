import 'dart:convert';
import 'dart:io';

import 'package:flutter_string_extractor/flutter_string_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory source;
  late File output;

  setUp(() {
    final temporary = Directory.systemTemp.createTempSync(
      'string_extractor_test_',
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

  Map<String, dynamic> extract() {
    FlutterStringExtractor.extractStrings(source.path, output.path);
    return jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
  }

  test('rejects case aliases of a source catalog before replacement', () {
    writeSource("void f() { 'Hello'.tr; }");
    final catalog = File(p.join(root.path, 'input.json'))
      ..writeAsStringSync('{"@@locale":"en","hello":"Hello"}');
    final alias = File(p.join(root.path, 'INPUT.json'));
    if (!alias.existsSync()) {
      markTestSkipped('Requires a case-insensitive filesystem');
      return;
    }
    expect(
      () => FlutterStringExtractor.extractStrings(
        source.path,
        alias.path,
        sourceArb: catalog.path,
        replace: true,
      ),
      throwsArgumentError,
    );
    expect(catalog.readAsStringSync(), '{"@@locale":"en","hello":"Hello"}');
  });

  test('decodes Dart literals instead of truncating at quotes', () {
    writeSource(r'''
void f() {
  "Don't stop".tr;
  'It\'s ready'.tr;
  "Line one\nLine two".tr();
  r'C:\new'.tr;
  ('Hello ' 'world').tr;
  tr( 'Spaced call' );
  """Multiple
lines""".tr;
}
''');
    expect(extract(), {
      "Don't stop": "Don't stop",
      "It's ready": "It's ready",
      'Line one\nLine two': 'Line one\nLine two',
      r'C:\new': r'C:\new',
      'Hello world': 'Hello world',
      'Spaced call': 'Spaced call',
      'Multiple\nlines': 'Multiple\nlines',
    });
  });

  test('ignores comments, unrelated calls and runtime interpolation', () {
    writeSource(r'''
// "Comment".tr
/* tr('Block comment') */
void f(String name) {
  othertr('Unrelated');
  "Hello $name".tr;
  tr('Real');
}
''');
    expect(extract(), {'Real': 'Real'});
  });

  test('scans nested directories and deduplicates', () {
    writeSource("void f() { 'Nested'.tr; }", 'screens/deep/page.dart');
    writeSource("void f() { 'Nested'.tr; 'Top'.tr; }");
    expect(extract(), {'Nested': 'Nested', 'Top': 'Top'});
  });

  test(
    'supports common translation call shapes without collecting arguments',
    () {
      writeSource('''
void f(context, int count) {
  'params'.trParams({'name': 'Alice'});
  'args'.trArgs(['Bob']);
  'singular'.trPlural('pluralKey', count);
  'one'.trPluralParams('many', count, {'name': 'Charlie'});
  'i18n text'.i18n;
  context.tr('context.key', namedArgs: {'name': 'David'});
  'easy.key'.tr(args: ['Ignored']);
  Text('widget.key').tr();
  Text('widget.plural').plural(count);
  plural('function.plural', count);
  'extension.plural'.plural(count);
  translate('translate.key', args: {'name': 'Eve'});
  translatePlural('translate.plural', count);
  FlutterI18n.translate(context, 'flutter.key', fallbackKey: 'fallback.key');
  FlutterI18n.plural(context, 'flutter.plural', count);
  Intl.message('Hello from intl', name: 'intlHello', desc: 'Description');
}
''');
      expect(extract(), {
        for (final key in [
          'params',
          'args',
          'singular',
          'pluralKey',
          'one',
          'many',
          'i18n text',
          'context.key',
          'easy.key',
          'widget.key',
          'widget.plural',
          'function.plural',
          'extension.plural',
          'translate.key',
          'translate.plural',
          'flutter.key',
          'fallback.key',
          'flutter.plural',
        ])
          key: key,
        'intlHello': 'Hello from intl',
      });
    },
  );

  test('preserves translations, stale keys and nested plural objects', () {
    writeSource(
      "void f() { 'Hello'.tr; 'New'.tr; 'days'.plural(2); 'home.title'.tr; }",
    );
    output.writeAsStringSync(
      jsonEncode({
        'Hello': 'Hallo',
        'Old': 'Alt',
        'days': {'one': 'Tag', 'other': 'Tage'},
        'home': {'title': 'Start'},
      }),
    );
    expect(extract(), {
      'Hello': 'Hallo',
      'Old': 'Alt',
      'New': 'New',
      'days': {'one': 'Tag', 'other': 'Tage'},
      'home': {'title': 'Start'},
    });
  });

  test('rejects malformed output without modifying it', () {
    writeSource("void f() { 'Hello'.tr; }");
    for (final content in ['{broken', '[]', '42']) {
      output.writeAsStringSync(content);
      expect(() => extract(), throwsA(isA<FormatException>()));
      expect(output.readAsStringSync(), content);
    }
  });

  test('rejects nonexistent source without modifying output', () {
    output.writeAsStringSync('{"Keep":"Safe"}');
    expect(
      () => FlutterStringExtractor.extractStrings(
        p.join(root.path, 'missing'),
        output.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(output.readAsStringSync(), '{"Keep":"Safe"}');
  });

  test('rejects Dart source destinations without modifying them', () {
    const code = "void f() { 'Hello'.tr; }";
    writeSource(code);
    final file = File(p.join(source.path, 'app.dart'));
    expect(
      () => FlutterStringExtractor.extractStrings(source.path, file.path),
      throwsA(isA<ArgumentError>()),
    );
    expect(file.readAsStringSync(), code);
  });

  test('refuses output symlinks and symlinked parents', () {
    writeSource("void f() { 'Hello'.tr; }");
    final target = File(p.join(root.path, 'target.json'))
      ..writeAsStringSync('{"Keep":"Safe"}');
    Link(output.path).createSync(target.path);
    expect(() => extract(), throwsA(isA<FileSystemException>()));
    expect(target.readAsStringSync(), '{"Keep":"Safe"}');
    final parent = p.join(root.path, 'linked');
    Link(parent).createSync(root.path);
    expect(
      () => FlutterStringExtractor.extractStrings(
        source.path,
        p.join(parent, 'target.json'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(target.readAsStringSync(), '{"Keep":"Safe"}');
  });

  test('invalid Dart aborts before replacing translations', () {
    writeSource("void f( { 'Hello'.tr;");
    output.writeAsStringSync('{"Keep":"Safe"}');
    expect(() => extract(), throwsA(isA<FormatException>()));
    expect(output.readAsStringSync(), '{"Keep":"Safe"}');
  });

  test('does not follow source symlinks or scan generated files', () {
    writeSource("void f() { 'Included'.tr; }");
    writeSource("void f() { 'Generated'.tr; }", 'model.g.dart');
    writeSource("void f() { 'Cache'.tr; }", '.dart_tool/cache.dart');
    writeSource("void f() { 'Build'.tr; }", 'build/cache.dart');
    final outside = File(p.join(root.path, 'outside.dart'))
      ..writeAsStringSync("void f() { 'Outside'.tr; }");
    Link(p.join(source.path, 'linked.dart')).createSync(outside.path);
    expect(extract(), {'Included': 'Included'});
  });

  test(
    'adds missing nested keys without creating duplicate flat namespaces',
    () {
      writeSource("void f() { 'home.subtitle'.tr; 'home.title'.tr; }");
      output.writeAsStringSync('{"home":{"title":"Start"}}');
      expect(extract(), {
        'home': {'title': 'Start', 'subtitle': 'home.subtitle'},
      });
    },
  );

  test('conflicting Intl message IDs abort without changing output', () {
    writeSource(
      "void f() { Intl.message('First', name: 'title'); Intl.message('Second', name: 'title'); }",
    );
    output.writeAsStringSync('{"Keep":"Safe"}');
    expect(() => extract(), throwsA(isA<FormatException>()));
    expect(output.readAsStringSync(), '{"Keep":"Safe"}');
  });

  test(
    'finds translation calls inside interpolation and const Text widgets',
    () {
      writeSource(r'''
void f() {
  Text("Header: ${tr('nested.key')}");
  const Text('const.widget').tr();
}
''');
      expect(extract(), {
        'nested.key': 'nested.key',
        'const.widget': 'const.widget',
      });
    },
  );

  test(
    'reports unresolved variable getters instead of quietly missing them',
    () {
      writeSource("void f(String key) { key.tr; }");
      final result = FlutterStringExtractor.extractStrings(
        source.path,
        output.path,
        dryRun: true,
      );
      expect(result.warnings, hasLength(1));
      expect(result.translations, isEmpty);
      expect(output.existsSync(), isFalse);
    },
  );

  test(
    'same translation key is not replaced by an argument to a dynamic extension',
    () {
      writeSource(
        "void f(String key) { key.trPlural('plural.key', 2); key.trParams({'name':'Alice'}); }",
      );
      final result = FlutterStringExtractor.extractStrings(
        source.path,
        output.path,
        dryRun: true,
      );
      expect(result.translations, {'plural.key': 'plural.key'});
      expect(result.warnings, hasLength(2));
    },
  );

  test(
    'Intl complex messages request a catalog instead of exporting incomplete branches',
    () {
      writeSource(
        "void f(n) { Intl.plural(n, one: 'One', other: 'Many', name: 'items'); }",
      );
      final result = FlutterStringExtractor.extractStrings(
        source.path,
        output.path,
        dryRun: true,
      );
      expect(result.translations, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('--from-arb'));
    },
  );

  test(
    'replacement still refuses invalid existing JSON and nonregular destinations',
    () {
      writeSource("void f() { 'Hello'.tr; }");
      output.writeAsStringSync('not JSON');
      expect(
        () => FlutterStringExtractor.extractStrings(
          source.path,
          output.path,
          replace: true,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(output.readAsStringSync(), 'not JSON');
      output.deleteSync();
      Directory(output.path).createSync();
      expect(() => extract(), throwsA(isA<FileSystemException>()));
    },
  );

  test('finds marked calls inside adjacent interpolated strings', () {
    writeSource(r'''void f() { Text('Header: ' '${tr("nested.key")}'); }''');
    expect(extract(), {'nested.key': 'nested.key'});
  });

  test('namespace collisions leave the original catalog untouched', () {
    writeSource("void f() { 'home.section.title'.tr; }");
    const original = '{"home":{"section":"Existing translation"}}';
    output.writeAsStringSync(original);
    expect(() => extract(), throwsA(isA<FormatException>()));
    expect(output.readAsStringSync(), original);
  });

  test('ARB import keeps existing translations and ICU values', () {
    writeSource("void f() { 'hello'.tr; }");
    final arb = File(p.join(root.path, 'app_en.arb'))
      ..writeAsStringSync(
        jsonEncode({
          'hello': 'Hello',
          'new': 'New message',
          'items': '{n, plural, one{One item} other{{n} items}}',
        }),
      );
    output.writeAsStringSync(
      jsonEncode({
        'hello': 'Hallo',
        'items': '{n, plural, one{Ein Element} other{{n} Elemente}}',
      }),
    );
    final result = FlutterStringExtractor.extractStrings(
      source.path,
      output.path,
      sourceArb: arb.path,
    );
    expect(result.translations, {
      'hello': 'Hallo',
      'new': 'New message',
      'items': '{n, plural, one{Ein Element} other{{n} Elemente}}',
    });
  });

  test(
    'retains private POSIX permissions when replacing a translation file',
    () {
      writeSource("void f() { 'Hello'.tr; }");
      output.writeAsStringSync('{"Keep":"Safe"}');
      final chmod = Process.runSync('/bin/chmod', ['600', output.path]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
      extract();
      expect(output.statSync().mode & 0x1ff, 0x180);
    },
    skip: Platform.isWindows,
  );

  test(
    'new POSIX translation files start with private permissions',
    () {
      writeSource("void f() { 'Hello'.tr; }");
      extract();
      expect(output.statSync().mode & 0x1ff, 0x180);
    },
    skip: Platform.isWindows,
  );
}
