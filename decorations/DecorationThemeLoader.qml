import QtQuick
import Quickshell
import Quickshell.Io
import "ThemeCompiler.js" as ThemeCompiler

Scope {
    id: root

    property var config: null
    property string themeAccent: "#47d7ff"
    property bool valid: false
    property string state: "loading"
    property string lastError: ""
    property var metadata: ({})
    property var compiled: null

    readonly property string builtinPath: root.localFilePath(
        Qt.resolvedUrl("styles/raised-edge.omadecor.json")
    )
    readonly property string userThemeDir: root.config
        ? root.config.configDir + "/themes" : ""
    readonly property string selectedPath: root.config && root.config.decorationThemeFile !== ""
        ? root.userThemeDir + "/" + root.config.decorationThemeFile
        : root.builtinPath

    signal validated(bool success)

    function localFilePath(value) {
        var text = String(value || "")
        if (text.indexOf("file://") === 0) text = text.slice(7)
        try {
            return decodeURIComponent(text)
        } catch (error) {
            return text
        }
    }

    function parameters() {
        if (!root.config) return ({})
        return {
            mainColor: root.config.useThemeAccent ? root.themeAccent : root.config.activeColor,
            lightWidth: root.config.lightWidth,
            darkWidth: root.config.darkWidth,
            darkening: -0.4 * (1 - root.config.shadeFactor),
            inactiveOpacity: root.config.inactiveOpacity
        }
    }

    function validateText(rawText) {
        root.valid = false
        root.compiled = null
        root.metadata = ({})
        if (String(rawText || "").length > 262144) {
            root.state = "error"
            root.lastError = "Theme exceeds the 256 KiB limit"
            root.validated(false)
            return
        }
        try {
            var theme = JSON.parse(String(rawText || ""))
            var validation = ThemeCompiler.validateTheme(theme)
            if (!validation.ok)
                throw new Error(validation.errors.length > 0
                    ? validation.errors[0].path + ": " + validation.errors[0].message
                    : "Theme validation failed")
            var result = ThemeCompiler.compileTheme(theme, root.parameters(), {
                accent: root.themeAccent,
                background: "#111111",
                foreground: "#eeeeee",
                border: root.config ? root.config.inactiveColor : "#64748b"
            }, { focused: true })
            if (!result.ok)
                throw new Error(result.errors.length > 0
                    ? result.errors[0].path + ": " + result.errors[0].message
                    : "Theme compilation failed")
            root.metadata = {
                id: String(theme.id),
                name: String(theme.name),
                version: String(theme.version),
                drawOperations: validation.drawOperations
            }
            root.compiled = result.compiled
            root.lastError = ""
            root.state = "ready"
            root.valid = true
            root.validated(true)
        } catch (error) {
            root.state = "error"
            root.lastError = String(error)
            root.validated(false)
        }
    }

    function diagnostics() {
        return {
            state: root.state,
            valid: root.valid,
            path: root.selectedPath,
            userTheme: root.config ? root.config.decorationThemeFile : "",
            metadata: root.metadata,
            error: root.lastError
        }
    }

    onSelectedPathChanged: {
        root.state = "loading"
        root.valid = false
        root.lastError = ""
    }

    FileView {
        id: themeFile
        path: root.selectedPath
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: root.validateText(text())
        onFileChanged: reload()
        onLoadFailed: function(error) {
            root.valid = false
            root.compiled = null
            root.metadata = ({})
            root.state = "error"
            root.lastError = "Theme file could not be loaded (" + String(error) + ")"
            root.validated(false)
        }
    }
}
