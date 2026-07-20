#!/usr/bin/env bash
# Theme-token consistency check.
#
# Counts raw-literal usages that bypass the design system (lib/theme/) and
# fails when any file's count goes UP versus the committed baseline. New code
# must use AppColors / AppRadius / AppShadows tokens — but existing violations
# are grandfathered, so this can land without a fleet-wide rewrite.
#
# Usage:
#   scripts/check_theme_tokens.sh           # check against baseline
#   scripts/check_theme_tokens.sh --update  # regenerate baseline (after a refactor)
#
# Tracked patterns:
#   raw_color   `Color(0x...)` literals
#   raw_radius  `BorderRadius.circular(<numeric>)` (should be AppRadius.*)
#   raw_shadow  inline `BoxShadow(` constructors (should be AppShadows.*)

set -euo pipefail

cd "$(dirname "$0")/.."

BASELINE="scripts/theme_tokens_baseline.txt"
MODE="${1:-check}"

# Collect counts per file. Output is `path<TAB>raw_color=N<TAB>raw_radius=N<TAB>raw_shadow=N`.
collect_counts() {
  # Files in scope: lib/**/*.dart minus lib/theme/ and lib/examples/.
  local files
  files=$(find lib -name '*.dart' -type f \
    -not -path 'lib/theme/*' \
    -not -path 'lib/examples/*' | sort)

  for f in $files; do
    # Strip line comments before counting so `// Color(0x...)` doesn't trip the
    # check. Block comments aren't perfectly handled — fine, false-positives are
    # rare and benign.
    local content
    content=$(sed 's://.*$::' "$f")
    local rc rr rs
    # `|| true` — grep exits 1 on no match, which would trip `set -e + pipefail`.
    rc=$(printf '%s\n' "$content" | { grep -oE 'Color\(0x' || true; } | wc -l | tr -d ' ')
    rr=$(printf '%s\n' "$content" | { grep -oE 'BorderRadius\.circular\([0-9]' || true; } | wc -l | tr -d ' ')
    rs=$(printf '%s\n' "$content" | { grep -oE 'BoxShadow\(' || true; } | wc -l | tr -d ' ')
    if [ "$rc" -gt 0 ] || [ "$rr" -gt 0 ] || [ "$rs" -gt 0 ]; then
      printf '%s\traw_color=%s\traw_radius=%s\traw_shadow=%s\n' "$f" "$rc" "$rr" "$rs"
    fi
  done
}

if [ "$MODE" = "--update" ]; then
  collect_counts > "$BASELINE"
  echo "Baseline updated: $BASELINE"
  exit 0
fi

if [ ! -f "$BASELINE" ]; then
  echo "Baseline missing — run: scripts/check_theme_tokens.sh --update" >&2
  exit 2
fi

CURRENT=$(collect_counts)
fail=0

# Build awk-friendly streams: "path key value" rows.
expand() {
  awk -F'\t' '{
    for (i = 2; i <= NF; i++) {
      split($i, kv, "=");
      print $1, kv[1], kv[2];
    }
  }'
}

baseline_expanded=$(expand < "$BASELINE")
current_expanded=$(printf '%s\n' "$CURRENT" | expand)

# For each (path,key) in current, compare to baseline (default 0). Report any growth.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  path=$(awk '{print $1}' <<<"$line")
  key=$(awk '{print $2}' <<<"$line")
  cur=$(awk '{print $3}' <<<"$line")
  base=$(awk -v p="$path" -v k="$key" '$1==p && $2==k {print $3; exit}' <<<"$baseline_expanded")
  base=${base:-0}
  if [ "$cur" -gt "$base" ]; then
    echo "FAIL  $path  $key: $base -> $cur" >&2
    fail=1
  fi
done <<<"$current_expanded"

if [ $fail -ne 0 ]; then
  cat >&2 <<'EOF'

New raw-literal usage detected. Replace with design-system tokens:
  Color(0x...)               → AppColors.* from lib/theme/app_colors.dart
  BorderRadius.circular(N)   → AppRadius.* from lib/theme/app_radius.dart
  BoxShadow(...)             → AppShadows.sm/md/lg from lib/theme/app_shadows.dart

If a violation is intentional (e.g. canvas painter, decorative glow), refactor
the file to be cleaner first; once you're happy, regenerate the baseline:

  scripts/check_theme_tokens.sh --update
EOF
  exit 1
fi

echo "ok — no new theme-token violations"
