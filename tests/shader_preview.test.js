const assert = require("node:assert/strict")
const childProcess = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const fixture = require("../scripts/preview-fixture.js")
const renderer = require("../scripts/render-shader-previews.js")

const width = fixture.windowBox.width
const height = fixture.windowBox.height
const texture = renderer.syntheticTexture()
assert.equal(texture.length, width * height * 4)
assert.equal(texture[3], 255)
assert.deepEqual(Array.from(texture.subarray(0, 3)),
    fixture.syntheticWindow(fixture.windowBox.x, fixture.windowBox.y))

const frame = Buffer.alloc(width * height * 4)
for (let offset = 0; offset < frame.length; offset += 4) {
    frame[offset] = 128 // already premultiplied red
    frame[offset + 3] = 128
}
const ppm = renderer.composeFrame(frame)
const header = Buffer.from(`P6\n${fixture.width} ${fixture.height}\n255\n`)
assert.deepEqual(ppm.subarray(0, header.length), header)
const insideX = fixture.windowBox.x + 10
const insideY = fixture.windowBox.y + 10
const inside = header.length + (insideY * fixture.width + insideX) * 3
const background = [17 + Math.floor(insideY / 26), 24 + Math.floor(insideY / 32),
    38 + Math.floor(insideY / 28)]
assert.equal(ppm[inside], Math.round(128 + background[0] * (1 - 128 / 255)))
assert.equal(ppm[inside + 1], Math.round(background[1] * (1 - 128 / 255)))
const outside = header.length
assert.deepEqual(Array.from(ppm.subarray(outside, outside + 3)), [17, 24, 38])
assert.throws(() => renderer.composeFrame(Buffer.alloc(1)), /truncated/)

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "omadecor-preview-test-"))
try {
    const shaders = path.join(temporary, "shaders")
    const previews = path.join(temporary, "previews")
    fs.mkdirSync(shaders)
    fs.mkdirSync(previews)
    fs.writeFileSync(path.join(shaders, "test-open_open.glsl"), "open shader")
    fs.writeFileSync(path.join(shaders, "test-open_close.glsl"), "close shader")
    const tasks = renderer.externalTasks(shaders, previews)
    assert.equal(tasks.length, 1)
    const previewName = path.basename(tasks[0].target)
    fs.writeFileSync(tasks[0].target, Buffer.from("GIF89a......."))
    const scanner = path.resolve(__dirname, "../scripts/scan-external-shaders.sh")
    const scan = () => childProcess.execFileSync("bash", [scanner, shaders, previews],
        { encoding: "utf8" }).trim().split("\n").map(JSON.parse)
    const records = scan()
    assert.equal(records.length, 2)
    assert(records.every(record => record.preview === previewName))
    fs.writeFileSync(path.join(shaders, "test-open_close.glsl"), "changed shader")
    assert(scan().every(record => record.preview === ""))
    fs.symlinkSync(path.join(shaders, "test-open_close.glsl"),
        path.join(shaders, "linked_close.glsl"))
    fs.writeFileSync(path.join(shaders, "linked_open.glsl"), "open shader")
    assert.equal(renderer.externalTasks(shaders, previews).length, 1)
} finally {
    fs.rmSync(temporary, { recursive: true, force: true })
}

console.log("Shader preview fixture tests passed")
