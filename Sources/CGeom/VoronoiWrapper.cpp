// Boost.Polygon Voronoi diagram of points and segments, exposed through CGeom.h.
// Edges are sampled into polylines whose points carry the distance to the
// nearest input site — this is what the V-carve medial-axis toolpath needs.
#include "CGeom.h"

#include <boost/polygon/voronoi_builder.hpp>
#include <boost/polygon/voronoi_diagram.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

namespace bp = boost::polygon;

struct kg_voronoi {
    std::vector<kg_vpoint> vertices;
    std::vector<kg_vedge> edges;
    std::vector<kg_vpoint> samples;
};

namespace {

struct P { double x, y; };
struct Seg { P a, b; };

double dist(P a, P b) { return std::hypot(a.x - b.x, a.y - b.y); }

double distToSegment(P p, Seg s) {
    double dx = s.b.x - s.a.x, dy = s.b.y - s.a.y;
    double len2 = dx * dx + dy * dy;
    if (len2 <= 0) return dist(p, s.a);
    double t = ((p.x - s.a.x) * dx + (p.y - s.a.y) * dy) / len2;
    t = std::clamp(t, 0.0, 1.0);
    return dist(p, P{s.a.x + t * dx, s.a.y + t * dy});
}

struct Sites {
    std::vector<P> points;  // snapped, in input units
    std::vector<Seg> segs;  // snapped, in input units

    // Geometry of a cell's site: either a point or a segment.
    bool isPoint(const bp::voronoi_cell<double> &cell) const {
        return cell.contains_point();
    }
    P pointOf(const bp::voronoi_cell<double> &cell) const {
        size_t idx = cell.source_index();
        if (idx < points.size()) return points[idx];
        const Seg &s = segs[idx - points.size()];
        return cell.source_category() == bp::SOURCE_CATEGORY_SEGMENT_START_POINT ? s.a : s.b;
    }
    Seg segOf(const bp::voronoi_cell<double> &cell) const {
        return segs[cell.source_index() - points.size()];
    }
    double distance(const bp::voronoi_cell<double> &cell, P p) const {
        return isPoint(cell) ? dist(p, pointOf(cell)) : distToSegment(p, segOf(cell));
    }
};

kg_site_kind kindOf(const bp::voronoi_cell<double> &cell, size_t pointCount) {
    if (cell.source_index() < pointCount) return KG_SITE_POINT;
    switch (cell.source_category()) {
    case bp::SOURCE_CATEGORY_SEGMENT_START_POINT: return KG_SITE_SEGMENT_START;
    case bp::SOURCE_CATEGORY_SEGMENT_END_POINT: return KG_SITE_SEGMENT_END;
    default: return KG_SITE_SEGMENT;
    }
}

// Point on the parabola equidistant from focus `f` and the line through `s`,
// whose foot on that line is at parameter `t` (distance along unit direction from s.a).
P parabolaPoint(P f, Seg s, double t, double *radius) {
    double dx = s.b.x - s.a.x, dy = s.b.y - s.a.y;
    double len = std::hypot(dx, dy);
    double ux = dx / len, uy = dy / len;
    P foot{s.a.x + ux * t, s.a.y + uy * t};
    double nx = -uy, ny = ux; // unit normal
    double ddx = foot.x - f.x, ddy = foot.y - f.y;
    double nd = nx * ddx + ny * ddy;
    if (nd > 0) { nx = -nx; ny = -ny; nd = -nd; } // normal toward focus
    double d2 = ddx * ddx + ddy * ddy;
    double h = nd != 0 ? -d2 / (2 * nd) : 0;
    *radius = h;
    return P{foot.x + nx * h, foot.y + ny * h};
}

double projectParam(P p, Seg s) {
    double dx = s.b.x - s.a.x, dy = s.b.y - s.a.y;
    double len = std::hypot(dx, dy);
    return ((p.x - s.a.x) * dx + (p.y - s.a.y) * dy) / len;
}

} // namespace

extern "C" {

kg_voronoi *kg_voronoi_build(const double *points, int32_t pointCount,
                             const double *segments, int32_t segmentCount,
                             double scale, double maxSampleStep) {
    auto *out = new kg_voronoi();
    if (scale <= 0) scale = 10000;
    if (maxSampleStep <= 0) maxSampleStep = 1e30;
    auto snap = [scale](double v) { return static_cast<int>(std::llround(v * scale)); };

    Sites sites;
    bp::voronoi_builder<int> builder;
    for (int32_t i = 0; i < pointCount; ++i) {
        int x = snap(points[2 * i]), y = snap(points[2 * i + 1]);
        builder.insert_point(x, y);
        sites.points.push_back(P{x / scale, y / scale});
    }
    for (int32_t i = 0; i < segmentCount; ++i) {
        const double *s = segments + 4 * i;
        int x0 = snap(s[0]), y0 = snap(s[1]), x1 = snap(s[2]), y1 = snap(s[3]);
        builder.insert_segment(x0, y0, x1, y1);
        sites.segs.push_back(Seg{P{x0 / scale, y0 / scale}, P{x1 / scale, y1 / scale}});
    }
    bp::voronoi_diagram<double> vd;
    builder.construct(&vd);

    const auto &verts = vd.vertices();
    const auto &edges = vd.edges();
    auto vertexIndex = [&](const bp::voronoi_vertex<double> *v) -> int32_t {
        return v ? static_cast<int32_t>(v - verts.data()) : -1;
    };

    out->vertices.reserve(verts.size());
    for (const auto &v : verts) {
        P p{v.x() / scale, v.y() / scale};
        double r = sites.distance(*v.incident_edge()->cell(), p);
        out->vertices.push_back(kg_vpoint{p.x, p.y, r});
    }

    const size_t np = sites.points.size();
    out->edges.reserve(edges.size());
    for (const auto &e : edges) {
        const auto &cell = *e.cell();
        kg_vedge ke{};
        ke.v0 = vertexIndex(e.vertex0());
        ke.v1 = vertexIndex(e.vertex1());
        ke.twin = static_cast<int32_t>(e.twin() - edges.data());
        size_t src = cell.source_index();
        ke.siteIndex = static_cast<int32_t>(src < np ? src : src - np);
        ke.siteKind = kindOf(cell, np);
        ke.isPrimary = e.is_primary() ? 1 : 0;
        ke.isCurved = e.is_curved() ? 1 : 0;
        ke.isInfinite = e.is_infinite() ? 1 : 0;
        ke.sampleStart = static_cast<int32_t>(out->samples.size());
        ke.sampleCount = 0;

        if (e.is_finite()) {
            P a{e.vertex0()->x() / scale, e.vertex0()->y() / scale};
            P b{e.vertex1()->x() / scale, e.vertex1()->y() / scale};
            const auto &other = *e.twin()->cell();
            bool curved = e.is_curved();
            const auto &pointCell = cell.contains_point() ? cell : other;
            const auto &segCell = cell.contains_point() ? other : cell;
            double length = dist(a, b);
            int n = std::max(1, static_cast<int>(std::ceil(length / maxSampleStep)));
            if (curved) {
                P focus = sites.pointOf(pointCell);
                Seg s = sites.segOf(segCell);
                double t0 = projectParam(a, s), t1 = projectParam(b, s);
                for (int k = 0; k <= n; ++k) {
                    double r = 0;
                    P q;
                    if (k == 0) q = a;
                    else if (k == n) q = b;
                    else q = parabolaPoint(focus, s, t0 + (t1 - t0) * k / n, &r);
                    r = sites.distance(cell, q);
                    out->samples.push_back(kg_vpoint{q.x, q.y, r});
                }
            } else {
                for (int k = 0; k <= n; ++k) {
                    double t = static_cast<double>(k) / n;
                    P q{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t};
                    out->samples.push_back(kg_vpoint{q.x, q.y, sites.distance(cell, q)});
                }
            }
            ke.sampleCount = n + 1;
        }
        out->edges.push_back(ke);
    }
    return out;
}

int32_t kg_voronoi_vertex_count(const kg_voronoi *vd) {
    return vd ? static_cast<int32_t>(vd->vertices.size()) : 0;
}
const kg_vpoint *kg_voronoi_vertices(const kg_voronoi *vd) {
    return vd ? vd->vertices.data() : nullptr;
}
int32_t kg_voronoi_edge_count(const kg_voronoi *vd) {
    return vd ? static_cast<int32_t>(vd->edges.size()) : 0;
}
const kg_vedge *kg_voronoi_edges(const kg_voronoi *vd) {
    return vd ? vd->edges.data() : nullptr;
}
int32_t kg_voronoi_sample_count(const kg_voronoi *vd) {
    return vd ? static_cast<int32_t>(vd->samples.size()) : 0;
}
const kg_vpoint *kg_voronoi_samples(const kg_voronoi *vd) {
    return vd ? vd->samples.data() : nullptr;
}
void kg_voronoi_free(kg_voronoi *vd) { delete vd; }

} // extern "C"
