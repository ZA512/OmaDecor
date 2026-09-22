#include "RaisedEdgeDecoration.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <ranges>
#include <string_view>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>

#include "globals.hpp"

namespace {
constexpr uint32_t ALL_EDGES = DECORATION_EDGE_TOP | DECORATION_EDGE_RIGHT | DECORATION_EDGE_BOTTOM | DECORATION_EDGE_LEFT;

std::string normalized(std::string value) {
    const auto first = std::ranges::find_if_not(value, [](const unsigned char c) { return std::isspace(c); });
    const auto last  = std::ranges::find_if_not(value | std::views::reverse, [](const unsigned char c) { return std::isspace(c); }).base();

    if (first >= last)
        return {};

    value = std::string(first, last);
    std::ranges::transform(value, value.begin(), [](const unsigned char c) { return std::tolower(c); });
    return value;
}
}

COmaRaisedEdgeDecoration::COmaRaisedEdgeDecoration(PHLWINDOW window) : IHyprWindowDecoration(window), m_window(window) {}

COmaRaisedEdgeDecoration::~COmaRaisedEdgeDecoration() {
    damageEntire();
}

SDecorationPositioningInfo COmaRaisedEdgeDecoration::getPositioningInfo() {
    if (!shouldDraw())
        m_extents = {};
    else if (g_theme && m_window)
        m_extents = themeExtents(*g_theme, m_window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT));
    else {
        const auto lightWidth = std::max<Config::INTEGER>(0, g_config.lightWidth->value());
        const auto darkWidth  = std::max<Config::INTEGER>(0, g_config.darkWidth->value());
        m_extents = {
            Vector2D{static_cast<double>(darkWidth), static_cast<double>(lightWidth)},
            Vector2D{static_cast<double>(lightWidth), static_cast<double>(darkWidth)},
        };
    }

    SDecorationPositioningInfo info;
    info.policy         = DECORATION_POSITION_STICKY;
    info.edges          = ALL_EDGES;
    info.priority       = 9990;
    info.desiredExtents = m_extents;
    info.reserved       = true;
    return info;
}

void COmaRaisedEdgeDecoration::onPositioningReply(const SDecorationPositioningReply& reply) {
    m_assignedGeometry = reply.assignedGeometry;
}

void COmaRaisedEdgeDecoration::draw(PHLMONITOR monitor, const float& alpha) {
    if (!monitor || !shouldDraw())
        return;

    if (g_theme)
        drawTheme(monitor, alpha, *g_theme);
    else
        drawLegacy(monitor, alpha);
}

void COmaRaisedEdgeDecoration::drawLegacy(PHLMONITOR monitor, const float& alpha) {

    auto box = assignedBoxGlobal().translate(-monitor->m_position + m_window->m_floatingOffset).scale(monitor->m_scale).round();
    if (box.width < 1 || box.height < 1)
        return;

    m_lastGlobalBox = assignedBoxGlobal().translate(m_window->m_floatingOffset);

    const auto lightWidth = static_cast<double>(std::clamp(std::lround(g_config.lightWidth->value() * monitor->m_scale), 0L,
                                                           std::lround(std::min(box.width, box.height))));
    const auto darkWidth  = static_cast<double>(std::clamp(std::lround(g_config.darkWidth->value() * monitor->m_scale), 0L,
                                                          std::lround(std::min(box.width, box.height))));
    const auto base       = mainColor();
    const auto main       = base.modifyA(base.a * alpha);
    const auto dark       = darkColor(main);

    if (darkWidth > 0) {
        addRectangle({box.x, box.y, darkWidth, box.height}, dark);
        addRectangle({box.x, box.y + box.height - darkWidth, box.width, darkWidth}, dark);
    }

    if (lightWidth > 0) {
        addRectangle({box.x + darkWidth, box.y, std::max(0.0, box.width - darkWidth), lightWidth}, main);
        addRectangle({box.x + box.width - lightWidth, box.y + lightWidth, lightWidth, std::max(0.0, box.height - lightWidth - darkWidth)}, main);
    }
}

void COmaRaisedEdgeDecoration::drawTheme(PHLMONITOR monitor, const float& alpha, const SOmaCompiledTheme& theme) {
    const auto windowSize = m_window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
    if (windowSize.x <= 0 || windowSize.y <= 0)
        return;

    auto outerGlobal   = assignedBoxGlobal();
    m_lastGlobalBox    = outerGlobal.translate(m_window->m_floatingOffset);
    const auto origin  = Vector2D{outerGlobal.x + m_extents.topLeft.x, outerGlobal.y + m_extents.topLeft.y};
    const auto active  = Desktop::focusState()->isWindowActive(m_window.lock());
    const auto& state  = active ? theme.focused : theme.inactive;
    const auto opacity = std::clamp(state.opacity * alpha, 0.0, 1.0);

    const auto minimumX = -m_extents.topLeft.x;
    const auto minimumY = -m_extents.topLeft.y;
    const auto maximumX = windowSize.x + m_extents.bottomRight.x;
    const auto maximumY = windowSize.y + m_extents.bottomRight.y;

    for (const auto& operation : state.operations) {
        auto box = operationBox(operation, windowSize);
        const auto left   = std::max(box.x, minimumX);
        const auto top    = std::max(box.y, minimumY);
        const auto right  = std::min(box.x + box.width, maximumX);
        const auto bottom = std::min(box.y + box.height, maximumY);
        if (right <= left || bottom <= top)
            continue;

        box = {origin.x + left, origin.y + top, right - left, bottom - top};
        box.translate(-monitor->m_position + m_window->m_floatingOffset).scale(monitor->m_scale).round();
        const auto operationAlpha = std::clamp(operation.color.alpha * operation.opacity * opacity, 0.0, 1.0);
        addRectangle(box, {static_cast<float>(operation.color.red), static_cast<float>(operation.color.green),
                           static_cast<float>(operation.color.blue), static_cast<float>(operationAlpha)});
    }
}

CBox COmaRaisedEdgeDecoration::operationBox(const SOmaDrawOperation& operation, const Vector2D& windowSize) const {
    if (operation.type == eOmaPrimitiveType::RECT)
        return {operation.x.resolve(windowSize.x), operation.y.resolve(windowSize.y), operation.width.resolve(windowSize.x),
                operation.height.resolve(windowSize.y)};

    const auto horizontal = operation.side == eOmaSide::TOP || operation.side == eOmaSide::BOTTOM;
    const auto extent     = horizontal ? windowSize.x : windowSize.y;
    const auto start      = operation.start.resolve(extent);
    const auto end        = operation.end.resolve(extent);
    const auto length     = std::max(0.0, end - start);
    double     offset     = 0.0;
    if (operation.placement == eOmaPlacement::OUTSIDE)
        offset = operation.distance + operation.thickness;
    else if (operation.placement == eOmaPlacement::CENTER)
        offset = operation.distance + operation.thickness / 2.0;
    else
        offset = -operation.distance;

    switch (operation.side) {
        case eOmaSide::TOP: return {start, -offset, length, operation.thickness};
        case eOmaSide::RIGHT: return {windowSize.x + offset - operation.thickness, start, operation.thickness, length};
        case eOmaSide::BOTTOM: return {start, windowSize.y + offset - operation.thickness, length, operation.thickness};
        case eOmaSide::LEFT: return {-offset, start, operation.thickness, length};
    }
    return {};
}

SBoxExtents COmaRaisedEdgeDecoration::themeExtents(const SOmaCompiledTheme& theme, const Vector2D& windowSize) const {
    double left = 0.0, top = 0.0, right = 0.0, bottom = 0.0;
    const auto includeState = [&](const SOmaCompiledState& state) {
        for (const auto& operation : state.operations) {
            const auto box = operationBox(operation, windowSize);
            left           = std::max(left, -box.x);
            top            = std::max(top, -box.y);
            right          = std::max(right, box.x + box.width - windowSize.x);
            bottom         = std::max(bottom, box.y + box.height - windowSize.y);
        }
    };
    includeState(theme.focused);
    includeState(theme.inactive);
    constexpr double MAX_EXTENT = 128.0;
    return {
        Vector2D{std::clamp(left, 0.0, MAX_EXTENT), std::clamp(top, 0.0, MAX_EXTENT)},
        Vector2D{std::clamp(right, 0.0, MAX_EXTENT), std::clamp(bottom, 0.0, MAX_EXTENT)},
    };
}

eDecorationType COmaRaisedEdgeDecoration::getDecorationType() {
    return DECORATION_CUSTOM;
}

void COmaRaisedEdgeDecoration::updateWindow(PHLWINDOW) {
    damageEntire();
}

void COmaRaisedEdgeDecoration::damageEntire() {
    if (m_lastGlobalBox.width > 0 && m_lastGlobalBox.height > 0)
        g_pHyprRenderer->damageBox(m_lastGlobalBox.copy().expand(2));
}

eDecorationLayer COmaRaisedEdgeDecoration::getDecorationLayer() {
    return DECORATION_LAYER_OVER;
}

uint64_t COmaRaisedEdgeDecoration::getDecorationFlags() {
    return DECORATION_PART_OF_MAIN_WINDOW;
}

std::string COmaRaisedEdgeDecoration::getDisplayName() {
    return "OmaDecor Native Theme";
}

void COmaRaisedEdgeDecoration::refreshConfiguration() {
    damageEntire();
    g_pDecorationPositioner->repositionDeco(this);
}

bool COmaRaisedEdgeDecoration::shouldDraw() const {
    if (!g_config.enabled || !g_config.enabled->value() || !validMapped(m_window))
        return false;

    const auto window = m_window.lock();
    if (!window || !window->m_ruleApplicator->decorate().valueOrDefault() || classIsExcluded())
        return false;

    return !Fullscreen::controller()->isFullscreen(window);
}

bool COmaRaisedEdgeDecoration::classIsExcluded() const {
    if (!g_config.excludedClasses)
        return false;

    const auto window = m_window.lock();
    if (!window)
        return false;

    const auto currentClass = normalized(window->m_class);
    const auto initialClass = normalized(window->m_initialClass);
    const auto configured   = g_config.excludedClasses->value();

    size_t begin = 0;
    while (begin <= configured.size()) {
        const auto end   = configured.find(',', begin);
        const auto entry = normalized(configured.substr(begin, end == std::string::npos ? std::string::npos : end - begin));
        if (!entry.empty() && (entry == currentClass || entry == initialClass))
            return true;
        if (end == std::string::npos)
            break;
        begin = end + 1;
    }

    return false;
}

CBox COmaRaisedEdgeDecoration::assignedBoxGlobal() const {
    if (!m_window)
        return {};

    auto box = m_assignedGeometry;
    box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(ALL_EDGES, m_window));

    const auto workspaceOffset = m_window->m_workspace && !m_window->m_pinned ? m_window->m_workspace->m_renderOffset->value() : Vector2D{};
    return box.translate(workspaceOffset);
}

CHyprColor COmaRaisedEdgeDecoration::mainColor() const {
    const auto active = Desktop::focusState()->isWindowActive(m_window.lock());
    const auto value  = active ? g_config.activeColor->value() : g_config.inactiveColor->value();
    return CHyprColor{static_cast<uint64_t>(value)};
}

CHyprColor COmaRaisedEdgeDecoration::darkColor(const CHyprColor& color) const {
    const auto factor = std::clamp(g_config.shadeFactor->value(), 0.F, 1.F);
    return {static_cast<float>(color.r * factor), static_cast<float>(color.g * factor), static_cast<float>(color.b * factor), static_cast<float>(color.a)};
}

void COmaRaisedEdgeDecoration::addRectangle(const CBox& box, const CHyprColor& color) {
    if (box.width <= 0 || box.height <= 0 || color.a <= 0)
        return;

    CRectPassElement::SRectData data;
    data.box   = box;
    data.color = color;
    g_pHyprRenderer->addPassElement(makeUnique<CRectPassElement>(data));
}
