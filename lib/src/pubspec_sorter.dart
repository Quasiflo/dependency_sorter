import 'package:yaml/yaml.dart';

import 'sort_config.dart';

/// The outcome of sorting a pubspec's dependency sections.
class SortResult {
  /// Creates a sort result.
  const SortResult({required this.contents, required this.sortedSections});

  /// The (possibly rewritten) pubspec contents.
  final String contents;

  /// Names of the sections that were reordered, in pubspec order.
  final List<String> sortedSections;

  /// Whether any section was reordered.
  bool get changed => sortedSections.isNotEmpty;
}

/// Reads the `dependency_sorter:` config section from pubspec [contents].
///
/// Returns [SortConfig.defaults] when the key is absent. Throws a
/// [FormatException] when the pubspec (or the config section) is malformed.
SortConfig parseSortConfig(String contents) {
  final Object? document = loadYaml(contents);
  if (document == null) return SortConfig.defaults;
  if (document is! YamlMap) {
    throw const FormatException('Pubspec does not contain a YAML map.');
  }
  final Object? raw = document['dependency_sorter'];
  if (raw == null) return SortConfig.defaults;
  if (raw is! YamlMap) {
    throw const FormatException(
      'Invalid "dependency_sorter" section: expected a map of flags.',
    );
  }
  return SortConfig.fromMap(Map<Object?, Object?>.from(raw));
}

/// Sorts the enabled dependency sections of a pubspec document.
///
/// Only the sections enabled in [config] are considered. Sorting is a pure
/// reordering of entry blocks: every other byte (comments, blank lines,
/// indentation, quoting, trailing newline, line endings) is preserved, and
/// already-sorted sections are left untouched.
///
/// Entry blocks carry their leading comment lines with them when reordered;
/// sections that cannot be parsed safely (flow-style maps, unexpected
/// indentation, unparseable keys) are left unchanged.
SortResult sortPubspecContents(String contents, SortConfig config) {
  if (!config.sortsAnything) {
    return SortResult(contents: contents, sortedSections: const []);
  }

  final String lineEnding = contents.contains('\r\n') ? '\r\n' : '\n';
  final bool hasTrailingNewline =
      contents.endsWith('\n') || contents.endsWith('\r');
  final List<String> lines = _splitLines(contents);

  final List<String> sortedSections = [];
  for (final String section in const [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    if (!_isSectionEnabled(section, config)) continue;
    if (_sortSection(lines, section)) sortedSections.add(section);
  }

  if (sortedSections.isEmpty) {
    return SortResult(contents: contents, sortedSections: const []);
  }
  var out = lines.join(lineEnding);
  if (hasTrailingNewline) out += lineEnding;
  return SortResult(contents: out, sortedSections: sortedSections);
}

bool _isSectionEnabled(String section, SortConfig config) {
  switch (section) {
    case 'dependencies':
      return config.sortDependencies;
    case 'dev_dependencies':
      return config.sortDevDependencies;
    case 'dependency_overrides':
      return config.sortDependencyOverrides;
    default:
      return false;
  }
}

/// Splits [contents] into lines without line breaks.
///
/// Handles both LF and CRLF input by stripping a trailing `\r` per line. The
/// final empty segment produced by a trailing newline is dropped; callers
/// restore it via [hasTrailingNewline]-style tracking.
List<String> _splitLines(String contents) {
  final List<String> raw = contents.split('\n');
  // Drop the artifact of a trailing newline: it is tracked separately so
  // joining stays lossless for files with and without a final newline.
  if (raw.isNotEmpty && raw.last == '') raw.removeLast();
  return [
    for (final line in raw)
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ];
}

/// Sorts a single top-level mapping section in place.
///
/// Returns `true` when the section was reordered.
bool _sortSection(List<String> lines, String section) {
  final int header = _findSectionHeader(lines, section);
  if (header == -1) return false;

  // An inline value (e.g. `dependencies: {}`) has nothing sortable.
  if (_hasInlineValue(lines[header], section)) return false;

  final int regionEnd = _findRegionEnd(lines, header);
  final int entryIndent = _findEntryIndent(lines, header + 1, regionEnd);
  if (entryIndent == -1) return false;

  final _SectionParse? parsed = _parseEntries(
    lines,
    header + 1,
    regionEnd,
    entryIndent,
  );
  if (parsed == null || parsed.entries.isEmpty) return false;

  final List<String> keys = [for (final e in parsed.entries) e.key];
  final List<String> sorted = List.of(keys)..sort();
  if (_listsEqual(keys, sorted)) return false;

  // Stable reorder: duplicate keys (invalid pubspecs) keep relative order.
  final List<_Entry> reordered = List.of(parsed.entries)
    ..sort((a, b) {
      final int order = a.key.compareTo(b.key);
      return order != 0 ? order : a.index.compareTo(b.index);
    });

  final List<String> rebuilt = [
    for (final entry in reordered) ...entry.lines,
    ...parsed.trailing,
  ];
  for (var i = 0; i < rebuilt.length; i++) {
    lines[header + 1 + i] = rebuilt[i];
  }
  return true;
}

/// Finds the top-level `section:` header, or -1 when absent.
int _findSectionHeader(List<String> lines, String section) {
  final RegExp header = RegExp(
    '^${RegExp.escape(section)}\\s*:(\\s*#.*)?\\s*\$',
  );
  for (var i = 0; i < lines.length; i++) {
    if (header.hasMatch(lines[i])) return i;
  }
  return -1;
}

/// Returns `true` when the header line carries an inline value.
bool _hasInlineValue(String headerLine, String section) {
  final int colon = headerLine.indexOf(':');
  if (colon == -1) return false;
  var rest = headerLine.substring(colon + 1).trim();
  // Strip a trailing comment to avoid mistaking `#` content for a value.
  final int comment = rest.indexOf('#');
  if (comment != -1) rest = rest.substring(0, comment).trim();
  return rest.isNotEmpty;
}

/// Finds the first line after [header] that starts a new top-level key.
int _findRegionEnd(List<String> lines, int header) {
  // A top-level key starts at column 0 and contains a colon. Indented lines
  // (entries, continuations, comments) belong to the current section.
  final RegExp topLevelKey = RegExp(r'^\S[^#]*:');
  for (var i = header + 1; i < lines.length; i++) {
    if (topLevelKey.hasMatch(lines[i])) return i;
  }
  return lines.length;
}

/// Finds the indentation of entry keys within [start, end), or -1.
///
/// The entry indent is the indent of the first key-like line. Comment-only
/// and blank lines are skipped.
int _findEntryIndent(List<String> lines, int start, int end) {
  for (var i = start; i < end; i++) {
    final String line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final _KeyMatch? match = _matchEntryKey(line);
    if (match == null) {
      // A non-key line (e.g. a stray scalar) means this is not a plain
      // dependency map; bail out rather than corrupt it.
      return -1;
    }
    return match.indent;
  }
  return -1;
}

final RegExp _bareKey = RegExp(r'^[A-Za-z0-9_.\-]+$');

/// A key-like line with its indent and decoded key.
class _KeyMatch {
  _KeyMatch(this.indent, this.key);
  final int indent;
  final String key;
}

/// Matches `key:` lines and extracts the key.
///
/// Supports bare, single-quoted and double-quoted keys. Returns `null` for
/// lines that are not key-like (continuations, list items, flow content).
_KeyMatch? _matchEntryKey(String line) {
  final int indent = line.length - line.trimLeft().length;
  final String trimmed = line.trimLeft();
  if (trimmed.startsWith('#') || trimmed.startsWith('- ')) return null;

  final int colon = _findKeyColon(trimmed);
  if (colon == -1) return null;
  final String rawKey = trimmed.substring(0, colon).trim();
  if (rawKey.isEmpty) return null;

  final String? key = _decodeKey(rawKey);
  if (key == null) return null;
  return _KeyMatch(indent, key);
}

/// Finds the colon terminating a mapping key, skipping colons inside quotes
/// and flow brackets. Returns -1 when there is none (e.g. `key # comment`
/// without a value, or a continuation line).
int _findKeyColon(String trimmed) {
  String? quote;
  var bracketDepth = 0;
  for (var i = 0; i < trimmed.length; i++) {
    final String char = trimmed[i];
    if (quote != null) {
      if (char == quote && trimmed[i - 1] != r'\') quote = null;
      continue;
    }
    switch (char) {
      case '"':
      case "'":
        // A quote only opens inside the key part (before any colon or
        // bracket); a quote later on starts a value, which we never reach
        // because we return at the first top-level colon.
        if (bracketDepth == 0) quote = char;
      case '{':
      case '[':
        bracketDepth++;
      case '}':
      case ']':
        if (bracketDepth > 0) bracketDepth--;
      case ':':
        if (bracketDepth > 0) continue;
        final String next = i + 1 < trimmed.length ? trimmed[i + 1] : '';
        // In YAML `key:` needs end-of-line or whitespace after the colon;
        // `http://...` inside a value must not count (we only scan keys,
        // but flow values like `{a: b}` are guarded by bracketDepth too).
        if (next == '' || next == ' ' || next == '\t') return i;
    }
  }
  return -1;
}

/// Decodes a raw key into its string value, or `null` when unsupported.
String? _decodeKey(String rawKey) {
  if (rawKey.length >= 2 &&
      ((rawKey.startsWith('"') && rawKey.endsWith('"')) ||
          (rawKey.startsWith("'") && rawKey.endsWith("'")))) {
    // Quoted keys: sorting uses the inner text, matching how the lint
    // compares decoded key strings for ordinary package names.
    return rawKey.substring(1, rawKey.length - 1);
  }
  if (_bareKey.hasMatch(rawKey)) return rawKey;
  // Flow collections or exotic scalars: not sortable entry keys.
  return null;
}

class _Entry {
  _Entry(this.key, this.index, this.lines);
  final String key;
  final int index;
  final List<String> lines;
}

class _SectionParse {
  _SectionParse(this.entries, this.trailing);
  final List<_Entry> entries;
  final List<String> trailing;
}

/// Groups a section's lines into entry blocks.
///
/// Leading comment lines travel with the entry that follows them; blank
/// lines stay with the preceding entry; comments after the last entry are
/// kept as trailing lines. Returns `null` when the region is not a plain
/// flat map (mixed indentation, unparseable keys, nested top-level content).
_SectionParse? _parseEntries(
  List<String> lines,
  int start,
  int end,
  int entryIndent,
) {
  final List<_Entry> entries = [];
  final List<String> pendingComments = [];
  final List<String> trailing = [];
  _Entry? current;
  var index = 0;

  void flushPendingAsTrailing() {
    trailing.addAll(pendingComments);
    pendingComments.clear();
  }

  for (var i = start; i < end; i++) {
    final String line = lines[i];
    if (line.trim().isEmpty) {
      // Blank lines stay with the preceding block so visual separators
      // survive reordering in a predictable way.
      if (current == null) {
        pendingComments.add(line);
      } else {
        current.lines.add(line);
      }
      continue;
    }
    if (line.trimLeft().startsWith('#')) {
      // Comments at (or above) the entry level attach to the entry that
      // follows them. More deeply indented comments belong to the current
      // entry's nested value and must travel with it.
      final int indent = line.length - line.trimLeft().length;
      if (current != null && indent > entryIndent) {
        current.lines.add(line);
      } else {
        pendingComments.add(line);
      }
      continue;
    }
    final _KeyMatch? match = _matchEntryKey(line);
    final int indent = line.length - line.trimLeft().length;
    if (match != null && indent == entryIndent) {
      current = _Entry(match.key, index++, [...pendingComments, line]);
      entries.add(current);
      pendingComments.clear();
      continue;
    }
    if (indent > entryIndent && current != null) {
      current.lines.add(line);
      continue;
    }
    // Anything else (dedented content, keys at the wrong level, flow
    // maps) is outside what we can reorder safely.
    return null;
  }
  flushPendingAsTrailing();
  return _SectionParse(entries, trailing);
}

bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
