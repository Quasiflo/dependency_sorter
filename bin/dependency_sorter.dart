import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dependency_sorter/dependency_sorter.dart';
import 'package:path/path.dart' as p;

/// Exit code used when `--check` finds a pubspec that needs sorting.
const int checkFailureExitCode = 1;

/// Exit code used for usage errors and unreadable/unwritable files.
const int errorExitCode = 2;

Future<void> main(final List<String> arguments) async {
  // Pin UTF-8 for output: status marks (✔/✖) are non-ASCII, and the
  // platform default encoding (e.g. Windows-1252 on Windows consoles)
  // would otherwise mangle them.
  stdout.encoding = utf8;
  stderr.encoding = utf8;

  final parser = ArgParser()
    ..addOption('path', abbr: 'p', help: 'Path to a pubspec.yaml file or a directory containing one.', valueHelp: 'path')
    ..addFlag(
      'check',
      abbr: 'c',
      negatable: false,
      help:
          'Report unsorted dependencies without modifying files. '
          'Exits with code $checkFailureExitCode when sorting is needed.',
    )
    ..addFlag(
      'diff',
      negatable: false,
      help:
          'Show a unified diff of the pending changes without modifying '
          'files. Implies check-mode behavior: exits with code '
          '$checkFailureExitCode when sorting is needed.',
    )
    ..addFlag('sort-dependencies', help: 'Sort the dependencies section.', defaultsTo: null)
    ..addFlag('sort-dev-dependencies', help: 'Sort the dev_dependencies section.', defaultsTo: null)
    ..addFlag('sort-dependency-overrides', help: 'Sort the dependency_overrides section.', defaultsTo: null)
    ..addFlag(
      'color',
      defaultsTo: true,
      help:
          'Use colors in terminal output. Enabled by default when the '
          'terminal supports it; disable with --no-color or NO_COLOR=1.',
    )
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Print the package version.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  late final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    _error('Error: ${e.message}');
    stderr
      ..writeln()
      ..writeln('Usage:')
      ..writeln(parser.usage);
    exit(errorExitCode);
  }

  final style = TerminalStyle(enabled: _wantsColor(stdout.supportsAnsiEscapes, results));

  if (results['help'] as bool) {
    stdout
      ..writeln(style.bold('Sort pubspec dependencies alphabetically.'))
      ..writeln()
      ..writeln(
        'Usage: dependency_sorter [options] [path]\n'
        '\n'
        'Fixes the file in place by default. Use --check in CI to fail '
        'instead of writing, or --diff to preview the pending changes.',
      )
      ..writeln()
      ..writeln(parser.usage);
    return;
  }

  if (results['version'] as bool) {
    // Plain on purpose: machine-readable, safe for scripts.
    stdout.writeln('dependency_sorter $packageVersion');
    return;
  }

  final rawPath = _resolveRawPath(results);
  final file = _resolvePubspecFile(rawPath);
  if (!file.existsSync()) {
    _error('Error: no pubspec.yaml found at "${file.path}".');
    exit(errorExitCode);
  }

  late final String original;
  try {
    original = file.readAsStringSync();
  } on FileSystemException catch (e) {
    _error('Error: cannot read "${file.path}": ${e.message}');
    exit(errorExitCode);
  }

  late final SortConfig fileConfig;
  try {
    fileConfig = parseSortConfig(original);
  } on FormatException catch (e) {
    _error('Error: invalid pubspec "${file.path}": ${e.message}');
    exit(errorExitCode);
  }

  final config = _applyFlagOverrides(fileConfig, results);
  final check = results['check'] as bool;
  final diff = results['diff'] as bool;

  final result = sortPubspecContents(original, config);

  if (!result.changed) {
    stdout.writeln('${TerminalStyle.okMark} ${style.green('Already sorted:')} ${file.path}');
    return;
  }

  if (diff) {
    stdout.write(unifiedDiff(path: file.path, from: original.split('\n'), to: result.contents.split('\n'), color: style.enabled));
    exit(checkFailureExitCode);
  }

  if (check) {
    stdout
      ..writeln('${TerminalStyle.failMark} ${style.yellow('Needs sorting:')} ${file.path}')
      ..writeln(style.dim('  unsorted: ${result.sortedSections.join(', ')}'))
      ..writeln(style.dim('  run without --check to fix.'));
    exit(checkFailureExitCode);
  }

  try {
    file.writeAsStringSync(result.contents);
  } on FileSystemException catch (e) {
    _error('Error: cannot write "${file.path}": ${e.message}');
    exit(errorExitCode);
  }
  stdout
    ..writeln('${TerminalStyle.okMark} ${style.green('Sorted:')} ${file.path}')
    ..writeln(style.dim('  sorted: ${result.sortedSections.join(', ')}'));
}

/// Whether colored output should be used.
///
/// Honors `--no-color` and the `NO_COLOR` convention, and requires a
/// terminal that supports ANSI escapes (so piped and CI output stays plain).
bool _wantsColor(final bool supportsAnsi, final ArgResults results) {
  if (!(results['color'] as bool)) {
    return false;
  }
  if (Platform.environment.containsKey('NO_COLOR')) {
    return false;
  }
  return supportsAnsi;
}

/// Writes an error to stderr, styled when the terminal supports it.
void _error(final String message) {
  // Recompute instead of threading the stdout style through: stderr may be
  // redirected independently. `results` is unavailable here, so this honors
  // NO_COLOR and terminal support; the --no-color flag is covered because
  // flag parsing already succeeded before any styled output... except for
  // parse errors themselves, where flags are unknown and colors stay on when
  // supported. That matches common CLI behavior.
  const style = TerminalStyle(enabled: true);
  if (stderr.supportsAnsiEscapes && !Platform.environment.containsKey('NO_COLOR')) {
    stderr.writeln('${TerminalStyle.failMark} ${style.red(message)}');
  } else {
    stderr.writeln('${TerminalStyle.failMark} $message');
  }
}

/// Returns the target path from `--path` or the positional argument.
String _resolveRawPath(final ArgResults results) {
  final flag = results['path'] as String?;
  final rest = results.rest;
  if (rest.length > 1) {
    _error('Error: expected at most one path argument.');
    exit(errorExitCode);
  }
  if (flag != null && rest.isNotEmpty) {
    _error('Error: pass a path either with --path or as an argument, not both.');
    exit(errorExitCode);
  }
  return flag ?? (rest.isNotEmpty ? rest.single : '.');
}

/// Resolves a user-supplied path to the pubspec file itself.
File _resolvePubspecFile(final String rawPath) {
  final type = FileSystemEntity.typeSync(rawPath, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    return File(p.join(rawPath, 'pubspec.yaml'));
  }
  return File(rawPath);
}

/// Applies explicit CLI flags over the in-pubspec config.
///
/// Only flags the user actually passed (`wasParsed`) override the file;
/// otherwise the pubspec config (or its defaults) wins.
SortConfig _applyFlagOverrides(final SortConfig base, final ArgResults results) {
  bool flagOr(final String name, {required final bool current}) => results.wasParsed(name) ? results[name] as bool : current;
  return SortConfig(
    sortDependencies: flagOr('sort-dependencies', current: base.sortDependencies),
    sortDevDependencies: flagOr('sort-dev-dependencies', current: base.sortDevDependencies),
    sortDependencyOverrides: flagOr('sort-dependency-overrides', current: base.sortDependencyOverrides),
  );
}
