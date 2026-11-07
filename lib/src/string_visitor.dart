import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Matches syntax only; custom APIs sharing these names are also candidates.
class StringVisitor extends RecursiveAstVisitor<void> {
  StringVisitor(
    this.messages, {
    this.allStrings = false,
    Iterable<String> functions = const [],
    Iterable<String> getters = const [],
    Set<String>? namedMessages,
    this.onWarning,
    this.onMessage,
  }) : functions = {
         'tr',
         'plural',
         'translate',
         'translatePlural',
         ...functions,
       },
       getters = {'tr', 'i18n', ...getters},
       namedMessages = namedMessages ?? {};

  final Map<String, String> messages;
  final bool allStrings;
  final Set<String> functions;
  final Set<String> getters;
  final Set<String> namedMessages;
  final void Function(int offset, String reason)? onWarning;
  final void Function(String key, int offset, String context)? onMessage;
  final Set<int> _warned = {};

  static const _extensions = {
    'tr',
    'trArgs',
    'trParams',
    'trPlural',
    'trPluralParams',
    'plural',
    'i18n',
  };

  Expression _unwrap(Expression expression) {
    while (expression is ParenthesizedExpression) {
      expression = expression.expression;
    }
    return expression;
  }

  String? _value(Expression expression) {
    final unwrapped = _unwrap(expression);
    return unwrapped is StringLiteral ? unwrapped.stringValue : null;
  }

  void _add(Expression expression, {String? key}) {
    final value = _value(expression);
    if (value != null && value.isNotEmpty) {
      if (key != null) {
        if (namedMessages.contains(key) && messages[key] != value) {
          throw FormatException(
            'Conflicting source messages for translation ID "$key".',
          );
        }
        namedMessages.add(key);
        messages[key] = value;
      } else {
        messages.putIfAbsent(value, () => value);
      }
      onMessage?.call(key ?? value, expression.offset, _context(expression));
    } else if (value == null && _warned.add(expression.offset)) {
      onWarning?.call(
        expression.offset,
        'Skipped dynamic translation expression; use a literal or --from-arb for catalog messages.',
      );
    }
  }

  String _context(AstNode expression) {
    final roles = <String>[];
    for (AstNode? node = expression.parent; node != null; node = node.parent) {
      final role = switch (node) {
        NamedArgument n => 'argument ${n.name.lexeme}',
        MethodInvocation n => 'call ${n.methodName.name}',
        InstanceCreationExpression n =>
          'widget ${n.constructorName.type.name.lexeme}',
        VariableDeclaration n => 'variable ${n.name.lexeme}',
        MethodDeclaration n => 'method ${n.name.lexeme}',
        FunctionDeclaration n => 'function ${n.name.lexeme}',
        ClassDeclaration n => 'class ${n.namePart.typeName.lexeme}',
        _ => null,
      };
      if (role != null) roles.add(role);
      if (roles.length == 6) break;
    }
    // Structural identifiers only; never serialize neighboring code or literals.
    return roles.reversed.join(' > ');
  }

  void _discover(StringLiteral node) {
    if (!allStrings) return;
    AstNode? parent = node.parent;
    while (parent != null) {
      if (parent is Directive ||
          parent is StringInterpolation ||
          parent is AdjacentStrings) {
        return;
      }
      parent = parent.parent;
    }
    _add(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _discover(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _discover(node);
    super.visitAdjacentStrings(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (allStrings) _add(node);
    // Discovery skips fragments; marked calls inside expressions still count.
    super.visitStringInterpolation(node);
  }

  Expression? _textArgument(Expression target) {
    target = _unwrap(target);
    if (target is MethodInvocation && target.methodName.name == 'Text') {
      return target.argumentList.arguments.whereType<Expression>().firstOrNull;
    }
    if (target is InstanceCreationExpression &&
        target.constructorName.type.name.lexeme == 'Text') {
      return target.argumentList.arguments.whereType<Expression>().firstOrNull;
    }
    return null;
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (getters.contains(node.propertyName.name)) {
      _add(node.realTarget);
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (getters.contains(node.identifier.name)) _add(node.prefix);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final target = node.realTarget;
    final positional = node.argumentList.arguments
        .whereType<Expression>()
        .toList();
    final named = {
      for (final argument
          in node.argumentList.arguments.whereType<NamedArgument>())
        argument.name.lexeme: argument.argumentExpression,
    };
    final targetName = target?.toSource().split('.').last;
    if (targetName == 'Intl' && name == 'message') {
      if (positional.isNotEmpty) {
        final key = named['name'] == null ? null : _value(named['name']!);
        if (named['name'] != null && key == null) {
          onWarning?.call(
            node.offset,
            'Skipped Intl.message with a dynamic name; use --from-arb.',
          );
        } else {
          _add(positional.first, key: key);
        }
      }
    } else if (targetName == 'Intl' &&
        {'plural', 'gender', 'select'}.contains(name)) {
      onWarning?.call(
        node.offset,
        'Intl.$name needs its message catalog; import it with --from-arb.',
      );
    } else if (targetName == 'FlutterI18n' &&
        {'translate', 'plural'}.contains(name)) {
      if (positional.length > 1) _add(positional[1]);
      if (named['fallbackKey'] != null) _add(named['fallbackKey']!);
    } else if ((_extensions.contains(name) || getters.contains(name)) &&
        target != null &&
        (_unwrap(target) is StringLiteral || _textArgument(target) != null)) {
      _add(_textArgument(target) ?? target);
      if ({'trPlural', 'trPluralParams'}.contains(name) &&
          positional.isNotEmpty) {
        _add(positional.first);
      }
    } else if (functions.contains(name) && positional.isNotEmpty) {
      _add(positional.first);
    } else if ((_extensions.contains(name) || getters.contains(name)) &&
        target != null) {
      _add(target);
      if ({'trPlural', 'trPluralParams'}.contains(name) &&
          positional.isNotEmpty) {
        _add(positional.first);
      }
    }
    super.visitMethodInvocation(node);
  }
}
