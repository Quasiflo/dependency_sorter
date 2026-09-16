#!/usr/bin/env bash
# Regenerates the animated SVG demos in docs/assets/.
#
# Records scripted terminal sessions with asciinema, then converts them with
# nemasvg (https://github.com/Quasiflo/nemasvg). Intermediate .cast files
# are temp-only; the committed artifacts are docs/assets/*.svg.
#
# Requirements: asciinema, nemasvg, dart (with `dart pub get` already run).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/doc/assets"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$ROOT/demo"' EXIT

for tool in asciinema nemasvg dart; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' not found on PATH" >&2
    exit 1
  fi
done

if [[ ! -f "$ROOT/.dart_tool/package_config.json" ]]; then
  echo "error: run 'dart pub get' first (missing .dart_tool/package_config.json)" >&2
  exit 1
fi

# Recordings must not inherit NO_COLOR, or the demos lose their colors.
unset NO_COLOR

mkdir -p "$ASSETS"

write_fixture() {
  mkdir -p "$ROOT/demo"
  cat > "$ROOT/demo/pubspec.yaml" <<'EOF'
name: demo_app
description: Sample app for the demo.

environment:
  sdk: ^3.10.0

dependencies:
  yaml: ^3.0.0
  args: ^2.0.0
  http: ^1.2.0

dev_dependencies:
  test: any
  lints: any
EOF
}

cd "$ROOT"

# Precompile once: `dart run` unconditionally rebuilds its snapshot inside
# asciinema's pty (while reusing the cache in a plain shell), which would
# bake compile noise into every recording. The drivers echo the `dart run`
# commands users actually type, then invoke this identical binary.
dart compile exe bin/dependency_sorter.dart -o "$WORK/ds" >&2
DS="$WORK/ds"

# Demo 1: fix in place, then show the idempotent re-run.
write_fixture
cat > "$WORK/fix.sh" <<EOF
printf '\$ dart run dependency_sorter --path demo\n'
"$DS" --path demo
sleep 1
printf '\$ dart run dependency_sorter --path demo\n'
"$DS" --path demo
sleep 1
EOF
asciinema record --overwrite --idle-time-limit 1 \
  --command "bash $WORK/fix.sh" "$WORK/fix.cast" >/dev/null
nemasvg "$WORK/fix.cast" "$ASSETS/demo-fix.svg" \
  --window --title 'dependency_sorter - idempotent sorting' --cols 76 --rows 14 \
  --idle-time-limit 2

# Demo 2: preview the same change with --diff.
write_fixture
cat > "$WORK/diff.sh" <<EOF
printf '\$ dart run dependency_sorter --diff --path demo\n'
sleep 1
"$DS" --diff --path demo
sleep 3
EOF
asciinema record --overwrite --idle-time-limit 1 \
  --command "bash $WORK/diff.sh" "$WORK/diff.cast" >/dev/null
nemasvg "$WORK/diff.cast" "$ASSETS/demo-diff.svg" \
  --window --title 'dependency_sorter - --diff' --cols 76 --rows 14 \
  --idle-time-limit 2

ls -la "$ASSETS"/demo-*.svg
