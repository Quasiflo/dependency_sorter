import 'dart:math';

import 'terminal.dart';

/// A minimal unified diff for `--diff` output.
///
/// Kept dependency-free on purpose to preserve this package's tiny
/// footprint. Pubspec files are small, so a simple longest-common-subsequence
/// diff is plenty fast.
///
/// When [color] is `true`, deletions print red, insertions green, and hunk
/// headers cyan. Defaults to plain text suitable for pipes and CI logs.
String unifiedDiff({
  required String path,
  required List<String> from,
  required List<String> to,
  int context = 3,
  bool color = false,
}) {
  final TerminalStyle style = TerminalStyle(enabled: color);
  final List<_Edit> edits = _diffEdits(from, to);
  if (edits.every((edit) => edit is _Equal)) return '';
  final StringBuffer out = StringBuffer()
    ..writeln(style.bold('--- a/$path'))
    ..writeln(style.bold('+++ b/$path'));

  // Line numbers (1-based) of each edit in the from/to files.
  var fromLine = 1;
  var toLine = 1;
  final List<(_Edit, int, int)> numbered = [
    for (final edit in edits)
      switch (edit) {
        _Equal() => (edit, fromLine++, toLine++),
        _Delete() => (edit, fromLine++, toLine),
        _Insert() => (edit, fromLine, toLine++),
      },
  ];

  // Group changed edits into hunks, expanded by [context] lines.
  final List<List<(_Edit, int, int)>> hunks = [];
  List<(_Edit, int, int)>? current;
  var hunkEnd = -1;
  for (var i = 0; i < numbered.length; i++) {
    final (edit, _, _) = numbered[i];
    if (edit is _Equal) continue;
    final int start = max(0, i - context);
    if (current == null || start > hunkEnd) {
      current = [];
      hunks.add(current);
    }
    hunkEnd = min(numbered.length, i + context + 1);
    while (current.length < hunkEnd - start) {
      current.add(numbered[start + current.length]);
    }
  }

  for (final hunk in hunks) {
    final (_, firstFrom, firstTo) = hunk.first;
    var fromCount = 0;
    var toCount = 0;
    for (final (edit, _, _) in hunk) {
      switch (edit) {
        case _Equal():
          fromCount++;
          toCount++;
        case _Delete():
          fromCount++;
        case _Insert():
          toCount++;
      }
    }
    // A hunk touching no lines of a file starts at the line before the
    // hunk (`-0,0` for an empty file), per unified-diff convention.
    final int fromStart = fromCount == 0 ? firstFrom - 1 : firstFrom;
    final int toStart = toCount == 0 ? firstTo - 1 : firstTo;
    out.writeln(style.cyan('@@ -$fromStart,$fromCount +$toStart,$toCount @@'));
    for (final (edit, _, _) in hunk) {
      switch (edit) {
        case _Equal(:final line):
          out.writeln(' $line');
        case _Delete(:final line):
          out.writeln(style.red('-$line'));
        case _Insert(:final line):
          out.writeln(style.green('+$line'));
      }
    }
  }
  return out.toString();
}

sealed class _Edit {
  const _Edit();
}

class _Equal extends _Edit {
  const _Equal(this.line);
  final String line;
}

class _Delete extends _Edit {
  const _Delete(this.line);
  final String line;
}

class _Insert extends _Edit {
  const _Insert(this.line);
  final String line;
}

/// Computes the edit script turning [from] into [to].
List<_Edit> _diffEdits(List<String> from, List<String> to) {
  final int m = from.length;
  final int n = to.length;
  final List<List<int>> lengths = List.generate(
    m + 1,
    (_) => List.filled(n + 1, 0),
  );
  for (var i = m - 1; i >= 0; i--) {
    for (var j = n - 1; j >= 0; j--) {
      lengths[i][j] = from[i] == to[j]
          ? lengths[i + 1][j + 1] + 1
          : max(lengths[i + 1][j], lengths[i][j + 1]);
    }
  }
  final List<_Edit> edits = [];
  var i = 0;
  var j = 0;
  while (i < m && j < n) {
    if (from[i] == to[j]) {
      edits.add(_Equal(from[i]));
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      edits.add(_Delete(from[i]));
      i++;
    } else {
      edits.add(_Insert(to[j]));
      j++;
    }
  }
  while (i < m) {
    edits.add(_Delete(from[i]));
    i++;
  }
  while (j < n) {
    edits.add(_Insert(to[j]));
    j++;
  }
  return edits;
}
