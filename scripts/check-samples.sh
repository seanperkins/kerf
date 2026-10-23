#!/bin/zsh
# Posts every samples/*.kerf with every built-in post processor and compares each program with the committed one in
# samples/expected/<post id>/<sample>.<extension>. Any difference, a sample that no longer posts cleanly, or a sample with
# no committed program fails the check, so a change anywhere in the CAM, the posts or the validator that moves a byte of
# the output is seen (and reviewed) before it lands.
# Usage: scripts/check-samples.sh            compare (exit 1 on a difference)
#        scripts/check-samples.sh --update   rewrite samples/expected after an intended change; review the diff
set -euo pipefail
cd "${0:A:h}/.."
source scripts/swiftpm-env.sh

update=0
case "${1:-}" in
  "") ;;
  --update) update=1 ;;
  *) echo "usage: scripts/check-samples.sh [--update]" >&2; exit 2 ;;
esac

swift build "${SWIFTPM_FLAGS[@]}" --product kerf-cli >&2
cli="$(swift build "${SWIFTPM_FLAGS[@]}" --product kerf-cli --show-bin-path)/kerf-cli"

mkdir -p .tmp
work="$(mktemp -d .tmp/check-samples.XXXXXX)"
trap 'rm -rf "$work"' EXIT

# Assigned first, so that a failing `posts` stops the script (a failure inside a for loop's word list would not).
ids="$("$cli" posts --builtin-only | cut -f1)"
samples=(samples/*.kerf)
[[ -n "$ids" && -e "${samples[1]}" ]] || { echo "FAIL: no posts or no samples found" >&2; exit 1; }
expected_count=$(( $(echo "$ids" | wc -l) * ${#samples} ))

failed=0
for id in ${(f)ids}; do
  for sample in $samples; do
    # --builtin-only: the posts and machines of whoever runs this must not change the result.
    if ! "$cli" export "$sample" --post "$id" --builtin-only --out "$work/$id" --quiet; then
      echo "FAIL: $sample did not post cleanly with $id" >&2
      failed=1
    fi
  done
done
(( failed == 0 )) || exit 1
# Every post and sample made a program: a short set must never replace, or pass for, the committed one.
(( $(find "$work" -type f | wc -l) == expected_count )) || { echo "FAIL: expected $expected_count programs" >&2; exit 1; }

if (( update )); then
  rm -rf samples/expected
  mkdir -p samples/expected
  cp -R "$work"/. samples/expected/
  echo "samples/expected rewritten: $(find samples/expected -type f | wc -l | tr -d ' ') programs"
  exit 0
fi

if diff -ru samples/expected "$work"; then
  echo "samples/expected matches: $(find samples/expected -type f | wc -l | tr -d ' ') programs"
else
  echo "FAIL: the programs above differ from samples/expected (scripts/check-samples.sh --update after an intended change)" >&2
  exit 1
fi
