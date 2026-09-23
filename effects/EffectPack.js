.pragma library

function create(record, validation, entries) {
    var manifest = record && record.manifest ? record.manifest : ({})
    return {
        id: String(manifest.id || ""),
        name: String(manifest.name || "Invalid pack"),
        version: String(manifest.version || ""),
        root: String(record && record.root || ""),
        state: validation && validation.ok ? "VALID" : "INVALID",
        compilation: String(record && record.compilation || "unknown"),
        metadata: manifest,
        effects: validation && validation.ok ? entries : [],
        errors: validation && Array.isArray(validation.errors) ? validation.errors : []
    }
}
