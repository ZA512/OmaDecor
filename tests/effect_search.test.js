const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

const source = fs.readFileSync("effects/EffectSearch.js", "utf8")
    .replace(/^\.pragma library\s*/, "")
const search = {}
vm.createContext(search)
vm.runInContext(source, search)

const choices = [
    { id: "none", name: "None", source: "OmaDecor" },
    { id: "liixini/circle.open", name: "Circle", pack: "Niri", author: "Liixini" },
    { id: "bmw/incinerate.close", name: "Incinerate", pack: "BMW", author: "Benyamin" },
    { id: "shader/fire.open", name: "Feu doré", pack: "Hyprland-Shader",
        author: "Jane", description: "Bright flame", license: "MIT" }
]

function ids(query) {
    return Array.from(search.filterEffects(choices, query), entry => entry.id)
}

assert.deepEqual(ids(""), choices.map(entry => entry.id))
assert.deepEqual(ids("  "), choices.map(entry => entry.id))
assert.deepEqual(ids("INCINERATE"), ["bmw/incinerate.close"])
assert.deepEqual(ids("niri liixini"), ["liixini/circle.open"])
assert.deepEqual(ids("shader/fire"), ["shader/fire.open"])
assert.deepEqual(ids("feu dore"), ["shader/fire.open"])
assert.deepEqual(ids("bright MIT"), ["shader/fire.open"])
assert.deepEqual(ids("missing"), [])
assert.deepEqual(Array.from(search.filterEffects(null, "fire")), [])
assert.equal(choices.length, 4)

const grouped = search.groupEffects([
    { id: "shader/fire.open", source: "external" },
    { id: "simple-fade-open", source: "builtin" },
    { id: "bmw/incinerate.open", effectId: "bmw/incinerate", source: "ported" },
    choices[0],
    { id: "global" },
    { id: "custom.unknown", source: "plugin" }
])
assert.deepEqual(Array.from(grouped, group => group.title), [
    "Default choices", "Effect packs", "OmaDecor basics",
    "External shader collection", "Other effects"
])
assert.deepEqual(Array.from(grouped[0].effects, entry => entry.id), ["none", "global"])
assert.deepEqual(Array.from(grouped[1].effects, entry => entry.id), ["bmw/incinerate.open"])
assert.deepEqual(Array.from(grouped[2].effects, entry => entry.id), ["simple-fade-open"])
assert.deepEqual(Array.from(grouped[3].effects, entry => entry.id), ["shader/fire.open"])
assert.deepEqual(Array.from(grouped[4].effects, entry => entry.id), ["custom.unknown"])
assert.deepEqual(Array.from(search.groupEffects(null)), [])

console.log("Effect search tests passed")
