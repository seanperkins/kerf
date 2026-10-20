# Third-party code

| Component | Version | Location | Licence |
|---|---|---|---|
| Clipper2 (Angus Johnson) | 1.5.4 (commit ef88ee97) — `CPP/Clipper2Lib` include + src | `Vendor/Clipper2/` | Boost Software License 1.0 (`Vendor/Clipper2/LICENSE`) |
| Boost.Polygon — Voronoi headers only (`voronoi_builder.hpp`, `voronoi_diagram.hpp`, `voronoi_geometry_type.hpp`, `detail/voronoi_*.hpp`) | Boost 1.86.0 | `Vendor/Boost/include/boost/polygon/` | Boost Software License 1.0 (`Vendor/Boost/LICENSE_1_0.txt`) |
| Boost.Config (`boost/config.hpp`, `boost/config/`, `boost/cstdint.hpp`, `boost/limits.hpp`) — required by the Voronoi headers | Boost 1.86.0 | `Vendor/Boost/include/boost/` | Boost Software License 1.0 |

Vendored files are unmodified. Do not edit them; wrap behaviour in `Sources/CGeom/`.
