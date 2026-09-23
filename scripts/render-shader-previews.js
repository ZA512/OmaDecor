#!/usr/bin/env node

// Batch-render HWS GLSL offscreen. External packs are opt-in and stay in cache.
// A separate process and timeout contain ordinary failures, not GPU hangs.
const childProcess = require("node:child_process")
const crypto = require("node:crypto")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const fixture = require("./preview-fixture.js")

const repoRoot = path.resolve(__dirname, "..")
const packRoot = path.join(repoRoot, "effects/packs")
const packIds = ["omadecor/simple-dissolve", "liixini/circle", "bmw/incinerate"]
const width = fixture.windowBox.width
const height = fixture.windowBox.height
const canvasWidth = fixture.width
const canvasHeight = fixture.height
const steps = 13

function run(command, args, timeoutMs) {
    const result = childProcess.spawnSync(command, args, {
        encoding: "utf8", timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024
    })
    if (result.error || result.status !== 0)
        throw new Error(`${command} failed: ${result.stderr || result.error || result.signal}`)
    return result.stdout.trim()
}

function syntheticTexture() {
    const pixels = Buffer.alloc(width * height * 4)
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const color = fixture.syntheticWindow(x + fixture.windowBox.x,
                y + fixture.windowBox.y)
            const offset = (y * width + x) * 4
            pixels[offset] = color[0]
            pixels[offset + 1] = color[1]
            pixels[offset + 2] = color[2]
            pixels[offset + 3] = 255
        }
    }
    return pixels
}

function composeFrame(rgba) {
    if (rgba.length !== width * height * 4)
        throw new Error("renderer returned a truncated frame")
    const header = Buffer.from(`P6\n${canvasWidth} ${canvasHeight}\n255\n`)
    const pixels = Buffer.alloc(canvasWidth * canvasHeight * 3)
    for (let y = 0; y < canvasHeight; y++) {
        for (let x = 0; x < canvasWidth; x++) {
            const background = [17 + Math.floor(y / 26), 24 + Math.floor(y / 32),
                38 + Math.floor(y / 28)]
            const localX = x - fixture.windowBox.x
            const localY = y - fixture.windowBox.y
            const inside = localX >= 0 && localX < width && localY >= 0 && localY < height
            const offset = (y * canvasWidth + x) * 3
            if (!inside) {
                for (let channel = 0; channel < 3; channel++)
                    pixels[offset + channel] = background[channel]
                continue
            }
            const source = (localY * width + localX) * 4
            const alpha = rgba[source + 3] / 255
            for (let channel = 0; channel < 3; channel++)
                pixels[offset + channel] = Math.min(255, Math.round(
                    rgba[source + channel] + background[channel] * (1 - alpha)))
        }
    }
    return Buffer.concat([header, pixels])
}

function sourcePath(record, eventName) {
    return record.artifacts && record.artifacts[eventName]
        ? record.artifacts[eventName]
        : path.join(record.root, record.manifest.shaders[eventName])
}

function externalTasks(shaderDir, previewDir) {
    if (!fs.existsSync(shaderDir) || !fs.statSync(shaderDir).isDirectory())
        throw new Error("external Hyprland-Shader pack is not installed")
    const names = fs.readdirSync(shaderDir)
    const bases = new Set()
    for (const name of names) {
        const match = name.match(/^([a-z0-9][a-z0-9-]{0,63})_(open|close)\.glsl$/)
        if (match) bases.add(match[1])
    }
    const tasks = []
    for (const base of [...bases].sort()) {
        const open = path.join(shaderDir, base + "_open.glsl")
        const close = path.join(shaderDir, base + "_close.glsl")
        if (![open, close].every(file => fs.existsSync(file)
                && fs.lstatSync(file).isFile() && fs.statSync(file).size <= 512 * 1024)) continue
        const hash = crypto.createHash("sha256")
            .update(fs.readFileSync(open)).update(fs.readFileSync(close))
            .digest("hex").slice(0, 16)
        tasks.push({ id: "hyprland-shader/" + base, open, close,
            target: path.join(previewDir, `${base}-${hash}.gif`), external: true })
    }
    return tasks
}

function renderPair(task, renderer, temporary) {
    const localDirectory = path.join(temporary, task.id.replace(/\//g, "-"))
    fs.mkdirSync(localDirectory)
    if (task.external) {
        run("glslangValidator", ["-S", "frag", task.open], 10000)
        run("glslangValidator", ["-S", "frag", task.close], 10000)
    }
    run(renderer, [task.open, task.close,
        path.join(temporary, "texture.rgba"), localDirectory,
        String(width), String(height), String(steps)], task.external ? 10000 : 45000)
    const eventFrames = {}
    for (const eventName of ["open", "close"]) {
        eventFrames[eventName] = []
        for (let index = 0; index < steps; index++) {
            const frameName = `${eventName}-${String(index).padStart(2, "0")}`
            const rgba = fs.readFileSync(path.join(localDirectory, frameName + ".rgba"))
            const framePath = path.join(localDirectory, frameName + ".ppm")
            fs.writeFileSync(framePath, composeFrame(rgba))
            eventFrames[eventName].push(framePath)
        }
    }
    const sequence = [
        ...eventFrames.open, ...Array(5).fill(eventFrames.open[steps - 1]),
        ...eventFrames.close, ...Array(5).fill(eventFrames.close[steps - 1])
    ]
    const candidate = path.join(localDirectory, "preview.gif")
    run("magick", ["-delay", "5", "-loop", "0", ...sequence,
        "-colors", "128", "-layers", "Optimize", candidate], task.external ? 15000 : 45000)
    const size = fs.statSync(candidate).size
    if (size <= 0 || size > 8 * 1024 * 1024)
        throw new Error("generated preview is empty or exceeds 8 MiB")
    if (fs.readFileSync(candidate).toString("ascii", 0, 6) !== "GIF89a")
        throw new Error("generated preview is not a GIF")
    fs.mkdirSync(path.dirname(task.target), { recursive: true })
    const temporaryTarget = path.join(path.dirname(task.target), `.preview-${process.pid}.gif`)
    try {
        fs.copyFileSync(candidate, temporaryTarget, fs.constants.COPYFILE_EXCL)
        fs.renameSync(temporaryTarget, task.target)
    } finally {
        if (fs.existsSync(temporaryTarget)) fs.unlinkSync(temporaryTarget)
    }
    process.stdout.write(`${task.id}: ${size} bytes -> ${task.target}\n`)
}

function main() {
    const requested = process.argv[2] || "all"
    const external = requested === "external" || requested.startsWith("external:")
    if (process.argv.length > 3 || (!external && requested !== "all" && !packIds.includes(requested))
            || (requested.startsWith("external:")
                && !/^[a-z0-9][a-z0-9-]{0,63}$/.test(requested.slice(9))))
        throw new Error("usage: node scripts/render-shader-previews.js [all|PACK_ID|external|external:NAME]")
    let tasks
    if (external) {
        const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local/share")
        const cacheHome = process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache")
        const shaderDir = path.join(dataHome, "omadecor/shader-packs/hyprland-shader/shaders")
        const previewDir = path.join(cacheHome, "omadecor/effects/previews/hyprland-shader")
        tasks = externalTasks(shaderDir, previewDir)
        if (requested.startsWith("external:"))
            tasks = tasks.filter(task => task.id === "hyprland-shader/" + requested.slice(9))
        if (tasks.length === 0) throw new Error("no complete external shader pair found")
        process.stdout.write(`Opt-in GPU render of ${tasks.length} external shader pair(s).\n`)
    } else {
        const selected = requested === "all" ? packIds : [requested]
        const scanOutput = run(path.join(repoRoot, "scripts/scan-effect-packs.sh"),
            ["--trusted-root", packRoot], 45000)
        const records = scanOutput.split("\n").filter(Boolean).map(JSON.parse)
        const trustedRoot = fs.realpathSync(packRoot)
        tasks = selected.map(effectId => {
            const record = records.find(entry => entry.ok === true && entry.manifest.id === effectId)
            if (!record || !record.manifest.compatibility.events.includes("open")
                    || !record.manifest.compatibility.events.includes("close")
                    || !fs.realpathSync(record.root).startsWith(trustedRoot + path.sep))
                throw new Error(effectId + ": trusted open/close pack unavailable")
            return { id: effectId, open: sourcePath(record, "open"),
                close: sourcePath(record, "close"),
                target: path.join(record.root, "preview.gif"), external: false }
        })
    }
    const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "omadecor-shader-preview-"))
    try {
        fs.writeFileSync(path.join(temporary, "texture.rgba"), syntheticTexture())
        const flags = run("pkg-config", ["--cflags", "--libs", "egl", "glesv2"], 10000)
            .split(/\s+/).filter(Boolean)
        const renderer = path.join(temporary, "preview-renderer")
        run("g++", ["-std=c++20", "-O2", "-Wall", "-Wextra", "-Wpedantic",
            path.join(__dirname, "preview-renderer.cpp"), "-o", renderer, ...flags], 30000)
        let failures = 0
        let skipped = 0
        for (const task of tasks) {
            if (task.external && fs.existsSync(task.target)) {
                skipped++
                continue
            }
            try {
                renderPair(task, renderer, temporary)
            } catch (error) {
                process.stderr.write(`${task.id}: ${error.message}\n`)
                failures++
            }
        }
        process.stdout.write(`Preview batch: ${tasks.length - failures - skipped} generated, `
            + `${skipped} cached, ${failures} failed.\n`)
        if (failures > 0) process.exitCode = 1
    } finally {
        fs.rmSync(temporary, { recursive: true, force: true })
    }
}

if (require.main === module) {
    try { main() } catch (error) {
        process.stderr.write(error.message + "\n")
        process.exitCode = 1
    }
}

module.exports = { syntheticTexture, composeFrame, externalTasks }
