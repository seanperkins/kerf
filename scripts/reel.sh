#!/bin/zsh
# Records a UI harness scenario and turns each recorded clip into a GIF and an MP4.
#
#   scripts/reel.sh reel-pause                  # harness/scenarios/reel-pause.json → docs/images/reel-pause.{gif,mp4}
#   scripts/reel.sh reel-pause --out docs/images --width 1280 --fps 10
#   scripts/reel.sh all                         # every harness/scenarios/reel-*.json
#
# A scenario records with the `record` / `endRecord` steps (docs/UI-HARNESS.md). The window is parked just off
# the edge of the screen and drawn as key without activating the app, so your focus stays where it is; --active
# activates the app on screen instead (table rows then take real clicks). Pointer steps
# (press, move, pointer) need Accessibility granted to your terminal. Needs ffmpeg (brew install ffmpeg).
#
# --out DIR     where the GIF and MP4 go (default docs/images)
# --width N     output width in pixels (default 1280; frames are recorded at 2x)
# --fps N       GIF frame rate (default 10; the MP4 is 30)
# --active      activate the app for the run (steals focus) instead of the quiet key window
# --light/--dark/--size WxH/--no-build   passed to scripts/ui.sh
set -euo pipefail
cd "${0:A:h}/.."

scenarios=(); out="docs/images"; width=1280; fps=10; active=0; ui_args=()
while (( $# )); do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --width) width="$2"; shift 2 ;;
    --fps) fps="$2"; shift 2 ;;
    --active) active=1; shift ;;
    --light|--dark|--no-build) ui_args+=("$1"); shift ;;
    --size) ui_args+=(--size "$2"); shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    all) scenarios+=(harness/scenarios/reel-*.json); shift ;;
    *) scenarios+=("$1"); shift ;;
  esac
done
(( ${#scenarios} )) || { echo "usage: scripts/reel.sh <scenario|file.json|all> [--out DIR] [--width N] [--fps N] [--no-active]" >&2; exit 2; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed: brew install ffmpeg" >&2; exit 2; }
if (( active )); then ui_args+=(--active); else ui_args+=(--key --offscreen); fi
mkdir -p "$out"

rc=0
for scenario in "${scenarios[@]}"; do
  [[ -f "$scenario" ]] || scenario="harness/scenarios/${scenario%.json}.json"
  run=".tmp/reel/$(basename "${scenario%.json}")-$(date +%H%M%S)"
  # A failed step after a recording still leaves the clip: encode what is there and report the failure.
  if ! scripts/ui.sh "$scenario" --out "$run" "${ui_args[@]}"; then rc=1; echo "encoding the clips the run wrote before it failed" >&2; fi
  # Later scenarios reuse the build.
  ui_args=(${ui_args:#--no-build}); ui_args+=(--no-build)
  # Plain captures in a clip scenario are stills for the README; "end" is the scenario's own check.
  for png in "$run"/*.png(N); do
    name="$(basename "${png%.png}")"
    [[ "$name" == end ]] && continue
    cp "$png" "$out/$name.png" && echo "wrote $out/$name.png ($(du -h "$png" | cut -f1))"
  done
  for list in "$run"/*.ffconcat(N); do
    name="$(basename "${list%.ffconcat}")"
    # Flatten the alpha channel first: with it, every frame is stored whole and the GIF is 50x larger. A
    # palette per clip from the frame differences keeps text crisp in 256 colours.
    ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" \
      -vf "fps=$fps,scale=$width:-2:flags=lanczos,format=rgb24,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
      -loop 0 "$out/$name.gif"
    ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" \
      -vf "fps=30,scale=$width:-2:flags=lanczos,format=yuv420p" -c:v libx264 -crf 20 -movflags +faststart "$out/$name.mp4"
    echo "wrote $out/$name.gif ($(du -h "$out/$name.gif" | cut -f1)) and $out/$name.mp4 ($(du -h "$out/$name.mp4" | cut -f1))"
  done
done
exit $rc
