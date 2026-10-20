# Kerf UI/UX review against Apple's Human Interface Guidelines

Date: 2026-10-20. Scope: `Sources/KerfApp` and the running app (window shell, sidebar, inspector, toolbar, menus, Job Setup and Export sheets, 3D preview, Welcome window, accessibility tree).

## Method and limits

- **Code review plus a visual pass.** I ran `dist/Kerf.app` (built 09:38 the same day) on a scratch copy of `samples/sign.kerf`, at the default window size of 1000 × 692 pt, in **dark mode only**. I drove it through the accessibility tree and captured only Kerf's own windows. Screenshots and tree dumps are in `.tmp/ux-review.kQoFUj/` (git-ignored): `01-main` to `09-export` `.png`, `tree-*.txt`.
- **Not checked:** light mode, Increase Contrast, a window wider than 1000 pt, Preferences, the Tool Database, the Clipart browser, VoiceOver itself (I read the accessibility tree but did not listen to it), and the file panels. Findings marked *(code)* come from reading the source only.
- **HIG sources.** I fetched the *Keyboards* and *Accessibility* pages and quote them. Other HIG topics are cited by name from my knowledge of the guidelines and were not re-fetched.
- **Side effects:** Kerf restored two "Untitled" windows from your earlier session; I did not touch them. I quit Kerf at the end (no save prompt) and handed focus back to the terminal.
- **Scope labels** (one line / one file / several files) replace time estimates.

## Fix first

### 1. 3D and split modes overflow the window
- **HIG:** Windows, Layout (adapt to the window size), Toolbars.
- **Where:** `ContentView.swift:74-86`, `KerfApp.swift:32`, `SimulationPreviewView.swift:219` (the playback bar).
- **Evidence:**
  - The default window is the minimum width, 1000 pt.
  - In **3D** mode the split view is laid out at **1695 pt** wide inside that 1000 pt window (accessibility frame `[-83,152 1695x692]` against a window at x = 264). The sidebar starts 347 pt left of the window edge, the inspector is off the right edge, and the playback bar and status bar are clipped on the left (`08-3d.png`). The centre pane is 1213 pt wide, and the playback bar (a dozen or more controls) runs from its left edge to its right edge, so it is apparently what refuses to shrink.
  - In **2D | 3D** mode the sidebar and inspector are clipped and inspector fields are cut off mid-value (`05-split.png`). The code asks for 2 × 320 pt of canvas (`ContentView.swift:82-83`).
  - A 1470 pt window (the size of your other restored window) would still be 225 pt short for 3D mode. That is computed from the frames and not tried.
  - Switching back to 2D restores the layout.
- **Fix:** Let the playback bar wrap or collapse into a menu (`ViewThatFits`). Drop the 320 pt split minimums. Collapse the inspector in 3D and split modes. Open at a larger default size and set the window minimum to what the content needs.
- **Scope:** several files.

### 2. Calculate, Export G-code and the Post picker are in the toolbar overflow
- **HIG:** Toolbars (put frequent actions in the toolbar, avoid crowding, let people customise).
- **Where:** `ContentView.swift:112-143`, `MachinePickers.swift:6-26`.
- **Evidence:** At the default width the toolbar shows the sidebar toggle, Job Setup, the view picker, Zoom to Fit, Snap and the 190 pt Machine picker. Behind the `»` menu are **Post, Tools, Calculate, Export G-code and Inspector** (`06-overflow.png`). The toolbar has no `toolbar(id:)`, so people cannot rearrange it.
- **Related problems:**
  - Machine and Post are job settings that change the bed limits and the G-code dialect, yet they are one click away.
  - The Welcome quick-start says "Choose the machine and post processor in the toolbar" (`SampleProjects.swift:44`), but Post is not visible there.
- **Fix:** Move Machine and Post into Job Setup. Show them read-only in the status bar and open Job Setup on click. Put Calculate and Export in `.primaryAction`. Make the toolbar customisable with `ToolbarItem(id:)`. Update the Welcome copy.
- **Scope:** several files.

### 3. Job Setup and Export hide settings below the fold
- **HIG:** Sheets, Layout.
- **Where:** `JobSetupSheet.swift:100`, `ExportGCodeSheet.swift:46`.
- **Evidence:**
  - **Job Setup** (`04-jobsetup.png`): the sheet is 680 pt tall and hangs 40 pt below the bottom of its 692 pt parent window. Its scroll area shows 579 pt of about 1120 pt of content. The XY-origin picker is cut in half. **Sides, Safe Z, Plunge Z, Home X/Y/Z and Grid spacing are all below the fold**, with no visible scroll indicator. Those are the safety-critical settings.
  - **Export G-code** (`09-export.png`): the summary form is fixed at 230 pt and its "XY origin" row is cut off. A two-sided job adds a "Side" row that would be clipped too.
  - Other sheets use the same fixed-height pattern *(code)*: `ModelPlacementSheet.swift:98`, `InlayWizardSheet.swift:82`.
- **Fix:** Put the heights and origin settings on the first screen, or split Job Setup into tabs (Material, Origin and Z zero, Heights). Drop the fixed form heights and size sheets to their content with a maximum.
- **Scope:** several files.

### 4. Tool palette buttons have glyph-sized hit targets
- **HIG:** Accessibility, "Offer sufficiently sized controls". The page lists macOS at **28 × 28 pt default and 20 × 20 pt minimum**.
- **Where:** `DesignCanvas.swift:33-41`.
- **Evidence:**
  - Unselected tool buttons report frames of 11–17 pt. The selected one reports its full 28 × 26 cell.
  - I clicked inside the cell but 4–5 pt away from the glyph, at the corner, the mid-left edge and the top centre. Nothing happened. Clicking the glyph switched the tool.
  - Other icon buttons report similar frames, but I did not click them to test the real hit area: Add layer 10 × 10, layer eye 17 × 11, lock 13 × 12, toolpath Calculate 13 × 13, origin dots 13 × 13.
- **Cause:** A `.plain` button with a clear background is only hit-tested on the glyph.
- **Fix:** Add `.contentShape(Rectangle())` to the label. For borderless buttons, pad the label to at least 20 pt.
- **Scope:** one file for the palette, a few more for the rest.

### 5. The status bar wraps and repeats itself
- **HIG:** Layout, Writing (be concise).
- **Where:** `ContentView.swift:146-170`.
- **Evidence:** At the default width the status bar wraps to three lines (`01-main.png`) and to four with a selection (`07-shape.png`), adding roughly 25–40 pt of height at the expense of the canvas. It repeats "Avid PRO6096 (Mach4) · Avid PRO6096 Mach4 (inch)", which the Job inspector also shows. The cursor readout prints `X 12.5  Y 3` with no unit *(code, `:159-161`; I did not hover over the canvas)*.
- **Fix:** One line per item with `.lineLimit(1)`. Keep only what changes (cursor, selection) in the bar and leave job facts to the Job inspector. Append `document.units.abbreviation` to the cursor readout.
- **Scope:** one file.

## Should fix

### 6. The inspector mixes two edit models and its fields do not line up
- **HIG:** Inspectors (changes apply immediately), Undo and redo, Layout.
- **Where:** `InspectorView.swift:150-156, 164-170`, `FormControls.swift:18-31`; contrast `OperationEditor.swift:67`.
- **Evidence:**
  - Position & Size needs **Apply** and **Revert**. Rotate needs **Apply** and defaults to 90. Move X and Move Y share one "Move" button next to the second field, and Scale X and Scale Y share "Scale" (`07-shape.png`). The toolpath editor applies every change at once.
  - Number fields do not share a right edge: about 30 pt of stagger in the shape inspector and up to about 55 pt in the Pocket form ("Start depth" against "Last pass thickness", `03-toolpath.png`). Rows are `LabeledContent` in a plain `VStack`, not a `Form` or `Grid`.
- **Fix:** Make X, Y, Width and Height commit when the field commits, and drop Apply and Revert (Undo covers it). Keep Rotate, Move and Scale as explicit actions, with one button per row or one clearly labelled button under each field pair. Use a `Grid` or `Form` so labels, fields and units form columns.
- **Scope:** one or two files.

### 7. Shortcuts that shadow standard macOS ones
- **HIG:** Keyboards. The page says: "In general, don't repurpose standard keyboard shortcuts for custom actions."

| Kerf | Binding | HIG table entry |
|---|---|---|
| Show Toolpaths (`KerfCommands.swift:209`) | ⌥⌘T | Show or hide a toolbar |
| Import (`:28`) | ⌘I | Italicize / Display an Info window |
| Rotate 90° (`:135`, `:137`) | ⌘[ ⌘] | Left-align / right-align |
| Show Bottom Side (`:68`) | ⌥⌘F | Jump to the search field |
| Group (`:91`) | ⌘G | Find next (conventional in drawing apps and Kerf has no Find, so low risk) |

- **Problem:** ⌥⌘T likely collides with the Hide Toolbar item SwiftUI adds to the View menu, so one of the two is shadowed *(inferred)*.
- **Fix:** Rebind the first four to unused keys (for example ⇧⌘I for Import).
- **Scope:** one file.

### 8. The toolpath forms show every parameter at once
- **HIG:** Disclosure controls, Inspectors.
- **Where:** `OperationForms.swift`, `Toolpaths2DForms.swift`.
- **Evidence** (interactive controls and content height against the 640 pt viewport): Profile **43 controls, 1258 pt**; Pocket 26 controls, 856 pt; V-Carve 17, 653 pt; Drilling 17, 596 pt. In Pocket the Calculate and Delete buttons sit at the very bottom, below the fold, and the toolbar's Calculate is in the overflow menu (finding 2). The whole app has 3 `DisclosureGroup`s.
- **Fix:** Group rarely changed parameters under "Advanced" disclosure groups, remembered per toolpath kind (`@SceneStorage`). Pin Calculate to the top or bottom of the inspector. Prototype in `ProfileForm`.
- **Scope:** several files.

### 9. The sidebar truncates at its minimum width
- **HIG:** Sidebars, Layout.
- **Where:** `ContentView.swift:19`, `SidebarView.swift:141-188, 277`.
- **Evidence** (sidebar minimum 220 pt, ideal 270): "Calculate All" truncates to "Calculate…", toolpath subtitles read "Pocket · T1 · 2m…" and "V-Carve · T6 · 4…", and the "Estimated time:" label wraps (`06-overflow.png`, `09-export.png`). In the Layers list each colour well reports 44 pt wide although the code asks for 28 pt (`SidebarView.swift:175`), so it overlaps the name field by 2 pt and "Layer 1" touches the swatch with no gap (`01-main.png`).
- **Fix:** Shorten the labels ("Calculate"), use icon buttons, or let the row wrap. Do not raise the sidebar minimum: finding 1 shows the layout is already over its width budget. Give the colour well a fixed frame with spacing after it.
- **Scope:** one file.

### 10. Several controls have generated or misleading VoiceOver names
- **HIG:** Accessibility, VoiceOver.
- **Evidence** (accessibility tree; I did not listen with VoiceOver):
  - The XY-origin picker is exposed as four buttons named **"Circle"** and one named "Large Filled Circle Inside A Circle". Nothing says which corner each is and nothing marks the selected one (`JobSetupSheet.swift:124-131`). This control sets where machine zero is.
  - The 3D Select and Draw toggles are named "Cursor Arrow Pointer" and "Pencil Writing On A Line" (`SimulationPreviewView.swift:204-211`).
  - The align buttons are named "Horizontal Left Alignment Guides" and so on (`InspectorView.swift:245-252`).
  - "Mirror ↔", "Distribute ↔" and "Space ↕" put an arrow glyph in the title (`InspectorView.swift:169-170, 232-240`).
  - Good: the tool palette, the layer buttons and the toolpath row buttons have proper labels, and the palette's tooltips include the shortcut.
- **Fix:** Add `.accessibilityLabel` ("Origin: lower left") and `.isSelected` to the origin dots and the 3D toggles. Replace the glyph titles with SF Symbols plus text.
- **Scope:** three files.

## Polish

### 11. File panels and alerts are app-modal *(code)*
- **HIG:** Sheets, Panels, Alerts.
- **Where:** about 20 `NSOpenPanel` / `NSSavePanel` `.runModal()` calls, several launched from inside a sheet (`ExportGCodeSheet.swift:165`, `SaveAllToolpathsSheet.swift:131`). `KerfDocument+Sheets.swift:40-45` runs a Delete Sheet alert with `runModal()`.
- **Problems:** Panels float over the whole app instead of attaching to the document window. In that alert, **Delete** is the first and therefore default button (undoable, so minor). Export Vectors asks people to pick the format by typing an extension (`KerfCommands.swift:238-243`).
- **Fix:** Use `beginSheetModal(for:)` or `.fileExporter` / `.fileImporter`. Set `hasDestructiveAction` on Delete. Add a format pop-up to the Export Vectors panel. The RecoveryPrompt alerts are app-level, so app-modal is fine there.
- **Scope:** several files; one shared helper.

### 12. Menus: one overloaded menu, and items stay enabled with nothing to act on *(code)*
- **HIG:** Menus, The menu bar.
- **Where:** `KerfCommands.swift:62-164`. The **Design** menu has about 25 entries covering drawing, alignment, booleans and layout. Mirror, Rotate, Combine, Break Apart, Join, Close Open Vectors and the Align submenu are not `.disabled` when nothing is selected (Group, Ungroup and Offset are). The single-key tool shortcuts (V, R, C…) do not appear next to the Draw submenu items (`:74-78`).
- **Fix:** Split into **Design** and **Arrange** (or **Object**) menus. Disable items when the selection is empty. Show the tool key in the menu where possible.
- **Scope:** one file.

### 13. Two different time estimates for the same job
- **HIG:** Feedback, Writing (consistency).
- **Where:** `ToolChangeSummaryView.swift:17`, `SimulationPreviewView.swift:155`.
- **Evidence:** After Calculate All the sidebar said "Estimated time: **10m 38s**" (`09-export.png`) while the 3D badge said "Estimated time **15m 14s**" (`08-3d.png`). I did not investigate why (they use `ToolpathCalculator` and `MachiningTimeEstimator` respectively). Before calculating, the sidebar shows "Estimated time: 0s · No tools" (`03-toolpath.png`), which reads like a result.
- **Fix:** Use one estimator, or label what each includes (cutting only, with rapids and tool changes). Show "Not calculated" instead of "0s".
- **Scope:** a few files.

### 14. The Export sheet lists the same validator warning twice
- **HIG:** Alerts, Writing.
- **Evidence** (`09-export.png`): "warning: Rapid plunge below the material top to Z-0.1050; use a feed move (14 more)" and then "warning line 1156: Rapid plunge … (14 more)". Each line also has a warning icon, so the word "warning" is redundant. This is the dialog that gates what goes to the machine.
- **Separately, not UI:** the shipped sample produces 15 "Rapid plunge below the material top" warnings. This may be normal peck-drilling re-entry, but the Welcome window invites people to run this sample, so confirm whether the G-code or the validator rule is wrong.
- **Fix:** Merge duplicate issues and drop the text prefix. Link each issue to its line in the preview.
- **Scope:** one or two files.

### 15. The Welcome window and sample content
- **HIG:** Onboarding, Writing.
- **Evidence:** In the Welcome window the link-style buttons have icons of different widths, so their labels start at four different x positions, and two sample descriptions truncate ("…a bore, to pra…", `02-welcome.png`; `WelcomeView.swift:35, 64`). In the sample, objects are named with hash suffixes ("Outline-5b61fcf9", "Hole-ad5805c2", `01-main.png`). I did not check whether other flows produce names like that.
- **Fix:** Use `Label` with a fixed icon width, allow two lines for the sample text, and give the sample readable object names.
- **Scope:** two files.

## Minor

### 16. Low-contrast status text *(computed, light mode)*
- **HIG:** Accessibility (contrast and colour). The page lists 4.5:1 for text up to 17 pt and 3:1 for 18 pt or bold, and says: "Offer visual indicators, like distinct shapes or icons, in addition to color."
- **Where:** `SidebarView.swift:113` ("open" in orange `caption2`), `OperationEditor.swift:172`, `ExportGCodeSheet.swift:84-90`.
- **Problem:** System orange on white is about 2.2:1 by my calculation. In dark mode (all I saw) it reads fine, and the status icons already differ by shape.
- **Fix:** Keep the coloured icon and set the text to `.primary` or `.secondary`.

### 17. Button titles
- **HIG:** Buttons, Sheets (use specific verbs).
- **Where:** `JobSetupSheet.swift:94` uses "OK" (`04-jobsetup.png`). `KeepOutZonesSheet.swift:82` and `ValidationSheet.swift:61` bind Done and Close to Return only.
- **Fix:** Rename to "Apply" or "Save". Add `.cancelAction` to Done and Close so Escape is explicit (SwiftUI may already dismiss on Escape; I did not test).

### 18. Spelling is British, defaults are US
- **HIG:** Writing (use your audience's language).
- **Where:** 23 UI strings, for example "Millimetres" and "Centre" (`FormControls.swift:95, 106`, visible in `04-jobsetup.png`) and "Colours" (`PreferencesView.swift:18`). Default units are inches (`AppPreferences.swift:10`) and the machine is American. `docs/DECISIONS.md` records no spelling decision.
- **Fix:** Choose one spelling and apply it everywhere. If British spelling is intentional, record it in `DECISIONS.md` and ignore this item.

### 19. Ambiguous toolbar and palette icons
- **HIG:** SF Symbols, Toolbars.
- **Evidence:** Zoom to Fit uses the diagonal-arrows glyph that macOS uses for full screen. Job Setup is an unlabeled dashed square (`01-main.png`). In the palette (`DrawingTools.swift:34-50`) Arc is a half-filled circle, and Smooth Curve (`scribble`) and Freehand (`hand.draw`) look alike. Seventeen tools sit in one column with one divider, and only eleven have a key.
- **Fix:** Choose clearer symbols and group the palette (select and edit, shapes, lines and curves, annotate).

### 20. Empty states are hand-built
- **HIG:** Loading / Empty states (a clear explanation and a next action).
- **Where:** `SidebarView.swift:256-264`. The Objects list has no empty state.
- **Fix:** Use `ContentUnavailableView` (macOS 14+, the project's target).

## Already right

- **Native structure:** `DocumentGroup`, `NavigationSplitView`, `.inspector`, a `Settings` scene and standard Undo.
- **Export safety:** the Export sheet shows validator results and a G-code preview before saving, and "Save Anyway" is a destructive-role button with a plain warning (`ExportGCodeSheet.swift:70-75`).
- **Undoable actions:** every edit goes through `document.perform("…")` with a name, which is why deletes need no confirmation dialog.
- **Canvas accessibility:** the canvas is one VoiceOver group with per-shape children, Tab and Shift-Tab move between vectors, and the group's value reads "8 vectors on material 24 x 12 x 0.75 in, 1 selected".
- **Tooltips:** nearly every control has a help tag, and the tool palette's include the shortcut ("Rectangle (R)").
- **Dark mode:** the app renders cleanly in dark mode, and selection feedback on the canvas and in the lists is clear.
- **Status icons:** they differ by shape as well as colour (`SidebarView.swift:346-365`).
- **Dialogs:** consistent Cancel and default-action pairing in `DrawingDialog` (`DrawingSheets.swift:53-56`).
## Checked and not a problem

- **Single-key tool shortcuts (V, R, T…)** only fire while the canvas is the first responder (`CanvasEvents.swift:249-280`, `CanvasNSView.swift:69`), so typing in the inspector does not switch tools.
- **Hard-coded colours** on the canvas, 3D view and image wells are document content, which the HIG allows.
- **Reduce Motion:** the app has no animations to reduce.
- **Delete confirmations:** none are needed because deletes are undoable.
- **Cancelling Job Setup** closed the sheet without applying anything.
