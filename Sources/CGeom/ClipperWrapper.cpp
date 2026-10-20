// Clipper2-backed offsetting and boolean operations exposed through CGeom.h.
#include "CGeom.h"
#include "PathsImpl.hpp"

#include "clipper2/clipper.h"

using namespace Clipper2Lib;

namespace {

PathsD toPaths(const double *xy, const int32_t *counts, int32_t pathCount) {
    PathsD paths;
    if (!xy || !counts || pathCount <= 0) return paths;
    paths.reserve(static_cast<size_t>(pathCount));
    size_t k = 0;
    for (int32_t i = 0; i < pathCount; ++i) {
        PathD path;
        path.reserve(static_cast<size_t>(counts[i]));
        for (int32_t j = 0; j < counts[i]; ++j, k += 2) {
            path.emplace_back(xy[k], xy[k + 1]);
        }
        paths.push_back(std::move(path));
    }
    return paths;
}

kg_paths *fromPaths(const PathsD &paths) {
    auto *out = new kg_paths();
    out->paths.reserve(paths.size());
    for (const auto &p : paths) {
        std::vector<double> flat;
        flat.reserve(p.size() * 2);
        for (const auto &pt : p) {
            flat.push_back(pt.x);
            flat.push_back(pt.y);
        }
        out->paths.push_back(std::move(flat));
    }
    return out;
}

int clampPrecision(int32_t p) { return p < 0 ? 0 : (p > 8 ? 8 : p); }

} // namespace

extern "C" {

int32_t kg_paths_count(const kg_paths *paths) {
    return paths ? static_cast<int32_t>(paths->paths.size()) : 0;
}

int32_t kg_paths_point_count(const kg_paths *paths, int32_t i) {
    if (!paths || i < 0 || i >= kg_paths_count(paths)) return 0;
    return static_cast<int32_t>(paths->paths[static_cast<size_t>(i)].size() / 2);
}

const double *kg_paths_points(const kg_paths *paths, int32_t i) {
    if (!paths || i < 0 || i >= kg_paths_count(paths)) return nullptr;
    return paths->paths[static_cast<size_t>(i)].data();
}

void kg_paths_free(kg_paths *paths) { delete paths; }

kg_paths *kg_offset(const double *xy, const int32_t *counts, int32_t pathCount,
                    double delta, kg_join_type join, kg_end_type end,
                    double miterLimit, double arcTolerance, int32_t precision) {
    JoinType jt = JoinType::Round;
    switch (join) {
    case KG_JOIN_SQUARE: jt = JoinType::Square; break;
    case KG_JOIN_ROUND: jt = JoinType::Round; break;
    case KG_JOIN_MITER: jt = JoinType::Miter; break;
    case KG_JOIN_BEVEL: jt = JoinType::Bevel; break;
    }
    EndType et = EndType::Polygon;
    switch (end) {
    case KG_END_POLYGON: et = EndType::Polygon; break;
    case KG_END_JOINED: et = EndType::Joined; break;
    case KG_END_BUTT: et = EndType::Butt; break;
    case KG_END_SQUARE: et = EndType::Square; break;
    case KG_END_ROUND: et = EndType::Round; break;
    }
    PathsD input = toPaths(xy, counts, pathCount);
    PathsD result = InflatePaths(input, delta, jt, et,
                                 miterLimit > 0 ? miterLimit : 2.0,
                                 clampPrecision(precision), arcTolerance);
    return fromPaths(result);
}

kg_paths *kg_boolean(kg_bool_op op, kg_fill_rule fill,
                     const double *subjXY, const int32_t *subjCounts, int32_t subjPathCount,
                     int32_t subjectsOpen,
                     const double *clipXY, const int32_t *clipCounts, int32_t clipPathCount,
                     int32_t precision) {
    ClipType ct = ClipType::Union;
    switch (op) {
    case KG_OP_INTERSECTION: ct = ClipType::Intersection; break;
    case KG_OP_UNION: ct = ClipType::Union; break;
    case KG_OP_DIFFERENCE: ct = ClipType::Difference; break;
    case KG_OP_XOR: ct = ClipType::Xor; break;
    }
    FillRule fr = FillRule::NonZero;
    switch (fill) {
    case KG_FILL_EVENODD: fr = FillRule::EvenOdd; break;
    case KG_FILL_NONZERO: fr = FillRule::NonZero; break;
    case KG_FILL_POSITIVE: fr = FillRule::Positive; break;
    case KG_FILL_NEGATIVE: fr = FillRule::Negative; break;
    }
    ClipperD clipper(clampPrecision(precision));
    PathsD subjects = toPaths(subjXY, subjCounts, subjPathCount);
    if (subjectsOpen) clipper.AddOpenSubject(subjects);
    else clipper.AddSubject(subjects);
    clipper.AddClip(toPaths(clipXY, clipCounts, clipPathCount));
    PathsD closed, open;
    clipper.Execute(ct, fr, closed, open);
    return fromPaths(subjectsOpen ? open : closed);
}

const char *kg_version(void) {
    return "CGeom 1.0 (Clipper2 1.5.4, Boost.Polygon 1.86.0)";
}

} // extern "C"
