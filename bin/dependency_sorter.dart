import 'dart:io';

import 'package:args/args.dart';
import 'package:dependency_sorter/dependency_sorter.dart';

/// Exit code used when `--check` finds a pubspec that needs sorting.
const int checkFailureExitCode = 1;

/// Exit code used for usage errors and unreadable/unwritable files.
const int errorExitCode = 2;

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addOption(
      'path',
      abbr: 'p',
      help: 'Path to a pubspec.yaml file or a directory containing one.',
      valueHelp: 'path',
    )
    ..addFlag(
      'check',
      abbr: 'c',
      negatable: false,
      help:
          'Report unsorted dependencies without modifying files. '
          'Exits with code $checkFailureExitCode when sorting is needed.',
    )
    ..addFlag(
      'sort-dependencies',
      help: 'Sort the dependencies section.',
      defaultsTo: null,
    )
    ..addFlag(
      'sort-dev-dependencies',
      help: 'Sort the dev_dependencies section.',
      defaultsTo: null,
    )
    ..addFlag(
      'sort-dependency-overrides',
      help: 'Sort the dependency_overrides section.',
      defaultsTo: null,
    )
    ..addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Print the package version.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln('Usage:');
    stderr.writeln(parser.usage);
    exit(errorExitCode);
  }

  if (results['help'] as bool) {
    stdout.writeln('Sort pubspec dependencies alphabetically.');
    stdout.writeln();
    stdout.writeln(
      'Usage: dependency_sorter [options] [path]\n'
      '\n'
      'Fixes the file in place by default. Use --check in CI to fail '
      'instead of writing.',
    );
    stdout.writeln();
    stdout.writeln(parser.usage);
    return;
  }

  if (results['version'] as bool) {
    stdout.writeln('dependency_sorter $packageVersion');
    return;
  }

  final String rawPath = _resolveRawPath(results);
  final File file = _resolvePubspecFile(rawPath);
  if (!file.existsSync()) {
    stderr.writeln('Error: no pubspec.yaml found at "${file.path}".');
    exit(errorExitCode);
  }

  late final String original;
  try {
    original = file.readAsStringSync();
  } on FileSystemException catch (e) {
    stderr.writeln('Error: cannot read "${file.path}": ${e.message}');
    exit(errorExitCode);
  }

  late final SortConfig fileConfig;
  try {
    fileConfig = parseSortConfig(original);
  } on FormatException catch (e) {
    stderr.writeln('Error: invalid pubspec "${file.path}": ${e.message}');
    exit(errorExitCode);
  }

  final SortConfig config = _applyFlagOverrides(fileConfig, results);
  final bool check = results['check'] as bool;

  final SortResult result = sortPubspecContents(original, config);

  if (!result.changed) {
    stdout.writeln('Already sorted: ${file.path}');
    return;
  }

  if (check) {
    stdout.writeln('Needs sorting: ${file.path}');
    stdout.writeln('  unsorted: ${result.sortedSections.join(', ')}');
    stdout.writeln('  run without --check to fix.');
    exit(checkFailureExitCode);
  }

  try {
    file.writeAsStringSync(result.contents);
  } on FileSystemException catch (e) {
    stderr.writeln('Error: cannot write "${file.path}": ${e.message}');
    exit(errorExitCode);
  }
  stdout.writeln('Sorted: ${file.path}');
  stdout.writeln('  sorted: ${result.sortedSections.join(', ')}');
}

/// Returns the target path from `--path` or the positional argument.
String _resolveRawPath(ArgResults results) {
  final String? flag = results['path'] as String?;
  final List<String> rest = results.rest;
  if (rest.length > 1) {
    stderr.writeln('Error: expected at most one path argument.');
    exit(errorExitCode);
  }
  if (flag != null && rest.isNotEmpty) {
    stderr.writeln(
      'Error: pass a path either with --path or as an argument, not both.',
    );
    exit(errorExitCode);
  }
  return flag ?? (rest.isNotEmpty ? rest.single : '.');
}

/// Resolves a user-supplied path to the pubspec file itself.
File _resolvePubspecFile(String rawPath) {
  final FileSystemEntityType type = FileSystemEntity.typeSync(
    rawPath,
    followLinks: false,
  );
  if (type == FileSystemEntityType.directory) {
    return File('$rawPath/pubspec.yaml');
  }
  return File(rawPath);
}

/// Applies explicit CLI flags over the in-pubspec config.
///
/// Only flags the user actually passed (`wasParsed`) override the file;
/// otherwise the pubspec config (or its defaults) wins.
SortConfig _applyFlagOverrides(SortConfig base, ArgResults results) {
  bool flagOr(String name, bool current) =>
      results.wasParsed(name) ? results[name] as bool : current;
  return SortConfig(
    sortDependencies: flagOr('sort-dependencies', base.sortDependencies),
    sortDevDependencies: flagOr(
      'sort-dev-dependencies',
      base.sortDevDependencies,
    ),
    sortDependencyOverrides: flagOr(
      'sort-dependency-overrides',
      base.sortDependencyOverrides,
    ),
  );
}
