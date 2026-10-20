// Internal definition of the opaque kg_paths handle.
#pragma once
#include <vector>

struct kg_paths {
    std::vector<std::vector<double>> paths; // each: interleaved x,y
};
