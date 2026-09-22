#include <cassert>
#include <cmath>
#include <iostream>

#include "ThemeEngine.hpp"

int main(int argc, char** argv) {
    assert(argc == 3);

    SOmaThemeInputs inputs;
    inputs.parameters = {
        {"mainColor", SOmaColor{0.278, 0.843, 1.0, 1.0}},
        {"lightWidth", 3.0},
        {"darkWidth", 7.0},
        {"inactiveOpacity", 0.4},
    };
    inputs.systemColors = {
        {"accent", SOmaColor{0.278, 0.843, 1.0, 1.0}},
        {"background", SOmaColor{0.067, 0.067, 0.067, 1.0}},
        {"foreground", SOmaColor{0.933, 0.933, 0.933, 1.0}},
        {"border", SOmaColor{0.392, 0.455, 0.545, 1.0}},
    };

    const auto result = loadOmaDecorationTheme(argv[1], inputs);
    assert(result && result.error.empty());
    assert(result.theme->id == "omadecor/raised-edge");
    assert(result.theme->focused.operations.size() == 4);
    assert(result.theme->inactive.operations.size() == 4);
    assert(std::abs(result.theme->focused.opacity - 1.0) < 0.0001);
    assert(std::abs(result.theme->inactive.opacity - 0.4) < 0.0001);
    assert(std::abs(result.theme->focused.operations[0].thickness - 3.0) < 0.0001);
    assert(std::abs(result.theme->focused.operations[2].thickness - 7.0) < 0.0001);
    assert(result.theme->focused.operations[0].color.blue > result.theme->focused.operations[2].color.blue);

    const auto edgeRect = loadOmaDecorationTheme(argv[2], inputs);
    assert(edgeRect && edgeRect.error.empty());
    assert(edgeRect.theme->id == "omadecor/edge-rect-test");
    assert(edgeRect.theme->focused.operations.size() == 2);
    assert(edgeRect.theme->focused.operations[0].type == eOmaPrimitiveType::EDGE);
    assert(edgeRect.theme->focused.operations[1].type == eOmaPrimitiveType::RECT);
    assert(std::abs(edgeRect.theme->inactive.opacity - 0.35) < 0.0001);

    std::cout << "native decoration theme engine: ok\n";
    return 0;
}
