import 'package:meta/meta.dart';

/// Which dependency sections of a pubspec should be sorted.
///
/// All sections are sorted by default, matching the behavior of the
/// `sort_pub_dependencies` lint. Individual sections can be disabled either
/// via the `dependency_sorter` key in the pubspec itself or via CLI flags
/// (which take precedence).
///
/// ```yaml
/// dependency_sorter:
///   sort_dependencies: true
///   sort_dev_dependencies: true
///   sort_dependency_overrides: true
/// ```
@immutable
class SortConfig {
  /// Creates a config. All sections are sorted unless explicitly disabled.
  const SortConfig({
    this.sortDependencies = true,
    this.sortDevDependencies = true,
    this.sortDependencyOverrides = true,
  });

  /// The default config: sort everything the lint checks.
  static const SortConfig defaults = SortConfig();

  /// Whether the top-level `dependencies:` map should be sorted.
  final bool sortDependencies;

  /// Whether the top-level `dev_dependencies:` map should be sorted.
  final bool sortDevDependencies;

  /// Whether the top-level `dependency_overrides:` map should be sorted.
  final bool sortDependencyOverrides;

  /// Parses a `dependency_sorter:` mapping from a pubspec.
  ///
  /// Unknown keys are ignored so older configs keep working when new
  /// options are added. Non-boolean values throw a [FormatException]
  /// describing the offending key.
  factory SortConfig.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return SortConfig.defaults;
    return SortConfig(
      sortDependencies: _parseFlag(
        map,
        'sort_dependencies',
        fallback: SortConfig.defaults.sortDependencies,
      ),
      sortDevDependencies: _parseFlag(
        map,
        'sort_dev_dependencies',
        fallback: SortConfig.defaults.sortDevDependencies,
      ),
      sortDependencyOverrides: _parseFlag(
        map,
        'sort_dependency_overrides',
        fallback: SortConfig.defaults.sortDependencyOverrides,
      ),
    );
  }

  /// Returns `true` when at least one section is enabled.
  bool get sortsAnything =>
      sortDependencies || sortDevDependencies || sortDependencyOverrides;

  /// Returns the section names this config enables, for CLI output.
  List<String> get enabledSections => [
    if (sortDependencies) 'dependencies',
    if (sortDevDependencies) 'dev_dependencies',
    if (sortDependencyOverrides) 'dependency_overrides',
  ];

  /// Returns a copy with the given fields replaced.
  SortConfig copyWith({
    bool? sortDependencies,
    bool? sortDevDependencies,
    bool? sortDependencyOverrides,
  }) => SortConfig(
    sortDependencies: sortDependencies ?? this.sortDependencies,
    sortDevDependencies: sortDevDependencies ?? this.sortDevDependencies,
    sortDependencyOverrides:
        sortDependencyOverrides ?? this.sortDependencyOverrides,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SortConfig &&
          sortDependencies == other.sortDependencies &&
          sortDevDependencies == other.sortDevDependencies &&
          sortDependencyOverrides == other.sortDependencyOverrides;

  @override
  int get hashCode => Object.hash(
    sortDependencies,
    sortDevDependencies,
    sortDependencyOverrides,
  );

  @override
  String toString() =>
      'SortConfig('
      'sortDependencies: $sortDependencies, '
      'sortDevDependencies: $sortDevDependencies, '
      'sortDependencyOverrides: $sortDependencyOverrides)';

  static bool _parseFlag(
    Map<Object?, Object?> map,
    String key, {
    required bool fallback,
  }) {
    if (!map.containsKey(key)) return fallback;
    final value = map[key];
    if (value is bool) return value;
    throw FormatException(
      'Invalid value for "dependency_sorter: $key": '
      'expected true or false, got "$value".',
    );
  }
}
