import QtQuick
import Quickshell
import Quickshell.Io
import "EffectValidator.js" as EffectValidator
import "EffectMetadata.js" as EffectMetadata
import "EffectPack.js" as EffectPack

Scope {
    id: root

    property var config: null
    property var effects: []
    property var packs: []
    property var invalidPacks: []
    property string state: "idle"
    property string lastError: ""
    property string scanOutput: ""
    property string scanError: ""
    property bool refreshPending: false

    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME")
        || (Quickshell.env("HOME") + "/.local/share")
    readonly property string builtinRoot: root.localFilePath(Qt.resolvedUrl("packs"))
    readonly property string userRoot: root.dataHome + "/omadecor/effects"
    readonly property string scannerPath: root.localFilePath(
        Qt.resolvedUrl("../scripts/scan-effect-packs.sh")
    )
    readonly property string settingsJson: JSON.stringify({
        parameters: root.config ? root.config.effectsPackParameters : ({}),
        timings: root.config ? root.config.effectsTimings : ({})
    })
    readonly property int validPackCount: root.packs.length
    readonly property int invalidPackCount: root.invalidPacks.length

    signal refreshed()

    function localFilePath(value) {
        var text = String(value || "")
        if (text.indexOf("file://") === 0) text = text.slice(7)
        try {
            return decodeURIComponent(text)
        } catch (error) {
            return text
        }
    }

    function invalidRecord(path, message, errors) {
        return {
            path: String(path || ""),
            error: String(message || "Invalid effect pack"),
            errors: Array.isArray(errors) ? errors : []
        }
    }

    function parseScanOutput(rawText) {
        var nextEffects = []
        var nextPacks = []
        var nextInvalid = []
        var seenPacks = ({})
        var seenEntries = ({})
        var lines = String(rawText || "").split("\n")
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
            var line = lines[lineIndex].trim()
            if (line === "") continue
            var record
            try {
                record = JSON.parse(line)
            } catch (error) {
                nextInvalid.push(root.invalidRecord("", "Scanner returned malformed JSON", []))
                continue
            }
            if (record.ok !== true) {
                nextInvalid.push(root.invalidRecord(record.path, record.error, []))
                continue
            }
            var validation = EffectValidator.validateEffect(record.manifest)
            if (validation.ok && record.manifest.compatibility.sourceFormat !== "native") {
                for (var eventIndex = 0;
                        eventIndex < record.manifest.compatibility.events.length;
                        eventIndex++) {
                    var adaptedEvent = record.manifest.compatibility.events[eventIndex]
                    if (!record.artifacts || typeof record.artifacts[adaptedEvent] !== "string"
                            || record.artifacts[adaptedEvent] === "") {
                        validation = {
                            ok: false,
                            errors: [{ path: "artifacts." + adaptedEvent,
                                message: "validated source-adapter artifact is missing" }]
                        }
                        break
                    }
                }
            }
            var entries = validation.ok
                ? EffectMetadata.entries(record.manifest, String(record.root || ""),
                    record.artifacts || {}) : []
            var pack = EffectPack.create(record, validation, entries)
            if (!validation.ok) {
                nextInvalid.push(root.invalidRecord(
                    String(record.root || "") + "/effect.json",
                    validation.errors.length > 0
                        ? validation.errors[0].path + ": " + validation.errors[0].message
                        : "Metadata validation failed",
                    validation.errors
                ))
                continue
            }
            if (seenPacks[pack.id]) {
                nextInvalid.push(root.invalidRecord(pack.root, "Duplicate pack id: " + pack.id, []))
                continue
            }
            var duplicateEntry = false
            var localEntries = ({})
            for (var entryIndex = 0; entryIndex < pack.effects.length; entryIndex++) {
                var entry = pack.effects[entryIndex]
                if (seenEntries[entry.id] || localEntries[entry.id]) {
                    duplicateEntry = true
                    break
                }
                localEntries[entry.id] = true
            }
            if (duplicateEntry) {
                nextInvalid.push(root.invalidRecord(pack.root, "Duplicate effect entry in " + pack.id, []))
                continue
            }
            seenPacks[pack.id] = true
            for (var localEntryId in localEntries) seenEntries[localEntryId] = true
            nextPacks.push(pack)
            for (var effectIndex = 0; effectIndex < pack.effects.length; effectIndex++)
                nextEffects.push(pack.effects[effectIndex])
        }
        nextPacks.sort(function(left, right) { return left.id < right.id ? -1 : left.id > right.id ? 1 : 0 })
        nextEffects.sort(function(left, right) {
            if (left.name < right.name) return -1
            if (left.name > right.name) return 1
            return left.id < right.id ? -1 : 1
        })
        root.packs = nextPacks
        root.effects = nextEffects
        root.invalidPacks = nextInvalid
        root.state = "ready"
        root.lastError = ""
        root.refreshed()
    }

    function refresh() {
        if (scanner.running) {
            root.refreshPending = true
            return false
        }
        root.state = "scanning"
        root.lastError = ""
        root.scanOutput = ""
        root.scanError = ""
        scanner.running = true
        return true
    }

    function diagnostics() {
        var packIds = []
        var effectIds = []
        for (var packIndex = 0; packIndex < root.packs.length; packIndex++)
            packIds.push(root.packs[packIndex].id)
        for (var effectIndex = 0; effectIndex < root.effects.length; effectIndex++)
            effectIds.push(root.effects[effectIndex].id)
        return {
            state: root.state,
            validPacks: root.validPackCount,
            invalidPacks: root.invalidPackCount,
            effects: root.effects.length,
            packIds: packIds,
            effectIds: effectIds,
            builtinRoot: root.builtinRoot,
            userRoot: root.userRoot,
            error: root.lastError,
            invalid: root.invalidPacks
        }
    }

    Process {
        id: scanner
        command: [
            "/usr/bin/bash", root.scannerPath,
            "--trusted-root", root.builtinRoot,
            "--root", root.userRoot,
            "--settings-json", root.settingsJson
        ]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.scanOutput = String(text || "")
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.scanError = String(text || "").trim()
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            if (exitCode === 0) root.parseScanOutput(root.scanOutput)
            else {
                root.effects = []
                root.packs = []
                root.state = "error"
                root.lastError = root.scanError || "Effect pack scanner failed"
                root.refreshed()
            }
            if (root.refreshPending) {
                root.refreshPending = false
                Qt.callLater(root.refresh)
            }
        }
    }

    Component.onCompleted: root.refresh()
}
