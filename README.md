# Flutter String Extractor — Flutter localization strings to JSON

[![pub.dev](https://img.shields.io/pub/v/flutter_string_extractor.svg)](https://pub.dev/packages/flutter_string_extractor)
[![CI](https://github.com/Reshail1/flutter_string_extractor/actions/workflows/ci.yml/badge.svg)](https://github.com/Reshail1/flutter_string_extractor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Extract static translation strings and keys from Flutter/Dart source into a
JSON catalog. Repeated runs preserve your translations and old keys by default.
Dart syntax parsing handles quotes, escapes, raw strings, multiline strings,
and adjacent literals, while ignoring comments.

Requires **Dart 3.9 or later**. No Flutter SDK is needed to run the extractor.
Source files are read only; extraction does not rewrite widgets or insert
translation calls.

Use it to collect GetX or Easy Localization keys, discover hardcoded Flutter
text before localization, or export an ARB catalog to a JSON dictionary. It
runs locally without a translation service or API key by default. An optional
[AI workflow](#optional-ai-discovery-and-translation) finds unmarked text and
translates it using your own OpenAI, Claude, or Gemini API key.

Package: [`flutter_string_extractor` on pub.dev](https://pub.dev/packages/flutter_string_extractor).
Source, issues, and releases: [Reshail1/flutter_string_extractor on GitHub](https://github.com/Reshail1/flutter_string_extractor).
See the [support table](#supported-translation-patterns) before choosing a
localization workflow.

## Quick start: extract Flutter strings to JSON

Install the published CLI and run it from your Flutter application root:

```bash
dart pub global activate flutter_string_extractor
flutter_string_extractor -s lib -o assets/translations/en.json
```

For this source:

```dart
Text('Welcome'.tr);
Text(tr('settings.title'));
```

the JSON dictionary is:

```json
{
  "Welcome": "Welcome",
  "settings.title": "settings.title"
}
```

Edit the values to add translations. Subsequent runs keep translated values and
add missing keys. Preview first with `--dry-run`.

This documentation describes **2.1.0**, including optional AI discovery and
translation. Upgrade an existing installation with
`dart pub global activate flutter_string_extractor`.

## Install from source

From this package directory:

```bash
dart pub get
dart run bin/main.dart -s /path/to/flutter_app/lib -o /path/to/flutter_app/assets/translations/en.json
```

For a command usable from any Flutter project:

```bash
dart pub global activate --source path .
# Run from your Flutter application's root:
flutter_string_extractor -s lib -o assets/translations/en.json
```

Add Dart's pub cache `bin` directory to your PATH if the activated command is
not found. The original library entry point and `-s` / `-o` options still work.

## Supported translation patterns

Matching uses syntax and exact method names, without resolving package imports.
Calls with the same names in custom libraries are candidates too.

| Approach | Recognized examples |
| --- | --- |
| GetX | `'title'.tr`, `.trArgs([...])`, `.trParams({...})`, `'one'.trPlural('many', count)`, `.trPluralParams(...)` |
| Easy Localization | `'title'.tr()`, `tr('title')`, `context.tr('title')`, `Text('title').tr()`, `const Text('title').tr()` |
| Easy Localization plurals | `'items'.plural(count)`, `plural('items', count)`, `context.plural('items', count)`, `Text('items').plural(count)` |
| Flutter Translate | `translate('title')`, `translatePlural('items', count)` |
| FlutterI18n | `FlutterI18n.translate(context, 'title')`, `.plural(context, 'items', count)`; literal `fallbackKey` values are included |
| i18n_extension | `'Hello'.i18n`, `'One item'.plural(count)` |
| Intl | `Intl.message('Hello', name: 'hello')` exports `"hello": "Hello"`; without a literal name, an unnamed static message uses its text as the key |
| gen-l10n / Flutter Intl | Import an ARB catalog with `--from-arb` for `AppLocalizations`, `S.of(context)`, and similar generated APIs |
| Custom wrappers | `--function localize` for `localize('title')` / `service.localize('title')`; `--getter localized` for `'title'.localized` or `'title'.localized()` |

GetX plural calls include both literal singular and plural keys. Translation
argument values, parameter names, and descriptions are not extracted in the
default mode. Duplicate keys are combined, and conflicting named Intl messages
abort the run before changing output.

References: [GetX](https://pub.dev/documentation/get/latest/get_utils_src_extensions_internacionalization/Trans.html),
[Easy Localization](https://pub.dev/packages/easy_localization),
[Flutter Translate](https://pub.dev/documentation/flutter_translate/latest/flutter_translate/translatePlural.html),
[FlutterI18n](https://pub.dev/documentation/flutter_i18n/latest/flutter_i18n/FlutterI18n-class.html),
[i18n_extension](https://pub.dev/packages/i18n_extension),
[Flutter internationalization](https://docs.flutter.dev/ui/internationalization).

## Preview, discover, and filter

```bash
# Preview the merged catalog; stdout contains JSON, stderr contains the summary.
flutter_string_extractor -s lib -o strings.json --dry-run

# Discover unmarked static literals such as Text('Welcome').
flutter_string_extractor -s lib -o strings.json --all-strings --dry-run

# Exclude files or directories using paths relative to the source directory.
flutter_string_extractor -s lib -o strings.json --exclude 'models/**' --exclude '**/debug_*.dart'

# Add your translation wrapper's exact method name.
flutter_string_extractor -s lib -o strings.json --function localize --getter localized
```

`--all-strings` includes static literals beyond UI text, such as URLs, test data,
and translation arguments. Review the preview before using them as translations.
Imports, exports, other directives, and runtime interpolation are excluded.
Marked calls inside interpolated expressions are still extracted.

Build/cache directories and source symlinks are never traversed.
Vendored SDK/dependency folders (`.fvm`, `.gradle`, `.symlinks`, `node_modules`,
and `Pods`) are also excluded. Generated `.g.dart`, `.freezed.dart`,
`app_localizations*.dart`, and `messages_*.dart` files
are skipped unless you pass `--include-generated`.

## Optional AI discovery and translation

AI discovery and translation are available from version **2.1.0**. This feature
is opt-in; the ordinary extraction commands above keep working offline.

**AI can make mistakes.** It may miss UI text, include internal strings, change
meaning, or produce inappropriate translations. Review every generated catalog
before shipping. AI mode sends candidate strings to your chosen provider under
that provider's data policies, and your API usage may incur charges. Source files
are never uploaded as complete files, but individual literals can still contain
private information. Credential filtering is best effort, not a confidentiality
guarantee: preview and exclude sensitive files before opting in.

From your Flutter project root, preview locally first:

```bash
flutter_string_extractor \
  --ai-provider openai --source-language en --languages de,fr,ar \
  --output-dir assets/translations --exclude 'test/**' --dry-run
```

AI mode scans Dart files recursively from `.` by default, including unmarked
static literals such as `Text('Welcome')`, tooltips, and accessibility labels.
Use `-s lib` to narrow the scan. Existing source exclusions and generated-file
controls apply. The preview shows candidates before AI filtering; it needs no
key, sends nothing, and changes no files. Candidate lists can contain non-UI text.

Set the chosen provider's API key in your shell environment or secret manager.
Keep real keys out of source code, shell history, committed configuration, and
command-line arguments. The CLI deliberately has no `--api-key` argument and
does not load `.env` files automatically.

| Provider | Environment variable | Default model |
| --- | --- | --- |
| `openai` | `OPENAI_API_KEY` | `gpt-6-luna` |
| `claude` | `ANTHROPIC_API_KEY` | `claude-haiku-5-5` |
| `gemini` | `GEMINI_API_KEY` | `gemini-3.5-flash-lite` |

These defaults target the providers' inexpensive model families, rather than
claiming to be the cheapest model for every account. Availability and pricing
change; `--model <model-id>` lets you choose any compatible text model you have
access to. Defaults were checked against [OpenAI's model catalog](https://developers.openai.com/api/docs/models),
[Claude's API guide](https://platform.claude.com/docs/en/claude_api_primer), and
[Gemini Flash-Lite documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite).
The implementations use the official [Responses API](https://developers.openai.com/api/docs/guides/text),
[Messages API](https://platform.claude.com/docs/en/api/messages/create), and
[generateContent API](https://ai.google.dev/api/generate-content).

Once the key is set and you have reviewed the preview, permit the AI requests:

```bash
flutter_string_extractor --ai-provider openai --languages de,fr,ar \
  --source-language en --output-dir assets/translations \
  --exclude 'test/**' --accept-ai

# Other providers; set ANTHROPIC_API_KEY or GEMINI_API_KEY respectively.
flutter_string_extractor --ai-provider claude --languages de,ur --accept-ai
flutter_string_extractor --ai-provider gemini --languages ja,es --accept-ai

# Override the provider default and cap the number of billable requests.
flutter_string_extractor --ai-provider openai --model your-model-id \
  --languages de --max-ai-requests 25 --accept-ai
```

The command creates `en.json`, `de.json`, `fr.json`, and `ar.json` in the output
directory. Keys remain under local control: unmarked text uses its original
text as the key; marked keys and named Intl/ARB messages keep their IDs. Supply
`--from-arb lib/l10n/app_en.arb` or an existing source-locale JSON catalog when
keys such as `settings.title` need real source text. Without source values, AI
can only infer meaning from the key. Existing source-catalog string values take
precedence over inferred text.

Existing values, nested dictionaries, and stale entries are preserved. Only
missing target entries are translated; even values equal to the source text are
treated as existing translations. To retranslate an entry, explicitly delete it
from the target catalog. AI mode rejects `--replace` and `-o`; use `--output-dir`.
Locale codes are normalized to lowercase with hyphens (`pt_BR` becomes
`pt-br.json`). Match these file names in your localization setup.

Calls are sequential, with at most 20 messages / 6,000 source characters per
batch and a default limit of 100 requests per run. Classification of newly seen
unmarked candidates also consumes requests; previously rejected candidates can
be classified again on subsequent runs. No automatic retries are made. Provider
errors, invalid JSON/IDs, missing translations, and changed placeholder names or
counts abort before any catalog writes. Requests have a 60-second timeout and a
1 MiB response limit. Provider error bodies are never printed. The request cap
is not a currency budget; earlier calls can still be billed if a later call fails.

Static messages longer than 2,000 characters are skipped with a warning. Runtime
interpolation and computed expressions still require manual localization.
Complex ICU plural/select messages are retained in the source catalog and
diagnosed instead of being translated by AI. Generated outputs are JSON, not
gen-l10n ARB files. A filesystem failure during final writes can leave some
catalogs updated; individual files use the staged writer described below.

**Dart code stays unchanged.** After reviewing the files, configure your
localization package and replace hardcoded widget text with its translation
calls. Creating translation files alone does not localize the running app.

For library usage, import `package:flutter_string_extractor/ai_string_extractor.dart`
and await `AiStringExtractor.extract('.', 'assets/translations', provider:
AiProvider.gemini, languages: ['de', 'ur'], acceptAi: true)`. It uses the same
environment keys and safety checks as the CLI. Use `dryRun: true` for local
preview; `result.previewJson`, `messages`, `filesScanned`, `translatedCount`,
`requestCount`, `outputFiles`, and `warnings` describe the result.

## Generated localizations and ICU messages

Generated getters do not contain the original message text. Use the source
catalog instead:

```bash
flutter_string_extractor -s lib -o strings.json --from-arb lib/l10n/app_en.arb
```

All message entries from that **one** source-locale catalog are imported,
including messages not referenced in the scanned code. ARB metadata (`@...` and
`@@...`) is omitted; ICU plural/select/placeholder strings are copied intact.
Catalog values take precedence over identity placeholders extracted from code;
existing output translations still win unless you choose `--replace`.

This exports a JSON dictionary, not a gen-l10n ARB file. Keep your original ARB
files for their metadata and Flutter code generation. Use this same catalog
route for `Intl.plural`, `Intl.gender`, and `Intl.select`: the extractor reports
these calls rather than exporting incomplete plural or gender branches.

Computed keys, variables such as `key.tr`, constant references such as
`LocaleKeys.title.tr`, concatenated expressions, and interpolated messages
cannot be resolved by this syntax-only scan. They produce location diagnostics
when used in recognized translation calls. Supply literals or import the source
catalog; the extractor does not evaluate Dart code or guess their values.

## Output and translation preservation

For `'Hello'.tr` and `tr('Settings')`, the initial catalog contains:

```json
{
  "Hello": "Hello",
  "Settings": "Settings"
}
```

After translating `Hello` to `Hallo`, running extraction again keeps `Hallo`.
Removed source keys remain in the output. Existing nested catalogs and plural /
gender objects are preserved; newly discovered dotted keys are added inside an
existing nested namespace. New catalogs use flat keys. Missing translations
start as key-to-key placeholders; plural/gender placeholders need the correct
structure for your localization package before use.

To explicitly reset the catalog to current extraction results:

```bash
flutter_string_extractor -s lib -o strings.json --replace
```

Only `.json` output destinations are accepted. Missing output directories are
created, except in a dry run. Missing source, syntax errors, conflicting message
IDs, malformed catalogs, and unsafe destinations abort before writing. Existing
JSON must be an object even in replacement mode. Top-level keys are sorted.

Writes use a private temporary directory beside the destination and a
same-filesystem rename, with cleanup afterward. Output symlinks, symlinked parent
directories, and directory destinations are rejected. On macOS/Linux, existing
POSIX access permissions are retained and new files use owner-only permissions
(`0600`); `/bin/chmod` must be available. Windows uses filesystem permissions
inherited from the destination directory. Replacement can change file ownership
or extended ACLs; review those separately when sharing catalogs. Portable file
checks do not fully prevent races with another process changing paths.

Errors and warnings go to stderr. Exit codes: `0` for a successful extraction or
preview, `1` for extraction/file errors, `64` for incorrect CLI arguments.
Warnings about unresolved messages do not change the successful exit code.

## Options

| Option | Default / behavior |
| --- | --- |
| `-s, --src-dir` | `lib` |
| `-o, --output-file` | `strings.json` |
| `--all-strings` | Discover all static literals except directives |
| `--dry-run` | Print merged JSON without modifying files |
| `--replace` | Discard existing translations and old keys explicitly |
| `--exclude` | Repeatable source-relative glob; quote patterns in the shell |
| `--include-generated` | Include generated files; build/cache exclusions still apply |
| `--function` | Repeatable translator method name; key is the first positional argument |
| `--getter` | Repeatable String getter/extension method name |
| `--from-arb` | Source ARB catalog to import |
| `--ai-provider` | Optional AI mode: `openai`, `claude`, or `gemini`; scan root defaults to `.` |
| `--languages` | Required AI target locale codes, comma-separated or repeated |
| `--source-language` | AI source locale; defaults to `en` |
| `--model` | Override the selected provider's low-cost model |
| `--output-dir` | AI catalog directory; defaults to `assets/translations` |
| `--accept-ai` | Required before AI network calls; acknowledges privacy, charges, and mistakes |
| `--max-ai-requests` | Hard per-run request limit; defaults to `100` |
| `-h, --help` | Display CLI help |

## Library usage

```dart
import 'package:flutter_string_extractor/flutter_string_extractor.dart';

void main() {
  final result = FlutterStringExtractor.extractStrings(
    'lib',
    'strings.json',
    dryRun: true,
    exclude: ['models/**'],
    functions: ['localize'],
    // sourceArb: 'lib/l10n/app_en.arb',
  );
  print(result.json);
  for (final warning in result.warnings) {
    print(warning);
  }
}
```

The result includes `translations`, `filesScanned`, `extractedCount`,
`addedCount`, and `warnings`. Existing two-argument calls still write output.

## Frequently asked questions

### How do I extract hardcoded Flutter text for localization?

Run `flutter_string_extractor -s lib -o strings.json --all-strings --dry-run`.
Review the JSON preview: discovery also includes URLs and other non-UI literals.
Remove `--dry-run` when ready to write the catalog. Add translation calls to
your widgets separately; the extractor keeps source files unchanged.

### Can I use it with AppLocalizations or S.of(context)?

Yes, import the source ARB file with
`--from-arb lib/l10n/app_en.arb`. Generated getters cannot supply the original
messages to a syntax-only scan. The import includes every message in that
catalog and keeps ICU strings intact; it does not create a new ARB file.

### Does it translate strings using AI or send my source to a server?

Default extraction stays local and creates placeholders. Optional AI mode sends
candidate strings to OpenAI, Claude, or Gemini using your own API key and
translates missing entries into requested languages. It requires `--ai-provider`
and `--accept-ai`; an AI `--dry-run` always stays local. A consumer chat
subscription alone does not supply the API key required by this workflow.

### Does rerunning extraction overwrite my translations?

Existing values, nested catalogs, and old keys remain by default. New keys are
added. `--replace` explicitly discards the previous catalog after validating it.

### Why was a translation key skipped?

Check stderr for the file and line. Variables, constant references, and
interpolation cannot be evaluated by this syntax-only extractor. Use literal
keys or import the source catalog. Custom wrapper names can be registered with
`--function` and `--getter`.

### Which installed CLI version am I using?

Run `dart pub global list`. To update a pub.dev installation, run
`dart pub global activate flutter_string_extractor` again.

## Development

```bash
dart pub get
dart analyze
dart test
dart test --test-randomize-ordering-seed=421
dart format --output=none --set-exit-if-changed lib bin/main.dart test example/main.dart
```

Tests exercise translation APIs, Unicode/escaped literals, ARB imports, nested
catalogs, CLI errors, permissions, and unsafe destinations. A seeded stress
case extracts 500 messages across 20 files and checks ten subsequent writes
for identical output. CI runs the suite on Linux, macOS, and Windows with
Dart 3.9.0 and stable. Formatting is checked with Dart 3.9.0 to keep the
formatter consistent across SDK updates. Fork pull requests receive read-only
CI permissions.

## Publishing releases

The [publishing workflow](.github/workflows/publish.yml) runs when a version tag
such as `v2.1.0` is pushed. It uses the official Dart reusable workflow and
short-lived OIDC authentication; no pub.dev credentials belong in this public
repository. Regular pushes to `main` run CI; publishing requires a version tag.

In the package's [pub.dev admin settings](https://pub.dev/packages/flutter_string_extractor/admin),
enable automated publishing from GitHub for repository
`Reshail1/flutter_string_extractor` and tag pattern `v{{version}}`. This
publisher setting is required separately from committing the workflow.
See [Dart's automated publishing guide](https://dart.dev/tools/pub/automated-publishing).

After updating `pubspec.yaml` and `CHANGELOG.md`, wait for the main commit's CI
checks to pass. Confirm the tag version equals the package version and has not
already been published, then release it:

```bash
git tag v2.1.0
git push origin v2.1.0
```

For later releases, use the new package version in both commands. Restrict
creation and modification of release tags to trusted maintainers in GitHub
repository rulesets: the pub.dev publisher grants that repository permission
to release the package. Never commit access tokens, pub credentials, or private
application catalogs.

## License

MIT.
