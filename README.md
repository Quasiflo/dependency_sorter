# Dependency_sorter

Sort your pubspec dependencies alphabetically!

Fixes what the [`sort_pub_dependencies`](https://dart.dev/tools/linter-rules/sort_pub_dependencies) lint reports — which has no `dart fix` support (see [dart-lang/sdk#47958](https://github.com/dart-lang/sdk/issues/47958)). A tiny, dependency-light CLI that reorders `dependencies`, `dev_dependencies` and `dependency_overrides` while preserving comments, blank lines and formatting.

## Install

Use as a dev dependency (recommended):

<!-- x-release-please-start-version -->

```yaml
dev_dependencies:
  dependency_sorter: ^0.1.0
```

<!-- x-release-please-end -->

```sh
dart pub get
dart run dependency_sorter
```

Or activate globally:

```sh
dart pub global activate dependency_sorter
dependency_sorter
```

## Usage

Fix the pubspec in place (default):

```sh
dart run dependency_sorter
```

Check without writing (for CI) — exits non-zero when sorting is needed:

```sh
dart run dependency_sorter --check
```

Point at a specific file or directory:

```sh
dart run dependency_sorter --path packages/my_app
dart run dependency_sorter packages/my_app/pubspec.yaml
```

Full options:

```sh
dart run dependency_sorter --help
```

| Flag | Description |
| --- | --- |
| `--path`, `-p` | Pubspec file or directory (default: `.`) |
| `--check`, `-c` | Report only; exit `1` when sorting is needed |
| `--[no-]sort-dependencies` | Toggle the `dependencies` section |
| `--[no-]sort-dev-dependencies` | Toggle the `dev_dependencies` section |
| `--[no-]sort-dependency-overrides` | Toggle the `dependency_overrides` section |
| `--version`, `-v` | Print the version |
| `--help`, `-h` | Show usage |

## Configuration

All three sections are sorted by default. Disable any of them per project with a `dependency_sorter` key in your pubspec (no effect on `pub get`):

```yaml
dependency_sorter:
  sort_dependencies: true
  sort_dev_dependencies: true
  sort_dependency_overrides: false
```

CLI flags take precedence over this config.

## Behavior Notes

- Comment-preserving: leading comments move with their entry, inline comments stay on their line, blank lines and CRLF/line endings are kept byte-for-byte.
- Sorting is case-sensitive code-unit order (`Args` before `args`), matching the lint.
- Already-sorted or unparseable sections (flow maps, odd indentation) are left untouched; sorting is idempotent.
- Exit codes: `0` success, `1` unsorted in `--check` mode, `2` usage or I/O errors.
