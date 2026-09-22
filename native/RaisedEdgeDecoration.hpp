#pragma once

#define WLR_USE_UNSTABLE

#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>

#include "ThemeEngine.hpp"

class COmaRaisedEdgeDecoration final : public IHyprWindowDecoration {
  public:
    explicit COmaRaisedEdgeDecoration(PHLWINDOW window);
    ~COmaRaisedEdgeDecoration() override;

    SDecorationPositioningInfo getPositioningInfo() override;
    void                       onPositioningReply(const SDecorationPositioningReply& reply) override;
    void                       draw(PHLMONITOR monitor, const float& alpha) override;
    eDecorationType            getDecorationType() override;
    void                       updateWindow(PHLWINDOW window) override;
    void                       damageEntire() override;
    eDecorationLayer           getDecorationLayer() override;
    uint64_t                   getDecorationFlags() override;
    std::string                getDisplayName() override;

    void                       refreshConfiguration();

  private:
    bool      shouldDraw() const;
    bool      classIsExcluded() const;
    CBox      assignedBoxGlobal() const;
    CHyprColor mainColor() const;
    CHyprColor darkColor(const CHyprColor& color) const;
    void      addRectangle(const CBox& box, const CHyprColor& color);
    void      drawLegacy(PHLMONITOR monitor, const float& alpha);
    void      drawTheme(PHLMONITOR monitor, const float& alpha, const SOmaCompiledTheme& theme);
    CBox      operationBox(const SOmaDrawOperation& operation, const Vector2D& windowSize) const;
    SBoxExtents themeExtents(const SOmaCompiledTheme& theme, const Vector2D& windowSize) const;

    PHLWINDOWREF m_window;
    CBox         m_assignedGeometry = {};
    CBox         m_lastGlobalBox    = {};
    SBoxExtents  m_extents          = {};
};
