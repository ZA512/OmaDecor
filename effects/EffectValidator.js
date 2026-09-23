.pragma library

var limits = {
    manifestBytes: 131072,
    shaderBytes: 524288,
    events: 12,
    requirements: 64,
    parameters: 64,
    presets: 32
}

var normalizedEvents = [
    "open", "close", "move", "resize", "workspace", "focus", "unfocus",
    "urgent", "float", "tile", "fullscreen-enter", "fullscreen-exit"
]

var parameterTypes = ["float", "int", "boolean", "color", "enum"]
var sourceTypes = ["native", "ported", "adapted", "external"]
var sourceFormats = ["native", "niri", "bmw"]

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function own(value, key) {
    return Object.prototype.hasOwnProperty.call(value, key)
}

function addError(errors, path, message) {
    errors.push({ path: path, message: message })
}

function rejectUnknown(value, allowed, path, errors) {
    if (!isObject(value)) return
    var keys = Object.keys(value)
    for (var index = 0; index < keys.length; index++)
        if (allowed.indexOf(keys[index]) === -1)
            addError(errors, path + "." + keys[index], "unsupported property")
}

function requireString(value, path, errors, maximum) {
    if (typeof value !== "string" || value.trim() === "") {
        addError(errors, path, "non-empty string required")
        return false
    }
    if (value.length > maximum) addError(errors, path, "string is too long")
    return true
}

function isPackId(value) {
    return /^[a-z0-9][a-z0-9._-]{0,63}\/[a-z0-9][a-z0-9._-]{0,63}$/.test(String(value || ""))
}

function isLocalId(value) {
    return /^[a-z][A-Za-z0-9-]{0,63}$/.test(String(value || ""))
}

function isVersion(value) {
    return /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(String(value || ""))
}

function isCapability(value) {
    return /^[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)+$/.test(String(value || ""))
}

function isRelativeFile(value) {
    var text = String(value || "")
    if (text === "" || text.length > 240 || text.charAt(0) === "/" || text.indexOf("\\") !== -1)
        return false
    var segments = text.split("/")
    for (var index = 0; index < segments.length; index++) {
        if (segments[index] === "" || segments[index] === "." || segments[index] === "..") return false
        if (!/^[A-Za-z0-9._-]+$/.test(segments[index])) return false
    }
    return true
}

function validColor(value) {
    return /^#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$/.test(String(value || ""))
}

function finiteNumber(value) {
    return typeof value === "number" && isFinite(value)
}

function validateParameterValue(definition, value) {
    if (!definition) return false
    if (definition.type === "float")
        return finiteNumber(value) && value >= definition.min && value <= definition.max
    if (definition.type === "int")
        return finiteNumber(value) && Math.floor(value) === value
            && value >= definition.min && value <= definition.max
    if (definition.type === "boolean") return typeof value === "boolean"
    if (definition.type === "color") return validColor(value)
    if (definition.type === "enum")
        return typeof value === "string" && Array.isArray(definition.options)
            && definition.options.indexOf(value) !== -1
    return false
}

function validateSource(source, errors) {
    if (!isObject(source)) {
        addError(errors, "source", "source must be an object")
        return
    }
    rejectUnknown(source, ["type", "project", "url", "revision", "authors", "portAuthors", "license", "adaptationNotes"], "source", errors)
    if (sourceTypes.indexOf(source.type) === -1) addError(errors, "source.type", "unsupported provenance type")
    requireString(source.project, "source.project", errors, 128)
    requireString(source.license, "source.license", errors, 64)
    if (!Array.isArray(source.authors) || source.authors.length === 0 || source.authors.length > 32)
        addError(errors, "source.authors", "one to 32 authors are required")
    else for (var authorIndex = 0; authorIndex < source.authors.length; authorIndex++)
        requireString(source.authors[authorIndex], "source.authors[" + authorIndex + "]", errors, 128)

    if (source.type !== "native") {
        requireString(source.url, "source.url", errors, 512)
        requireString(source.revision, "source.revision", errors, 128)
    }
    if (source.type === "ported" || source.type === "adapted") {
        if (!Array.isArray(source.portAuthors) || source.portAuthors.length === 0)
            addError(errors, "source.portAuthors", "ported/adapted effects require port authors")
        if (typeof source.adaptationNotes !== "string" || source.adaptationNotes.trim() === "")
            addError(errors, "source.adaptationNotes", "ported/adapted effects require adaptation notes")
    }
}

function validateParameters(parameters, presets, errors) {
    if (!Array.isArray(parameters)) {
        addError(errors, "parameters", "parameters must be an array")
        return
    }
    if (parameters.length > limits.parameters) addError(errors, "parameters", "parameter budget exceeded")
    var definitions = ({})
    for (var index = 0; index < parameters.length; index++) {
        var parameter = parameters[index]
        var path = "parameters[" + index + "]"
        if (!isObject(parameter)) {
            addError(errors, path, "parameter must be an object")
            continue
        }
        rejectUnknown(parameter, ["id", "name", "type", "default", "min", "max", "step", "options"], path, errors)
        if (!isLocalId(parameter.id)) addError(errors, path + ".id", "invalid parameter id")
        else if (definitions[parameter.id]) addError(errors, path + ".id", "duplicate parameter id")
        else definitions[parameter.id] = parameter
        requireString(parameter.name, path + ".name", errors, 128)
        if (parameterTypes.indexOf(parameter.type) === -1) {
            addError(errors, path + ".type", "unsupported parameter type")
            continue
        }
        if (parameter.type === "float" || parameter.type === "int") {
            if (!finiteNumber(parameter.min) || !finiteNumber(parameter.max) || parameter.min > parameter.max)
                addError(errors, path, "numeric parameter requires finite min/max")
            if (!finiteNumber(parameter.step) || parameter.step <= 0)
                addError(errors, path + ".step", "numeric parameter requires a positive step")
        }
        if (parameter.type === "enum") {
            if (!Array.isArray(parameter.options) || parameter.options.length === 0 || parameter.options.length > 64)
                addError(errors, path + ".options", "enum parameter requires one to 64 options")
            else {
                var uniqueOptions = ({})
                for (var optionIndex = 0; optionIndex < parameter.options.length; optionIndex++) {
                    var option = String(parameter.options[optionIndex] || "")
                    if (option === "" || option.length > 64) addError(errors, path + ".options[" + optionIndex + "]", "invalid enum option")
                    if (uniqueOptions[option]) addError(errors, path + ".options[" + optionIndex + "]", "duplicate enum option")
                    uniqueOptions[option] = true
                }
            }
        }
        if (!own(parameter, "default") || !validateParameterValue(parameter, parameter.default))
            addError(errors, path + ".default", "default does not satisfy parameter definition")
    }

    if (!isObject(presets)) {
        addError(errors, "presets", "presets must be an object")
        return
    }
    var presetNames = Object.keys(presets)
    if (presetNames.length > limits.presets) addError(errors, "presets", "preset budget exceeded")
    for (var presetIndex = 0; presetIndex < presetNames.length; presetIndex++) {
        var presetName = presetNames[presetIndex]
        var preset = presets[presetName]
        var presetPath = "presets." + presetName
        if (!isLocalId(presetName)) addError(errors, presetPath, "invalid preset id")
        if (!isObject(preset)) {
            addError(errors, presetPath, "preset must be an object")
            continue
        }
        var values = Object.keys(preset)
        for (var valueIndex = 0; valueIndex < values.length; valueIndex++) {
            var parameterId = values[valueIndex]
            if (!definitions[parameterId]) addError(errors, presetPath + "." + parameterId, "unknown parameter")
            else if (!validateParameterValue(definitions[parameterId], preset[parameterId]))
                addError(errors, presetPath + "." + parameterId, "value does not satisfy parameter definition")
        }
    }
}

function validateEffect(manifest) {
    var errors = []
    if (!isObject(manifest)) return { ok: false, state: "INVALID", errors: [{ path: "$", message: "manifest must be an object" }] }
    rejectUnknown(manifest, [
        "$schema", "schemaVersion", "kind", "id", "name", "version", "description", "source",
        "compatibility", "shaders", "requires", "duration", "renderingCost",
        "parameters", "presets", "preview"
    ], "$", errors)
    if (manifest.schemaVersion !== 1) addError(errors, "schemaVersion", "only schemaVersion 1 is supported")
    if (manifest.kind !== "omadecor-effect-pack") addError(errors, "kind", "invalid pack kind")
    if (!isPackId(manifest.id)) addError(errors, "id", "id must use namespace/name syntax")
    requireString(manifest.name, "name", errors, 128)
    if (!isVersion(manifest.version)) addError(errors, "version", "version must be semantic")
    if (typeof manifest.description !== "string" || manifest.description.length > 512)
        addError(errors, "description", "description must be at most 512 characters")
    validateSource(manifest.source, errors)

    var compatibility = manifest.compatibility
    var events = []
    if (!isObject(compatibility)) addError(errors, "compatibility", "compatibility must be an object")
    else {
        rejectUnknown(compatibility, ["sourceFormat", "events"], "compatibility", errors)
        if (sourceFormats.indexOf(compatibility.sourceFormat) === -1)
            addError(errors, "compatibility.sourceFormat", "unsupported source format")
        if (!Array.isArray(compatibility.events) || compatibility.events.length === 0
                || compatibility.events.length > limits.events)
            addError(errors, "compatibility.events", "one to twelve events are required")
        else {
            var seenEvents = ({})
            for (var eventIndex = 0; eventIndex < compatibility.events.length; eventIndex++) {
                var eventName = compatibility.events[eventIndex]
                if (normalizedEvents.indexOf(eventName) === -1)
                    addError(errors, "compatibility.events[" + eventIndex + "]", "unsupported event")
                if (seenEvents[eventName]) addError(errors, "compatibility.events[" + eventIndex + "]", "duplicate event")
                seenEvents[eventName] = true
                events.push(eventName)
            }
        }
    }

    if (!isObject(manifest.shaders)) addError(errors, "shaders", "shaders must be an object")
    else {
        var shaderEvents = Object.keys(manifest.shaders)
        for (var shaderIndex = 0; shaderIndex < shaderEvents.length; shaderIndex++) {
            var shaderEvent = shaderEvents[shaderIndex]
            if (events.indexOf(shaderEvent) === -1) addError(errors, "shaders." + shaderEvent, "shader event is not declared")
            if (!isRelativeFile(manifest.shaders[shaderEvent])) addError(errors, "shaders." + shaderEvent, "shader path must stay inside the pack")
        }
        for (var requiredShaderIndex = 0; requiredShaderIndex < events.length; requiredShaderIndex++)
            if (!own(manifest.shaders, events[requiredShaderIndex]))
                addError(errors, "shaders." + events[requiredShaderIndex], "declared event requires a shader")
    }

    if (!Array.isArray(manifest.requires) || manifest.requires.length > limits.requirements)
        addError(errors, "requires", "requires must be an array of at most 64 capabilities")
    else {
        var seenRequirements = ({})
        for (var requirementIndex = 0; requirementIndex < manifest.requires.length; requirementIndex++) {
            var requirement = manifest.requires[requirementIndex]
            if (!isCapability(requirement)) addError(errors, "requires[" + requirementIndex + "]", "invalid capability")
            if (seenRequirements[requirement]) addError(errors, "requires[" + requirementIndex + "]", "duplicate capability")
            seenRequirements[requirement] = true
        }
    }

    if (!isObject(manifest.duration)) addError(errors, "duration", "duration must be an object")
    else {
        rejectUnknown(manifest.duration, ["defaultMs", "minMs", "maxMs"], "duration", errors)
        var duration = manifest.duration
        if (!finiteNumber(duration.defaultMs) || !finiteNumber(duration.minMs) || !finiteNumber(duration.maxMs)
                || duration.minMs < 0 || duration.maxMs > 5000 || duration.minMs > duration.defaultMs
                || duration.defaultMs > duration.maxMs)
            addError(errors, "duration", "duration must satisfy 0 <= min <= default <= max <= 5000")
    }
    if (["low", "medium", "high"].indexOf(manifest.renderingCost) === -1)
        addError(errors, "renderingCost", "renderingCost must be low, medium, or high")
    if (manifest.preview !== undefined && !isRelativeFile(manifest.preview))
        addError(errors, "preview", "preview path must stay inside the pack")
    validateParameters(manifest.parameters, manifest.presets, errors)
    return { ok: errors.length === 0, state: errors.length === 0 ? "VALID" : "INVALID", errors: errors }
}

function missingCapabilities(manifest, capabilities) {
    var available = ({})
    var values = Array.isArray(capabilities) ? capabilities : []
    for (var index = 0; index < values.length; index++) available[String(values[index])] = true
    var missing = []
    var requirements = manifest && Array.isArray(manifest.requires) ? manifest.requires : []
    for (var requirementIndex = 0; requirementIndex < requirements.length; requirementIndex++)
        if (!available[requirements[requirementIndex]]) missing.push(requirements[requirementIndex])
    return missing
}
