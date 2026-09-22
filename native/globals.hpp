#pragma once

#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

#include "ThemeEngine.hpp"

inline HANDLE PHANDLE = nullptr;

struct SOmaDecorConfig {
    SP<Config::Values::CBoolValue>   enabled;
    SP<Config::Values::CIntValue>    lightWidth;
    SP<Config::Values::CIntValue>    darkWidth;
    SP<Config::Values::CColorValue>  activeColor;
    SP<Config::Values::CColorValue>  inactiveColor;
    SP<Config::Values::CFloatValue>  shadeFactor;
    SP<Config::Values::CFloatValue>  inactiveOpacity;
    SP<Config::Values::CStringValue> excludedClasses;
    SP<Config::Values::CStringValue> themePath;
};

inline SOmaDecorConfig g_config = {};
inline std::shared_ptr<const SOmaCompiledTheme> g_theme;
inline std::string                              g_themeError;
