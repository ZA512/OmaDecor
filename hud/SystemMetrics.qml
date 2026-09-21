import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool enabled: false
    property int intervalMs: 2000

    property bool cpuAvailable: false
    property bool memoryAvailable: false
    property bool networkAvailable: false
    property real cpuPercent: 0
    property real memoryPercent: 0
    property double memoryUsedBytes: 0
    property double memoryTotalBytes: 0
    property double networkReceiveBytesPerSecond: 0
    property double networkTransmitBytesPerSecond: 0
    property string lastError: ""
    property double lastUpdatedAtMs: 0

    property double previousCpuTotal: -1
    property double previousCpuIdle: -1
    property double previousNetworkReceive: -1
    property double previousNetworkTransmit: -1
    property double previousNetworkAtMs: -1

    function parseCpu(rawText) {
        var line = String(rawText || "").split("\n")[0] || ""
        var fields = line.trim().split(/\s+/)
        if (fields.length < 6 || fields[0] !== "cpu") {
            root.cpuAvailable = false
            return
        }

        var total = 0
        for (var index = 1; index < fields.length; index++) {
            var value = Number(fields[index])
            if (isFinite(value)) total += value
        }
        var idle = Number(fields[4] || 0) + Number(fields[5] || 0)
        if (root.previousCpuTotal >= 0 && total > root.previousCpuTotal) {
            var deltaTotal = total - root.previousCpuTotal
            var deltaIdle = idle - root.previousCpuIdle
            root.cpuPercent = Math.max(0, Math.min(100, 100 * (deltaTotal - deltaIdle) / deltaTotal))
            root.cpuAvailable = true
        }
        root.previousCpuTotal = total
        root.previousCpuIdle = idle
        root.markUpdated()
    }

    function parseMemory(rawText) {
        var lines = String(rawText || "").split("\n")
        var totalKiB = 0
        var availableKiB = 0
        for (var index = 0; index < lines.length; index++) {
            var match = lines[index].match(/^(MemTotal|MemAvailable):\s+(\d+)\s+kB$/)
            if (!match) continue
            if (match[1] === "MemTotal") totalKiB = Number(match[2])
            else availableKiB = Number(match[2])
        }
        if (totalKiB <= 0 || availableKiB < 0) {
            root.memoryAvailable = false
            return
        }
        root.memoryTotalBytes = totalKiB * 1024
        root.memoryUsedBytes = Math.max(0, (totalKiB - availableKiB) * 1024)
        root.memoryPercent = Math.max(0, Math.min(100, root.memoryUsedBytes * 100 / root.memoryTotalBytes))
        root.memoryAvailable = true
        root.markUpdated()
    }

    function parseNetwork(rawText) {
        var lines = String(rawText || "").split("\n")
        var received = 0
        var transmitted = 0
        var found = false
        for (var index = 2; index < lines.length; index++) {
            var parts = lines[index].split(":")
            if (parts.length !== 2) continue
            var interfaceName = parts[0].trim()
            if (interfaceName === "" || interfaceName === "lo") continue
            var fields = parts[1].trim().split(/\s+/)
            if (fields.length < 9) continue
            var rx = Number(fields[0])
            var tx = Number(fields[8])
            if (!isFinite(rx) || !isFinite(tx)) continue
            received += rx
            transmitted += tx
            found = true
        }

        var now = Date.now()
        if (found && root.previousNetworkAtMs > 0 && now > root.previousNetworkAtMs) {
            var seconds = (now - root.previousNetworkAtMs) / 1000
            root.networkReceiveBytesPerSecond = Math.max(0, (received - root.previousNetworkReceive) / seconds)
            root.networkTransmitBytesPerSecond = Math.max(0, (transmitted - root.previousNetworkTransmit) / seconds)
            root.networkAvailable = true
        }
        root.previousNetworkReceive = received
        root.previousNetworkTransmit = transmitted
        root.previousNetworkAtMs = now
        root.markUpdated()
    }

    function markUpdated() {
        root.lastUpdatedAtMs = Date.now()
        root.lastError = ""
    }

    function refresh() {
        if (!root.enabled) return
        cpuFile.reload()
        memoryFile.reload()
        networkFile.reload()
    }

    function humanRate(bytesPerSecond) {
        var value = Math.max(0, Number(bytesPerSecond) || 0)
        if (value >= 1024 * 1024 * 1024) return (value / (1024 * 1024 * 1024)).toFixed(1) + " GB/s"
        if (value >= 1024 * 1024) return (value / (1024 * 1024)).toFixed(1) + " MB/s"
        if (value >= 1024) return (value / 1024).toFixed(1) + " KB/s"
        return Math.round(value) + " B/s"
    }

    function diagnostics() {
        return {
            intervalMs: root.intervalMs,
            lastUpdatedAtMs: root.lastUpdatedAtMs,
            error: root.lastError,
            cpu: { available: root.cpuAvailable, percent: root.cpuPercent },
            memory: {
                available: root.memoryAvailable,
                percent: root.memoryPercent,
                usedBytes: root.memoryUsedBytes,
                totalBytes: root.memoryTotalBytes
            },
            network: {
                available: root.networkAvailable,
                receiveBytesPerSecond: root.networkReceiveBytesPerSecond,
                transmitBytesPerSecond: root.networkTransmitBytesPerSecond
            }
        }
    }

    Timer {
        interval: root.intervalMs
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    FileView {
        id: cpuFile
        path: "/proc/stat"
        watchChanges: false
        printErrors: false
        onLoaded: root.parseCpu(text())
        onLoadFailed: function() {
            root.cpuAvailable = false
            root.lastError = "CPU metrics unavailable"
        }
    }

    FileView {
        id: memoryFile
        path: "/proc/meminfo"
        watchChanges: false
        printErrors: false
        onLoaded: root.parseMemory(text())
        onLoadFailed: function() {
            root.memoryAvailable = false
            root.lastError = "Memory metrics unavailable"
        }
    }

    FileView {
        id: networkFile
        path: "/proc/net/dev"
        watchChanges: false
        printErrors: false
        onLoaded: root.parseNetwork(text())
        onLoadFailed: function() {
            root.networkAvailable = false
            root.lastError = "Network metrics unavailable"
        }
    }
}
