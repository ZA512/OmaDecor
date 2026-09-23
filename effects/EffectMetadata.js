.pragma library

function runtimeEvent(eventName) {
    if (eventName === "fullscreen-enter") return "fullscreenEnter"
    if (eventName === "fullscreen-exit") return "fullscreenExit"
    return eventName
}

function entryId(packId, eventName) {
    return String(packId) + "." + String(eventName)
}

function joinAuthors(source) {
    return source && Array.isArray(source.authors) ? source.authors.join(", ") : ""
}

function entries(manifest, packRoot, artifacts) {
    var result = []
    var events = manifest.compatibility.events
    for (var index = 0; index < events.length; index++) {
        var eventName = events[index]
        result.push({
            id: entryId(manifest.id, eventName),
            effectId: manifest.id,
            eventId: eventName,
            name: manifest.name,
            version: manifest.version,
            events: [runtimeEvent(eventName)],
            path: artifacts && artifacts[eventName]
                ? artifacts[eventName] : packRoot + "/" + manifest.shaders[eventName],
            source: manifest.source.type,
            sourceFormat: manifest.compatibility.sourceFormat,
            pack: manifest.source.project,
            author: joinAuthors(manifest.source),
            license: manifest.source.license,
            description: manifest.description,
            requires: manifest.requires.slice(),
            duration: manifest.duration,
            renderingCost: manifest.renderingCost,
            parameters: manifest.parameters,
            presets: manifest.presets,
            provenance: manifest.source,
            packRoot: packRoot,
            preview: manifest.preview ? packRoot + "/" + manifest.preview : ""
        })
    }
    return result
}
