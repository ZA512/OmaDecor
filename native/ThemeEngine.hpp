#pragma once

#include <memory>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>

enum class eOmaPrimitiveType {
    EDGE,
    RECT,
};

enum class eOmaSide {
    TOP,
    RIGHT,
    BOTTOM,
    LEFT,
};

enum class eOmaPlacement {
    INSIDE,
    CENTER,
    OUTSIDE,
};

struct SOmaScalar {
    double relative = 0.0;
    double pixels   = 0.0;

    double resolve(double extent) const {
        return relative * extent + pixels;
    }
};

struct SOmaColor {
    double red   = 0.0;
    double green = 0.0;
    double blue  = 0.0;
    double alpha = 1.0;
};

struct SOmaDrawOperation {
    eOmaPrimitiveType type      = eOmaPrimitiveType::RECT;
    eOmaSide          side      = eOmaSide::TOP;
    eOmaPlacement     placement = eOmaPlacement::OUTSIDE;
    SOmaScalar        start     = {};
    SOmaScalar        end       = {.relative = 1.0};
    SOmaScalar        x         = {};
    SOmaScalar        y         = {};
    SOmaScalar        width     = {};
    SOmaScalar        height    = {};
    double            thickness = 0.0;
    double            distance  = 0.0;
    SOmaColor         color     = {};
    double            opacity   = 1.0;
};

struct SOmaCompiledState {
    double                         opacity = 1.0;
    std::vector<SOmaDrawOperation> operations;
};

struct SOmaCompiledTheme {
    std::string       id;
    std::string       name;
    std::string       version;
    SOmaCompiledState focused;
    SOmaCompiledState inactive;
};

using SOmaParameterValue = std::variant<double, bool, std::string, SOmaColor>;

struct SOmaThemeInputs {
    std::unordered_map<std::string, SOmaParameterValue> parameters;
    std::unordered_map<std::string, SOmaColor>          systemColors;
};

struct SOmaThemeLoadResult {
    std::shared_ptr<const SOmaCompiledTheme> theme;
    std::string                              error;

    explicit operator bool() const {
        return theme != nullptr;
    }
};

SOmaThemeLoadResult loadOmaDecorationTheme(const std::string& path, const SOmaThemeInputs& inputs);
bool applyOmaThemeParameterOverrides(const std::string& json, SOmaThemeInputs& inputs, std::string& error);
