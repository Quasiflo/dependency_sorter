import 'package:dependency_sorter/dependency_sorter.dart';

/// Sorts the `dependencies` of a pubspec document.
///
/// Run with `dart run example/dependency_sorter_example.dart`.
void main() {
  const unsorted = '''
dependencies:
  yaml: any
  args: any
''';

  final result = sortPubspecContents(unsorted, SortConfig.defaults);
  // Example output is shown via stdout, so printing is intentional.
  // ignore: avoid_print
  print(result.contents);
}
