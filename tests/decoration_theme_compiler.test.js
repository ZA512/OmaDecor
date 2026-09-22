const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

const source = fs.readFileSync("decorations/ThemeCompiler.js", "utf8")
    .replace(/^\.pragma library\s*/, "")
const context = {}
vm.createContext(context)
vm.runInContext(source, context)

const theme = JSON.parse(fs.readFileSync(
    "decorations/styles/raised-edge.omadecor.json", "utf8"
))
const systemPalette = {
    accent: "#47d7ff",
    background: "#111111",
    foreground: "#eeeeee",
    border: "#64748b"
}

const validation = context.validateTheme(theme)
assert.equal(validation.ok, true, JSON.stringify(validation.errors))
assert.equal(validation.drawOperations, 4)

const focused = context.compileTheme(theme, {}, systemPalette, { focused: true })
assert.equal(focused.ok, true, JSON.stringify(focused.errors))
assert.equal(focused.compiled.id, "omadecor/raised-edge")
assert.equal(focused.compiled.appearance.opacity, 1)
assert.equal(focused.compiled.layers[0].top.thickness, 2)
assert.equal(focused.compiled.layers[0].bottom.thickness, 5)
assert.equal(focused.compiled.layers[0].top.paint.color, "#47d7ff")
assert.match(focused.compiled.layers[0].bottom.paint.color, /^#[0-9a-f]{6}$/)
assert.notEqual(
    focused.compiled.layers[0].bottom.paint.color,
    focused.compiled.layers[0].top.paint.color
)

const inactive = context.compileTheme(theme, {
    mainColor: "#ff8800",
    lightWidth: 3,
    darkWidth: 7,
    inactiveOpacity: 0.4
}, systemPalette, { focused: false })
assert.equal(inactive.ok, true, JSON.stringify(inactive.errors))
assert.equal(inactive.compiled.appearance.opacity, 0.4)
assert.equal(inactive.compiled.layers[0].top.thickness, 3)
assert.equal(inactive.compiled.layers[0].left.thickness, 7)
assert.equal(inactive.compiled.layers[0].top.paint.color, "#ff8800")

const unsupported = structuredClone(theme)
unsupported.requires.push("modifier.glow")
const unsupportedResult = context.validateTheme(unsupported)
assert.equal(unsupportedResult.ok, false)
assert.match(JSON.stringify(unsupportedResult.errors), /unsupported capability: modifier\.glow/)

const cyclic = structuredClone(theme)
cyclic.palette.main = { ref: "palette.dark" }
cyclic.palette.dark = { ref: "palette.main" }
cyclic.requires = cyclic.requires.filter(capability => capability !== "color.oklch-derive")
const cyclicResult = context.validateTheme(cyclic)
assert.equal(cyclicResult.ok, false)
assert.match(JSON.stringify(cyclicResult.errors), /cyclic reference/)

const invalidOverride = context.compileTheme(theme, {
    darkWidth: 100
}, systemPalette, { focused: true })
assert.equal(invalidOverride.ok, false)
assert.match(JSON.stringify(invalidOverride.errors), /outside the declared range/)

const invalidDimension = structuredClone(theme)
invalidDimension.layers[0].top.thickness = "huge"
const invalidDimensionResult = context.validateTheme(invalidDimension)
assert.equal(invalidDimensionResult.ok, false)
assert.match(JSON.stringify(invalidDimensionResult.errors), /number required/)

const edgeRectTheme = JSON.parse(fs.readFileSync(
    "tests/fixtures/edge-rect.omadecor.json", "utf8"
))
const edgeRectValidation = context.validateTheme(edgeRectTheme)
assert.equal(edgeRectValidation.ok, true, JSON.stringify(edgeRectValidation.errors))
const edgeRect = context.compileTheme(edgeRectTheme, {
    markerWidth: 64,
    markerColor: "#112233",
    enabled: false,
    mode: "compact"
}, systemPalette, { focused: true })
assert.equal(edgeRect.ok, true, JSON.stringify(edgeRect.errors))
assert.equal(edgeRect.compiled.parameters.markerWidth, 64)
assert.equal(edgeRect.compiled.parameters.enabled, false)
assert.equal(edgeRect.compiled.parameters.mode, "compact")
assert.equal(edgeRect.compiled.layers[1].width, 64)
assert.equal(edgeRect.compiled.layers[1].paint.color, "#112233")

console.log("decoration theme compiler: ok")
