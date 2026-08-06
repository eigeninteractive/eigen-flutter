import 'dart:convert';
import 'dart:io';

import 'package:code_builder/code_builder.dart';
import 'package:dart_style/dart_style.dart';

part 'payload_emitter.dart';

/// Generates standalone immutable Dart payload types from an EigenInteractive
/// game contract. This is tooling code used by `bin/generate_payloads.dart`; game
/// applications do not import it at runtime.
String generatePayloadLibrary(Map<String, dynamic> contract) {
  if (contract['formatVersion'] != 1) {
    throw FormatException(
      'Unsupported game contract formatVersion ${contract['formatVersion']}',
    );
  }
  final game = _typeName(contract['game'] as String);
  final versions = contract['versions'] as Map<String, dynamic>;
  final declarations = <_PayloadDeclaration>[];

  final orderedVersions = versions.keys.toList()
    ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  for (final version in orderedVersions) {
    final prefix = '${game}V$version';
    final versionNode = versions[version] as Map<String, dynamic>;
    final schemas = versionNode['schemas'] as Map<String, dynamic>;
    final context = _GenerationContext(prefix, declarations);

    for (final payload in const ['observation', 'action', 'config']) {
      context.registerRoot(
        _pascal(payload),
        schemas[payload] as Map<String, dynamic>,
      );
    }

    context
      ..emitDefinitions()
      ..emitRoot('Observation')
      ..emitRoot('Action')
      ..emitRoot('Config');
    declarations.add(
      _PayloadRulesBase(
        name: '${prefix}RulesBase',
        observation: '${prefix}Observation',
        action: '${prefix}Action',
        config: '${prefix}Config',
      ),
    );
  }
  return const _PayloadEmitter().emit(declarations);
}

/// Copies validated fixture documents embedded in a contract into the layout
/// consumed by `package:eigen_flutter/testing.dart`.
void writeContractFixtures(
  Map<String, dynamic> contract,
  Directory outputDirectory,
) {
  for (final entry in contractFixtureContents(contract).entries) {
    final file = File('${outputDirectory.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
}

/// Returns the normalized fixture files embedded in [contract], keyed by their
/// safe POSIX relative paths. Used by both write mode and the CLI drift check.
Map<String, String> contractFixtureContents(Map<String, dynamic> contract) {
  final files = <String, String>{};
  for (final fixture in contract['fixtures'] as List<dynamic>) {
    final item = fixture as Map<String, dynamic>;
    final relativePath = item['path'] as String;
    if (relativePath.startsWith('/') ||
        relativePath.split('/').contains('..')) {
      throw FormatException('Unsafe fixture path: $relativePath');
    }
    files[relativePath] =
        '${const JsonEncoder.withIndent('  ').convert(item['document'])}\n';
  }
  return files;
}

final class _GenerationContext {
  _GenerationContext(this.prefix, this._declarations);

  final String prefix;
  final List<_PayloadDeclaration> _declarations;
  final Map<String, Map<String, dynamic>> _definitions = {};
  final Map<String, Map<String, dynamic>> _roots = {};
  final Map<String, String> _emittedSchemas = {};

  void registerRoot(String name, Map<String, dynamic> schema) {
    _roots[name] = schema;
    final definitions = schema[r'$defs'] as Map<String, dynamic>? ?? const {};
    for (final entry in definitions.entries) {
      final value = entry.value as Map<String, dynamic>;
      final prior = _definitions[entry.key];
      if (prior != null &&
          jsonEncode(_canonical(prior)) != jsonEncode(_canonical(value))) {
        throw FormatException(
          'Schema definition ${entry.key} differs between payloads',
        );
      }
      _definitions[entry.key] = value;
    }
  }

  void emitDefinitions() {
    for (final entry in _definitions.entries) {
      _emitNamed(_definitionName(entry.key), entry.value);
    }
  }

  void emitRoot(String name) {
    final schema = _roots[name]!;
    _emitNamed('$prefix$name', schema);
  }

  String _definitionName(String name) {
    final dartName = _pascal(name);
    return dartName.startsWith(prefix) ? dartName : '$prefix$dartName';
  }

  void _emitNamed(String name, Map<String, dynamic> schema) {
    final signature = jsonEncode(_canonical(schema));
    final prior = _emittedSchemas[name];
    if (prior != null) {
      if (prior != signature) {
        throw FormatException(
          'Schemas that map to Dart type $name have incompatible shapes',
        );
      }
      return;
    }
    _emittedSchemas[name] = signature;
    if (_isStringEnum(schema)) {
      _declarations.add(_emitEnum(name, schema));
      return;
    }
    if (schema['type'] == 'object') {
      _declarations.add(_emitClass(name, schema));
      return;
    }
    throw FormatException(
      'Named schema $name must be an object or string enum',
    );
  }

  _PayloadEnum _emitEnum(String name, Map<String, dynamic> schema) {
    final values = (schema['enum'] as List<dynamic>).cast<String>();
    if (values.isEmpty) {
      throw FormatException('Enum $name must declare at least one value');
    }
    final names = <String>{};
    return _PayloadEnum(
      name: name,
      values: [
        for (final value in values)
          _PayloadEnumValue(
            name: _uniqueIdentifier(
              names,
              _identifier(value),
              owner: name,
              wireName: value,
            ),
            wireValue: value,
          ),
      ],
    );
  }

  _PayloadClass _emitClass(String name, Map<String, dynamic> schema) {
    final properties =
        (schema['properties'] as Map<String, dynamic>? ?? const {});
    final required = (schema['required'] as List<dynamic>? ?? const {})
        .cast<String>()
        .toSet();
    final fields = <_PayloadField>[];
    final fieldNames = <String>{};

    for (final entry in properties.entries) {
      final fieldSchema = entry.value as Map<String, dynamic>;
      final fieldName = _uniqueIdentifier(
        fieldNames,
        _identifier(entry.key),
        owner: name,
        wireName: entry.key,
      );
      final isRequired = required.contains(entry.key);
      final type = _typeOf(
        fieldSchema,
        suggestedName: '$name${_pascal(entry.key)}',
      );
      final resolvedType = isRequired || type.nullable
          ? type
          : type.asNullable();
      final wireLiteral = _dartString(entry.key);
      final path = _dartPath(entry.key);
      final value = isRequired
          ? '_payloadRequired(json, $wireLiteral, $path)'
          : 'json[$wireLiteral]';
      final decode = _decode(
        fieldSchema,
        value,
        path,
        suggestedName: '$name${_pascal(entry.key)}',
      );
      final encode = isRequired
          ? _encode(
              fieldSchema,
              fieldName,
              suggestedName: '$name${_pascal(entry.key)}',
            )
          : _encodeNonNull(
              fieldSchema,
              '$fieldName!',
              suggestedName: '$name${_pascal(entry.key)}',
            );
      fields.add(
        _PayloadField(
          wireName: entry.key,
          name: fieldName,
          type: resolvedType,
          required: isRequired,
          decode: decode,
          encode: encode,
          nullAwareMapValue: !isRequired && _usesIdentityEncoding(fieldSchema),
        ),
      );
    }

    return _PayloadClass(name: name, fields: fields);
  }

  _DartType _typeOf(
    Map<String, dynamic> schema, {
    required String suggestedName,
  }) {
    final nullable = _nullableBranch(schema);
    if (nullable != null) {
      return _typeOf(nullable, suggestedName: suggestedName).asNullable();
    }
    final reference = schema[r'$ref'] as String?;
    if (reference != null) {
      final name = reference.split('/').last;
      return _DartType(_definitionName(name));
    }
    if (_isStringEnum(schema)) {
      final inlineName = suggestedName;
      _definitions.putIfAbsent('__inline__$inlineName', () => schema);
      _emitNamed(inlineName, schema);
      return _DartType(inlineName);
    }
    if (schema['type'] == 'object') {
      _emitNamed(suggestedName, schema);
      return _DartType(suggestedName);
    }
    if (schema['type'] == 'array') {
      final items = _arrayItemSchema(schema);
      final itemType = _typeOf(items, suggestedName: '${suggestedName}Item');
      return _DartType('List<${itemType.dart}>', list: true);
    }
    return switch (schema['type']) {
      'integer' => const _DartType('int'),
      'number' => const _DartType('num'),
      'string' => const _DartType('String'),
      'boolean' => const _DartType('bool'),
      _ when _numericConstants(schema) => const _DartType('int'),
      _ => throw FormatException(
        'Unsupported schema for $suggestedName: ${jsonEncode(schema)}',
      ),
    };
  }

  Map<String, dynamic> _arrayItemSchema(Map<String, dynamic> schema) {
    final items = schema['items'];
    if (items is Map<String, dynamic>) return items;
    final prefixItems = schema['prefixItems'] as List<dynamic>?;
    if (prefixItems == null || prefixItems.isEmpty) {
      throw const FormatException('Array schema has no items');
    }
    final first = prefixItems.first as Map<String, dynamic>;
    final signature = jsonEncode(_canonical(first));
    if (prefixItems.any((item) => jsonEncode(_canonical(item)) != signature)) {
      throw const FormatException(
        'Heterogeneous tuples are not supported yet; use a named object',
      );
    }
    return first;
  }

  String _decode(
    Map<String, dynamic> schema,
    String value,
    String path, {
    required String suggestedName,
  }) {
    final nullable = _nullableBranch(schema);
    if (nullable != null) {
      return '$value == null ? null : ${_decode(nullable, value, path, suggestedName: suggestedName)}';
    }
    final reference = schema[r'$ref'] as String?;
    if (reference != null) {
      final name = _definitionName(reference.split('/').last);
      final target = _definitions[reference.split('/').last]!;
      if (_isStringEnum(target)) return '$name.fromJson($value, $path)';
      return '$name.fromJson(_payloadMap($value, $path))';
    }
    if (_isStringEnum(schema)) {
      return '$suggestedName.fromJson($value, $path)';
    }
    if (schema['type'] == 'object') {
      return '$suggestedName.fromJson(_payloadMap($value, $path))';
    }
    if (schema['type'] == 'array') {
      final item = _arrayItemSchema(schema);
      final itemDecode = _decode(
        item,
        'item',
        _indexedPath(path),
        suggestedName: '${suggestedName}Item',
      );
      return '_payloadList($value, $path).indexed.map((entry) { '
          'final index = entry.\$1; final item = entry.\$2; '
          'return $itemDecode; }).toList()';
    }
    return switch (schema['type']) {
      'integer' => '_payloadInt($value, $path)',
      'number' => '_payloadNum($value, $path)',
      'string' => '_payloadString($value, $path)',
      'boolean' => '_payloadBool($value, $path)',
      _ when _numericConstants(schema) => '_payloadInt($value, $path)',
      _ => throw FormatException('Unsupported decoder for $suggestedName'),
    };
  }

  String _encode(
    Map<String, dynamic> schema,
    String value, {
    required String suggestedName,
  }) {
    final nullable = _nullableBranch(schema);
    if (nullable != null) {
      return '$value == null ? null : ${_encode(nullable, '$value!', suggestedName: suggestedName)}';
    }
    final reference = schema[r'$ref'] as String?;
    if (reference != null) {
      final target = _definitions[reference.split('/').last]!;
      return _isStringEnum(target) ? '$value.toJson()' : '$value.toJson()';
    }
    if (_isStringEnum(schema)) return '$value.toJson()';
    if (schema['type'] == 'object') return '$value.toJson()';
    if (schema['type'] == 'array') {
      final item = _arrayItemSchema(schema);
      return '$value.map((item) => ${_encode(item, 'item', suggestedName: '${suggestedName}Item')}).toList()';
    }
    return value;
  }

  String _encodeNonNull(
    Map<String, dynamic> schema,
    String value, {
    required String suggestedName,
  }) {
    final nullable = _nullableBranch(schema);
    return _encode(nullable ?? schema, value, suggestedName: suggestedName);
  }
}

String _indexedPath(String path) {
  if (path.startsWith('"') && path.endsWith('"')) {
    return '${path.substring(0, path.length - 1)}[\$index]"';
  }
  return "$path + '[\$index]'";
}

final class _DartType {
  const _DartType(this.base, {this.nullable = false, this.list = false});

  final String base;
  final bool nullable;
  final bool list;

  String get dart => nullable ? '$base?' : base;

  _DartType asNullable() =>
      nullable ? this : _DartType(base, nullable: true, list: list);
}

Map<String, dynamic>? _nullableBranch(Map<String, dynamic> schema) {
  final anyOf = schema['anyOf'] as List<dynamic>?;
  if (anyOf == null || anyOf.length != 2) return null;
  final branches = anyOf.cast<Map<String, dynamic>>();
  final nullIndex = branches.indexWhere((branch) => branch['type'] == 'null');
  return nullIndex == -1 ? null : branches[1 - nullIndex];
}

bool _numericConstants(Map<String, dynamic> schema) {
  final anyOf = schema['anyOf'] as List<dynamic>?;
  return anyOf != null &&
      anyOf.isNotEmpty &&
      anyOf.every(
        (branch) =>
            branch is Map<String, dynamic> &&
            branch['const'] is num &&
            (branch['const'] as num).toInt() == branch['const'],
      );
}

bool _usesIdentityEncoding(Map<String, dynamic> schema) {
  final nullable = _nullableBranch(schema);
  if (nullable != null) return _usesIdentityEncoding(nullable);
  return schema[r'$ref'] == null &&
      !_isStringEnum(schema) &&
      (const {
            'integer',
            'number',
            'string',
            'boolean',
          }.contains(schema['type']) ||
          _numericConstants(schema));
}

bool _isStringEnum(Map<String, dynamic> schema) =>
    schema['type'] == 'string' &&
    schema['enum'] is List<dynamic> &&
    (schema['enum'] as List<dynamic>).every((value) => value is String);

Object? _canonical(Object? value) {
  if (value is List<dynamic>) return value.map(_canonical).toList();
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  return value;
}

String _pascal(String value) => value
    .split(RegExp('[^A-Za-z0-9]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

String _typeName(String value) {
  final pascal = _pascal(value);
  if (pascal.isEmpty) {
    throw FormatException('Game name "$value" cannot form a Dart type name');
  }
  return RegExp(r'^[0-9]').hasMatch(pascal) ? 'Game$pascal' : pascal;
}

String _identifier(String value) {
  final pascal = _pascal(value);
  if (pascal.isEmpty) {
    throw FormatException('Wire name "$value" cannot form a Dart identifier');
  }
  final candidate = RegExp(r'^[0-9]').hasMatch(pascal)
      ? 'value$pascal'
      : '${pascal[0].toLowerCase()}${pascal.substring(1)}';
  return _dartKeywords.contains(candidate) ? '${candidate}Value' : candidate;
}

String _uniqueIdentifier(
  Set<String> used,
  String identifier, {
  required String owner,
  required String wireName,
}) {
  if (used.add(identifier)) return identifier;
  throw FormatException(
    'Wire name "$wireName" collides with another member of $owner after '
    'Dart identifier normalization ($identifier)',
  );
}

const _dartKeywords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'false',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};
