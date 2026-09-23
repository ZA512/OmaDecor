.pragma library

function searchText(value) {
    var text = String(value === undefined || value === null ? "" : value).toLowerCase()
    if (typeof text.normalize === "function")
        return text.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    return text
}

function filterEffects(choices, query) {
    var entries = Array.isArray(choices) ? choices : []
    var terms = searchText(query).trim().split(/\s+/).filter(function(term) {
        return term !== ""
    })
    if (terms.length === 0) return entries.slice()

    return entries.filter(function(entry) {
        var fields = ["name", "id", "pack", "source", "author", "license", "description"]
        var haystack = fields.map(function(field) {
            return searchText(entry && entry[field])
        }).join(" ")
        return terms.every(function(term) { return haystack.indexOf(term) !== -1 })
    })
}

function groupEffects(choices) {
    var groups = [
        { title: "Default choices", effects: [] },
        { title: "Effect packs", effects: [] },
        { title: "OmaDecor basics", effects: [] },
        { title: "External shader collection", effects: [] },
        { title: "Other effects", effects: [] }
    ]
    var entries = Array.isArray(choices) ? choices : []
    for (var index = 0; index < entries.length; index++) {
        var entry = entries[index]
        if (!entry) continue
        var groupIndex = entry.id === "none" || entry.id === "global" ? 0
            : entry.effectId ? 1
            : entry.source === "builtin" ? 2
            : entry.source === "external" ? 3 : 4
        groups[groupIndex].effects.push(entry)
    }
    return groups.filter(function(group) { return group.effects.length > 0 })
}
