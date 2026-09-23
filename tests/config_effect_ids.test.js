const assert = require("node:assert/strict")
const fs = require("node:fs")

const source = fs.readFileSync("core/ConfigStore.qml", "utf8")
const body = source.match(/    function normalizedEffectId\(value, fallback\) \{([\s\S]*?)\n    \}/)
assert.ok(body, "ConfigStore.normalizedEffectId must exist")
const normalizedEffectId = new Function("value", "fallback", body[1])

assert.equal(normalizedEffectId("simple-fade-open", "none"), "simple-fade-open")
assert.equal(normalizedEffectId("hyprland-shader.circle.close", "none"),
    "hyprland-shader.circle.close")
assert.equal(normalizedEffectId("omadecor/simple-dissolve.open", "none"),
    "omadecor/simple-dissolve.open")
assert.equal(normalizedEffectId("liixini/circle.close", "none"), "liixini/circle.close")
assert.equal(normalizedEffectId("bmw/incinerate.open", "none"), "bmw/incinerate.open")
assert.equal(normalizedEffectId("bmw/incinerate/other.open", "none"), "none")
assert.equal(normalizedEffectId("bmw/../incinerate.open", "none"), "none")
assert.equal(normalizedEffectId("bmw/incinerate.open@2", "none"), "none")

const parametersBody = source.match(/    function normalizedEffectPackParameters\(value\) \{([\s\S]*?)\n    \}/)
assert.ok(parametersBody, "ConfigStore.normalizedEffectPackParameters must exist")
const normalizedParameters = new Function("value", "root", parametersBody[1])
const clean = normalizedParameters({
    "bmw/incinerate": { scale: 1.6, turbulence: 0.45, color: "#ff4400" },
    "bad/../pack": { scale: 1 },
    "custom/pack": { bad: Infinity, good: true }
}, { objectValue: (value, fallback) => value && !Array.isArray(value)
    && typeof value === "object" ? value : fallback })
assert.equal(clean["bmw/incinerate"].scale, 1.6)
assert.equal(clean["bmw/incinerate"].color, "#ff4400")
assert.equal(clean["custom/pack"].bad, undefined)
assert.equal(clean["custom/pack"].good, true)
assert.equal(clean["bad/../pack"], undefined)

console.log("effect pack config ids: ok")
