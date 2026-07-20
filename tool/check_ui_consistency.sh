#!/usr/bin/env bash
# UI-consistency ratchet.
#
# Counts occurrences of patterns the design system is migrating away from
# (hardcoded colors, inline radii/font sizes, raw snackbars/spinners, ...)
# and fails if any count grew past the recorded baseline. Counts shrinking
# is the goal; run with --update after a cleanup PR to tighten the baseline.
#
#   tool/check_ui_consistency.sh            # check against baseline
#   tool/check_ui_consistency.sh --update   # rewrite baseline with current counts
#
# Prefer instead of the banned patterns:
#   AppColors.* / AppRadius.* / AppSpacing.* / AppTextStyles.* / AppBreakpoints.*
#   showSuccessToast/showErrorToast/... (lib/utils/app_toast.dart)
#   ListSkeleton / AsyncStateView (lib/widgets/common/)
#   StatusChip (lib/widgets/common/status_chip.dart)
#   confirmDestructive (lib/utils/confirm_dialog.dart)

set -u
cd "$(dirname "$0")/.."

BASELINE="tool/ui_consistency_baseline.txt"

# name|grep-mode|pattern  (counted in lib/ excluding lib/theme/, *.dart only)
CHECKS=(
  'hex-colors|F|Color(0xFF'
  'material-colors|E|\bColors\.[a-z]'
  'inline-radius|E|BorderRadius\.circular\( *[0-9]'
  'inline-edgeinsets|E|EdgeInsets\.(all|fromLTRB)\( *[0-9]|(horizontal|vertical): *[0-9]'
  'inline-fontsize|F|fontSize:'
  'hardcoded-breakpoints|E|(width|maxWidth) *[<>]=? *(600|700|900|1200)\b'
  'raw-snackbars|F|showSnackBar('
  'raw-spinners|F|CircularProgressIndicator('
  'private-status-chips|E|class _StatusChip\b'
)

count_pattern() {
  local mode="$1" pattern="$2"
  if [ "$mode" = "F" ]; then
    grep -r -F "$pattern" lib --include='*.dart' --exclude-dir=theme | wc -l
  else
    grep -r -E "$pattern" lib --include='*.dart' --exclude-dir=theme | wc -l
  fi
}

if [ "${1:-}" = "--update" ]; then
  : > "$BASELINE"
  for check in "${CHECKS[@]}"; do
    IFS='|' read -r name mode pattern <<<"$check"
    printf '%s %s\n' "$name" "$(count_pattern "$mode" "$pattern")" >> "$BASELINE"
  done
  echo "Baseline updated:"
  cat "$BASELINE"
  exit 0
fi

if [ ! -f "$BASELINE" ]; then
  echo "No baseline at $BASELINE — run with --update to create it." >&2
  exit 1
fi

fail=0
printf '%-24s %9s %9s\n' pattern baseline current
for check in "${CHECKS[@]}"; do
  IFS='|' read -r name mode pattern <<<"$check"
  base=$(awk -v n="$name" '$1==n{print $2}' "$BASELINE")
  cur=$(count_pattern "$mode" "$pattern")
  if [ -z "$base" ]; then
    printf '%-24s %9s %9s  NEW (run --update)\n' "$name" '-' "$cur"
    fail=1
  elif [ "$cur" -gt "$base" ]; then
    printf '%-24s %9s %9s  REGRESSION (+%d)\n' "$name" "$base" "$cur" $((cur - base))
    fail=1
  elif [ "$cur" -lt "$base" ]; then
    printf '%-24s %9s %9s  improved (-%d, consider --update)\n' "$name" "$base" "$cur" $((base - cur))
  else
    printf '%-24s %9s %9s  ok\n' "$name" "$base" "$cur"
  fi
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "FAIL: a banned UI pattern got more common. Use the design-system" >&2
  echo "tokens/components listed at the top of tool/check_ui_consistency.sh," >&2
  echo "or (only if genuinely intentional) re-run with --update." >&2
  exit 1
fi
echo
echo "OK"
