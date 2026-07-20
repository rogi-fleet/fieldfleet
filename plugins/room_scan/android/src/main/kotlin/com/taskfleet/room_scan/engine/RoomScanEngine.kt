package com.taskfleet.room_scan.engine

import com.taskfleet.room_scan.RoomScanPlatformView

/**
 * Native-engine lifecycle contract. Mirrors `protocol RoomScanEngine` on iOS.
 *
 * Implementations own the AR session and the surface view. [attach] binds
 * the engine to the Flutter platform view; [detach] releases the view binding
 * without tearing down the session (so the engine can survive a brief view
 * recreation).
 */
interface RoomScanEngine {
    fun attach(view: RoomScanPlatformView)
    fun detach()
    fun start()
    fun finish()
    fun stop()
    fun resume()
    fun cancel()

    /**
     * Pop the most recent tap-based corner. Returns the new remaining
     * count, or -1 if the engine doesn't track discrete taps (RoomPlan
     * has no equivalent on Android — every supported engine here is
     * tap-based, but the contract keeps parity with iOS).
     */
    fun undoLastTap(): Int = -1
}
