// CGeom — small C-compatible wrapper around vendored C++ geometry libraries:
//   * Clipper2 (polygon offsetting and boolean operations)
//   * Boost.Polygon Voronoi (Voronoi diagram of points/segments, for medial axis)
// All coordinates are doubles in document units. Paths are passed as flat,
// interleaved x,y arrays plus a per-path point count array.
// Every *_t* result returned by this API must be released with its *_free function.
#ifndef CGEOM_H
#define CGEOM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Path sets (results of offset / boolean)

typedef struct kg_paths kg_paths;

int32_t kg_paths_count(const kg_paths *paths);
int32_t kg_paths_point_count(const kg_paths *paths, int32_t pathIndex);
/// Interleaved x,y doubles (2 * point_count values). Valid until kg_paths_free.
const double *kg_paths_points(const kg_paths *paths, int32_t pathIndex);
void kg_paths_free(kg_paths *paths);

// MARK: - Offsetting (Clipper2 InflatePaths)

typedef enum {
    KG_JOIN_SQUARE = 0,
    KG_JOIN_ROUND = 1,
    KG_JOIN_MITER = 2,
    KG_JOIN_BEVEL = 3
} kg_join_type;

typedef enum {
    KG_END_POLYGON = 0, ///< closed paths: offset outward (+delta) or inward (-delta)
    KG_END_JOINED = 1,  ///< open paths treated as closed outline (both sides joined)
    KG_END_BUTT = 2,    ///< open paths, square blunt ends
    KG_END_SQUARE = 3,  ///< open paths, ends extended by delta
    KG_END_ROUND = 4    ///< open paths, round ends
} kg_end_type;

/// Offset paths by `delta` (positive grows closed polygons).
/// `precision` = decimal places kept (0...8); 6 is a good default.
/// `arcTolerance` is in document units (0 = Clipper default of 0.25% of delta).
kg_paths *kg_offset(const double *xy, const int32_t *counts, int32_t pathCount,
                    double delta, kg_join_type join, kg_end_type end,
                    double miterLimit, double arcTolerance, int32_t precision);

// MARK: - Boolean operations

typedef enum {
    KG_OP_INTERSECTION = 1,
    KG_OP_UNION = 2,
    KG_OP_DIFFERENCE = 3,
    KG_OP_XOR = 4
} kg_bool_op;

typedef enum {
    KG_FILL_EVENODD = 0,
    KG_FILL_NONZERO = 1,
    KG_FILL_POSITIVE = 2,
    KG_FILL_NEGATIVE = 3
} kg_fill_rule;

/// Boolean of subject polygons against clip polygons.
/// If `subjectsOpen` is non-zero the subjects are open polylines (e.g. raster lines)
/// and the result contains the clipped open polylines.
kg_paths *kg_boolean(kg_bool_op op, kg_fill_rule fill,
                     const double *subjXY, const int32_t *subjCounts, int32_t subjPathCount,
                     int32_t subjectsOpen,
                     const double *clipXY, const int32_t *clipCounts, int32_t clipPathCount,
                     int32_t precision);

// MARK: - Voronoi diagram (Boost.Polygon)

typedef struct kg_voronoi kg_voronoi;

typedef enum {
    KG_SITE_POINT = 0,          ///< an input point site
    KG_SITE_SEGMENT_START = 1,  ///< start point of an input segment
    KG_SITE_SEGMENT_END = 2,    ///< end point of an input segment
    KG_SITE_SEGMENT = 3         ///< interior of an input segment
} kg_site_kind;

typedef struct {
    double x, y;
    double radius; ///< distance to the nearest input site(s)
} kg_vpoint;

typedef struct {
    int32_t v0, v1;       ///< vertex indices, -1 if the edge is infinite on that side
    int32_t twin;         ///< index of the twin (opposite half-) edge
    int32_t siteIndex;    ///< input index of the site whose cell this half-edge bounds
                          ///< (points are 0..pointCount-1, segments are their own index 0..segCount-1)
    int32_t siteKind;     ///< kg_site_kind of that site
    uint8_t isPrimary;    ///< 0 for secondary edges (segment ↔ its own endpoint)
    uint8_t isCurved;     ///< parabolic arc (point ↔ segment)
    uint8_t isInfinite;
    uint8_t _pad;
    int32_t sampleStart;  ///< first index into kg_voronoi_samples (finite edges only)
    int32_t sampleCount;  ///< number of samples (>= 2 for finite edges, 0 otherwise)
} kg_vedge;

/// Build the Voronoi diagram of points (x,y pairs) and segments (x0,y0,x1,y1 quads).
/// Segments must not cross each other (touching at endpoints is fine).
/// Input is snapped to an integer grid of 1/`scale` units (e.g. scale 10000 for inches).
/// Finite edges are sampled into polylines with spacing <= `maxSampleStep` (doc units),
/// each sample carrying its distance to the bounding sites (for V-carve depth).
kg_voronoi *kg_voronoi_build(const double *points, int32_t pointCount,
                             const double *segments, int32_t segmentCount,
                             double scale, double maxSampleStep);
int32_t kg_voronoi_vertex_count(const kg_voronoi *vd);
const kg_vpoint *kg_voronoi_vertices(const kg_voronoi *vd);
int32_t kg_voronoi_edge_count(const kg_voronoi *vd);
const kg_vedge *kg_voronoi_edges(const kg_voronoi *vd);
int32_t kg_voronoi_sample_count(const kg_voronoi *vd);
const kg_vpoint *kg_voronoi_samples(const kg_voronoi *vd);
void kg_voronoi_free(kg_voronoi *vd);

/// Version string of the wrapper and vendored libs (for diagnostics).
const char *kg_version(void);

#ifdef __cplusplus
}
#endif

#endif // CGEOM_H
