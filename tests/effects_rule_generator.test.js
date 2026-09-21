const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

const source = fs.readFileSync("effects/RuleGenerator.js", "utf8")
    .replace(/^\.pragma library\s*/, "")
const context = {}
vm.createContext(context)
vm.runInContext(source, context)

const disabled = context.generate(false, {}, {}, [], "/tmp/passthrough.glsl")
assert.match(disabled, /safely suspended/)
assert.doesNotMatch(disabled, /hl\.window_rule/)

const generated = context.generate(
    true,
    {
        open: "simple-fade-open",
        close: "simple-fade-close",
        move: "simple-wobble",
        resize: "none"
    },
    {
        "simple-fade-open": "/plugins/omadecor/effects/shaders/simple-fade-open.glsl",
        "simple-fade-close": "/plugins/omadecor/effects/shaders/simple-fade-close.glsl",
        "simple-wobble": "/plugins/omadecor/effects/shaders/simple-wobble.glsl"
    },
    ["kitty", "org.gnome.Calculator", "unsafe class"],
    "/plugins/omadecor/effects/shaders/passthrough.glsl"
)

assert.match(generated, /omadecor-effects-open-default/)
assert.match(generated, /\+shader_open_default:/)
assert.match(generated, /\+shader_move_default:[^\n]+@0\.35/)
assert.match(generated, /omadecor-effects-exclude-kitty-open/)
assert.match(generated, /omadecor-effects-exclude-org-gnome-calculator-open/)
assert.equal(context.exactClass("org.gnome.Calculator"), "^(org\\.gnome\\.Calculator)$")
assert.match(generated, /\+shader_close:[^\n]+passthrough\.glsl/)
assert.doesNotMatch(generated, /unsafe-class/)

console.log("effects rule generator: ok")
