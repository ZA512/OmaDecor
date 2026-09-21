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
    const auto visible    = shouldDraw();
    const auto lightWidth = visible ? std::max<Config::INTEGER>(0, g_config.lightWidth->value()) : 0;
    const auto darkWidth  = visible ? std::max<Config::INTEGER>(0, g_config.darkWidth->value()) : 0;

    m_extents = {
        Vector2D{static_cast<double>(darkWidth), static_cast<double>(lightWidth)},
        Vector2D{static_cast<double>(lightWidth), static_cast<double>(darkWidth)},
    };

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
    return "OmaDecor Raised Edge";
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
