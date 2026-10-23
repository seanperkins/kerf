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
stage=""
old=""
# Whatever stops the script, the committed programs end up in samples/expected: a swap that was begun and not finished is undone.
cleanup() {
  rm -rf "$work"
  [[ -z "$stage" ]] || rm -rf "$stage"
  if [[ -n "$old" && -e "$old" && ! -e samples/expected ]]; then mv "$old" samples/expected; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
# Every post and sample made a program of its own: a short or muddled set must never replace, or pass for, the committed one.
for id in ${(f)ids}; do
  (( $(find "$work/$id" -type f | wc -l) == ${#samples} )) || { echo "FAIL: $id did not make ${#samples} programs" >&2; exit 1; }
  for sample in $samples; do
    stem="${sample:t:r}"
    ls "$work/$id/$stem".* > /dev/null 2>&1 || { echo "FAIL: no program for $stem with $id" >&2; exit 1; }
  done
done
(( $(find "$work" -type f | wc -l) == expected_count )) || { echo "FAIL: expected $expected_count programs" >&2; exit 1; }

if (( update )); then
  # Staged next to the committed set and swapped in whole, so a failed copy leaves the committed programs as they were.
  stage="$(mktemp -d samples/.expected-new.XXXXXX)"
  cp -R "$work"/. "$stage"/
  (( $(find "$stage" -type f | wc -l) == expected_count )) || { echo "FAIL: the copy is short" >&2; exit 1; }
  # The committed set is moved aside, not deleted, until the new one is in its place; a failed or interrupted swap puts it
  # back (`cleanup`).
  old="samples/.expected-old.$$"
  if [[ -e samples/expected ]]; then mv samples/expected "$old"; fi
  mv "$stage" samples/expected || { echo "FAIL: could not put the new programs in place; the committed ones are back" >&2; exit 1; }
  # The commit point: from here the new set is the corpus, and what is left of the old one is only to be deleted.
  gone="$old"
  stage=""
  old=""
  rm -rf "$gone"
  echo "samples/expected rewritten: $expected_count programs"
  exit 0
fi

if diff -ru samples/expected "$work"; then
  echo "samples/expected matches: $expected_count programs"
else
  echo "FAIL: the programs above differ from samples/expected (scripts/check-samples.sh --update after an intended change)" >&2
  exit 1
fi
