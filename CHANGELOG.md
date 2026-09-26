# Changelog

## [0.3.0](https://github.com/Quasiflo/dependency_sorter/compare/v0.2.0...v0.3.0) (2026-09-26)


### Features

* colorful CLI output with status marks and --no-color support ([3cb6630](https://github.com/Quasiflo/dependency_sorter/commit/3cb663042462132a1cff48e63f43bffadb548bcc))


### Bug Fixes

* pin UTF-8 for CLI output and test harness decoding ([#7](https://github.com/Quasiflo/dependency_sorter/issues/7)) ([acd075b](https://github.com/Quasiflo/dependency_sorter/commit/acd075bc6de48727e99f761f5265343c34659345))

## [0.2.0](https://github.com/Quasiflo/dependency_sorter/tree/v0.2.0) (2026-09-15)


### Features

* add --diff flag showing a unified diff without writing ([72410d2](https://github.com/Quasiflo/dependency_sorter/commit/72410d20f82e1a310ce73abc2c2a0ba001ae46f2))
* add comment-preserving pubspec dependency sorter CLI ([3f60a71](https://github.com/Quasiflo/dependency_sorter/commit/3f60a718d729da99eab444d72094453f8c463361))


### Bug Fixes

* pin blank separator lines in place when reordering entries ([9200be0](https://github.com/Quasiflo/dependency_sorter/commit/9200be0399f951b08397b44c3424a8fefa7c271a))

## 0.1.0

- Initial release: `dependency_sorter` CLI that sorts `dependencies`, `dev_dependencies` and `dependency_overrides` alphabetically while preserving comments and formatting.
- `--check` mode for CI, per-section toggles via CLI flags and the `dependency_sorter` pubspec key.
