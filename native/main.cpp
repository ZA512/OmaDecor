#define WLR_USE_UNSTABLE

#include <ranges>
#include <stdexcept>
#include <string>
#include <string_view>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/render/Renderer.hpp>

#include "RaisedEdgeDecoration.hpp"
#include "globals.hpp"

namespace {
constexpr std::string_view DISPLAY_NAME = "OmaDecor Raised Edge";

COmaRaisedEdgeDecoration* decorationFor(PHLWINDOW window) {
    if (!window)
        return nullptr;

    for (const auto& decoration : window->m_windowDecorations) {
        if (decoration->getDisplayName() == DISPLAY_NAME)
            return dynamic_cast<COmaRaisedEdgeDecoration*>(decoration.get());
    }

    return nullptr;
}

void attachDecoration(PHLWINDOW window) {
    if (!window || !validMapped(window) || window->isHidden() || decorationFor(window))
        return;

    HyprlandAPI::addWindowDecoration(PHANDLE, window, makeUnique<COmaRaisedEdgeDecoration>(window));
}

void refreshWindow(PHLWINDOW window) {
    if (!window)
        return;

    if (auto* decoration = decorationFor(window))
        decoration->refreshConfiguration();
    else
        attachDecoration(window);
}

void refreshAllWindows() {
    for (const auto& window : Desktop::windowState()->windows())
        refreshWindow(window);
}

void damageAllDecorations() {
    for (const auto& window : Desktop::windowState()->windows()) {
        if (auto* decoration = decorationFor(window))
            decoration->damageEntire();
    }
}
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash()) {
        HyprlandAPI::addNotification(PHANDLE, "[OmaDecor] Native plugin/header version mismatch", CHyprColor{1.F, 0.2F, 0.2F, 1.F}, 5000);
        throw std::runtime_error("OmaDecor was built against different Hyprland headers");
    }

    g_config.enabled = makeShared<Config::Values::CBoolValue>("plugin:omadecor:enabled", "Enable the native Raised Edge decoration", true);
    g_config.lightWidth = makeShared<Config::Values::CIntValue>("plugin:omadecor:light_width", "Width of the top and right edges", 2,
                                                                Config::Values::SIntValueOptions{.min = 0, .max = 20});
    g_config.darkWidth = makeShared<Config::Values::CIntValue>("plugin:omadecor:dark_width", "Width of the bottom and left edges", 5,
                                                               Config::Values::SIntValueOptions{.min = 0, .max = 20});
    g_config.activeColor = makeShared<Config::Values::CColorValue>("plugin:omadecor:col.active", "Main color for active windows", 0xFF47D7FF);
    g_config.inactiveColor = makeShared<Config::Values::CColorValue>("plugin:omadecor:col.inactive", "Main color for inactive windows", 0xFF64748B);
    g_config.shadeFactor = makeShared<Config::Values::CFloatValue>("plugin:omadecor:shade_factor", "Multiplier used to derive the dark edge color", 0.45F,
                                                                   Config::Values::SFloatValueOptions{.min = 0.F, .max = 1.F});
    g_config.excludedClasses = makeShared<Config::Values::CStringValue>("plugin:omadecor:excluded_classes", "Comma-separated exact app classes to exclude", "");

    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.enabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.lightWidth);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.darkWidth);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.activeColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.inactiveColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.shadeFactor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_config.excludedClasses);

    HyprlandAPI::reloadConfig();

    static auto openListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW window) { attachDecoration(window); });
    static auto activeListener = Event::bus()->m_events.window.active.listen([](PHLWINDOW, Desktop::eFocusReason) { damageAllDecorations(); });
    static auto classListener = Event::bus()->m_events.window.class_.listen([](PHLWINDOW window) { refreshWindow(window); });
    static auto fullscreenListener = Event::bus()->m_events.window.fullscreen.listen([](PHLWINDOW window) { refreshWindow(window); });
    static auto floatingListener = Event::bus()->m_events.window.floating.listen([](PHLWINDOW window) { refreshWindow(window); });
    static auto configListener = Event::bus()->m_events.config.reloaded.listen([] { refreshAllWindows(); });

    refreshAllWindows();
    HyprlandAPI::addNotification(PHANDLE, "[OmaDecor] Native Raised Edge loaded", CHyprColor{0.2F, 1.F, 0.4F, 1.F}, 3000);

    return {"omadecor-native", "Compositor-native Raised Edge window decoration", "OmaDecor contributors", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {}
