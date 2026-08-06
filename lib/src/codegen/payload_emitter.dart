part of 'payload_generator.dart';

sealed class _PayloadDeclaration {
  const _PayloadDeclaration();
}

final class _PayloadEnum extends _PayloadDeclaration {
  const _PayloadEnum({required this.name, required this.values});

  final String name;
  final List<_PayloadEnumValue> values;
}

final class _PayloadEnumValue {
  const _PayloadEnumValue({required this.name, required this.wireValue});

  final String name;
  final String wireValue;
}

final class _PayloadClass extends _PayloadDeclaration {
  const _PayloadClass({required this.name, required this.fields});

  final String name;
  final List<_PayloadField> fields;
}

final class _PayloadField {
  const _PayloadField({
    required this.wireName,
    required this.name,
    required this.type,
    required this.required,
    required this.decode,
    required this.encode,
    required this.nullAwareMapValue,
  });

  final String wireName;
  final String name;
  final _DartType type;
  final bool required;
  final String decode;
  final String encode;
  final bool nullAwareMapValue;
}

final class _PayloadRulesBase extends _PayloadDeclaration {
  const _PayloadRulesBase({
    required this.name,
    required this.observation,
    required this.action,
    required this.config,
  });

  final String name;
  final String observation;
  final String action;
  final String config;
}

final class _PayloadEmitter {
  const _PayloadEmitter();

  String emit(List<_PayloadDeclaration> declarations) {
    final library = Library(
      (builder) => builder
        ..comments.addAll([
          'GENERATED CODE - DO NOT MODIFY BY HAND.',
          'Generated from the game-owned EigenInteractive contract.',
        ])
        ..ignoreForFile.addAll([
          'prefer_adjacent_string_concatenation',
          'prefer_null_aware_operators',
          'unnecessary_non_null_assertion',
          'unused_element',
        ])
        ..directives.add(
          Directive.import('package:eigen_flutter/eigen_flutter.dart'),
        )
        ..body.addAll([
          ..._runtimeHelpers,
          for (final declaration in declarations) _emitDeclaration(declaration),
        ]),
    );
    final source = library.accept(
      DartEmitter(useNullSafetySyntax: true, orderDirectives: true),
    );
    return DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    ).format('$source');
  }

  Spec _emitDeclaration(_PayloadDeclaration declaration) =>
      switch (declaration) {
        _PayloadEnum() => _emitEnum(declaration),
        _PayloadClass() => _emitClass(declaration),
        _PayloadRulesBase() => _emitRulesBase(declaration),
      };

  Enum _emitEnum(_PayloadEnum declaration) {
    final fromCases = declaration.values
        .map(
          (value) =>
              '${_dartString(value.wireValue)} => '
              '${declaration.name}.${value.name},',
        )
        .join('\n');
    final toCases = declaration.values
        .map(
          (value) =>
              '${declaration.name}.${value.name} => '
              '${_dartString(value.wireValue)},',
        )
        .join('\n');
    return Enum(
      (builder) => builder
        ..name = declaration.name
        ..values.addAll([
          for (final value in declaration.values)
            EnumValue((builder) => builder.name = value.name),
        ])
        ..methods.addAll([
          Method(
            (builder) => builder
              ..name = 'fromJson'
              ..static = true
              ..returns = refer(declaration.name)
              ..requiredParameters.add(
                Parameter(
                  (builder) => builder
                    ..name = 'value'
                    ..type = refer('Object?'),
                ),
              )
              ..optionalParameters.add(
                Parameter(
                  (builder) => builder
                    ..name = 'path'
                    ..type = refer('String')
                    ..defaultTo = Code(_dartString(declaration.name)),
                ),
              )
              ..lambda = true
              ..body = Code(
                'switch (value) {\n'
                '$fromCases\n'
                '_ => throw FormatException('
                "'\$path: unknown ${declaration.name} value \$value'),\n"
                '}',
              ),
          ),
          Method(
            (builder) => builder
              ..name = 'toJson'
              ..returns = refer('String')
              ..lambda = true
              ..body = Code('switch (this) {\n$toCases\n}'),
          ),
        ]),
    );
  }

  Class _emitClass(_PayloadClass declaration) {
    return Class(
      (builder) => builder
        ..name = declaration.name
        ..modifier = ClassModifier.final$
        ..constructors.addAll([
          _payloadConstructor(declaration),
          _fromJsonConstructor(declaration),
        ])
        ..fields.addAll([
          for (final field in declaration.fields)
            Field(
              (builder) => builder
                ..name = field.name
                ..type = refer(field.type.dart)
                ..modifier = FieldModifier.final$,
            ),
        ])
        ..methods.addAll([
          _toJsonMethod(declaration),
          _equalityMethod(declaration),
          _hashCodeMethod(declaration),
        ]),
    );
  }

  Constructor _payloadConstructor(_PayloadClass declaration) {
    return Constructor(
      (builder) => builder
        ..optionalParameters.addAll([
          for (final field in declaration.fields)
            Parameter((builder) {
              builder
                ..name = field.name
                ..named = true
                ..required = field.required;
              if (field.type.list) {
                builder.type = refer(
                  field.type.dart.replaceFirst('List<', 'Iterable<'),
                );
              } else {
                builder.toThis = true;
              }
            }),
        ])
        ..initializers.addAll([
          for (final field in declaration.fields)
            if (field.type.list)
              Code(
                field.type.nullable
                    ? '${field.name} = ${field.name} == null '
                          '? null : List.unmodifiable(${field.name})'
                    : '${field.name} = List.unmodifiable(${field.name})',
              ),
        ]),
    );
  }

  Constructor _fromJsonConstructor(_PayloadClass declaration) {
    final arguments = declaration.fields
        .map((field) {
          final value = field.required
              ? field.decode
              : 'json.containsKey(${_dartString(field.wireName)}) '
                    '? ${field.decode} : null';
          return '${field.name}: $value,';
        })
        .join('\n');
    return Constructor(
      (builder) => builder
        ..name = 'fromJson'
        ..factory = true
        ..requiredParameters.add(
          Parameter(
            (builder) => builder
              ..name = 'json'
              ..type = refer('Map<String, dynamic>'),
          ),
        )
        ..body = Code(
          'const path = ${_dartString(declaration.name)};\n'
          'return ${declaration.name}(\n$arguments\n);',
        ),
    );
  }

  Method _toJsonMethod(_PayloadClass declaration) {
    final entries = declaration.fields
        .map((field) {
          final entry = '${_dartString(field.wireName)}: ${field.encode},';
          if (field.required) return entry;
          if (field.nullAwareMapValue) {
            return '${_dartString(field.wireName)}: ?${field.name},';
          }
          return 'if (${field.name} != null) $entry';
        })
        .join('\n');
    return Method(
      (builder) => builder
        ..name = 'toJson'
        ..returns = refer('Map<String, dynamic>')
        ..lambda = true
        ..body = Code('{\n$entries\n}'),
    );
  }

  Method _equalityMethod(_PayloadClass declaration) {
    final fields = declaration.fields
        .map((field) => '_payloadEquals(${field.name}, other.${field.name})')
        .join(' && ');
    final comparison = fields.isEmpty
        ? 'other is ${declaration.name}'
        : 'other is ${declaration.name} && $fields';
    return Method(
      (builder) => builder
        ..name = 'operator =='
        ..returns = refer('bool')
        ..annotations.add(refer('override'))
        ..requiredParameters.add(
          Parameter(
            (builder) => builder
              ..name = 'other'
              ..type = refer('Object'),
          ),
        )
        ..lambda = true
        ..body = Code('identical(this, other) || $comparison'),
    );
  }

  Method _hashCodeMethod(_PayloadClass declaration) {
    final values = declaration.fields
        .map((field) => '_payloadHash(${field.name})')
        .join(', ');
    return Method(
      (builder) => builder
        ..name = 'hashCode'
        ..type = MethodType.getter
        ..returns = refer('int')
        ..annotations.add(refer('override'))
        ..lambda = true
        ..body = Code('Object.hashAll([$values])'),
    );
  }

  Class _emitRulesBase(_PayloadRulesBase declaration) {
    Method parser(String name, String type) => Method(
      (builder) => builder
        ..name = name
        ..returns = refer(type)
        ..annotations.add(refer('override'))
        ..requiredParameters.add(
          Parameter(
            (builder) => builder
              ..name = 'json'
              ..type = refer('Map<String, dynamic>'),
          ),
        )
        ..lambda = true
        ..body = Code('$type.fromJson(json)'),
    );

    return Class(
      (builder) => builder
        ..name = declaration.name
        ..abstract = true
        ..extend = TypeReference(
          (builder) => builder
            ..symbol = 'GameRules'
            ..types.addAll([
              refer(declaration.observation),
              refer(declaration.action),
              refer(declaration.config),
            ]),
        )
        ..constructors.add(Constructor((builder) => builder.constant = true))
        ..methods.addAll([
          parser('parseConfig', declaration.config),
          parser('parseObservation', declaration.observation),
          parser('parseAction', declaration.action),
          Method(
            (builder) => builder
              ..name = 'serializeAction'
              ..returns = refer('Map<String, dynamic>')
              ..annotations.add(refer('override'))
              ..requiredParameters.add(
                Parameter(
                  (builder) => builder
                    ..name = 'action'
                    ..type = refer(declaration.action),
                ),
              )
              ..lambda = true
              ..body = const Code('action.toJson()'),
          ),
        ]),
    );
  }

  static final List<Method> _runtimeHelpers = [
    _helper(
      name: '_payloadEquals',
      returns: 'bool',
      parameters: [('Object?', 'left'), ('Object?', 'right')],
      body: r'''
if (identical(left, right)) return true;
if (left is List && right is List) {
  return left.length == right.length &&
      Iterable<int>.generate(left.length)
          .every((index) => _payloadEquals(left[index], right[index]));
}
if (left is Map && right is Map) {
  return left.length == right.length &&
      left.keys.every(
        (key) =>
            right.containsKey(key) && _payloadEquals(left[key], right[key]),
      );
}
return left == right;
''',
    ),
    _helper(
      name: '_payloadHash',
      returns: 'int',
      parameters: [('Object?', 'value')],
      body: r'''
if (value is List) return Object.hashAll(value.map(_payloadHash));
if (value is Map) {
  final keys = value.keys.toList()
    ..sort((left, right) => left.toString().compareTo(right.toString()));
  return Object.hashAll(
    keys.map((key) => Object.hash(key, _payloadHash(value[key]))),
  );
}
return value.hashCode;
''',
    ),
    _helper(
      name: '_payloadRequired',
      returns: 'Object?',
      parameters: [
        ('Map<String, dynamic>', 'json'),
        ('String', 'key'),
        ('String', 'path'),
      ],
      body: r'''
if (json.containsKey(key)) return json[key];
throw FormatException('$path: required field is missing');
''',
    ),
    _guardHelper(
      name: '_payloadMap',
      returns: 'Map<String, dynamic>',
      acceptedType: 'Map<String, dynamic>',
      expected: 'an object',
    ),
    _guardHelper(
      name: '_payloadList',
      returns: 'List<dynamic>',
      acceptedType: 'List<dynamic>',
      expected: 'an array',
    ),
    _guardHelper(
      name: '_payloadString',
      returns: 'String',
      acceptedType: 'String',
      expected: 'a string',
    ),
    _guardHelper(
      name: '_payloadInt',
      returns: 'int',
      acceptedType: 'int',
      expected: 'an integer',
    ),
    _guardHelper(
      name: '_payloadNum',
      returns: 'num',
      acceptedType: 'num',
      expected: 'a number',
    ),
    _guardHelper(
      name: '_payloadBool',
      returns: 'bool',
      acceptedType: 'bool',
      expected: 'a boolean',
    ),
  ];

  static Method _guardHelper({
    required String name,
    required String returns,
    required String acceptedType,
    required String expected,
  }) => _helper(
    name: name,
    returns: returns,
    parameters: [('Object?', 'value'), ('String', 'path')],
    body:
        "if (value is $acceptedType) return value;\n"
        "throw FormatException('\$path: expected $expected');",
  );

  static Method _helper({
    required String name,
    required String returns,
    required List<(String, String)> parameters,
    required String body,
  }) => Method(
    (builder) => builder
      ..name = name
      ..returns = refer(returns)
      ..requiredParameters.addAll([
        for (final (type, name) in parameters)
          Parameter(
            (builder) => builder
              ..name = name
              ..type = refer(type),
          ),
      ])
      ..body = Code(body),
  );
}

String _dartString(String value) {
  // `code_builder.literalString` deliberately leaves `$` and backslashes
  // untouched. JSON's double-quoted escaping is also valid Dart escaping;
  // only interpolation needs one additional Dart-specific escape.
  return jsonEncode(value).replaceAll(r'$', r'\$');
}

String _dartPath(String wireName) {
  final suffix = _dartString('.$wireName');
  return '${r'"$path'}${suffix.substring(1)}';
}
