import 'package:dependency_sorter/dependency_sorter.dart';
import 'package:test/test.dart';

void main() {
  group('unifiedDiff', () {
    test('returns empty string for identical inputs', () {
      expect(unifiedDiff(path: 'pubspec.yaml', from: ['a', 'b'], to: ['a', 'b']), isEmpty);
    });

    test('returns empty string for two empty inputs', () {
      expect(unifiedDiff(path: 'pubspec.yaml', from: const [], to: const []), isEmpty);
    });

    test('marks reordered lines as deletions and insertions', () {
      final diff = unifiedDiff(path: 'pubspec.yaml', from: const ['dependencies:', '  yaml: any', '  args: any'], to: const ['dependencies:', '  args: any', '  yaml: any']);
      expect(diff, contains('--- a/pubspec.yaml'));
      expect(diff, contains('+++ b/pubspec.yaml'));
      expect(diff, contains('@@ -1,3 +1,3 @@'));
      // The moved line is expressed as a deletion plus an insertion; the
      // shared line stays as context.
      expect(diff, contains('-  yaml: any'));
      expect(diff, contains('+  yaml: any'));
      // Context lines are shown with a leading space.
      expect(diff, contains(' dependencies:'));
      expect(diff, contains('   args: any'));
    });

    test('splits distant changes into separate hunks', () {
      final from = <String>['header: true', ...List.generate(10, (final i) => 'pad_$i: $i'), 'old_a: 1', ...List.generate(10, (final i) => 'mid_$i: $i'), 'old_b: 2'];
      final to = <String>['header: true', ...List.generate(10, (final i) => 'pad_$i: $i'), 'new_a: 1', ...List.generate(10, (final i) => 'mid_$i: $i'), 'new_b: 2'];
      final diff = unifiedDiff(path: 'pubspec.yaml', from: from, to: to);
      // Two change regions far apart produce two hunk headers.
      expect('@@'.allMatches(diff).length, 4);
      expect(diff, contains('-old_a: 1'));
      expect(diff, contains('+new_a: 1'));
      expect(diff, contains('-old_b: 2'));
      expect(diff, contains('+new_b: 2'));
    });

    test('handles appended lines', () {
      final diff = unifiedDiff(path: 'pubspec.yaml', from: const ['a: 1'], to: const ['a: 1', 'b: 2']);
      expect(diff, contains('+b: 2'));
      final deletions = diff.split('\n').where((final line) => line.startsWith('-') && !line.startsWith('---')).toList();
      expect(deletions, isEmpty);
    });
    test('colors deletions, insertions and headers when enabled', () {
      final diff = unifiedDiff(path: 'pubspec.yaml', from: const ['dependencies:', '  b: any'], to: const ['dependencies:', '  a: any'], color: true);
      expect(diff, contains('\x1b[31m-  b: any\x1b[0m'));
      expect(diff, contains('\x1b[32m+  a: any\x1b[0m'));
      expect(diff, contains('\x1b[36m@@'));
      expect(diff, contains('\x1b[1m--- a/pubspec.yaml\x1b[0m'));
    });
  });
}
