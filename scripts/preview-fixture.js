// Synthetic window and CPU reference masks for the trusted preview renderer.
// No user window or compositor capture is involved.
const width = 360
const height = 202
const windowBox = { x: 22, y: 12, width: 316, height: 178 }
const seed = 0.41

function clamp(value) {
    return Math.max(0, Math.min(1, value))
}

function smoothstep(start, end, value) {
    const t = clamp((value - start) / (end - start))
    return t * t * (3 - 2 * t)
}

function dissolveMask(x, y, progress, closing) {
    const u = (x - windowBox.x) / windowBox.width
    const v = (y - windowBox.y) / windowBox.height
    const cellX = Math.floor(u * 72)
    const cellY = Math.floor(v * 42)
    const shiftedX = cellX + seed * 97
    const shiftedY = cellY + seed * 97
    const noise = Math.sin(shiftedX * 127.1 + shiftedY * 311.7) * 43758.5453
    const threshold = noise - Math.floor(noise)
    const eased = smoothstep(0, 1, progress)
    const amount = closing ? 1.08 - 1.16 * eased : -0.08 + 1.16 * eased
    return smoothstep(threshold - 0.08, threshold + 0.08, amount)
}

function circleMask(x, y, progress, closing) {
    const u = (x - windowBox.x) / windowBox.width
    const v = (y - windowBox.y) / windowBox.height
    const centerX = 0.5 + (seed - 0.5) * 0.15
    const centerY = 0.5 + (seed * 0.7 - 0.35) * 0.15
    const distance = Math.SQRT2 * Math.hypot(centerX - u, centerY - v)
    const amount = closing ? 1 - clamp(progress) : clamp(progress)
    return 1 - smoothstep(-0.3, 0, distance - amount * 1.3)
}

function syntheticWindow(x, y) {
    const localX = x - windowBox.x
    const localY = y - windowBox.y
    if (localX < 2 || localY < 2 || localX >= windowBox.width - 2
            || localY >= windowBox.height - 2)
        return [85, 105, 137]
    if (localY < 30) {
        const dot = (localX - 17) ** 2 + (localY - 15) ** 2 < 16
            || (localX - 31) ** 2 + (localY - 15) ** 2 < 16
            || (localX - 45) ** 2 + (localY - 15) ** 2 < 16
        return dot ? [109, 211, 238] : [36, 48, 69]
    }
    if (localX < 72) {
        const line = localY > 46 && localY < 51 && localX > 14 && localX < 57
            || localY > 65 && localY < 70 && localX > 14 && localX < 49
            || localY > 84 && localY < 89 && localX > 14 && localX < 62
        return line ? [96, 151, 183] : [28, 39, 58]
    }
    if (localX > 90 && localX < 190 && localY > 49 && localY < 98)
        return [55, 129 + Math.floor(localY / 8), 161]
    if (localX > 202 && localX < 291 && localY > 49 && localY < 98)
        return [99, 83, 171]
    if (localX > 90 && localX < 291 && localY > 110 && localY < 151) {
        const curve = 130 + Math.sin(localX / 17) * 8
        return Math.abs(localY - curve) < 2 ? [91, 216, 212] : [40, 57, 80]
    }
    return [34, 47, 68]
}

module.exports = { dissolveMask, circleMask, syntheticWindow, windowBox, width, height }
