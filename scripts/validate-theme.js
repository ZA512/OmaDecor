#!/usr/bin/env node

const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const themePath = process.argv[2]
if (!themePath) {
    console.error("Usage: node scripts/validate-theme.js <theme.omadecor.json>")
    process.exit(2)
}

let theme
try {
    theme = JSON.parse(fs.readFileSync(themePath, "utf8"))
} catch (error) {
    console.error(`Invalid JSON: ${error.message}`)
    process.exit(1)
}

const compilerSource = fs.readFileSync(
    path.join(__dirname, "../decorations/ThemeCompiler.js"),
    "utf8"
).replace(/^\.pragma library\s*/, "")
const context = {}
vm.createContext(context)
vm.runInContext(compilerSource, context)

const result = context.validateTheme(theme)
if (!result.ok) {
    for (const error of result.errors)
        console.error(`${error.path}: ${error.message}`)
    process.exit(1)
}

console.log(`${theme.id} ${theme.version}: valid V1 Core theme (${result.drawOperations} draw operations)`)
