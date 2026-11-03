# Flutter String Extractor Example

This example previews the strings extracted from a Flutter project's source
without creating or modifying a translation file. Requires Dart 3.9+.

## Usage

Run from this package directory:

```bash
dart run example/main.dart /path/to/flutter_app/lib
```

The preview is JSON on stdout; unresolved keys are reported on stderr. To write
a catalog, use `dart run bin/main.dart -s /path/to/flutter_app/lib -o strings.json`.
Existing translations are preserved by default.

## Source Code Examples

The extractor recognizes actual Dart expressions, including:

```dart
// Using .tr extension
Text("Hello".tr);
Text('Welcome back'.tr);

// Using tr() function
Text(tr("Settings"));
Text(tr('Logout'));

// Other supported translation patterns
Text('Welcome @name'.trParams({'name': userName}));
Text(context.tr('profile.title'));
Text('items').plural(itemCount);
Text(translate('home.title'));
Text(FlutterI18n.translate(context, 'account.title'));
Text('Good morning'.i18n);
```

For the first four expressions, the preview contains:

```json
{
  "Hello": "Hello",
  "Welcome back": "Welcome back",
  "Settings": "Settings",
  "Logout": "Logout"
}
```

Comments are ignored. Dynamic keys are reported rather than guessed. For
`AppLocalizations` or `S.of(context)` messages, import their source ARB catalog
with the CLI's `--from-arb` option. See [the package README](../README.md) for
the full support table and file-safety details.
