import 'dart:io';

import 'package:dependency_sorter/dependency_sorter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Golden tests: each `test/fixtures/*.unsorted.yaml` is sorted with the
/// default config and compared byte-for-byte against its `.sorted.yaml`
/// sibling.
///
/// To update goldens after an intentional behavior change, delete the
/// `.sorted.yaml` files and run this test with `UPDATE_GOLDENS=true`; then
/// review the resulting diff carefully before committing.
void main() {
  group('golden fixtures', () {
    final Directory fixtures = Directory(
      p.join(Directory.current.path, 'test', 'fixtures'),
    );
    final List<File> inputs =
        fixtures
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.unsorted.yaml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('fixtures directory is not empty', () {
      expect(inputs, isNotEmpty);
    });

    for (final File input in inputs) {
      final String name = p.basenameWithoutExtension(
        p.basenameWithoutExtension(input.path),
      );
      test(name, () {
        final File expectedFile = File(
          p.join(fixtures.path, '$name.sorted.yaml'),
        );
        final SortResult result = sortPubspecContents(
          input.readAsStringSync(),
          SortConfig.defaults,
        );
        if (Platform.environment['UPDATE_GOLDENS'] == 'true') {
          expectedFile.writeAsStringSync(result.contents);
          return;
        }
        expect(
          expectedFile.existsSync(),
          isTrue,
          reason: 'missing golden $name.sorted.yaml',
        );
        expect(result.contents, expectedFile.readAsStringSync());
      });
    }
  });
}
