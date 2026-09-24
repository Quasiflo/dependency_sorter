/// Minimal terminal styling for CLI output.
///
/// Hand-rolled ANSI helpers (no dependencies, keeping this package's tiny
/// footprint). All styling is gated on [enabled]: when `false` every method
/// returns its input unchanged, so piped or CI output stays plain text.
/// The CLI enables styling only when the terminal supports it (see
/// `stdout.supportsAnsiEscapes`), unless the user passes `--no-color` or
/// sets the `NO_COLOR` environment variable.
class TerminalStyle {
  /// Creates a style. Pass `enabled: false` for plain output.
  const TerminalStyle({required this.enabled});

  /// Whether ANSI escape codes are emitted.
  final bool enabled;

  /// Check mark used for success messages.
  static const String okMark = '\u2714';

  /// Cross mark used for failures and errors.
  static const String failMark = '\u2716';

  /// Wraps [text] in the given ANSI [code], or returns it unchanged.
  String wrap(final String text, final String code) => enabled ? '\x1b[${code}m$text\x1b[0m' : text;

  /// Bold text.
  String bold(final String text) => wrap(text, '1');

  /// Dimmed (faint) text, for secondary detail lines.
  String dim(final String text) => wrap(text, '2');

  /// Red text, for errors.
  String red(final String text) => wrap(text, '31');

  /// Green text, for success messages.
  String green(final String text) => wrap(text, '32');

  /// Yellow text, for action-required messages.
  String yellow(final String text) => wrap(text, '33');

  /// Cyan text, for diff hunk headers.
  String cyan(final String text) => wrap(text, '36');
}
