import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'src/string_visitor.dart';
import 'src/catalog_io.dart';

/// The dictionary to write (or preview) and a summary of the source scan.
class ExtractionResult {
  ExtractionResult(
    this.translations,
    this.filesScanned,
    this.extractedCount,
    this.addedCount,
    this.warnings,
  );

  final Map<String, dynamic> translations;
  final int filesScanned;
  final int extractedCount;
  final int addedCount;
  final List<String> warnings;

  String get json =>
      '${const JsonEncoder.withIndent('  ').convert(translations)}\n';
}

/// Extracts static translation strings without executing application code.
class FlutterStringExtractor {
  /// Preserves existing translations and exports a sorted JSON dictionary.
  static ExtractionResult extractStrings(
    String directory,
    String outputFile, {
    bool allStrings = false,
    bool dryRun = false,
    bool replace = false,
    bool includeGenerated = false,
    Iterable<String> exclude = const [],
    Iterable<String> functions = const [],
    Iterable<String> getters = const [],
    String? sourceArb,
  }) {
    final source = Directory(p.normalize(p.absolute(directory)));
    if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException('Source directory does not exist', directory);
    }
    final output = File(p.normalize(p.absolute(outputFile)));
    if (p.extension(output.path).toLowerCase() != '.json') {
      throw ArgumentError('Output must be a .json file, never a source file.');
    }
    CatalogIO.validateOutput(output);

    final messages = <String, String>{};
    final namedMessages = <String>{};
    final warnings = <String>[];
    final patterns = exclude
        .map((pattern) => Glob(pattern, context: p.posix))
        .toList();
    final files = _dartFiles(
      source,
      source.path,
      patterns,
      includeGenerated,
    ).toList()..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        throwIfDiagnostics: false,
      );
      if (parsed.errors.isNotEmpty) {
        final error = parsed.errors.first;
        final location = parsed.lineInfo.getLocation(error.offset);
        throw FormatException(
          '${file.path}:${location.lineNumber}:${location.columnNumber}: ${error.message}',
        );
      }
      parsed.unit.accept(
        StringVisitor(
          messages,
          namedMessages: namedMessages,
          allStrings: allStrings,
          functions: functions,
          getters: getters,
          onWarning: (offset, reason) {
            final location = parsed.lineInfo.getLocation(offset);
            warnings.add(
              '${file.path}:${location.lineNumber}:${location.columnNumber}: $reason',
            );
          },
        ),
      );
    }

    if (sourceArb != null) {
      final catalog = File(p.absolute(sourceArb));
      if ((catalog.resolveSymbolicLinksSync() == output.path ||
          (output.existsSync() &&
              FileSystemEntity.identicalSync(catalog.path, output.path)))) {
        throw ArgumentError('Output must differ from the source ARB catalog.');
      }
      for (final entry in CatalogIO.readDictionary(catalog).entries) {
        if (entry.key.startsWith('@')) continue;
        if (entry.value is! String) {
          throw FormatException(
            'ARB message "${entry.key}" must be a string (${catalog.path})',
          );
        }
        messages[entry.key] = entry.value as String;
      }
    }

    // Validate even in replacement mode so a mistaken path cannot clobber data.
    final existing = output.existsSync()
        ? CatalogIO.readDictionary(output)
        : <String, dynamic>{};
    final translations = replace ? <String, dynamic>{} : existing;
    var added = 0;
    for (final entry in messages.entries) {
      if (!CatalogIO.containsKey(translations, entry.key)) {
        CatalogIO.insert(translations, entry.key, entry.value);
        added++;
      }
    }
    final sorted = {
      for (final key in translations.keys.toList()..sort())
        key: translations[key],
    };
    final result = ExtractionResult(
      Map.unmodifiable(sorted),
      files.length,
      messages.length,
      added,
      List.unmodifiable(warnings),
    );
    if (!dryRun) CatalogIO.writeOutput(output, result.json);
    return result;
  }

  static Iterable<File> _dartFiles(
    Directory directory,
    String root,
    List<Glob> exclude,
    bool includeGenerated,
  ) sync* {
    for (final entity in directory.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      final relative = p.split(p.relative(entity.path, from: root)).join('/');
      if (exclude.any(
        (pattern) =>
            pattern.matches(relative) ||
            (entity is Directory && pattern.matches('$relative/')),
      ))
        continue;
      if (entity is Directory) {
        if (!{
          '.git',
          '.dart_tool',
          'build',
          '.idea',
          '.pub-cache',
          '.fvm',
          '.gradle',
          '.symlinks',
          'node_modules',
          'Pods',
        }.contains(name)) {
          yield* _dartFiles(entity, root, exclude, includeGenerated);
        }
      } else if (entity is File &&
          name.endsWith('.dart') &&
          (includeGenerated ||
              (!name.endsWith('.g.dart') &&
                  !name.endsWith('.freezed.dart') &&
                  !name.startsWith('app_localizations') &&
                  !name.startsWith('messages_')))) {
        yield entity;
      }
    }
  }
}
