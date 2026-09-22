.pragma library

var limits = {
    layers: 128,
    drawOperations: 256,
    parameters: 64,
    paletteEntries: 64,
    variants: 32,
    exteriorPixels: 128
}

var supportedCapabilities = [
    "primitive.edge",
    "primitive.frame",
    "primitive.rect",
    "paint.solid",
    "state.focused",
    "color.oklch-derive"
]

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function own(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key)
}

function clone(value) {
    return JSON.parse(JSON.stringify(value))
}

function sortedKeys(value) {
    return isObject(value) ? Object.keys(value).sort() : []
}

function hasCapability(name) {
    return supportedCapabilities.indexOf(String(name || "")) !== -1
}

function addError(errors, path, message) {
    errors.push({ path: path, message: message })
}

function isLocalId(value) {
    return /^[a-z][A-Za-z0-9-]{0,63}$/.test(String(value || ""))
}

function isThemeId(value) {
    return /^[a-z0-9][a-z0-9._-]{0,63}\/[a-z0-9][a-z0-9._-]{0,63}$/.test(String(value || ""))
}

function isColor(value) {
    return /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(String(value || ""))
}

function isReference(value) {
    return isObject(value) && sortedKeys(value).length === 1 && typeof value.ref === "string"
}

function capabilityForLayer(type) {
    return "primitive." + String(type || "")
}

function validateParameter(name, definition, errors) {
    var path = "parameters." + name
    if (!isObject(definition)) {
        addError(errors, path, "parameter definition must be an object")
        return
    }
    if (["number", "color", "boolean", "enum"].indexOf(definition.type) === -1)
        addError(errors, path + ".type", "unsupported parameter type")
    if (typeof definition.label !== "string" || definition.label.trim() === "")
        addError(errors, path + ".label", "label is required")
    if (!own(definition, "default")) addError(errors, path + ".default", "default is required")
    if (definition.type === "number") {
        if (typeof definition.min !== "number" || typeof definition.max !== "number" || definition.min > definition.max)
            addError(errors, path, "number parameters require a valid min/max range")
        if (typeof definition.step !== "number" || definition.step <= 0)
            addError(errors, path + ".step", "number parameters require a positive step")
    }
    if (definition.type === "enum" && (!Array.isArray(definition.options) || definition.options.length === 0))
        addError(errors, path + ".options", "enum parameters require options")
}

function validatePaint(paint, path, required, errors) {
    if (!isObject(paint) || paint.type !== "solid" || !own(paint, "color")) {
        addError(errors, path, "V1 Core supports only solid paint with a color")
        return
    }
    if (required.indexOf("paint.solid") === -1)
        addError(errors, path, "paint.solid must be declared in requires")
}

function validateLayer(layer, index, required, layerIds, errors) {
    var path = "layers[" + index + "]"
    if (!isObject(layer)) {
        addError(errors, path, "layer must be an object")
        return 0
    }
    if (!isLocalId(layer.id)) addError(errors, path + ".id", "invalid layer id")
    else if (layerIds.indexOf(layer.id) !== -1) addError(errors, path + ".id", "duplicate layer id")
    else layerIds.push(layer.id)

    if (["edge", "frame", "rect"].indexOf(layer.type) === -1) {
        addError(errors, path + ".type", "primitive is not supported by V1 Core")
        return 0
    }
    var capability = capabilityForLayer(layer.type)
    if (required.indexOf(capability) === -1)
        addError(errors, path, capability + " must be declared in requires")

    if (layer.type === "edge") {
        if (["top", "right", "bottom", "left"].indexOf(layer.side) === -1)
            addError(errors, path + ".side", "invalid edge side")
        if (!own(layer, "thickness")) addError(errors, path + ".thickness", "thickness is required")
        validatePaint(layer.paint, path + ".paint", required, errors)
        return 1
    }
    if (layer.type === "rect") {
        var coordinates = ["x", "y", "width", "height"]
        for (var coordinateIndex = 0; coordinateIndex < coordinates.length; coordinateIndex++) {
            var coordinate = coordinates[coordinateIndex]
            if (!own(layer, coordinate)) addError(errors, path + "." + coordinate, coordinate + " is required")
        }
        validatePaint(layer.paint, path + ".paint", required, errors)
        return 1
    }

    var sides = ["top", "right", "bottom", "left"]
    var operationCount = 0
    for (var sideIndex = 0; sideIndex < sides.length; sideIndex++) {
        var side = sides[sideIndex]
        if (!own(layer, side)) continue
        operationCount += 1
        if (!isObject(layer[side]) || !own(layer[side], "thickness"))
            addError(errors, path + "." + side, "frame side requires thickness")
        else validatePaint(layer[side].paint, path + "." + side + ".paint", required, errors)
    }
    if (operationCount === 0) addError(errors, path, "frame requires at least one side")
    return operationCount
}

function validateTheme(theme) {
    var errors = []
    if (!isObject(theme)) return { ok: false, errors: [{ path: "$", message: "theme must be an object" }] }
    if (theme.schemaVersion !== 1) addError(errors, "schemaVersion", "only schemaVersion 1 is supported")
    if (theme.kind !== "omadecor-decoration") addError(errors, "kind", "invalid theme kind")
    if (!isThemeId(theme.id)) addError(errors, "id", "id must use author/theme syntax")
    if (typeof theme.name !== "string" || theme.name.trim() === "") addError(errors, "name", "name is required")
    if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/.test(String(theme.version || "")))
        addError(errors, "version", "version must be semantic")

    var required = Array.isArray(theme.requires) ? theme.requires.slice() : []
    if (!Array.isArray(theme.requires)) addError(errors, "requires", "requires must be an array")
    var seenCapabilities = []
    for (var capabilityIndex = 0; capabilityIndex < required.length; capabilityIndex++) {
        var requirement = String(required[capabilityIndex] || "")
        if (seenCapabilities.indexOf(requirement) !== -1)
            addError(errors, "requires[" + capabilityIndex + "]", "duplicate capability")
        seenCapabilities.push(requirement)
        if (!hasCapability(requirement))
            addError(errors, "requires[" + capabilityIndex + "]", "unsupported capability: " + requirement)
    }

    var parameters = isObject(theme.parameters) ? theme.parameters : {}
    var parameterNames = sortedKeys(parameters)
    if (!isObject(theme.parameters)) addError(errors, "parameters", "parameters must be an object")
    if (parameterNames.length > limits.parameters) addError(errors, "parameters", "parameter budget exceeded")
    for (var parameterIndex = 0; parameterIndex < parameterNames.length; parameterIndex++) {
        var parameterName = parameterNames[parameterIndex]
        if (!isLocalId(parameterName)) addError(errors, "parameters." + parameterName, "invalid parameter id")
        validateParameter(parameterName, parameters[parameterName], errors)
    }

    var palette = isObject(theme.palette) ? theme.palette : {}
    var paletteNames = sortedKeys(palette)
    if (!isObject(theme.palette)) addError(errors, "palette", "palette must be an object")
    if (paletteNames.length > limits.paletteEntries) addError(errors, "palette", "palette budget exceeded")
    for (var paletteIndex = 0; paletteIndex < paletteNames.length; paletteIndex++) {
        var paletteName = paletteNames[paletteIndex]
        if (!isLocalId(paletteName)) addError(errors, "palette." + paletteName, "invalid palette id")
        var paletteEntry = palette[paletteName]
        if (!isReference(paletteEntry) && !isColor(paletteEntry) && !(isObject(paletteEntry) && isObject(paletteEntry.derive)))
            addError(errors, "palette." + paletteName, "invalid palette entry")
        if (isObject(paletteEntry) && isObject(paletteEntry.derive) && required.indexOf("color.oklch-derive") === -1)
            addError(errors, "palette." + paletteName, "color.oklch-derive must be declared in requires")
    }

    var layers = Array.isArray(theme.layers) ? theme.layers : []
    if (!Array.isArray(theme.layers)) addError(errors, "layers", "layers must be an array")
    if (layers.length > limits.layers) addError(errors, "layers", "layer budget exceeded")
    var layerIds = []
    var operations = 0
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++)
        operations += validateLayer(layers[layerIndex], layerIndex, required, layerIds, errors)
    if (operations > limits.drawOperations) addError(errors, "layers", "draw operation budget exceeded")

    var variants = theme.variants === undefined ? [] : theme.variants
    if (!Array.isArray(variants)) addError(errors, "variants", "variants must be an array")
    else {
        if (variants.length > limits.variants) addError(errors, "variants", "variant budget exceeded")
        for (var variantIndex = 0; variantIndex < variants.length; variantIndex++) {
            var variant = variants[variantIndex]
            var variantPath = "variants[" + variantIndex + "]"
            if (!isObject(variant) || !isObject(variant.when) || !isObject(variant.patch)) {
                addError(errors, variantPath, "variant requires when and patch objects")
                continue
            }
            var states = sortedKeys(variant.when)
            for (var stateIndex = 0; stateIndex < states.length; stateIndex++) {
                var stateName = states[stateIndex]
                var stateCapability = "state." + stateName
                if (!hasCapability(stateCapability))
                    addError(errors, variantPath + ".when." + stateName, "state is not supported by V1 Core")
                else if (required.indexOf(stateCapability) === -1)
                    addError(errors, variantPath + ".when." + stateName, stateCapability + " must be declared in requires")
                if (typeof variant.when[stateName] !== "boolean")
                    addError(errors, variantPath + ".when." + stateName, "state condition must be boolean")
            }
            if (isObject(variant.patch.layers)) {
                var patchedIds = sortedKeys(variant.patch.layers)
                for (var patchedIndex = 0; patchedIndex < patchedIds.length; patchedIndex++)
                    if (layerIds.indexOf(patchedIds[patchedIndex]) === -1)
                        addError(errors, variantPath + ".patch.layers." + patchedIds[patchedIndex], "unknown layer id")
            }
        }
    }
    if (theme.transitions !== undefined)
        addError(errors, "transitions", "state transitions are reserved but not implemented by V1 Core")

    if (errors.length === 0) {
        var probe = compileTheme(theme, {}, {
            accent: "#47d7ff",
            background: "#111111",
            foreground: "#eeeeee",
            border: "#64748b"
        }, { focused: true }, true)
        if (!probe.ok) errors = probe.errors
    }
    return { ok: errors.length === 0, errors: errors, drawOperations: operations }
}

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
}

function srgbToLinear(value) {
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
}

function linearToSrgb(value) {
    return value <= 0.0031308 ? 12.92 * value : 1.055 * Math.pow(value, 1 / 2.4) - 0.055
}

function parseColor(value) {
    if (!isColor(value)) return null
    var text = String(value).slice(1)
    return {
        r: parseInt(text.slice(0, 2), 16) / 255,
        g: parseInt(text.slice(2, 4), 16) / 255,
        b: parseInt(text.slice(4, 6), 16) / 255,
        a: text.length === 8 ? parseInt(text.slice(6, 8), 16) / 255 : 1
    }
}

function colorToOklch(color) {
    var r = srgbToLinear(color.r)
    var g = srgbToLinear(color.g)
    var b = srgbToLinear(color.b)
    var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    var lightness = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
    var a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
    var bValue = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
    return {
        l: lightness,
        c: Math.sqrt(a * a + bValue * bValue),
        h: Math.atan2(bValue, a) * 180 / Math.PI,
        a: color.a
    }
}

function channelHex(value) {
    var text = Math.round(clamp(value, 0, 1) * 255).toString(16)
    return text.length < 2 ? "0" + text : text
}

function oklchToColor(value) {
    var angle = value.h * Math.PI / 180
    var a = value.c * Math.cos(angle)
    var b = value.c * Math.sin(angle)
    var l = value.l + 0.3963377774 * a + 0.2158037573 * b
    var m = value.l - 0.1055613458 * a - 0.0638541728 * b
    var s = value.l - 0.0894841775 * a - 1.291485548 * b
    l = l * l * l
    m = m * m * m
    s = s * s * s
    var red = linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
    var green = linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
    var blue = linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)
    var result = "#" + channelHex(red) + channelHex(green) + channelHex(blue)
    if (value.a < 0.999) result += channelHex(value.a)
    return result
}

function deepMerge(target, patch) {
    var output = clone(target)
    var keys = sortedKeys(patch)
    for (var index = 0; index < keys.length; index++) {
        var key = keys[index]
        if (isObject(output[key]) && isObject(patch[key])) output[key] = deepMerge(output[key], patch[key])
        else output[key] = clone(patch[key])
    }
    return output
}

function validateResolvedNumber(value, path, minimum, maximum, allowRelative, errors) {
    if (typeof value === "number" && isFinite(value)) {
        if (value < minimum || value > maximum) addError(errors, path, "resolved number is outside the allowed range")
        return
    }
    if (allowRelative && isObject(value) && (own(value, "rel") || own(value, "px"))) {
        if (own(value, "rel") && (typeof value.rel !== "number" || !isFinite(value.rel) || value.rel < -4 || value.rel > 4))
            addError(errors, path + ".rel", "relative component is outside -4…4")
        if (own(value, "px") && (typeof value.px !== "number" || !isFinite(value.px) || value.px < -4096 || value.px > 4096))
            addError(errors, path + ".px", "pixel component is outside -4096…4096")
        return
    }
    addError(errors, path, allowRelative ? "number or relative value required" : "number required")
}

function validateCompiledLayer(layer, index, errors) {
    var path = "layers[" + index + "]"
    if (own(layer, "opacity")) validateResolvedNumber(layer.opacity, path + ".opacity", 0, 1, false, errors)
    function validateResolvedPaint(paint, paintPath) {
        if (!isObject(paint) || paint.type !== "solid" || !isColor(paint.color))
            addError(errors, paintPath, "solid paint must resolve to a color")
    }
    function validateResolvedEdgePart(part, partPath) {
        if (!isObject(part)) return
        validateResolvedNumber(part.thickness, partPath + ".thickness", 0, limits.exteriorPixels, false, errors)
        if (own(part, "distance"))
            validateResolvedNumber(part.distance, partPath + ".distance", 0, limits.exteriorPixels, false, errors)
        validateResolvedPaint(part.paint, partPath + ".paint")
    }
    if (layer.type === "frame") {
        var sides = ["top", "right", "bottom", "left"]
        for (var sideIndex = 0; sideIndex < sides.length; sideIndex++) {
            var side = sides[sideIndex]
            if (own(layer, side)) validateResolvedEdgePart(layer[side], path + "." + side)
        }
    } else if (layer.type === "edge") {
        validateResolvedEdgePart(layer, path)
        if (own(layer, "start")) validateResolvedNumber(layer.start, path + ".start", -4096, 4096, true, errors)
        if (own(layer, "end")) validateResolvedNumber(layer.end, path + ".end", -4096, 4096, true, errors)
    } else if (layer.type === "rect") {
        validateResolvedNumber(layer.x, path + ".x", -4096, 4096, true, errors)
        validateResolvedNumber(layer.y, path + ".y", -4096, 4096, true, errors)
        validateResolvedNumber(layer.width, path + ".width", 0, 4096, true, errors)
        validateResolvedNumber(layer.height, path + ".height", 0, 4096, true, errors)
        validateResolvedPaint(layer.paint, path + ".paint")
    }
}

function compileTheme(theme, overrides, systemPalette, state, skipValidation) {
    if (!skipValidation) {
        var validation = validateTheme(theme)
        if (!validation.ok) return validation
    }
    var errors = []
    var parameterCache = {}
    var paletteCache = {}
    var resolving = []
    var parameters = isObject(theme.parameters) ? theme.parameters : {}
    var supplied = isObject(overrides) ? overrides : {}
    var system = isObject(systemPalette) ? systemPalette : {}

    function resolveReference(reference, path) {
        var parts = String(reference || "").split(".")
        if (parts.length !== 2) {
            addError(errors, path, "invalid reference: " + reference)
            return null
        }
        if (parts[0] === "system") {
            if (["accent", "background", "foreground", "border"].indexOf(parts[1]) === -1 || !isColor(system[parts[1]])) {
                addError(errors, path, "unavailable system color: " + reference)
                return null
            }
            return String(system[parts[1]]).toLowerCase()
        }
        if (parts[0] === "param") return resolveParameter(parts[1], path)
        if (parts[0] === "palette") return resolvePalette(parts[1], path)
        addError(errors, path, "unsupported reference namespace: " + reference)
        return null
    }

    function resolveValue(value, path) {
        if (isReference(value)) return resolveReference(value.ref, path)
        if (isObject(value) && (own(value, "rel") || own(value, "px"))) {
            var relative = {}
            if (own(value, "rel")) relative.rel = Number(value.rel)
            if (own(value, "px")) relative.px = Number(value.px)
            return relative
        }
        return value
    }

    function resolveParameter(name, path) {
        if (own(parameterCache, name)) return parameterCache[name]
        if (!own(parameters, name)) {
            addError(errors, path, "unknown parameter: " + name)
            return null
        }
        var marker = "param." + name
        if (resolving.indexOf(marker) !== -1) {
            addError(errors, path, "cyclic reference involving " + marker)
            return null
        }
        resolving.push(marker)
        var definition = parameters[name]
        var raw = own(supplied, name) ? supplied[name] : definition.default
        var value = resolveValue(raw, path)
        if (definition.type === "number") {
            if (typeof value !== "number" || !isFinite(value) || value < definition.min || value > definition.max)
                addError(errors, path, "number is outside the declared range")
        } else if (definition.type === "color") {
            if (!isColor(value)) addError(errors, path, "color must resolve to #RRGGBB or #RRGGBBAA")
            else value = String(value).toLowerCase()
        } else if (definition.type === "boolean") {
            if (typeof value !== "boolean") addError(errors, path, "boolean value required")
        } else if (definition.type === "enum") {
            if (!Array.isArray(definition.options) || definition.options.indexOf(value) === -1)
                addError(errors, path, "value is not an enum option")
        }
        resolving.pop()
        parameterCache[name] = value
        return value
    }

    function resolvePalette(name, path) {
        if (own(paletteCache, name)) return paletteCache[name]
        if (!isObject(theme.palette) || !own(theme.palette, name)) {
            addError(errors, path, "unknown palette entry: " + name)
            return null
        }
        var marker = "palette." + name
        if (resolving.indexOf(marker) !== -1) {
            addError(errors, path, "cyclic reference involving " + marker)
            return null
        }
        resolving.push(marker)
        var entry = theme.palette[name]
        var value
        if (isReference(entry)) value = resolveReference(entry.ref, path)
        else if (isColor(entry)) value = String(entry).toLowerCase()
        else if (isObject(entry) && isObject(entry.derive)) {
            var base = resolveValue(entry.derive.from, path + ".derive.from")
            var parsed = parseColor(base)
            if (!parsed) addError(errors, path, "derived palette source must resolve to a color")
            else {
                var oklch = colorToOklch(parsed)
                oklch.l = clamp(oklch.l + Number(entry.derive.lightness || 0), 0, 1)
                oklch.c = Math.max(0, oklch.c + Number(entry.derive.chroma || 0))
                oklch.h += Number(entry.derive.hue || 0)
                if (own(entry.derive, "alpha")) oklch.a = clamp(Number(entry.derive.alpha), 0, 1)
                value = oklchToColor(oklch)
            }
        } else addError(errors, path, "invalid palette entry")
        resolving.pop()
        paletteCache[name] = value
        return value
    }

    var parameterNames = sortedKeys(parameters)
    for (var parameterIndex = 0; parameterIndex < parameterNames.length; parameterIndex++)
        resolveParameter(parameterNames[parameterIndex], "parameters." + parameterNames[parameterIndex])
    var paletteNames = sortedKeys(theme.palette)
    for (var paletteIndex = 0; paletteIndex < paletteNames.length; paletteIndex++)
        resolvePalette(paletteNames[paletteIndex], "palette." + paletteNames[paletteIndex])

    var effectiveAppearance = clone(theme.appearance || { opacity: 1 })
    var effectiveLayers = clone(theme.layers || [])
    var variants = Array.isArray(theme.variants) ? theme.variants : []
    var currentState = isObject(state) ? state : {}
    for (var variantIndex = 0; variantIndex < variants.length; variantIndex++) {
        var variant = variants[variantIndex]
        var matches = true
        var stateNames = sortedKeys(variant.when)
        for (var stateIndex = 0; stateIndex < stateNames.length; stateIndex++) {
            var stateName = stateNames[stateIndex]
            if ((currentState[stateName] === true) !== variant.when[stateName]) matches = false
        }
        if (!matches) continue
        if (isObject(variant.patch.theme)) effectiveAppearance = deepMerge(effectiveAppearance, variant.patch.theme)
        if (isObject(variant.patch.layers)) {
            for (var layerIndex = 0; layerIndex < effectiveLayers.length; layerIndex++) {
                var layerPatch = variant.patch.layers[effectiveLayers[layerIndex].id]
                if (isObject(layerPatch)) effectiveLayers[layerIndex] = deepMerge(effectiveLayers[layerIndex], layerPatch)
            }
        }
    }

    function resolveTree(value, path) {
        if (isReference(value)) return resolveReference(value.ref, path)
        if (Array.isArray(value)) {
            var arrayResult = []
            for (var arrayIndex = 0; arrayIndex < value.length; arrayIndex++)
                arrayResult.push(resolveTree(value[arrayIndex], path + "[" + arrayIndex + "]"))
            return arrayResult
        }
        if (!isObject(value)) return value
        if (own(value, "rel") || own(value, "px")) return resolveValue(value, path)
        var objectResult = {}
        var keys = sortedKeys(value)
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++)
            objectResult[keys[keyIndex]] = resolveTree(value[keys[keyIndex]], path + "." + keys[keyIndex])
        return objectResult
    }

    var compiledLayers = resolveTree(effectiveLayers, "layers")
    var appearance = resolveTree(effectiveAppearance, "appearance")
    if (own(appearance, "opacity"))
        validateResolvedNumber(appearance.opacity, "appearance.opacity", 0, 1, false, errors)
    for (var compiledIndex = 0; compiledIndex < compiledLayers.length; compiledIndex++)
        validateCompiledLayer(compiledLayers[compiledIndex], compiledIndex, errors)
    return {
        ok: errors.length === 0,
        errors: errors,
        compiled: errors.length === 0 ? {
            id: theme.id,
            name: theme.name,
            version: theme.version,
            parameters: parameterCache,
            palette: paletteCache,
            appearance: appearance,
            layers: compiledLayers
        } : null
    }
}
