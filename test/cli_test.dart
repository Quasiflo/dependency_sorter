import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Integration tests for the executable.
///
/// These spawn `dart bin/dependency_sorter.dart` in a temporary directory so
/// CLI behaviour (file resolution, `--check` exit codes, config precedence)
/// is exercised end to end.
void main() {
  group('dependency_sorter CLI', () {
    late Directory tmp;
    late String bin;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('dependency_sorter_cli.');
      bin = '${Directory.current.path}/bin/dependency_sorter.dart';
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<ProcessResult> runCli(
      List<String> args, {
      String? workingDirectory,
    }) => Process.run(
      Platform.resolvedExecutable,
      [bin, ...args],
      workingDirectory: workingDirectory ?? tmp.path,
      // Pin UTF-8 decoding: the CLI emits non-ASCII status marks, and the
      // platform default (e.g. Windows-1252) would mangle them into
      // mojibake. Must match the stdout/stderr encoding set in bin/.
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    String out(ProcessResult result) => result.stdout as String;
    String err(ProcessResult result) => result.stderr as String;

    void writePubspec(String contents, [String name = 'pubspec.yaml']) =>
        File('${tmp.path}/$name').writeAsStringSync(contents);

    test('sorts the pubspec in place by default', () async {
      writePubspec('dependencies:\n  b: any\n  a: any\n');
      final result = await runCli([]);
      expect(result.exitCode, 0, reason: err(result));
      expect(
        File('${tmp.path}/pubspec.yaml').readAsStringSync(),
        'dependencies:\n  a: any\n  b: any\n',
      );
      expect(out(result), contains('Sorted:'));
      // Status marks print even without color support (this output is
      // piped, so ANSI codes are disabled here).
      expect(out(result), contains('\u2714'));
      expect(out(result), isNot(contains('\x1b[')));
    });

    test('resolves a directory and an explicit file path', () async {
      writePubspec('dependencies:\n  b: any\n  a: any\n');
      final fromDir = await runCli(['.']);
      expect(fromDir.exitCode, 0, reason: err(fromDir));

      writePubspec('dependencies:\n  b: any\n  a: any\n');
      final fromFile = await runCli(['${tmp.path}/pubspec.yaml']);
      expect(fromFile.exitCode, 0, reason: err(fromFile));
      expect(
        File('${tmp.path}/pubspec.yaml').readAsStringSync(),
        contains('a: any\n  b: any'),
      );
    });

    test('--check exits 1 without writing when sorting is needed', () async {
      writePubspec('dependencies:\n  b: any\n  a: any\n');
      final result = await runCli(['--check']);
      expect(result.exitCode, 1, reason: out(result));
      expect(out(result), contains('Needs sorting'));
      expect(out(result), contains('\u2716'));
      // File untouched.
      expect(
        File('${tmp.path}/pubspec.yaml').readAsStringSync(),
        'dependencies:\n  b: any\n  a: any\n',
      );
    });

    test('--check exits 0 when already sorted', () async {
      writePubspec('dependencies:\n  a: any\n  b: any\n');
      final result = await runCli(['--check']);
      expect(result.exitCode, 0, reason: err(result));
      expect(out(result), contains('Already sorted'));
    });

    test('CLI flags override the in-pubspec config', () async {
      writePubspec('''
dependency_sorter:
  sort_dependencies: false
dependencies:
  b: any
  a: any
''');
      // Config alone: untouched.
      final check = await runCli(['--check']);
      expect(check.exitCode, 0, reason: out(check));

      // Explicit flag wins over the config.
      final sorted = await runCli(['--sort-dependencies']);
      expect(sorted.exitCode, 0, reason: err(sorted));
      expect(
        File('${tmp.path}/pubspec.yaml').readAsStringSync(),
        contains('a: any\n  b: any'),
      );
    });

    test('in-pubspec config can disable a section', () async {
      writePubspec('''
dependency_sorter:
  sort_dev_dependencies: false
dev_dependencies:
  b: any
  a: any
''');
      final result = await runCli(['--check']);
      expect(result.exitCode, 0, reason: out(result));
    });

    test('--diff prints a unified diff without writing', () async {
      writePubspec('dependencies:\n  b: any\n  a: any\n');
      final result = await runCli(['--diff']);
      expect(result.exitCode, 1, reason: out(result));
      expect(out(result), contains('--- a/'));
      expect(out(result), contains('+++ b/'));
      expect(out(result), contains('-  b: any'));
      expect(out(result), contains('+  b: any'));
      // File untouched.
      expect(
        File('${tmp.path}/pubspec.yaml').readAsStringSync(),
        'dependencies:\n  b: any\n  a: any\n',
      );
    });

    test('--diff exits 0 when already sorted', () async {
      writePubspec('dependencies:\n  a: any\n  b: any\n');
      final result = await runCli(['--diff']);
      expect(result.exitCode, 0, reason: err(result));
      expect(out(result), contains('Already sorted'));
    });

    test('errors clearly when the pubspec is missing', () async {
      final result = await runCli(['--path', '${tmp.path}/missing.yaml']);
      expect(result.exitCode, 2);
      expect(err(result), contains('no pubspec.yaml'));
      expect(err(result), contains('\u2716'));
    });

    test('--help and --version work', () async {
      final help = await runCli(['--help']);
      expect(help.exitCode, 0);
      expect(help.stdout, contains('Usage:'));

      final version = await runCli(['--version']);
      expect(version.exitCode, 0);
      expect(version.stdout, contains('dependency_sorter'));
    });
  });
}
