const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

const generatorPath = "effects/backends/HyprWindowShadeRuleGenerator.js"
const source = fs.readFileSync(generatorPath, "utf8")
    .replace(/^\.pragma library\s*/, "")
const context = {}
vm.createContext(context)
vm.runInContext(source, context)

const disabled = context.generate(false, {}, {}, {}, [], "/tmp/passthrough.glsl")
assert.match(disabled, /safely suspended/)
assert.doesNotMatch(disabled, /hl\.window_rule/)

const generated = context.generate(
    true,
    {
        open: "simple-fade-open",
        close: "hyprland-shader.fire.close",
        move: "simple-wobble",
        resize: "none"
    },
    {
        open: 0.65,
        close: 0.8,
        move: 0.45,
        resize: 0.35
    },
    {
        "simple-fade-open": "/plugins/omadecor/effects/shaders/simple-fade-open.glsl",
        "simple-wobble": "/plugins/omadecor/effects/shaders/simple-wobble.glsl",
        "hyprland-shader.fire.close": "/home/user/.local/share/omadecor/shader-packs/hyprland-shader/shaders/fire_close.glsl"
    },
    [
        { appClass: "kitty", disableEffects: true, effectOverrides: { open: "simple-fade-open" } },
        {
            appClass: "org.gnome.Calculator",
            disableEffects: false,
            effectOverrides: { open: "none", move: "simple-wobble" }
        },
        { appClass: "unsafe class", disableEffects: true, effectOverrides: {} }
    ],
    "/plugins/omadecor/effects/shaders/passthrough.glsl"
)

assert.match(generated, /omadecor-effects-open-default/)
assert.match(generated, /\+shader_open_default:[^\n]+@0\.65/)
assert.match(generated, /\+shader_close_default:[^\n]+@0\.8/)
assert.match(generated, /\+shader_move_default:[^\n]+@0\.45/)
assert.match(generated, /omadecor-effects-exclude-kitty-open/)
assert.match(generated, /omadecor-effects-override-org-gnome-calculator-open/)
assert.match(generated, /omadecor-effects-override-org-gnome-calculator-move/)
assert.match(generated, /fire_close\.glsl/)
assert.match(generated, /omadecor-effects-override-org-gnome-calculator-move[^]*@0\.45/)
assert.equal(context.exactClass("org.gnome.Calculator"), "^(org\\.gnome\\.Calculator)$")
assert.match(generated, /\+shader_close:[^\n]+passthrough\.glsl/)
assert.doesNotMatch(generated, /passthrough\.glsl@/)
assert.doesNotMatch(generated, /omadecor-effects-override-kitty/)
assert.doesNotMatch(generated, /unsafe-class/)
const previousOverride = context.previousOwnedTags(generated)
    .find(item => item.tag.startsWith("+shader_move:")
        && item.classPattern.includes("org"))
assert.equal(previousOverride.classPattern, "^(org\\.gnome\\.Calculator)$")
const manualRule = '\nhl.window_rule({\n    name = "personal-rule",\n'
    + '    match = { class = ".*" },\n'
    + '    tag = "+shader_move:/manual/custom.glsl",\n})\n'
assert(!context.previousOwnedTags(generated + manualRule)
    .some(item => item.tag.includes("/manual/custom.glsl")))

const clearedMove = context.generate(true, { move: "none" }, { move: 0.45 }, {}, [],
    "/plugins/omadecor/effects/shaders/passthrough.glsl", generated)
assert.match(clearedMove, /tag = "-shader_move_default:[^\n]+simple-wobble\.glsl@0\.45"/)
assert.doesNotMatch(clearedMove, /tag = "\+shader_move_default:/)
const cleanupPosition = context.generate(true, { move: "simple-wobble" },
    { move: 0.45 }, { "simple-wobble": "/plugins/omadecor/effects/shaders/simple-wobble.glsl" },
    [], "/tmp/passthrough.glsl", generated)
assert(cleanupPosition.indexOf('tag = "-shader_move_default:')
    < cleanupPosition.indexOf('tag = "+shader_move_default:'))
const clearedAgain = context.generate(true, { move: "none" }, {}, {}, [],
    "/tmp/passthrough.glsl", clearedMove)
assert.doesNotMatch(clearedAgain, /shader_move_default/)
const suspended = context.generate(false, {}, {}, {}, [], "/tmp/passthrough.glsl", generated)
assert.match(suspended, /tag = "-shader_move_default:/)
assert.doesNotMatch(suspended, /tag = "\+shader_move_default:/)
const legacyClients = JSON.stringify([
    { tags: [
        "shader_move_default:/managed/old.glsl@0.45*",
        "shader_move_default:/manual/custom.glsl*",
        "shader_move_default:/managed/../manual/custom.glsl*",
        "shader_close:/managed/app-override.glsl*",
        "shader_move_default:/managed/static.glsl"
    ] },
    { tags: ["shader_move_default:/managed/old.glsl@0.45*"] }
])
const migrated = context.generate(true, { move: "none" }, {}, {}, [],
    "/tmp/passthrough.glsl", "", legacyClients, ["/managed/"])
assert.match(migrated, /tag = "-shader_move_default:\/managed\/old\.glsl@0\.45"/)
assert.equal((migrated.match(/omadecor-effects-cleanup-/g) || []).length, 1)
assert.doesNotMatch(migrated, /manual|app-override|static/)

assert.equal(fs.existsSync("effects/RuleGenerator.js"), false)
for (const platformFile of [
    "effects/EffectsManager.qml",
    "effects/ShaderCatalog.qml",
    "Service.qml",
    "Panel.qml"
]) {
    const platformSource = fs.readFileSync(platformFile, "utf8")
    assert.doesNotMatch(
        platformSource,
        /shader_(?:open|close|move|resize|workspace|focus|unfocus|urgent|float|tile|fullscreen)/,
        `${platformFile} must not know HyprWindowShade tag syntax`
    )
}

console.log("effects rule generator: ok")
