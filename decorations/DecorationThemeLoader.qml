import QtQuick
import Qt.labs.folderlistmodel
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
    property var parameterDefinitions: []
    property var availableThemes: []

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
        var result = ({})
        if (root.config.decorationThemeFile === "") {
            result = {
                mainColor: root.config.useThemeAccent ? root.themeAccent : root.config.activeColor,
                lightWidth: root.config.lightWidth,
                darkWidth: root.config.darkWidth,
                darkening: -0.4 * (1 - root.config.shadeFactor),
                inactiveOpacity: root.config.inactiveOpacity
            }
        }
        var custom = root.config.decorationParameters || {}
        for (var name in custom) result[name] = custom[name]
        return result
    }

    function rebuildCatalog() {
        var result = [{
            fileName: "",
            label: "Raised Edge (built-in)",
            source: "built-in"
        }]
        for (var index = 0; index < userThemeFiles.count; index++) {
            var fileName = String(userThemeFiles.get(index, "fileName") || "")
            if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,111}\.omadecor\.json$/.test(fileName)) continue
            result.push({
                fileName: fileName,
                label: fileName.slice(0, -".omadecor.json".length),
                source: "user"
            })
        }
        root.availableThemes = result
    }

    function buildParameterDefinitions(theme, compilation) {
        var definitions = []
        var parameters = theme && theme.parameters ? theme.parameters : {}
        var values = compilation && compilation.parameters ? compilation.parameters : {}
        var names = Object.keys(parameters).sort()
        for (var index = 0; index < names.length; index++) {
            var name = names[index]
            var definition = parameters[name]
            definitions.push({
                id: name,
                type: String(definition.type),
                label: String(definition.label || name),
                unit: String(definition.unit || ""),
                minimum: definition.min,
                maximum: definition.max,
                step: definition.step,
                options: Array.isArray(definition.options) ? definition.options : [],
                value: values[name]
            })
        }
        return definitions
    }

    function validateText(rawText) {
        root.valid = false
        root.compiled = null
        root.metadata = ({})
        root.parameterDefinitions = []
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
            root.parameterDefinitions = root.buildParameterDefinitions(theme, result.compiled)
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
            availableThemes: root.availableThemes.length,
            parameters: root.parameterDefinitions,
            metadata: root.metadata,
            error: root.lastError
        }
    }

    onSelectedPathChanged: {
        root.state = "loading"
        root.valid = false
        root.lastError = ""
        Qt.callLater(themeFile.reload)
    }

    onThemeAccentChanged: Qt.callLater(themeFile.reload)

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
            root.parameterDefinitions = []
            root.state = "error"
            root.lastError = "Theme file could not be loaded (" + String(error) + ")"
            root.validated(false)
        }
    }

    FolderListModel {
        id: userThemeFiles
        folder: root.userThemeDir === "" ? "file:///nonexistent/omadecor-themes"
            : "file://" + root.userThemeDir
        nameFilters: ["*.omadecor.json"]
        showFiles: true
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        onCountChanged: root.rebuildCatalog()
        onStatusChanged: root.rebuildCatalog()
    }

    Connections {
        target: root.config

        function onRevisionChanged() {
            themeFile.reload()
        }
    }

    Component.onCompleted: root.rebuildCatalog()
}
