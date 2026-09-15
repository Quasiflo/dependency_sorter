import 'dart:math';

import 'package:dependency_sorter/dependency_sorter.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Property tests over randomly generated pubspecs (fixed seed, so runs are
/// deterministic).
///
/// For every generated document we assert:
/// - enabled sections come out sorted,
/// - the YAML data is unchanged (key order aside),
/// - sorting is idempotent,
/// - disabled sections keep their original key order.
void main() {
  group('sortPubspecContents properties', () {
    test('holds over randomized pubspecs', () {
      const iterations = 200;
      final Random random = Random(42);
      for (var i = 0; i < iterations; i++) {
        final String input = _generatePubspec(random);
        final SortConfig config = _generateConfig(random);
        final SortResult result = sortPubspecContents(input, config);

        _expectSortedSections(result.contents, config);
        expect(
          _canonicalize(loadYaml(result.contents)),
          equals(_canonicalize(loadYaml(input))),
          reason: 'iteration $i changed the YAML data:\n$input',
        );
        final SortResult again = sortPubspecContents(result.contents, config);
        expect(
          again.changed,
          isFalse,
          reason: 'iteration $i is not idempotent:\n$input',
        );
        _expectDisabledUntouched(input, result.contents, config);
      }
    });
  });
}

const List<String> _keyPool = [
  'args',
  'yaml',
  'path',
  'meta',
  'collection',
  'http',
  'test',
  'lints',
  'flutter',
  'flutter_test',
  'cupertino_icons',
  'shared_icons',
  'provider',
  'riverpod',
  'Args',
  'YAML',
  'my_package',
  'my-package',
  'my.package',
  'a',
  'Zebra',
];

const List<String> _sections = [
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
];

String _generatePubspec(Random random) {
  final StringBuffer out = StringBuffer('name: example\n');
  final String lineEnding = random.nextBool() ? '\r\n' : '\n';
  if (random.nextBool()) out.write('description: generated fixture$lineEnding');
  for (final String section in _sections) {
    if (!random.nextBool()) continue;
    out.write('$lineEnding$section:$lineEnding');
    final int count = random.nextInt(6);
    // Sample without replacement: duplicate keys are rejected by the YAML
    // parser (the sorter itself tolerates them; duplicates are covered by
    // dedicated unit tests instead).
    final List<String> shuffled = List.of(_keyPool)..shuffle(random);
    final List<String> keys = shuffled.take(count).toList();
    for (final String key in keys) {
      if (random.nextDouble() < 0.2) out.write(lineEnding);
      if (random.nextDouble() < 0.25) {
        out.write('  # Comment for $key$lineEnding');
      }
      final String renderedKey = random.nextDouble() < 0.15 ? "'$key'" : key;
      final String value = _generateValue(random, key);
      final String inline = random.nextDouble() < 0.2 ? ' # inline note' : '';
      out.write('  $renderedKey:$value$inline$lineEnding');
    }
    if (random.nextDouble() < 0.4) out.write(lineEnding);
  }
  if (random.nextDouble() < 0.3) {
    out.write(
      '${lineEnding}flutter:$lineEnding  uses-material-design: true$lineEnding',
    );
  }
  var text = out.toString();
  // Randomly drop the trailing newline; both forms must round-trip.
  if (random.nextBool() && text.endsWith(lineEnding)) {
    text = text.substring(0, text.length - lineEnding.length);
  }
  return text;
}

String _generateValue(Random random, String key) {
  final double roll = random.nextDouble();
  if (roll < 0.5) return ' any';
  if (roll < 0.65) return ' ^1.2.3';
  if (roll < 0.75) {
    return '\n    sdk: flutter';
  }
  if (roll < 0.85) {
    return '\n    path: ../$key';
  }
  return '\n    git:\n      url: https://example.com/$key.git\n      ref: main';
}

SortConfig _generateConfig(Random random) {
  return SortConfig(
    sortDependencies: random.nextBool(),
    sortDevDependencies: random.nextBool(),
    sortDependencyOverrides: random.nextBool(),
  );
}

void _expectSortedSections(String contents, SortConfig config) {
  final Object? document = loadYaml(contents);
  if (document is! YamlMap) return;
  for (final MapEntry<String, bool> section in {
    'dependencies': config.sortDependencies,
    'dev_dependencies': config.sortDevDependencies,
    'dependency_overrides': config.sortDependencyOverrides,
  }.entries) {
    if (!section.value) continue;
    final Object? raw = document[section.key];
    if (raw is! YamlMap) continue;
    final List<String> keys = [
      for (final Object? key in raw.keys) key.toString(),
    ];
    final List<String> sorted = List.of(keys)..sort();
    expect(keys, orderedEquals(sorted), reason: section.key);
  }
}

void _expectDisabledUntouched(String input, String output, SortConfig config) {
  bool enabled(String section) {
    switch (section) {
      case 'dependencies':
        return config.sortDependencies;
      case 'dev_dependencies':
        return config.sortDevDependencies;
      case 'dependency_overrides':
        return config.sortDependencyOverrides;
      default:
        return true;
    }
  }

  List<String> keysOf(String contents, String section) {
    final Object? document = loadYaml(contents);
    if (document is! YamlMap) return const [];
    final Object? raw = document[section];
    if (raw is! YamlMap) return const [];
    return [for (final Object? key in raw.keys) key.toString()];
  }

  for (final String section in _sections) {
    if (enabled(section)) continue;
    expect(
      keysOf(output, section),
      orderedEquals(keysOf(input, section)),
      reason: 'disabled section $section was reordered',
    );
  }
}

/// Converts parsed YAML into plain collections with maps sorted by key, so
/// [equals] compares data ignoring key order.
Object? _canonicalize(Object? node) {
  if (node is YamlMap) {
    final List<MapEntry<String, Object?>> entries = [
      for (final MapEntry<Object?, Object?> entry in node.entries)
        MapEntry(entry.key.toString(), _canonicalize(entry.value)),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }
  if (node is YamlList) return [for (final item in node) _canonicalize(item)];
  return node;
}
