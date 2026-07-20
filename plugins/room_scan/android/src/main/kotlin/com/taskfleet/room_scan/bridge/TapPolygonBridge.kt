package com.taskfleet.room_scan.bridge

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Converts a list of tapped XZ floor points (metres) into a
 * FloorPlanScanResult-shaped map suitable for sending across the event
 * channel. Mirrors `Bridge/TapPolygonBridge.swift` on iOS exactly.
 */
object TapPolygonBridge {
    fun toJson(
        polygon: List<FloatArray>,
        captureId: String,
        engine: String
    ): Map<String, Any?> {
        val ccw = ensureCCW(polygon)
        val polyJson = ccw.map { mapOf("x" to it[0].toDouble(), "y" to it[1].toDouble()) }
        val roomId = UUID.randomUUID().toString()
        val room = mapOf(
            "id" to roomId,
            "label" to null,
            "floorPolygonMeters" to polyJson,
            "roomToWorld" to mapOf("x" to 0.0, "y" to 0.0, "yaw" to 0.0)
        )
        return mapOf(
            "captureId" to captureId,
            "engine" to engine,
            "confidence" to 0.5,
            "rooms" to listOf(room),
            "openings" to emptyList<Any>(),
            "objects" to emptyList<Any>(),
            "capturedAt" to iso8601(Date())
        )
    }

    private fun ensureCCW(polygon: List<FloatArray>): List<FloatArray> {
        var sum = 0f
        for (i in polygon.indices) {
            val p = polygon[i]
            val q = polygon[(i + 1) % polygon.size]
            sum += (q[0] - p[0]) * (q[1] + p[1])
        }
        return if (sum > 0) polygon.reversed() else polygon
    }

    private fun iso8601(d: Date): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(d)
    }
}
