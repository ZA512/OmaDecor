#include "ThemeEngine.hpp"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <optional>
#include <regex>
#include <sstream>
#include <unordered_set>

#include <json-c/json.h>

namespace {
constexpr size_t MAX_THEME_BYTES = 256 * 1024;
constexpr size_t MAX_LAYERS      = 128;
constexpr size_t MAX_OPERATIONS  = 256;
constexpr double MAX_EXTENT      = 128.0;

using JsonPtr = std::unique_ptr<json_object, decltype(&json_object_put)>;
using Value   = std::variant<double, bool, std::string, SOmaColor>;

json_object* member(json_object* object, const char* key) {
    json_object* value = nullptr;
    return object && json_object_get_type(object) == json_type_object && json_object_object_get_ex(object, key, &value) ? value : nullptr;
}

std::optional<std::string> stringValue(json_object* value) {
    if (!value || json_object_get_type(value) != json_type_string)
        return std::nullopt;
    return std::string{json_object_get_string(value)};
}

std::optional<double> numberValue(json_object* value) {
    if (!value || (json_object_get_type(value) != json_type_double && json_object_get_type(value) != json_type_int))
        return std::nullopt;
    const auto number = json_object_get_double(value);
    return std::isfinite(number) ? std::optional<double>{number} : std::nullopt;
}

std::optional<bool> boolValue(json_object* value) {
    if (!value || json_object_get_type(value) != json_type_boolean)
        return std::nullopt;
    return json_object_get_boolean(value) != 0;
}

double clamp(const double value, const double minimum, const double maximum) {
    return std::max(minimum, std::min(maximum, value));
}

std::optional<SOmaColor> parseColor(const std::string& text) {
    if (text.size() != 7 && text.size() != 9)
        return std::nullopt;
    if (text[0] != '#')
        return std::nullopt;
    try {
        const auto component = [&text](const size_t offset) { return std::stoi(text.substr(offset, 2), nullptr, 16) / 255.0; };
        return SOmaColor{component(1), component(3), component(5), text.size() == 9 ? component(7) : 1.0};
    } catch (...) {
        return std::nullopt;
    }
}

struct SOklch {
    double lightness = 0.0;
    double chroma    = 0.0;
    double hue       = 0.0;
    double alpha     = 1.0;
};

double srgbToLinear(const double value) {
    return value <= 0.04045 ? value / 12.92 : std::pow((value + 0.055) / 1.055, 2.4);
}

double linearToSrgb(const double value) {
    return value <= 0.0031308 ? 12.92 * value : 1.055 * std::pow(value, 1.0 / 2.4) - 0.055;
}

SOklch colorToOklch(const SOmaColor& color) {
    const auto red   = srgbToLinear(color.red);
    const auto green = srgbToLinear(color.green);
    const auto blue  = srgbToLinear(color.blue);
    const auto l     = std::cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue);
    const auto m     = std::cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue);
    const auto s     = std::cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue);
    const auto a     = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
    const auto b     = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
    return {
        0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
        std::sqrt(a * a + b * b),
        std::atan2(b, a) * 180.0 / std::numbers::pi,
        color.alpha,
    };
}

SOmaColor oklchToColor(const SOklch& color) {
    const auto angle = color.hue * std::numbers::pi / 180.0;
    const auto a     = color.chroma * std::cos(angle);
    const auto b     = color.chroma * std::sin(angle);
    auto       l     = color.lightness + 0.3963377774 * a + 0.2158037573 * b;
    auto       m     = color.lightness - 0.1055613458 * a - 0.0638541728 * b;
    auto       s     = color.lightness - 0.0894841775 * a - 1.291485548 * b;
    l                = l * l * l;
    m                = m * m * m;
    s                = s * s * s;
    return {
        clamp(linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s), 0.0, 1.0),
        clamp(linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s), 0.0, 1.0),
        clamp(linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s), 0.0, 1.0),
        clamp(color.alpha, 0.0, 1.0),
    };
}

void mergeObject(json_object* target, json_object* patch) {
    if (!target || !patch || json_object_get_type(target) != json_type_object || json_object_get_type(patch) != json_type_object)
        return;
    json_object_object_foreach(patch, key, patchValue) {
        auto* targetValue = member(target, key);
        if (targetValue && json_object_get_type(targetValue) == json_type_object && json_object_get_type(patchValue) == json_type_object)
            mergeObject(targetValue, patchValue);
        else
            json_object_object_add(target, key, json_object_get(patchValue));
    }
}

class CThemeCompiler {
  public:
    CThemeCompiler(json_object* root, const SOmaThemeInputs& inputs) : m_root(root), m_inputs(inputs) {}

    SOmaThemeLoadResult compile() {
        if (!m_root || json_object_get_type(m_root) != json_type_object)
            return failure("theme root must be an object");
        if (numberValue(member(m_root, "schemaVersion")).value_or(-1) != 1)
            return failure("unsupported schemaVersion");
        if (stringValue(member(m_root, "kind")).value_or("") != "omadecor-decoration")
            return failure("invalid theme kind");

        const auto id      = stringValue(member(m_root, "id")).value_or("");
        const auto name    = stringValue(member(m_root, "name")).value_or("");
        const auto version = stringValue(member(m_root, "version")).value_or("");
        if (!std::regex_match(id, std::regex{"^[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._-]{0,63}$"}))
            return failure("invalid theme id");
        if (name.empty() || name.size() > 128)
            return failure("invalid theme name");
        if (!std::regex_match(version, std::regex{"^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$"}))
            return failure("invalid theme version");
        if (!loadCapabilities())
            return failure(m_error);

        m_parameters = member(m_root, "parameters");
        m_palette    = member(m_root, "palette");
        if (!m_parameters || json_object_get_type(m_parameters) != json_type_object || !m_palette || json_object_get_type(m_palette) != json_type_object)
            return failure("parameters and palette must be objects");
        if (json_object_object_length(m_parameters) > 64 || json_object_object_length(m_palette) > 64)
            return failure("parameter or palette budget exceeded");

        auto result    = std::make_shared<SOmaCompiledTheme>();
        result->id      = id;
        result->name    = name;
        result->version = version;
        if (!compileState(true, result->focused) || !compileState(false, result->inactive))
            return failure(m_error);
        return {result, {}};
    }

  private:
    SOmaThemeLoadResult failure(std::string message) const {
        return {nullptr, std::move(message)};
    }

    bool loadCapabilities() {
        auto* capabilities = member(m_root, "requires");
        if (!capabilities || json_object_get_type(capabilities) != json_type_array || json_object_array_length(capabilities) > 64) {
            m_error = "requires must be a bounded array";
            return false;
        }
        static const std::unordered_set<std::string> SUPPORTED = {
            "primitive.edge", "primitive.frame", "primitive.rect", "paint.solid", "state.focused", "color.oklch-derive",
        };
        for (size_t index = 0; index < json_object_array_length(capabilities); ++index) {
            const auto capability = stringValue(json_object_array_get_idx(capabilities, index));
            if (!capability || !SUPPORTED.contains(*capability)) {
                m_error = "unsupported capability at requires[" + std::to_string(index) + "]";
                return false;
            }
            m_capabilities.insert(*capability);
        }
        return true;
    }

    std::optional<Value> resolveReference(const std::string& reference) {
        const auto separator = reference.find('.');
        if (separator == std::string::npos || reference.find('.', separator + 1) != std::string::npos) {
            m_error = "invalid reference: " + reference;
            return std::nullopt;
        }
        const auto scope = reference.substr(0, separator);
        const auto name  = reference.substr(separator + 1);
        if (scope == "system") {
            const auto found = m_inputs.systemColors.find(name);
            if (found == m_inputs.systemColors.end()) {
                m_error = "unknown system color: " + reference;
                return std::nullopt;
            }
            return found->second;
        }
        if (scope == "param")
            return resolveParameter(name);
        if (scope == "palette") {
            const auto color = resolvePalette(name);
            if (color)
                return *color;
            return std::nullopt;
        }
        m_error = "unsupported reference namespace: " + reference;
        return std::nullopt;
    }

    std::optional<Value> resolveValue(json_object* value) {
        if (!value) {
            m_error = "missing value";
            return std::nullopt;
        }
        if (const auto number = numberValue(value))
            return *number;
        if (const auto boolean = boolValue(value))
            return *boolean;
        if (const auto text = stringValue(value))
            return *text;
        if (json_object_get_type(value) == json_type_object) {
            if (const auto reference = stringValue(member(value, "ref")))
                return resolveReference(*reference);
        }
        m_error = "unsupported value";
        return std::nullopt;
    }

    std::optional<Value> resolveParameter(const std::string& name) {
        if (const auto cached = m_parameterCache.find(name); cached != m_parameterCache.end())
            return cached->second;
        const auto marker = "param." + name;
        if (std::ranges::find(m_resolving, marker) != m_resolving.end()) {
            m_error = "cyclic reference involving " + marker;
            return std::nullopt;
        }
        auto* definition = member(m_parameters, name.c_str());
        if (!definition || json_object_get_type(definition) != json_type_object) {
            m_error = "unknown parameter: " + name;
            return std::nullopt;
        }
        m_resolving.push_back(marker);
        std::optional<Value> resolved;
        if (const auto override = m_inputs.parameters.find(name); override != m_inputs.parameters.end())
            resolved = std::visit([](const auto& item) -> Value { return item; }, override->second);
        else
            resolved = resolveValue(member(definition, "default"));
        m_resolving.pop_back();
        if (!resolved)
            return std::nullopt;

        const auto type = stringValue(member(definition, "type")).value_or("");
        if (type == "number") {
            const auto* number = std::get_if<double>(&*resolved);
            const auto  min    = numberValue(member(definition, "min"));
            const auto  max    = numberValue(member(definition, "max"));
            if (!number || !min || !max || *number < *min || *number > *max) {
                m_error = "parameter outside range: " + name;
                return std::nullopt;
            }
        } else if (type == "color") {
            if (const auto* text = std::get_if<std::string>(&*resolved)) {
                const auto color = parseColor(*text);
                if (!color) {
                    m_error = "invalid color parameter: " + name;
                    return std::nullopt;
                }
                resolved = *color;
            } else if (!std::holds_alternative<SOmaColor>(*resolved)) {
                m_error = "invalid color parameter: " + name;
                return std::nullopt;
            }
        } else if (type == "boolean" && !std::holds_alternative<bool>(*resolved)) {
            m_error = "invalid boolean parameter: " + name;
            return std::nullopt;
        } else if (type == "enum") {
            const auto* text    = std::get_if<std::string>(&*resolved);
            auto*       options = member(definition, "options");
            bool        found   = false;
            if (text && options && json_object_get_type(options) == json_type_array) {
                for (size_t index = 0; index < json_object_array_length(options); ++index)
                    found = found || stringValue(json_object_array_get_idx(options, index)).value_or("") == *text;
            }
            if (!found) {
                m_error = "invalid enum parameter: " + name;
                return std::nullopt;
            }
        } else if (type != "number" && type != "color" && type != "boolean" && type != "enum") {
            m_error = "unsupported parameter type: " + type;
            return std::nullopt;
        }
        m_parameterCache[name] = *resolved;
        return resolved;
    }

    std::optional<SOmaColor> resolvePalette(const std::string& name) {
        if (const auto cached = m_paletteCache.find(name); cached != m_paletteCache.end())
            return cached->second;
        const auto marker = "palette." + name;
        if (std::ranges::find(m_resolving, marker) != m_resolving.end()) {
            m_error = "cyclic reference involving " + marker;
            return std::nullopt;
        }
        auto* entry = member(m_palette, name.c_str());
        if (!entry) {
            m_error = "unknown palette entry: " + name;
            return std::nullopt;
        }
        m_resolving.push_back(marker);
        std::optional<SOmaColor> result;
        if (const auto text = stringValue(entry))
            result = parseColor(*text);
        else if (json_object_get_type(entry) == json_type_object) {
            if (const auto reference = stringValue(member(entry, "ref"))) {
                const auto resolved = resolveReference(*reference);
                if (resolved) {
                    if (const auto* color = std::get_if<SOmaColor>(&*resolved))
                        result = *color;
                    else if (const auto* colorText = std::get_if<std::string>(&*resolved))
                        result = parseColor(*colorText);
                }
            } else if (auto* derive = member(entry, "derive")) {
                if (!m_capabilities.contains("color.oklch-derive"))
                    m_error = "color.oklch-derive is not declared";
                else {
                    const auto base = resolveColor(member(derive, "from"));
                    if (base) {
                        auto transformed = colorToOklch(*base);
                        const auto modifier = [this, derive](const char* key, const double fallback) -> std::optional<double> {
                            auto* value = member(derive, key);
                            if (!value)
                                return fallback;
                            const auto resolved = resolveScalar(value, false);
                            if (!resolved)
                                return std::nullopt;
                            return resolved->pixels;
                        };
                        const auto lightness = modifier("lightness", 0.0);
                        const auto chroma    = modifier("chroma", 0.0);
                        const auto hue       = modifier("hue", 0.0);
                        const auto alpha     = modifier("alpha", transformed.alpha);
                        if (!lightness || !chroma || !hue || !alpha) {
                            m_error = "palette modifier did not resolve to a number";
                            m_resolving.pop_back();
                            return std::nullopt;
                        }
                        transformed.lightness = clamp(transformed.lightness + *lightness, 0.0, 1.0);
                        transformed.chroma    = std::max(0.0, transformed.chroma + *chroma);
                        transformed.hue += *hue;
                        transformed.alpha = clamp(*alpha, 0.0, 1.0);
                        result = oklchToColor(transformed);
                    }
                }
            }
        }
        m_resolving.pop_back();
        if (!result) {
            if (m_error.empty())
                m_error = "invalid palette entry: " + name;
            return std::nullopt;
        }
        m_paletteCache[name] = *result;
        return result;
    }

    std::optional<SOmaColor> resolveColor(json_object* value) {
        if (const auto text = stringValue(value))
            return parseColor(*text);
        if (value && json_object_get_type(value) == json_type_object) {
            if (const auto reference = stringValue(member(value, "ref"))) {
                const auto resolved = resolveReference(*reference);
                if (resolved) {
                    if (const auto* color = std::get_if<SOmaColor>(&*resolved))
                        return *color;
                    if (const auto* colorText = std::get_if<std::string>(&*resolved))
                        return parseColor(*colorText);
                }
            }
        }
        if (m_error.empty())
            m_error = "color did not resolve";
        return std::nullopt;
    }

    std::optional<SOmaScalar> resolveScalar(json_object* value, const bool allowRelative) {
        if (const auto number = numberValue(value))
            return SOmaScalar{.pixels = *number};
        if (!value || json_object_get_type(value) != json_type_object) {
            m_error = "numeric value did not resolve";
            return std::nullopt;
        }
        if (const auto reference = stringValue(member(value, "ref"))) {
            const auto resolved = resolveReference(*reference);
            if (resolved) {
                if (const auto* number = std::get_if<double>(&*resolved))
                    return SOmaScalar{.pixels = *number};
            }
            m_error = "numeric reference did not resolve: " + *reference;
            return std::nullopt;
        }
        if (allowRelative && (member(value, "rel") || member(value, "px"))) {
            const auto relative = numberValue(member(value, "rel")).value_or(0.0);
            const auto pixels   = numberValue(member(value, "px")).value_or(0.0);
            if (relative < -4.0 || relative > 4.0 || pixels < -4096.0 || pixels > 4096.0) {
                m_error = "relative value outside bounds";
                return std::nullopt;
            }
            return SOmaScalar{relative, pixels};
        }
        m_error = "invalid numeric value";
        return std::nullopt;
    }

    bool compilePaint(json_object* paint, SOmaDrawOperation& operation) {
        if (!m_capabilities.contains("paint.solid") || stringValue(member(paint, "type")).value_or("") != "solid") {
            m_error = "only declared paint.solid is supported";
            return false;
        }
        const auto color = resolveColor(member(paint, "color"));
        if (!color)
            return false;
        operation.color = *color;
        return true;
    }

    std::optional<eOmaPlacement> placement(json_object* layer) {
        const auto text = stringValue(member(layer, "placement")).value_or("outside");
        if (text == "inside")
            return eOmaPlacement::INSIDE;
        if (text == "center")
            return eOmaPlacement::CENTER;
        if (text == "outside")
            return eOmaPlacement::OUTSIDE;
        m_error = "invalid placement";
        return std::nullopt;
    }

    std::optional<eOmaSide> side(const std::string& text) {
        if (text == "top")
            return eOmaSide::TOP;
        if (text == "right")
            return eOmaSide::RIGHT;
        if (text == "bottom")
            return eOmaSide::BOTTOM;
        if (text == "left")
            return eOmaSide::LEFT;
        m_error = "invalid edge side";
        return std::nullopt;
    }

    bool compileEdge(json_object* layer, const eOmaSide edgeSide, SOmaCompiledState& state, const double inheritedOpacity,
                     const std::optional<eOmaPlacement> inheritedPlacement = std::nullopt) {
        SOmaDrawOperation operation;
        operation.type      = eOmaPrimitiveType::EDGE;
        operation.side      = edgeSide;
        operation.opacity   = inheritedOpacity;
        if (inheritedPlacement)
            operation.placement = *inheritedPlacement;
        else {
            const auto resolvedPlacement = placement(layer);
            if (!resolvedPlacement)
                return false;
            operation.placement = *resolvedPlacement;
        }
        if (member(layer, "start")) {
            const auto start = resolveScalar(member(layer, "start"), true);
            if (!start)
                return false;
            operation.start = *start;
        }
        if (member(layer, "end")) {
            const auto end = resolveScalar(member(layer, "end"), true);
            if (!end)
                return false;
            operation.end = *end;
        }
        const auto thickness = resolveScalar(member(layer, "thickness"), false);
        const auto distance  = member(layer, "distance") ? resolveScalar(member(layer, "distance"), false) : std::optional<SOmaScalar>{SOmaScalar{}};
        if (!thickness || !distance || thickness->pixels < 0.0 || distance->pixels < 0.0 ||
            thickness->pixels + distance->pixels > MAX_EXTENT || !compilePaint(member(layer, "paint"), operation))
            return false;
        operation.thickness = thickness->pixels;
        operation.distance  = distance->pixels;
        state.operations.push_back(operation);
        return state.operations.size() <= MAX_OPERATIONS;
    }

    bool compileLayer(json_object* layer, SOmaCompiledState& state) {
        if (boolValue(member(layer, "visible")).value_or(true) == false)
            return true;
        if (const auto clip = stringValue(member(layer, "clip")); clip && *clip != "none") {
            m_error = "clip modes other than none are not implemented";
            return false;
        }
        const auto type = stringValue(member(layer, "type")).value_or("");
        if (!m_capabilities.contains("primitive." + type)) {
            m_error = "primitive capability is not declared: " + type;
            return false;
        }
        const auto opacityScalar = member(layer, "opacity") ? resolveScalar(member(layer, "opacity"), false) : std::optional<SOmaScalar>{SOmaScalar{.pixels = 1.0}};
        if (!opacityScalar || opacityScalar->pixels < 0.0 || opacityScalar->pixels > 1.0)
            return false;
        const auto opacity = opacityScalar->pixels;
        if (type == "edge") {
            const auto edgeSide = side(stringValue(member(layer, "side")).value_or(""));
            return edgeSide && compileEdge(layer, *edgeSide, state, opacity);
        }
        if (type == "frame") {
            if (const auto join = stringValue(member(layer, "join")); join && *join != "square") {
                m_error = "frame joins other than square are reserved for a future capability";
                return false;
            }
            const auto framePlacement = placement(layer);
            if (!framePlacement)
                return false;
            static constexpr std::pair<const char*, eOmaSide> SIDES[] = {
                {"top", eOmaSide::TOP}, {"right", eOmaSide::RIGHT}, {"bottom", eOmaSide::BOTTOM}, {"left", eOmaSide::LEFT},
            };
            bool found = false;
            for (const auto& [key, edgeSide] : SIDES) {
                auto* part = member(layer, key);
                if (!part)
                    continue;
                found = true;
                if (!compileEdge(part, edgeSide, state, opacity, framePlacement))
                    return false;
            }
            if (!found)
                m_error = "frame has no sides";
            return found;
        }
        if (type == "rect") {
            SOmaDrawOperation operation;
            operation.type    = eOmaPrimitiveType::RECT;
            operation.opacity = opacity;
            const auto x      = resolveScalar(member(layer, "x"), true);
            const auto y      = resolveScalar(member(layer, "y"), true);
            const auto width  = resolveScalar(member(layer, "width"), true);
            const auto height = resolveScalar(member(layer, "height"), true);
            if (!x || !y || !width || !height || !compilePaint(member(layer, "paint"), operation))
                return false;
            operation.x      = *x;
            operation.y      = *y;
            operation.width  = *width;
            operation.height = *height;
            state.operations.push_back(operation);
            return state.operations.size() <= MAX_OPERATIONS;
        }
        m_error = "unsupported primitive: " + type;
        return false;
    }

    bool variantMatches(json_object* variant, const bool focused) {
        auto* when = member(variant, "when");
        if (!when || json_object_get_type(when) != json_type_object) {
            m_error = "variant when must be an object";
            return false;
        }
        bool matches = true;
        json_object_object_foreach(when, key, expectedValue) {
            if (std::string_view{key} != "focused" || !m_capabilities.contains("state.focused")) {
                m_error = "unsupported variant state: " + std::string{key};
                return false;
            }
            const auto expected = boolValue(expectedValue);
            if (!expected) {
                m_error = "variant state must be boolean";
                return false;
            }
            matches = matches && (*expected == focused);
        }
        return matches;
    }

    bool compileState(const bool focused, SOmaCompiledState& state) {
        auto* layers = member(m_root, "layers");
        if (!layers || json_object_get_type(layers) != json_type_array || json_object_array_length(layers) > MAX_LAYERS) {
            m_error = "layers must be a bounded array";
            return false;
        }
        auto* variants = member(m_root, "variants");
        if (variants && (json_object_get_type(variants) != json_type_array || json_object_array_length(variants) > 32)) {
            m_error = "variants must be a bounded array";
            return false;
        }
        if (member(m_root, "transitions")) {
            m_error = "transitions are not implemented by V1 Core";
            return false;
        }

        json_object* appearanceCopyRaw = nullptr;
        auto*        appearance        = member(m_root, "appearance");
        if (appearance)
            json_object_deep_copy(appearance, &appearanceCopyRaw, nullptr);
        JsonPtr appearanceCopy{appearanceCopyRaw ? appearanceCopyRaw : json_object_new_object(), &json_object_put};

        std::vector<json_object*> matchingPatches;
        if (variants) {
            for (size_t index = 0; index < json_object_array_length(variants); ++index) {
                auto* variant = json_object_array_get_idx(variants, index);
                m_error.clear();
                const auto matches = variantMatches(variant, focused);
                if (!m_error.empty())
                    return false;
                if (!matches)
                    continue;
                auto* patch = member(variant, "patch");
                if (!patch || json_object_get_type(patch) != json_type_object) {
                    m_error = "variant patch must be an object";
                    return false;
                }
                matchingPatches.push_back(patch);
                if (auto* themePatch = member(patch, "theme"))
                    mergeObject(appearanceCopy.get(), themePatch);
            }
        }
        const auto opacity = member(appearanceCopy.get(), "opacity") ? resolveScalar(member(appearanceCopy.get(), "opacity"), false)
                                                                      : std::optional<SOmaScalar>{SOmaScalar{.pixels = 1.0}};
        if (!opacity || opacity->pixels < 0.0 || opacity->pixels > 1.0) {
            m_error = "appearance opacity outside range";
            return false;
        }
        state.opacity = opacity->pixels;

        std::unordered_set<std::string> layerIds;
        for (size_t index = 0; index < json_object_array_length(layers); ++index) {
            auto* sourceLayer = json_object_array_get_idx(layers, index);
            const auto layerId = stringValue(member(sourceLayer, "id")).value_or("");
            if (!std::regex_match(layerId, std::regex{"^[a-z][A-Za-z0-9-]{0,63}$"}) || !layerIds.insert(layerId).second) {
                m_error = "invalid or duplicate layer id";
                return false;
            }
            json_object* layerCopyRaw = nullptr;
            if (json_object_deep_copy(sourceLayer, &layerCopyRaw, nullptr) != 0 || !layerCopyRaw) {
                m_error = "could not copy layer";
                return false;
            }
            JsonPtr layerCopy{layerCopyRaw, &json_object_put};
            for (auto* patch : matchingPatches) {
                auto* layerPatches = member(patch, "layers");
                if (auto* layerPatch = member(layerPatches, layerId.c_str()))
                    mergeObject(layerCopy.get(), layerPatch);
            }
            if (!compileLayer(layerCopy.get(), state)) {
                if (m_error.empty())
                    m_error = "invalid layer: " + layerId;
                return false;
            }
        }
        return true;
    }

    json_object*                                      m_root       = nullptr;
    json_object*                                      m_parameters = nullptr;
    json_object*                                      m_palette    = nullptr;
    const SOmaThemeInputs&                            m_inputs;
    std::unordered_set<std::string>                   m_capabilities;
    std::unordered_map<std::string, Value>            m_parameterCache;
    std::unordered_map<std::string, SOmaColor>        m_paletteCache;
    std::vector<std::string>                          m_resolving;
    std::string                                       m_error;
};
}

SOmaThemeLoadResult loadOmaDecorationTheme(const std::string& path, const SOmaThemeInputs& inputs) {
    if (path.empty())
        return {nullptr, "theme path is empty"};

    std::error_code errorCode;
    const auto      status = std::filesystem::symlink_status(path, errorCode);
    if (errorCode || !std::filesystem::is_regular_file(status) || std::filesystem::is_symlink(status))
        return {nullptr, "theme path must be a regular non-symlink file"};
    const auto size = std::filesystem::file_size(path, errorCode);
    if (errorCode || size == 0 || size > MAX_THEME_BYTES)
        return {nullptr, "theme file size is outside the allowed range"};
    if (!path.ends_with(".omadecor.json"))
        return {nullptr, "theme file must use the .omadecor.json extension"};

    std::ifstream stream{path, std::ios::binary};
    if (!stream)
        return {nullptr, "theme file could not be opened"};
    std::ostringstream buffer;
    buffer << stream.rdbuf();
    const auto source = buffer.str();

    auto* tokener = json_tokener_new_ex(32);
    if (!tokener)
        return {nullptr, "JSON parser allocation failed"};
    json_tokener_set_flags(tokener, JSON_TOKENER_STRICT | JSON_TOKENER_VALIDATE_UTF8);
    auto* root       = json_tokener_parse_ex(tokener, source.data(), static_cast<int>(source.size()));
    const auto error = json_tokener_get_error(tokener);
    json_tokener_free(tokener);
    if (error != json_tokener_success || !root) {
        if (root)
            json_object_put(root);
        return {nullptr, "invalid theme JSON"};
    }
    JsonPtr rootOwner{root, &json_object_put};
    return CThemeCompiler{root, inputs}.compile();
}

bool applyOmaThemeParameterOverrides(const std::string& json, SOmaThemeInputs& inputs, std::string& error) {
    if (json.empty() || json == "{}")
        return true;
    if (json.size() > 16 * 1024) {
        error = "theme parameter payload exceeds 16 KiB";
        return false;
    }

    auto* tokener = json_tokener_new_ex(8);
    if (!tokener) {
        error = "theme parameter parser allocation failed";
        return false;
    }
    json_tokener_set_flags(tokener, JSON_TOKENER_STRICT | JSON_TOKENER_VALIDATE_UTF8);
    auto* root       = json_tokener_parse_ex(tokener, json.data(), static_cast<int>(json.size()));
    const auto parse = json_tokener_get_error(tokener);
    json_tokener_free(tokener);
    if (parse != json_tokener_success || !root || json_object_get_type(root) != json_type_object || json_object_object_length(root) > 64) {
        if (root)
            json_object_put(root);
        error = "theme parameters must be a bounded JSON object";
        return false;
    }
    JsonPtr owner{root, &json_object_put};
    json_object_object_foreach(root, key, value) {
        const std::string name{key};
        if (!std::regex_match(name, std::regex{"^[a-z][A-Za-z0-9-]{0,63}$"})) {
            error = "invalid theme parameter name";
            return false;
        }
        switch (json_object_get_type(value)) {
            case json_type_boolean: inputs.parameters[name] = json_object_get_boolean(value) != 0; break;
            case json_type_double:
            case json_type_int: {
                const auto number = json_object_get_double(value);
                if (!std::isfinite(number) || number < -1000000.0 || number > 1000000.0) {
                    error = "theme parameter number outside bounds";
                    return false;
                }
                inputs.parameters[name] = number;
                break;
            }
            case json_type_string: {
                const std::string text{json_object_get_string(value)};
                if (text.size() > 128) {
                    error = "theme parameter string exceeds 128 bytes";
                    return false;
                }
                inputs.parameters[name] = text;
                break;
            }
            default: error = "theme parameter values must be scalar"; return false;
        }
    }
    return true;
}
