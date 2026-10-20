# File ownership (parallel workstreams)

Each workstream edits only the paths it owns. **Frozen** shared paths accept additive changes
only (new types, new members with defaults, new enum cases only where all switches are in the
same module) — never renames, removals or signature changes. Anything else: note it in
`docs/DECISIONS.md` and leave a `TODO(<workstream>)`.

| Workstream | Owns | Tests |
|---|---|---|
| **scaffold** (frozen after commit) | `Package.swift`, `Sources/CADCore/Model/`, `Sources/CADCore/Kernel/`, `Sources/CAMCore/Model/` (incl. `Parameters/`), `Sources/CGeom/`, `Vendor/`, `scripts/test.sh` | `Tests/CGeomTests/` |
| **cad-io** | `Sources/CADCore/IO/` (except `STLImporter.swift`), `Sources/CADCore/Geometry/`, `Sources/CADCore/Persistence/` | `Tests/CADCoreTests/` (new files named `IO*`, `Geometry*`, `Text*`) |
| **cam-2d** | `Sources/CAMCore/Ops2D/` (Profile, Pocket, Drill, Fluting, Texture + shared helpers e.g. `Ops2D/Support/`) | `Tests/CAMCoreTests/` files prefixed `Ops2D` |
| **cam-vcarve** | `Sources/CAMCore/OpsVCarve/` (VCarve, Inlay, medial axis) | `Tests/CAMCoreTests/` files prefixed `VCarve` |
| **cam-3d** | `Sources/CAMCore/Ops3D/`, `Sources/CADCore/IO/STLImporter.swift` | `Tests/CAMCoreTests/` files prefixed `Relief`, `Tests/CADCoreTests/STL*` |
| **post** | `Sources/PostCore/` | `Tests/PostCoreTests/` |
| **preview** | `Sources/CAMCore/Simulation/`, `Sources/KerfApp/Preview/` | `Tests/CAMCoreTests/` files prefixed `Sim` |
| **app-shell** | `Sources/KerfApp/App/`, `Sources/KerfApp/Canvas/`, `Sources/KerfApp/Panels/`, `scripts/bundle.sh`, `scripts/run.sh`, `Resources/` | — (logic that needs tests goes in the owning core module) |

Rules:
* `Package.swift` changes (new targets/deps) go through the integrator only.
* cam-2d helpers that cam-vcarve / cam-3d want to reuse (pass linking, ramping, safe-Z
  retracts) live in `Sources/CAMCore/Ops2D/Support/` and are `public` or `internal`; other
  workstreams call them but do not edit them.
* `docs/DECISIONS.md` is append-only for everyone; prefix entries with the workstream name.
* Never commit `*.exe`.
