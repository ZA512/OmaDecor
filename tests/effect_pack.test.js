const assert = require("node:assert/strict")
const childProcess = require("node:child_process")
const crypto = require("node:crypto")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")

function loadLibrary(fileName) {
    const source = fs.readFileSync(fileName, "utf8").replace(/^\.pragma library\s*/, "")
    const context = {}
    vm.createContext(context)
    vm.runInContext(source, context)
    return context
}

const validator = loadLibrary("effects/EffectValidator.js")
const metadata = loadLibrary("effects/EffectMetadata.js")
const effectPack = loadLibrary("effects/EffectPack.js")
const manifestPath = "effects/packs/native/simple-dissolve/effect.json"
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"))

const validation = validator.validateEffect(manifest)
assert.equal(validation.ok, true, JSON.stringify(validation.errors))

const entries = metadata.entries(manifest, path.dirname(path.resolve(manifestPath)))
assert.equal(entries.length, 2)
assert.equal(entries[0].effectId, "omadecor/simple-dissolve")
assert.deepEqual(Array.from(entries[0].requires), [
    "shader.progress", "shader.random-seed", "shader.window-texture"
])
assert.ok(entries.some(entry => entry.id === "omadecor/simple-dissolve.open"))
assert.ok(entries.some(entry => entry.id === "omadecor/simple-dissolve.close"))

const pack = effectPack.create({ root: "/pack", compilation: "validated", manifest }, validation, entries)
assert.equal(pack.state, "VALID")
assert.equal(pack.effects.length, 2)

assert.deepEqual(Array.from(validator.missingCapabilities(manifest, [
    "shader.progress", "shader.window-texture"
])), ["shader.random-seed"])

const unsafe = structuredClone(manifest)
unsafe.shaders.open = "../escape.glsl"
assert.equal(validator.validateEffect(unsafe).ok, false)

const unknownProperty = structuredClone(manifest)
unknownProperty.execute = "payload.sh"
assert.equal(validator.validateEffect(unknownProperty).ok, false)

const malformedEnum = structuredClone(manifest)
malformedEnum.parameters = [{ id: "mode", name: "Mode", type: "enum", default: "soft" }]
assert.equal(validator.validateEffect(malformedEnum).ok, false)

const scannerOutput = childProcess.execFileSync("scripts/scan-effect-packs.sh", [
    "--trusted-root", "effects/packs"
], { encoding: "utf8" }).trim().split("\n").filter(Boolean).map(JSON.parse)
const scanned = scannerOutput.find(record => record.ok
    && record.manifest.id === "omadecor/simple-dissolve")
assert.ok(scanned)
assert.equal(scanned.compilation, "validated")
assert.equal(scanned.manifest.preview, "preview.gif")
const preview = fs.readFileSync(path.join(scanned.root, scanned.manifest.preview))
assert.equal(preview.toString("ascii", 0, 6), "GIF89a")
assert.equal(preview.readUInt16LE(6), 360)
assert.equal(preview.readUInt16LE(8), 202)
const previewMasks = require("../scripts/preview-fixture.js")
const previewMask = previewMasks.dissolveMask
for (const [x, y] of [[22, 12], [54, 93], [190, 141], [337, 189]]) {
    assert.equal(previewMask(x, y, 0, false), 0)
    assert.equal(previewMask(x, y, 1, false), 1)
    assert.equal(previewMask(x, y, 0, true), 1)
    assert.equal(previewMask(x, y, 1, true), 0)
}

const niriRecord = scannerOutput.find(record => record.ok
    && record.manifest.id === "liixini/circle")
assert.ok(niriRecord)
assert.equal(niriRecord.compilation, "validated")
assert.equal(niriRecord.manifest.preview, "preview.gif")
const circlePreview = fs.readFileSync(path.join(niriRecord.root, niriRecord.manifest.preview))
assert.equal(circlePreview.toString("ascii", 0, 6), "GIF89a")
assert.equal(circlePreview.readUInt16LE(6), 360)
assert.equal(circlePreview.readUInt16LE(8), 202)
assert.equal(previewMasks.circleMask(180, 101, 0, false), 0)
assert.ok(previewMasks.circleMask(180, 101, 1, false) > 0.99)
assert.ok(previewMasks.circleMask(180, 101, 0, true) > 0.99)
assert.equal(previewMasks.circleMask(180, 101, 1, true), 0)
const niriValidation = validator.validateEffect(niriRecord.manifest)
assert.equal(niriValidation.ok, true, JSON.stringify(niriValidation.errors))
const niriEntries = metadata.entries(niriRecord.manifest, niriRecord.root, niriRecord.artifacts)
assert.equal(niriEntries.length, 2)
for (const entry of niriEntries) {
    assert.equal(entry.sourceFormat, "niri")
    assert.ok(fs.existsSync(entry.path))
    assert.ok(entry.path.includes("/niri-v1/"))
    assert.notEqual(entry.path, path.join(niriRecord.root, niriRecord.manifest.shaders[entry.eventId]))
}
for (const [eventName, expectedHash] of Object.entries({
    open: "84fe1ba21a4893e41a77c0a9acdc723230d7e7da1d70e726d6d6970a0a0e8737",
    close: "66406261c9e540aad6a9e086f5372f38cd67873dfa8fbf8db7818c30775b2bcc"
})) {
    const source = fs.readFileSync("effects/packs/niri/circle/" + eventName + ".glsl")
    assert.equal(crypto.createHash("sha256").update(source).digest("hex"), expectedHash)
}

const bmwRecord = scannerOutput.find(record => record.ok
    && record.manifest.id === "bmw/incinerate")
assert.ok(bmwRecord)
assert.equal(bmwRecord.compilation, "validated")
assert.equal(bmwRecord.manifest.preview, "preview.gif")
const bmwPreview = fs.readFileSync(path.join(bmwRecord.root, bmwRecord.manifest.preview))
assert.equal(bmwPreview.toString("ascii", 0, 6), "GIF89a")
assert.equal(bmwPreview.readUInt16LE(6), 360)
assert.equal(bmwPreview.readUInt16LE(8), 202)
const bmwValidation = validator.validateEffect(bmwRecord.manifest)
assert.equal(bmwValidation.ok, true, JSON.stringify(bmwValidation.errors))
const bmwEntries = metadata.entries(bmwRecord.manifest, bmwRecord.root, bmwRecord.artifacts)
assert.equal(bmwEntries.length, 2)
assert.ok(bmwEntries.every(entry => entry.sourceFormat === "bmw"
    && entry.path.includes("/bmw-incinerate-v1/") && fs.existsSync(entry.path)))
const configuredRecords = childProcess.execFileSync("scripts/scan-effect-packs.sh", [
    "--trusted-root", "effects/packs",
    "--settings-json", JSON.stringify({
        parameters: { "bmw/incinerate": {
            scale: 1.6, turbulence: 0.45, color: "#ff4400"
        } },
        timings: { open: 1.35, close: 0.8 }
    })
], { encoding: "utf8" }).trim().split("\n").filter(Boolean).map(JSON.parse)
const configuredBmw = configuredRecords.find(record => record.ok
    && record.manifest.id === "bmw/incinerate")
assert.ok(configuredBmw)
assert.notEqual(configuredBmw.artifacts.open, bmwRecord.artifacts.open)
assert.notEqual(configuredBmw.artifacts.close, bmwRecord.artifacts.close)
assert.match(fs.readFileSync(configuredBmw.artifacts.open, "utf8"), /const float uDuration = 1\.35;/)
assert.match(fs.readFileSync(configuredBmw.artifacts.close, "utf8"), /const float uDuration = 0\.8;/)
assert.match(fs.readFileSync(configuredBmw.artifacts.open, "utf8"), /const float uScale = 1\.6;/)
assert.match(fs.readFileSync(configuredBmw.artifacts.open, "utf8"), /const float uTurbulence = 0\.45;/)
assert.match(fs.readFileSync(configuredBmw.artifacts.open, "utf8"), /vec3\(255\.0, 68\.0, 0\.0\)/)
const invalidSettingsRecords = childProcess.execFileSync("scripts/scan-effect-packs.sh", [
    "--trusted-root", "effects/packs",
    "--settings-json", JSON.stringify({ parameters: { "bmw/incinerate": { scale: 999 } } })
], { encoding: "utf8" }).trim().split("\n").filter(Boolean).map(JSON.parse)
assert.ok(invalidSettingsRecords.some(record => !record.ok
    && /BMW adaptation failed/.test(record.error)))
const malformedSettings = childProcess.spawnSync("scripts/scan-effect-packs.sh", [
    "--settings-json", "not-json"
], { encoding: "utf8" })
assert.notEqual(malformedSettings.status, 0)
for (const [fileName, expectedHash] of Object.entries({
    "incinerate.frag": "a398ba215e44f1c61b6a311c47646f84915453f470890dd6840a1c2a28063af9",
    "common.glsl": "35dd19b584d190a169b5261efc43d7698703a690e414d9c6527fb0e79f4c8b31"
})) {
    const source = fs.readFileSync("effects/packs/bmw/incinerate/" + fileName)
    assert.equal(crypto.createHash("sha256").update(source).digest("hex"), expectedHash)
}
const invalidParameters = childProcess.spawnSync("scripts/compile-bmw-incinerate.sh", [
    "effects/packs/bmw/incinerate/incinerate.frag",
    "effects/packs/bmw/incinerate/common.glsl", "open", "2", "999", "0.3", "#ffb47f"
], { encoding: "utf8" })
assert.notEqual(invalidParameters.status, 0)
assert.match(invalidParameters.stderr, /parameters are invalid/)

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "omadecor-effect-pack-"))
try {
    const badRoot = path.join(temporaryRoot, "vendor", "symlinked")
    fs.mkdirSync(badRoot, { recursive: true })
    fs.writeFileSync(path.join(badRoot, "effect.json"), JSON.stringify(manifest))
    fs.writeFileSync(path.join(badRoot, "LICENSE"), "test")
    fs.symlinkSync(path.resolve("effects/packs/native/simple-dissolve/open.glsl"), path.join(badRoot, "open.glsl"))
    fs.copyFileSync("effects/packs/native/simple-dissolve/close.glsl", path.join(badRoot, "close.glsl"))

    const unsupportedRoot = path.join(temporaryRoot, "vendor", "unsupported")
    fs.mkdirSync(unsupportedRoot, { recursive: true })
    const unsupported = structuredClone(niriRecord.manifest)
    unsupported.id = "fixture/unsupported"
    fs.writeFileSync(path.join(unsupportedRoot, "effect.json"), JSON.stringify(unsupported))
    fs.writeFileSync(path.join(unsupportedRoot, "LICENSE"), "test")
    fs.copyFileSync("effects/packs/niri/circle/close.glsl", path.join(unsupportedRoot, "close.glsl"))
    fs.writeFileSync(path.join(unsupportedRoot, "open.glsl"),
        fs.readFileSync("effects/packs/niri/circle/open.glsl", "utf8")
        .replace("niri_clamped_progress", "niri_progress"))

    const changedBmwRoot = path.join(temporaryRoot, "vendor", "changed-bmw")
    fs.mkdirSync(changedBmwRoot, { recursive: true })
    fs.writeFileSync(path.join(changedBmwRoot, "effect.json"), JSON.stringify(bmwRecord.manifest))
    fs.copyFileSync("effects/packs/bmw/incinerate/LICENSE", path.join(changedBmwRoot, "LICENSE"))
    fs.copyFileSync("effects/packs/bmw/incinerate/common.glsl", path.join(changedBmwRoot, "common.glsl"))
    fs.copyFileSync("effects/packs/bmw/incinerate/incinerate.frag", path.join(changedBmwRoot, "incinerate.frag"))
    fs.appendFileSync(path.join(changedBmwRoot, "incinerate.frag"), "\n// changed\n")

    const unsafePreviewRoot = path.join(temporaryRoot, "vendor", "preview")
    fs.mkdirSync(unsafePreviewRoot, { recursive: true })
    const unsafePreview = structuredClone(manifest)
    unsafePreview.id = "fixture/preview"
    unsafePreview.preview = "preview.svg"
    fs.writeFileSync(path.join(unsafePreviewRoot, "effect.json"), JSON.stringify(unsafePreview))
    fs.writeFileSync(path.join(unsafePreviewRoot, "LICENSE"), "test")
    fs.copyFileSync("effects/packs/native/simple-dissolve/open.glsl",
        path.join(unsafePreviewRoot, "open.glsl"))
    fs.copyFileSync("effects/packs/native/simple-dissolve/close.glsl",
        path.join(unsafePreviewRoot, "close.glsl"))
    fs.writeFileSync(path.join(unsafePreviewRoot, "preview.svg"), "<svg/>")

    const badOutput = childProcess.execFileSync("scripts/scan-effect-packs.sh", [
        "--root", temporaryRoot
    ], { encoding: "utf8" }).trim().split("\n").filter(Boolean).map(JSON.parse)
    assert.equal(badOutput.length, 4)
    assert.ok(badOutput.every(record => record.ok === false))
    assert.ok(badOutput.some(record => /non-symlinked/.test(record.error)))
    assert.ok(badOutput.some(record => /unsupported Niri symbol: niri_progress/.test(record.error)))
    assert.ok(badOutput.some(record => /source differs from the pinned upstream revision/.test(record.error)))
    assert.ok(badOutput.some(record => /preview must be an image/.test(record.error)))
} finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true })
}

console.log("effect pack v1: ok")
