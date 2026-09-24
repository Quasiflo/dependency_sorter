import 'package:dependency_sorter/dependency_sorter.dart';
import 'package:test/test.dart';

void main() {
  group('sortPubspecContents', () {
    test('leaves an already-sorted pubspec untouched', () {
      const input = '''
name: example

dependencies:
  args: ^2.0.0
  yaml: ^3.0.0
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isFalse);
      expect(result.sortedSections, isEmpty);
      expect(result.contents, input);
    });

    test('sorts a simple unsorted dependencies section', () {
      const input = '''
name: example

dependencies:
  yaml: ^3.0.0
  args: ^2.0.0
''';
      const expected = '''
name: example

dependencies:
  args: ^2.0.0
  yaml: ^3.0.0
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isTrue);
      expect(result.sortedSections, ['dependencies']);
      expect(result.contents, expected);
    });

    test('sorts all three sections and reports each', () {
      const input = '''
name: example

dependencies:
  yaml: any
  args: any
dev_dependencies:
  test: any
  lints: any
dependency_overrides:
  zeta: any
  alpha: any
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.sortedSections, ['dependencies', 'dev_dependencies', 'dependency_overrides']);
      expect(result.contents, contains('dependencies:\n  args: any\n  yaml: any'));
      expect(result.contents, contains('dev_dependencies:\n  lints: any\n  test: any'));
      expect(result.contents, contains('dependency_overrides:\n  alpha: any\n  zeta: any'));
    });

    test('respects disabled sections', () {
      const input = '''
dependencies:
  yaml: any
  args: any
dev_dependencies:
  test: any
  lints: any
''';
      final result = sortPubspecContents(input, const SortConfig(sortDevDependencies: false));
      expect(result.sortedSections, ['dependencies']);
      expect(result.contents, contains('args: any\n  yaml: any'));
      // dev_dependencies left alone.
      expect(result.contents, contains('test: any\n  lints: any'));
    });

    test('does nothing when every section is disabled', () {
      const input = 'dependencies:\n  b: any\n  a: any\n';
      const config = SortConfig(sortDependencies: false, sortDevDependencies: false, sortDependencyOverrides: false);
      final result = sortPubspecContents(input, config);
      expect(result.changed, isFalse);
      expect(result.contents, input);
    });

    test('moves multiline git/path/sdk blocks as a whole', () {
      const input = '''
dependencies:
  my_app:
    path: ../my_app
    version: ^1.0.0
  args: ^2.0.0
  flutter:
    sdk: flutter
''';
      const expected = '''
dependencies:
  args: ^2.0.0
  flutter:
    sdk: flutter
  my_app:
    path: ../my_app
    version: ^1.0.0
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('carries leading comments with their entry', () {
      const input = '''
dependencies:
  # YAML support.
  yaml: ^3.0.0
  # CLI args.
  args: ^2.0.0
''';
      const expected = '''
dependencies:
  # CLI args.
  args: ^2.0.0
  # YAML support.
  yaml: ^3.0.0
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('preserves trailing inline comments on entries', () {
      const input = '''
dependencies:
  yaml: ^3.0.0 # keep me
  args: ^2.0.0 # me too
''';
      const expected = '''
dependencies:
  args: ^2.0.0 # me too
  yaml: ^3.0.0 # keep me
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('preserves comments inside nested values', () {
      const input = '''
dependencies:
  zeta:
    git:
      url: https://example.com/zeta.git
      # Pinned for stability.
      ref: abc123
  alpha: ^1.0.0
''';
      const expected = '''
dependencies:
  alpha: ^1.0.0
  zeta:
    git:
      url: https://example.com/zeta.git
      # Pinned for stability.
      ref: abc123
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('pins blank separators in place while entries reorder', () {
      const input = '''
dependencies:
  yaml: any

  args: any
''';
      // The separator stays between the first and second slot; only the
      // entries permute around it.
      const expected = '''
dependencies:
  args: any

  yaml: any
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
      // And the result is stable.
      final again = sortPubspecContents(result.contents, SortConfig.defaults);
      expect(again.changed, isFalse);
    });

    test('keeps end-of-section blanks and comments at the end', () {
      const input = '''
dependencies:
  yaml: any
  args: any
  # Trailing note about the section.

next_section: true
''';
      // The trailing blank and comment belong to the end of the section,
      // not to the entry above them, so they stay at the end.
      const expected = '''
dependencies:
  args: any
  yaml: any
  # Trailing note about the section.

next_section: true
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('leaves the separator above the next section in place', () {
      // Regression test: the blank line separating dev_dependencies from
      // the following section used to travel with the moved entry.
      const input = '''
dev_dependencies:
  flutter_test:
    sdk: flutter
  dependency_sorter:
    git: https://example.com/dependency_sorter.git

flutter:
  uses-material-design: true
''';
      const expected = '''
dev_dependencies:
  dependency_sorter:
    git: https://example.com/dependency_sorter.git
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('keeps a leading blank line at the top of the section', () {
      const input = '''
dependencies:

  yaml: any
  args: any
''';
      const expected = '''
dependencies:

  args: any
  yaml: any
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('handles quoted keys', () {
      const input = '''
dependencies:
  "yaml": any
  'args': any
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isTrue);
      expect(result.contents.indexOf('args'), lessThan(result.contents.indexOf('yaml')));
    });

    test('uses case-sensitive code-unit order like the lint', () {
      const input = '''
dependencies:
  yaml: any
  Args: any
  args: any
''';
      // 'Args' (65..) < 'args' (97..) < 'yaml' in code-unit order.
      const expected = '''
dependencies:
  Args: any
  args: any
  yaml: any
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, expected);
    });

    test('leaves files without dependency sections unchanged', () {
      const input = 'name: example\ndescription: Just a package.\n';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isFalse);
      expect(result.contents, input);
    });

    test('leaves empty sections unchanged', () {
      const input = 'name: example\ndependencies:\ndev_dependencies:\n';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isFalse);
      expect(result.contents, input);
    });

    test('leaves inline flow maps unchanged', () {
      const input = 'name: example\ndependencies: {}\n';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isFalse);
      expect(result.contents, input);
    });

    test('ignores similarly named nested keys', () {
      const input = '''
name: example

dependencies:
  yaml: any
  args: any

flutter:
  dependencies: not-a-real-section
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.sortedSections, ['dependencies']);
      expect(result.contents, contains('dependencies: not-a-real-section'));
    });

    test('does not touch dependency keys under other top-level maps', () {
      const input = '''
dependencies:
  yaml: any
  args: any
environment:
  sdk: ^3.0.0
''';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, contains('environment:\n  sdk: ^3.0.0'));
    });

    test('is idempotent', () {
      const input = '''
# Header comment.
dependencies:
  # b comment.
  b:
    path: ../b # inline.
  a: ^1.0.0

  # trailing.
dev_dependencies:
  test: any
  lints: any
''';
      final once = sortPubspecContents(input, SortConfig.defaults);
      final twice = sortPubspecContents(once.contents, SortConfig.defaults);
      expect(twice.changed, isFalse);
      expect(twice.contents, once.contents);
    });

    test('preserves missing trailing newline', () {
      const input = 'dependencies:\n  b: any\n  a: any';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, 'dependencies:\n  a: any\n  b: any');
      expect(result.contents.endsWith('\n'), isFalse);
    });

    test('preserves CRLF line endings and trailing newline', () {
      const input = 'dependencies:\r\n  b: any\r\n  a: any\r\n';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.contents, 'dependencies:\r\n  a: any\r\n  b: any\r\n');
    });

    test('leaves duplicate keys in stable order without crashing', () {
      const input = 'dependencies:\n  b: "1"\n  a: any\n  b: "2"\n';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isTrue);
      expect(result.contents, 'dependencies:\n  a: any\n  b: "1"\n  b: "2"\n');
    });

    test('leaves sections with unexpected indentation unchanged', () {
      const input = 'dependencies:\n b: any\n   a: any\n';
      final result = sortPubspecContents(input, SortConfig.defaults);
      expect(result.changed, isFalse);
      expect(result.contents, input);
    });
  });

  group('parseSortConfig', () {
    test('returns defaults when the key is absent', () {
      expect(parseSortConfig('name: example\n'), SortConfig.defaults);
    });

    test('parses partial flags, keeping defaults for the rest', () {
      const input = '''
dependency_sorter:
  sort_dev_dependencies: false
''';
      expect(parseSortConfig(input), const SortConfig(sortDevDependencies: false));
    });

    test('parses all flags', () {
      const input = '''
dependency_sorter:
  sort_dependencies: false
  sort_dev_dependencies: false
  sort_dependency_overrides: false
''';
      expect(parseSortConfig(input), const SortConfig(sortDependencies: false, sortDevDependencies: false, sortDependencyOverrides: false));
    });

    test('ignores unknown keys', () {
      const input = '''
dependency_sorter:
  some_future_option: false
''';
      expect(parseSortConfig(input), SortConfig.defaults);
    });

    test('throws on non-boolean values', () {
      const input = '''
dependency_sorter:
  sort_dependencies: yes-please
''';
      expect(() => parseSortConfig(input), throwsFormatException);
    });

    test('throws when the section is not a map', () {
      const input = 'dependency_sorter: false\n';
      expect(() => parseSortConfig(input), throwsFormatException);
    });
  });
}
