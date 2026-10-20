# UI harness

A scripted way to look at the running app without a person (or an agent) driving the screen:
`scripts/ui.sh <scenario>` builds a debug Kerf, runs a short list of steps against a real document
window, and writes PNGs and text dumps. It exists so a UI change can be checked in light and dark mode, at
any window size, in states that are tedious to reach by hand (a calculated job, a sheet open, a toolpath
selected), and so a reviewer can read the result as an image and as an accessibility tree.

```sh
scripts/ui.sh main                    # harness/scenarios/main.json
scripts/ui.sh toolpaths --light       # force light (or --dark) mode
scripts/ui.sh sheets --size 1000x640  # override the window's content size
scripts/ui.sh interact --active       # draw the window as the key window (steals focus for a moment)
scripts/ui.sh path/to/mine.json --out .tmp/ui/mine
```

Output goes to `.tmp/ui/<scenario>-<time>/` (git-ignored):

| File | What it is |
|---|---|
| `<name>.png` | The window as drawn, title bar and toolbar included, at 2x. Sheets are separate PNGs. |
| `<name>.ax.txt` | The accessibility tree: role, label, value, help, enabled state and the frame in window points (origin top left). This is what VoiceOver sees, and it shows real control sizes. |
| `<name>.menus.txt` | The menu bar: titles, enabled state and key equivalents for the current selection. |
| `harness.log` | The steps run and any error. |

## How it works

`Kerf --ui-scenario file.json --ui-out dir` (debug builds only, `#if DEBUG`) skips the Welcome window,
the recovery timer and prompt, opens an untitled document, and runs the steps from inside the process
(`Sources/KerfApp/Harness/`). The window is drawn into a bitmap by the app itself, so **no Screen Recording
permission is needed**, the window does not have to be in front, and the display can be asleep. SwiftUI
only builds its accessibility nodes for an attached client, so the `.ax.txt` dump and the `press` step read
the app's own tree through the Accessibility API from a background thread; that needs your terminal to be
trusted for Accessibility (without it the dump lists only the window chrome and says so).

`scripts/ui.sh` gives each run its own `HOME` inside the output folder, so the app never reads or writes
your real preferences, tool library, recovery copies or window state. A 90 s watchdog on its own thread
ends a run that hangs.

## Scenario format

```json
{
  "name": "profile inspector, light",
  "appearance": "light",
  "window": [1280, 820],
  "steps": [
    {"op": "sample", "name": "sign"},
    {"op": "tab", "value": "toolpaths"},
    {"op": "calculate"},
    {"op": "selectToolpath", "name": "Profile 1"},
    {"op": "expand", "name": "Last Pass"},
    {"op": "capture", "name": "profile"}
  ]
}
```

`appearance` is `light`, `dark` or `system`; `window` is the content size in points (the document window's
minimum is 1000 x 640). Steps run in order and the run stops at the first error, naming the step.

| op | arguments | does |
|---|---|---|
| `sample` | `name`: `sign` | loads the sample project into the document |
| `appearance` | `value`: light / dark / system | changes appearance mid-run |
| `size` | `size`: `[w, h]` | resizes the window |
| `mode` | `value`: 2d / split / 3d | centre view |
| `tab` | `value`: design / toolpaths | sidebar tab |
| `tool` | `value`: a canvas tool (`rectangle`, `nodeEdit`…) | active drawing tool |
| `select` | `names`: shape names | selects shapes |
| `selectToolpath` | `name` | selects a toolpath (and shows the Toolpaths tab) |
| `calculate` | | calculates all toolpaths and waits |
| `sheet` / `closeSheet` | `value`: jobSetup, exportGCode, validation, … | opens or closes a sheet |
| `expand` | `name`: a collapsible section's title | opens it (the state the app remembers) |
| `press` | `name`: text in a control's label, title, help or id; `value`: optional role (`AXButton`) | clicks that control with a real mouse event |
| `wait` | `seconds` | lets background work finish (the 3D preview builds its stock asynchronously) |
| `capture` | `name` | window PNG and accessibility tree |
| `captureSheet` | `name` | the open sheet's PNG and accessibility tree |
| `menus` | `name` | the menu bar dump |

`scripts/ui.sh --help` and `HarnessScenario.ops` list them too; a bad scenario fails with the valid ops.
Add a scenario by dropping a JSON file in `harness/scenarios/` (`HarnessScenarioTests` checks every file
there parses).

## Limits

- The window is drawn inactive unless you pass `--active` (grey traffic lights, grey selection). `--active`
  asks to bring Kerf to the front for the run; macOS may not grant it.
- `menus` lists the menu bar's structure, titles and key equivalents. Items that depend on the focused document
  (Group, Mirror, Align…) show as disabled, because SwiftUI's menu focus does not reach the document in this
  setup, so check enablement in the running app. Every harness flag takes a value (`--ui-active 1`): a bare
  flag shifts AppKit's `-key value` argument pairing, and the next value is taken for a file to open.
- Popovers, pop-up menu contents and file panels are not captured. `menus` dumps the menu bar's structure.
- SceneKit (the 3D preview) is composited from its own snapshot; give it a `wait` before a capture, or the
  simulated stock is not built yet.
- `press` delivers a mouse click; it does not toggle a disclosure group (use `expand`) and does not type.
- Debug builds only. A release build has no harness.
