import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property int currentSchemaVersion: 1
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string configDir: root.configHome + "/omadecor"
    readonly property string configPath: root.configDir + "/config.json"

    property bool loaded: false
    property bool hasValidConfig: false
    property bool healthy: true
    property string lastError: ""
    property int revision: 0

    property bool decorationsEnabled: true
    property string decorationStyle: "raised-edge"
    property string decorationThemeId: "omadecor/raised-edge"
    property string decorationThemeFile: ""
    property int lightWidth: 2
    property int darkWidth: 5
    property real shadeFactor: 0.45
    property bool useThemeAccent: true
    property string activeColor: "#47d7ff"
    property string inactiveColor: "#64748b"
    property real inactiveOpacity: 0.55
    property int stockBorderSize: 5
    property var excludedClasses: []

    property bool hudEnabled: false
    property string hudScope: "active-window"
    property bool effectsEnabled: false
    property var effectsEvents: ({
        open: "simple-fade-open",
        close: "simple-fade-close",
        move: "none",
        resize: "none",
        workspace: "none",
        fullscreenEnter: "none",
        fullscreenExit: "none",
        float: "none",
        tile: "none",
        focus: "none",
        unfocus: "none",
        urgent: "none"
    })
    property string effectsOverrideFingerprint: ""
    property var applications: []
    property var hudClassExclusions: []
    property var effectsClassExclusions: []

    property string pendingWrite: ""
    property bool writeQueued: false

    signal configurationLoaded()
    signal configurationChanged()

    function defaults() {
        return {
            schemaVersion: root.currentSchemaVersion,
            decorations: {
                enabled: true,
                style: "raised-edge",
                theme: "omadecor/raised-edge",
                themeFile: "",
                settings: {
                    lightWidth: 2,
                    darkWidth: 5,
                    shadeFactor: 0.45,
                    useThemeAccent: true,
                    activeColor: "#47d7ff",
                    inactiveColor: "#64748b",
                    inactiveOpacity: 0.55,
                    stockBorderSize: 5,
                    excludedClasses: []
                }
            },
            hud: {
                enabled: false,
                scope: "active-window"
            },
            effects: {
                enabled: false,
                events: {
                    open: "simple-fade-open",
                    close: "simple-fade-close",
                    move: "none",
                    resize: "none",
                    workspace: "none",
                    fullscreenEnter: "none",
                    fullscreenExit: "none",
                    float: "none",
                    tile: "none",
                    focus: "none",
                    unfocus: "none",
                    urgent: "none"
                },
                overrideFingerprint: ""
            },
            applications: []
        }
    }

    function objectValue(value, fallback) {
        return value && typeof value === "object" && !Array.isArray(value) ? value : fallback
    }

    function clampedInteger(value, fallback, minimum, maximum) {
        var parsed = Math.round(Number(value))
        if (!isFinite(parsed)) return fallback
        return Math.max(minimum, Math.min(maximum, parsed))
    }

    function clampedNumber(value, fallback, minimum, maximum) {
        var parsed = Number(value)
        if (!isFinite(parsed)) return fallback
        return Math.max(minimum, Math.min(maximum, parsed))
    }

    function normalizedColor(value, fallback) {
        var text = String(value || "")
        return /^#[0-9a-fA-F]{6}$/.test(text) ? text.toLowerCase() : fallback
    }

    function normalizedThemeFile(value) {
        var text = String(value || "").trim()
        if (text === "") return ""
        return /^[A-Za-z0-9][A-Za-z0-9._-]{0,111}\.omadecor\.json$/.test(text) ? text : ""
    }

    function normalizedThemeId(value) {
        var text = String(value || "")
        return /^[a-z0-9][a-z0-9._-]{0,63}\/[a-z0-9][a-z0-9._-]{0,63}$/.test(text)
            ? text : "omadecor/raised-edge"
    }

    function normalizedClasses(value) {
        if (!Array.isArray(value)) return []
        var result = []
        for (var index = 0; index < value.length; index++) {
            var entry = String(value[index] || "").trim()
            if (entry === "" || entry.length > 128 || /[,\n\r\0]/.test(entry)) continue
            if (result.indexOf(entry) === -1) result.push(entry)
        }
        return result
    }

    function normalizedText(value, maximum) {
        var text = String(value || "").replace(/[\n\r\0]/g, " ").trim()
        return text.slice(0, maximum)
    }

    function normalizedEffectId(value, fallback) {
        var effectId = String(value || "")
        var allowed = ["none", "simple-fade-open", "simple-fade-close", "soft-focus-pulse", "simple-wobble"]
        return allowed.indexOf(effectId) !== -1 ? effectId : fallback
    }

    function effectCompatible(eventName, effectId) {
        if (effectId === "none") return true
        if (effectId === "simple-fade-open") return eventName === "open"
        if (effectId === "simple-fade-close") return eventName === "close"
        if (effectId === "soft-focus-pulse")
            return ["focus", "unfocus", "urgent"].indexOf(eventName) !== -1
        if (effectId === "simple-wobble")
            return ["move", "resize", "workspace", "fullscreenEnter", "fullscreenExit", "float", "tile"].indexOf(eventName) !== -1
        return false
    }

    function normalizedEffectEvents(value) {
        var incoming = root.objectValue(value, {})
        var defaults = root.defaults().effects.events
        var result = ({})
        var names = ["open", "close", "move", "resize", "workspace", "fullscreenEnter",
            "fullscreenExit", "float", "tile", "focus", "unfocus", "urgent"]
        for (var index = 0; index < names.length; index++) {
            var name = names[index]
            var effectId = root.normalizedEffectId(incoming[name], defaults[name])
            result[name] = root.effectCompatible(name, effectId) ? effectId : defaults[name]
        }
        return result
    }

    function normalizedEffectOverrides(value) {
        var incoming = root.objectValue(value, {})
        var result = ({})
        var names = ["open", "close", "move", "resize", "workspace", "fullscreenEnter",
            "fullscreenExit", "float", "tile", "focus", "unfocus", "urgent"]
        for (var index = 0; index < names.length; index++) {
            var name = names[index]
            if (incoming[name] === undefined || incoming[name] === "global") continue
            var effectId = root.normalizedEffectId(incoming[name], "none")
            result[name] = root.effectCompatible(name, effectId) ? effectId : "none"
        }
        return result
    }

    function normalizedApplication(value) {
        if (!value || typeof value !== "object" || Array.isArray(value)) return null
        var appClass = root.normalizedText(value.appClass || value["class"], 128)
        if (!/^[A-Za-z0-9._:+-]{1,128}$/.test(appClass)) return null
        return {
            appClass: appClass,
            name: root.normalizedText(value.name || appClass, 128),
            title: root.normalizedText(value.title, 256),
            disableDecorations: value.disableDecorations === true,
            disableHud: value.disableHud === true,
            disableEffects: value.disableEffects === true,
            effectOverrides: root.normalizedEffectOverrides(value.effectOverrides)
        }
    }

    function normalizedApplications(value) {
        if (!Array.isArray(value)) return []
        var result = []
        var seen = []
        for (var index = 0; index < value.length; index++) {
            var entry = root.normalizedApplication(value[index])
            if (!entry) continue
            var key = entry.appClass.toLowerCase()
            if (seen.indexOf(key) !== -1) continue
            seen.push(key)
            result.push(entry)
        }
        return result
    }

    function refreshApplicationExclusions() {
        var hud = []
        var effects = []
        for (var index = 0; index < root.applications.length; index++) {
            var entry = root.applications[index]
            if (entry.disableHud === true) hud.push(entry.appClass)
            if (entry.disableEffects === true) effects.push(entry.appClass)
        }
        root.hudClassExclusions = hud
        root.effectsClassExclusions = effects
    }

    function normalized(data) {
        var fallback = root.defaults()
        var decorations = root.objectValue(data.decorations, fallback.decorations)
        var settings = root.objectValue(decorations.settings, fallback.decorations.settings)
        var hud = root.objectValue(data.hud, fallback.hud)
        var effects = root.objectValue(data.effects, fallback.effects)

        return {
            schemaVersion: root.currentSchemaVersion,
            decorations: {
                enabled: decorations.enabled !== false,
                style: decorations.style === "raised-edge" ? "raised-edge" : "raised-edge",
                theme: root.normalizedThemeId(decorations.theme),
                themeFile: root.normalizedThemeFile(decorations.themeFile),
                settings: {
                    lightWidth: root.clampedInteger(settings.lightWidth, 2, 0, 20),
                    darkWidth: root.clampedInteger(settings.darkWidth, 5, 0, 20),
                    shadeFactor: root.clampedNumber(settings.shadeFactor, 0.45, 0, 1),
                    useThemeAccent: settings.useThemeAccent !== false,
                    activeColor: root.normalizedColor(settings.activeColor, "#47d7ff"),
                    inactiveColor: root.normalizedColor(settings.inactiveColor, "#64748b"),
                    inactiveOpacity: root.clampedNumber(settings.inactiveOpacity, 0.55, 0, 1),
                    stockBorderSize: root.clampedInteger(settings.stockBorderSize, 5, 0, 20),
                    excludedClasses: root.normalizedClasses(settings.excludedClasses)
                }
            },
            hud: {
                enabled: hud.enabled === true,
                scope: "active-window"
            },
            effects: {
                enabled: effects.enabled === true,
                events: root.normalizedEffectEvents(effects.events),
                overrideFingerprint: root.normalizedText(effects.overrideFingerprint, 512)
            },
            applications: root.normalizedApplications(data.applications)
        }
    }

    function applyData(data) {
        var clean = root.normalized(data)
        root.decorationsEnabled = clean.decorations.enabled
        root.decorationStyle = clean.decorations.style
        root.decorationThemeId = clean.decorations.theme
        root.decorationThemeFile = clean.decorations.themeFile
        root.lightWidth = clean.decorations.settings.lightWidth
        root.darkWidth = clean.decorations.settings.darkWidth
        root.shadeFactor = clean.decorations.settings.shadeFactor
        root.useThemeAccent = clean.decorations.settings.useThemeAccent
        root.activeColor = clean.decorations.settings.activeColor
        root.inactiveColor = clean.decorations.settings.inactiveColor
        root.inactiveOpacity = clean.decorations.settings.inactiveOpacity
        root.stockBorderSize = clean.decorations.settings.stockBorderSize
        root.excludedClasses = clean.decorations.settings.excludedClasses
        root.hudEnabled = clean.hud.enabled
        root.hudScope = clean.hud.scope
        root.effectsEnabled = clean.effects.enabled
        root.effectsEvents = clean.effects.events
        root.effectsOverrideFingerprint = clean.effects.overrideFingerprint
        root.applications = clean.applications
        root.refreshApplicationExclusions()
        root.revision += 1
    }

    function snapshot() {
        return root.normalized({
            schemaVersion: root.currentSchemaVersion,
            decorations: {
                enabled: root.decorationsEnabled,
                style: root.decorationStyle,
                theme: root.decorationThemeId,
                themeFile: root.decorationThemeFile,
                settings: {
                    lightWidth: root.lightWidth,
                    darkWidth: root.darkWidth,
                    shadeFactor: root.shadeFactor,
                    useThemeAccent: root.useThemeAccent,
                    activeColor: root.activeColor,
                    inactiveColor: root.inactiveColor,
                    inactiveOpacity: root.inactiveOpacity,
                    stockBorderSize: root.stockBorderSize,
                    excludedClasses: root.excludedClasses
                }
            },
            hud: {
                enabled: root.hudEnabled,
                scope: root.hudScope
            },
            effects: {
                enabled: root.effectsEnabled,
                events: root.effectsEvents,
                overrideFingerprint: root.effectsOverrideFingerprint
            },
            applications: root.applications
        })
    }

    function loadText(rawText, missing) {
        var parsed
        if (missing) {
            root.applyData(root.defaults())
            root.hasValidConfig = true
            root.healthy = true
            root.lastError = ""
            root.loaded = true
            root.configurationLoaded()
            root.scheduleSave()
            return
        }

        try {
            parsed = JSON.parse(String(rawText || ""))
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
                throw new Error("root must be an object")
            if (Number(parsed.schemaVersion) !== root.currentSchemaVersion)
                throw new Error("unsupported schemaVersion")
        } catch (error) {
            if (!root.hasValidConfig) root.applyData(root.defaults())
            root.healthy = false
            root.lastError = "Invalid config.json: " + String(error)
            root.loaded = true
            root.configurationLoaded()
            return
        }

        root.applyData(parsed)
        root.hasValidConfig = true
        root.healthy = true
        root.lastError = ""
        root.loaded = true
        root.configurationLoaded()
    }

    function scheduleSave() {
        if (!root.loaded) return
        saveTimer.restart()
    }

    function persist() {
        root.pendingWrite = JSON.stringify(root.snapshot(), null, 2) + "\n"
        if (symlinkCheck.running || mkdirProcess.running) {
            root.writeQueued = true
            return
        }
        root.writeQueued = false
        symlinkCheck.running = true
    }

    function finishWriteCycle() {
        if (!root.writeQueued) return
        root.writeQueued = false
        root.persist()
    }

    function setModuleEnabled(moduleName, enabled) {
        var next = enabled === true
        if (moduleName === "decorations") root.decorationsEnabled = next
        else if (moduleName === "hud") root.hudEnabled = next
        else if (moduleName === "effects") root.effectsEnabled = next
        else return false
        root.revision += 1
        root.configurationChanged()
        root.scheduleSave()
        return true
    }

    function setDecorationSettings(values) {
        var incoming = values || {}
        var cleanDecoration = root.normalized({
            decorations: {
                enabled: root.decorationsEnabled,
                style: root.decorationStyle,
                theme: root.decorationThemeId,
                themeFile: incoming.themeFile !== undefined ? incoming.themeFile : root.decorationThemeFile,
                settings: {
                    lightWidth: incoming.lightWidth !== undefined ? incoming.lightWidth : root.lightWidth,
                    darkWidth: incoming.darkWidth !== undefined ? incoming.darkWidth : root.darkWidth,
                    shadeFactor: incoming.shadeFactor !== undefined ? incoming.shadeFactor : root.shadeFactor,
                    useThemeAccent: incoming.useThemeAccent !== undefined ? incoming.useThemeAccent : root.useThemeAccent,
                    activeColor: incoming.activeColor !== undefined ? incoming.activeColor : root.activeColor,
                    inactiveColor: incoming.inactiveColor !== undefined ? incoming.inactiveColor : root.inactiveColor,
                    inactiveOpacity: incoming.inactiveOpacity !== undefined ? incoming.inactiveOpacity : root.inactiveOpacity,
                    stockBorderSize: incoming.stockBorderSize !== undefined ? incoming.stockBorderSize : root.stockBorderSize,
                    excludedClasses: incoming.excludedClasses !== undefined ? incoming.excludedClasses : root.excludedClasses
                }
            },
            hud: { enabled: root.hudEnabled },
            effects: { enabled: root.effectsEnabled },
            applications: root.applications
        }).decorations
        var clean = cleanDecoration.settings
        root.decorationThemeId = cleanDecoration.theme
        root.decorationThemeFile = cleanDecoration.themeFile
        root.lightWidth = clean.lightWidth
        root.darkWidth = clean.darkWidth
        root.shadeFactor = clean.shadeFactor
        root.useThemeAccent = clean.useThemeAccent
        root.activeColor = clean.activeColor
        root.inactiveColor = clean.inactiveColor
        root.inactiveOpacity = clean.inactiveOpacity
        root.stockBorderSize = clean.stockBorderSize
        root.excludedClasses = clean.excludedClasses
        root.revision += 1
        root.configurationChanged()
        root.scheduleSave()
    }

    function setEffectEvent(eventName, effectId) {
        var name = String(eventName || "")
        var allowedEvents = ["open", "close", "move", "resize", "workspace", "fullscreenEnter",
            "fullscreenExit", "float", "tile", "focus", "unfocus", "urgent"]
        if (allowedEvents.indexOf(name) === -1) return false
        var cleanId = root.normalizedEffectId(effectId, "none")
        if (!root.effectCompatible(name, cleanId)) return false
        var next = ({})
        for (var key in root.effectsEvents) next[key] = root.effectsEvents[key]
        next[name] = cleanId
        root.effectsEvents = next
        root.revision += 1
        root.configurationChanged()
        root.scheduleSave()
        return true
    }

    function setEffectsOverrideFingerprint(value) {
        root.effectsOverrideFingerprint = root.normalizedText(value, 512)
        root.revision += 1
        root.configurationChanged()
        root.scheduleSave()
        return true
    }

    function addApplication(value) {
        var entry = root.normalizedApplication(value)
        if (!entry) return false
        var next = root.applications.slice()
        var key = entry.appClass.toLowerCase()
        for (var index = 0; index < next.length; index++) {
            if (String(next[index].appClass).toLowerCase() !== key) continue
            if (!value || value.effectOverrides === undefined)
                entry.effectOverrides = next[index].effectOverrides || ({})
            next[index] = entry
            root.applications = next
            root.refreshApplicationExclusions()
            root.revision += 1
            root.configurationChanged()
            root.scheduleSave()
            return true
        }
        next.push(entry)
        root.applications = next
        root.refreshApplicationExclusions()
        root.revision += 1
        root.configurationChanged()
        root.scheduleSave()
        return true
    }

    function removeApplication(appClass) {
        var key = String(appClass || "").trim().toLowerCase()
        if (key === "") return false
        var next = []
        var removed = false
        for (var index = 0; index < root.applications.length; index++) {
            var entry = root.applications[index]
            if (String(entry.appClass).toLowerCase() === key) removed = true
            else next.push(entry)
        }
        if (!removed) return false
        root.applications = next
        root.refreshApplicationExclusions()
        root.revision += 1
        root.configurationChanged()
        root.scheduleSave()
        return true
    }

    function setApplicationExclusions(appClass, values) {
        var key = String(appClass || "").trim().toLowerCase()
        var incoming = values || {}
        var next = root.applications.slice()
        for (var index = 0; index < next.length; index++) {
            var current = next[index]
            if (String(current.appClass).toLowerCase() !== key) continue
            next[index] = root.normalizedApplication({
                appClass: current.appClass,
                name: current.name,
                title: current.title,
                disableDecorations: incoming.disableDecorations !== undefined
                    ? incoming.disableDecorations === true : current.disableDecorations,
                disableHud: incoming.disableHud !== undefined
                    ? incoming.disableHud === true : current.disableHud,
                disableEffects: incoming.disableEffects !== undefined
                    ? incoming.disableEffects === true : current.disableEffects,
                effectOverrides: current.effectOverrides
            })
            root.applications = next
            root.refreshApplicationExclusions()
            root.revision += 1
            root.configurationChanged()
            root.scheduleSave()
            return true
        }
        return false
    }

    function setApplicationEffectOverride(appClass, eventName, effectId) {
        var classKey = String(appClass || "").trim().toLowerCase()
        var eventKey = String(eventName || "")
        var allowedEvents = ["open", "close", "move", "resize", "workspace", "fullscreenEnter",
            "fullscreenExit", "float", "tile", "focus", "unfocus", "urgent"]
        if (classKey === "" || allowedEvents.indexOf(eventKey) === -1) return false

        var requested = String(effectId || "global")
        var cleanId = requested === "global" ? "global" : root.normalizedEffectId(requested, "none")
        if (cleanId !== "global" && !root.effectCompatible(eventKey, cleanId)) return false
        var next = root.applications.slice()
        for (var index = 0; index < next.length; index++) {
            var current = next[index]
            if (String(current.appClass).toLowerCase() !== classKey) continue
            var overrides = ({})
            var currentOverrides = root.objectValue(current.effectOverrides, {})
            for (var key in currentOverrides) overrides[key] = currentOverrides[key]
            if (cleanId === "global") delete overrides[eventKey]
            else overrides[eventKey] = cleanId
            next[index] = root.normalizedApplication({
                appClass: current.appClass,
                name: current.name,
                title: current.title,
                disableDecorations: current.disableDecorations,
                disableHud: current.disableHud,
                disableEffects: current.disableEffects,
                effectOverrides: overrides
            })
            root.applications = next
            root.refreshApplicationExclusions()
            root.revision += 1
            root.configurationChanged()
            root.scheduleSave()
            return true
        }
        return false
    }

    function decorationExcludedClasses() {
        var combined = root.excludedClasses.slice()
        var seen = []
        for (var directIndex = 0; directIndex < combined.length; directIndex++)
            seen.push(String(combined[directIndex]).toLowerCase())
        for (var index = 0; index < root.applications.length; index++) {
            var entry = root.applications[index]
            if (entry.disableDecorations !== true) continue
            var key = String(entry.appClass).toLowerCase()
            if (seen.indexOf(key) !== -1) continue
            seen.push(key)
            combined.push(entry.appClass)
        }
        return combined
    }

    function moduleExcludedClasses(flagName) {
        var result = []
        for (var index = 0; index < root.applications.length; index++) {
            var entry = root.applications[index]
            if (entry[flagName] === true) result.push(entry.appClass)
        }
        return result
    }

    function hudExcludedClasses() {
        return root.hudClassExclusions
    }

    function effectsExcludedClasses() {
        return root.effectsClassExclusions
    }

    function resetToDefaults() {
        root.applyData(root.defaults())
        root.hasValidConfig = true
        root.healthy = true
        root.lastError = ""
        root.configurationChanged()
        root.scheduleSave()
    }

    function reload() {
        configFile.reload()
    }

    function diagnostics() {
        return {
            loaded: root.loaded,
            hasValidConfig: root.hasValidConfig,
            healthy: root.healthy,
            error: root.lastError,
            schemaVersion: root.currentSchemaVersion,
            revision: root.revision,
            path: root.configPath,
            applicationCount: root.applications.length
        }
    }

    Timer {
        id: saveTimer
        interval: 120
        repeat: false
        onTriggered: root.persist()
    }

    Process {
        id: symlinkCheck
        command: ["/usr/bin/test", "-L", root.configPath]
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0) {
                root.healthy = false
                root.lastError = "Refusing to write symlinked config.json"
                root.pendingWrite = ""
                root.finishWriteCycle()
                return
            }
            if (exitCode !== 1) {
                root.healthy = false
                root.lastError = "Unable to validate config.json target"
                root.pendingWrite = ""
                root.finishWriteCycle()
                return
            }
            mkdirProcess.running = true
        }
    }

    Process {
        id: mkdirProcess
        command: ["/usr/bin/mkdir", "-p", root.configDir]
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.healthy = false
                root.lastError = "Unable to create OmaDecor config directory"
                root.pendingWrite = ""
                root.finishWriteCycle()
                return
            }
            configFile.setText(root.pendingWrite)
            root.pendingWrite = ""
            root.finishWriteCycle()
        }
    }

    FileView {
        id: configFile
        path: root.configPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadText(text(), false)
        onLoadFailed: root.loadText("", true)
        onFileChanged: reload()
        onSaved: reload()
        onSaveFailed: function() {
            root.healthy = false
            root.lastError = "Unable to save config.json"
        }
    }
}
