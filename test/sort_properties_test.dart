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
      final random = Random(42);
      for (var i = 0; i < iterations; i++) {
        final input = _generatePubspec(random);
        final config = _generateConfig(random);
        final result = sortPubspecContents(input, config);

        _expectSortedSections(result.contents, config);
        expect(_canonicalize(loadYaml(result.contents)), equals(_canonicalize(loadYaml(input))), reason: 'iteration $i changed the YAML data:\n$input');
        final again = sortPubspecContents(result.contents, config);
        expect(again.changed, isFalse, reason: 'iteration $i is not idempotent:\n$input');
        _expectDisabledUntouched(input, result.contents, config);
      }
    });
  });
}

const List<String> _keyPool = ['args', 'yaml', 'path', 'meta', 'collection', 'http', 'test', 'lints', 'flutter', 'flutter_test', 'cupertino_icons', 'shared_icons', 'provider', 'riverpod', 'Args', 'YAML', 'my_package', 'my-package', 'my.package', 'a', 'Zebra'];

const List<String> _sections = ['dependencies', 'dev_dependencies', 'dependency_overrides'];

String _generatePubspec(final Random random) {
  final out = StringBuffer('name: example\n');
  final lineEnding = random.nextBool() ? '\r\n' : '\n';
  if (random.nextBool()) {
    out.write('description: generated fixture$lineEnding');
  }
  for (final section in _sections) {
    if (!random.nextBool()) {
      continue;
    }
    out.write('$lineEnding$section:$lineEnding');
    final count = random.nextInt(6);
    // Sample without replacement: duplicate keys are rejected by the YAML
    // parser (the sorter itself tolerates them; duplicates are covered by
    // dedicated unit tests instead).
    final shuffled = List<String>.of(_keyPool)..shuffle(random);
    final keys = shuffled.take(count).toList();
    for (final key in keys) {
      if (random.nextDouble() < 0.2) {
        out.write(lineEnding);
      }
      if (random.nextDouble() < 0.25) {
        out.write('  # Comment for $key$lineEnding');
      }
      final renderedKey = random.nextDouble() < 0.15 ? "'$key'" : key;
      final value = _generateValue(random, key);
      final inline = random.nextDouble() < 0.2 ? ' # inline note' : '';
      out.write('  $renderedKey:$value$inline$lineEnding');
    }
    if (random.nextDouble() < 0.4) {
      out.write(lineEnding);
    }
  }
  if (random.nextDouble() < 0.3) {
    out.write('${lineEnding}flutter:$lineEnding  uses-material-design: true$lineEnding');
  }
  var text = out.toString();
  // Randomly drop the trailing newline; both forms must round-trip.
  if (random.nextBool() && text.endsWith(lineEnding)) {
    text = text.substring(0, text.length - lineEnding.length);
  }
  return text;
}

String _generateValue(final Random random, final String key) {
  final roll = random.nextDouble();
  if (roll < 0.5) {
    return ' any';
  }
  if (roll < 0.65) {
    return ' ^1.2.3';
  }
  if (roll < 0.75) {
    return '\n    sdk: flutter';
  }
  if (roll < 0.85) {
    return '\n    path: ../$key';
  }
  return '\n    git:\n      url: https://example.com/$key.git\n      ref: main';
}

SortConfig _generateConfig(final Random random) => SortConfig(sortDependencies: random.nextBool(), sortDevDependencies: random.nextBool(), sortDependencyOverrides: random.nextBool());

void _expectSortedSections(final String contents, final SortConfig config) {
  final Object? document = loadYaml(contents);
  if (document is! YamlMap) {
    return;
  }
  for (final section in {'dependencies': config.sortDependencies, 'dev_dependencies': config.sortDevDependencies, 'dependency_overrides': config.sortDependencyOverrides}.entries) {
    if (!section.value) {
      continue;
    }
    final Object? raw = document[section.key];
    if (raw is! YamlMap) {
      continue;
    }
    final keys = <String>[for (final Object? key in raw.keys) key.toString()];
    final sorted = List<String>.of(keys)..sort();
    expect(keys, orderedEquals(sorted), reason: section.key);
  }
}

void _expectDisabledUntouched(final String input, final String output, final SortConfig config) {
  bool enabled(final String section) {
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

  List<String> keysOf(final String contents, final String section) {
    final Object? document = loadYaml(contents);
    if (document is! YamlMap) {
      return const [];
    }
    final Object? raw = document[section];
    if (raw is! YamlMap) {
      return const [];
    }
    return [for (final Object? key in raw.keys) key.toString()];
  }

  for (final section in _sections) {
    if (enabled(section)) {
      continue;
    }
    expect(keysOf(output, section), orderedEquals(keysOf(input, section)), reason: 'disabled section $section was reordered');
  }
}

/// Converts parsed YAML into plain collections with maps sorted by key, so
/// [equals] compares data ignoring key order.
Object? _canonicalize(final Object? node) {
  if (node is YamlMap) {
    final entries = <MapEntry<String, Object?>>[for (final MapEntry<Object?, Object?> entry in node.entries) MapEntry(entry.key.toString(), _canonicalize(entry.value))]..sort((final a, final b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }
  if (node is YamlList) {
    return [for (final item in node) _canonicalize(item)];
  }
  return node;
}
