package com.senkjm.media_manager

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.util.Range
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Read-only video-encoder capability probe for Flutter.
 *
 * Flutter only uses the result to grey out / hide transcode options; whether an
 * encoder actually works is decided by Rust when transcoding starts (it tries to
 * open the encoder for real). So this probe must never be authoritative, must
 * never create a `MediaCodec` instance, and must degrade to "nothing known"
 * instead of throwing when a vendor API misbehaves.
 *
 * Channel: [CHANNEL], method `listEncoders` (optional Boolean argument `force`
 * bypasses the in-process cache). The reply is a JSON string:
 *
 * {
 *   "ok": true,
 *   "sdk": 34,
 *   "encoders": [
 *     { "mime": "video/avc", "name": "c2.qti.avc.encoder", "hardware": true,
 *       "bitrate_modes": ["cbr", "vbr", "cq"], "bitrate_range": [min, max],
 *       "width_range": [min, max], "height_range": [min, max],
 *       "width_alignment": 2, "height_alignment": 2,
 *       "fps_range": [min, max],
 *       "profile_levels": ["avc.profileHigh.level5.1"] }
 *   ]
 * }
 *
 * Keys whose value a device refuses to report are omitted (Dart treats a
 * missing key as "unknown", not as "unsupported"). On a hard failure the reply
 * is `{"ok": false, "error": "…"}` and Flutter keeps every option enabled.
 *
 * Must be registered from [MainActivity.configureFlutterEngine] (see
 * `CodecCapsProbe.register`).
 */
object CodecCapsProbe {
    const val CHANNEL = "wdmm/codec_caps"

    /** Cached JSON for the current process; probing costs a few dozen ms. */
    @Volatile
    private var cachedJson: String? = null

    fun register(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "listEncoders" -> {
                    val force = call.arguments as? Boolean ?: false
                    result.success(probeJson(force))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Returns the capability JSON, reusing the process cache unless [force]. */
    fun probeJson(force: Boolean = false): String {
        if (!force) {
            val hit = cachedJson
            if (hit != null) return hit
        }
        val fresh = probe()
        cachedJson = fresh
        return fresh
    }

    /** Runs the probe synchronously (pure queries, no codec instances). */
    fun probe(): String =
        try {
            val encoders = JSONArray()
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            for (info in list.codecInfos) {
                if (!info.isEncoder) continue
                // API 29+ exposes alias entries pointing at the same encoder.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                    safe { info.isAlias } == true
                ) {
                    continue
                }
                val types = safe { info.supportedTypes } ?: continue
                for (mime in types) {
                    if (mime == null || !mime.startsWith("video/")) continue
                    val entry = safe { probeType(info, mime) } ?: continue
                    encoders.put(entry)
                }
            }
            JSONObject()
                .put("ok", true)
                .put("sdk", Build.VERSION.SDK_INT)
                .put("encoders", encoders)
                .toString()
        } catch (t: Throwable) {
            JSONObject()
                .put("ok", false)
                .put("error", "${t.javaClass.simpleName}: ${t.message}")
                .toString()
        }

    // ── per (codec, mime) probing ────────────────────────────────────────────

    private fun probeType(info: MediaCodecInfo, mime: String): JSONObject {
        val caps = info.getCapabilitiesForType(mime)
        val entry = JSONObject()
        entry.put("mime", mime)
        entry.put("name", info.name.orEmpty())
        entry.put("hardware", isHardware(info))

        // Encoder capabilities (bitrate control) — absent for some mimes.
        safe { caps.encoderCapabilities }?.let { encoderCaps ->
            val modes = JSONArray()
            if (safe { encoderCaps.isBitrateModeSupported(
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR,
                ) } == true
            ) {
                modes.put("cbr")
            }
            if (safe { encoderCaps.isBitrateModeSupported(
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
                ) } == true
            ) {
                modes.put("vbr")
            }
            if (safe { encoderCaps.isBitrateModeSupported(
                    MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CQ,
                ) } == true
            ) {
                modes.put("cq")
            }
            // Empty list means "every query threw": report nothing rather than
            // "no mode supported", so Dart keeps the UI permissive.
            if (modes.length() > 0) entry.put("bitrate_modes", modes)
        }

        // Video capabilities (bitrate range / resolution / fps). The bitrate
        // range lives on VideoCapabilities, not EncoderCapabilities.
        safe { caps.videoCapabilities }?.let { videoCaps ->
            putRange(entry, "bitrate_range", safe { videoCaps.bitrateRange })
            putRange(entry, "width_range", safe { videoCaps.supportedWidths })
            putRange(entry, "height_range", safe { videoCaps.supportedHeights })
            safe { videoCaps.widthAlignment }?.let {
                entry.put("width_alignment", it)
            }
            safe { videoCaps.heightAlignment }?.let {
                entry.put("height_alignment", it)
            }
            putRange(entry, "fps_range", safe { videoCaps.supportedFrameRates })
        }

        // Profile/Level pairs, human readable for the settings screen.
        val levels = JSONArray()
        safe { caps.profileLevels }?.forEach { profileLevel ->
            val label = safe {
                profileLevelLabel(mime, profileLevel.profile, profileLevel.level)
            } ?: "profile${profileLevel.profile}.level${profileLevel.level}"
            levels.put(label)
        }
        entry.put("profile_levels", levels)
        return entry
    }

    /**
     * Hardware acceleration flag. `isHardwareAccelerated()` is API 29+; below
     * that fall back to the well-known naming convention (AOSP software
     * encoders are `OMX.google.*` / `c2.android.*`).
     */
    private fun isHardware(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            safe { info.isHardwareAccelerated }?.let { return it }
        }
        val name = info.name.orEmpty()
        if (name.isEmpty()) return false
        return !name.startsWith("OMX.google.") && !name.startsWith("c2.android.")
    }

    private fun putRange(obj: JSONObject, key: String, range: Range<*>?) {
        if (range == null) return
        val lower = (range.lower as? Number)?.toDouble() ?: return
        val upper = (range.upper as? Number)?.toDouble() ?: return
        obj.put(key, JSONArray().put(number(lower)).put(number(upper)))
    }

    /** Keeps integer ranges integer in JSON (JSONObject has no unsigned int). */
    private fun number(value: Double): Any =
        if (value == Math.floor(value) && value <= Int.MAX_VALUE) {
            value.toLong()
        } else {
            value
        }

    // ── profile / level labels ───────────────────────────────────────────────

    private fun profileLevelLabel(mime: String, profile: Int, level: Int): String =
        when (mime) {
            "video/avc" -> "avc.profile${avcProfileName(profile)}.level${avcLevelName(level)}"
            "video/hevc" -> "hevc.profile${hevcProfileName(profile)}.level${hevcLevelName(level)}"
            "video/mp4v-es" -> "mpeg4.profile${mpeg4ProfileName(profile)}.level${mpeg4LevelName(level)}"
            else -> "profile$profile.level$level"
        }

    private fun avcProfileName(profile: Int): String =
        when (profile) {
            MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline -> "Baseline"
            MediaCodecInfo.CodecProfileLevel.AVCProfileMain -> "Main"
            MediaCodecInfo.CodecProfileLevel.AVCProfileExtended -> "Extended"
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh -> "High"
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh10 -> "High10"
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh422 -> "High422"
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh444 -> "High444"
            MediaCodecInfo.CodecProfileLevel.AVCProfileConstrainedBaseline -> "ConstrainedBaseline"
            MediaCodecInfo.CodecProfileLevel.AVCProfileConstrainedHigh -> "ConstrainedHigh"
            else -> "$profile"
        }

    private fun avcLevelName(level: Int): String =
        when (level) {
            MediaCodecInfo.CodecProfileLevel.AVCLevel1 -> "1"
            MediaCodecInfo.CodecProfileLevel.AVCLevel1b -> "1b"
            MediaCodecInfo.CodecProfileLevel.AVCLevel11 -> "1.1"
            MediaCodecInfo.CodecProfileLevel.AVCLevel12 -> "1.2"
            MediaCodecInfo.CodecProfileLevel.AVCLevel13 -> "1.3"
            MediaCodecInfo.CodecProfileLevel.AVCLevel2 -> "2"
            MediaCodecInfo.CodecProfileLevel.AVCLevel21 -> "2.1"
            MediaCodecInfo.CodecProfileLevel.AVCLevel22 -> "2.2"
            MediaCodecInfo.CodecProfileLevel.AVCLevel3 -> "3"
            MediaCodecInfo.CodecProfileLevel.AVCLevel31 -> "3.1"
            MediaCodecInfo.CodecProfileLevel.AVCLevel32 -> "3.2"
            MediaCodecInfo.CodecProfileLevel.AVCLevel4 -> "4"
            MediaCodecInfo.CodecProfileLevel.AVCLevel41 -> "4.1"
            MediaCodecInfo.CodecProfileLevel.AVCLevel42 -> "4.2"
            MediaCodecInfo.CodecProfileLevel.AVCLevel5 -> "5"
            MediaCodecInfo.CodecProfileLevel.AVCLevel51 -> "5.1"
            MediaCodecInfo.CodecProfileLevel.AVCLevel52 -> "5.2"
            MediaCodecInfo.CodecProfileLevel.AVCLevel6 -> "6"
            MediaCodecInfo.CodecProfileLevel.AVCLevel61 -> "6.1"
            MediaCodecInfo.CodecProfileLevel.AVCLevel62 -> "6.2"
            else -> "$level"
        }

    private fun hevcProfileName(profile: Int): String =
        when (profile) {
            MediaCodecInfo.CodecProfileLevel.HEVCProfileMain -> "Main"
            MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 -> "Main10"
            MediaCodecInfo.CodecProfileLevel.HEVCProfileMainStill -> "MainStill"
            MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 -> "Main10HDR10"
            MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus -> "Main10HDR10Plus"
            else -> "$profile"
        }

    private fun hevcLevelName(level: Int): String =
        when (level) {
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel1 -> "1"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel2 -> "2"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel21 -> "2.1"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel3 -> "3"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel31 -> "3.1"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel4 -> "4"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel41 -> "4.1"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel5 -> "5"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel51 -> "5.1"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel52 -> "5.2"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel6 -> "6"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel61 -> "6.1"
            MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel62 -> "6.2"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel1 -> "1(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel2 -> "2(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel21 -> "2.1(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel3 -> "3(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel31 -> "3.1(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel4 -> "4(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel41 -> "4.1(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel5 -> "5(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel51 -> "5.1(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel52 -> "5.2(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel6 -> "6(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel61 -> "6.1(H)"
            MediaCodecInfo.CodecProfileLevel.HEVCHighTierLevel62 -> "6.2(H)"
            else -> "$level"
        }

    private fun mpeg4ProfileName(profile: Int): String =
        when (profile) {
            MediaCodecInfo.CodecProfileLevel.MPEG4ProfileSimple -> "Simple"
            MediaCodecInfo.CodecProfileLevel.MPEG4ProfileSimpleScalable -> "SimpleScalable"
            MediaCodecInfo.CodecProfileLevel.MPEG4ProfileCore -> "Core"
            MediaCodecInfo.CodecProfileLevel.MPEG4ProfileMain -> "Main"
            MediaCodecInfo.CodecProfileLevel.MPEG4ProfileAdvancedSimple -> "AdvancedSimple"
            else -> "$profile"
        }

    private fun mpeg4LevelName(level: Int): String =
        when (level) {
            MediaCodecInfo.CodecProfileLevel.MPEG4Level0 -> "0"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level0b -> "0b"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level1 -> "1"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level2 -> "2"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level3 -> "3"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level3b -> "3b"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level4 -> "4"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level4a -> "4a"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level5 -> "5"
            MediaCodecInfo.CodecProfileLevel.MPEG4Level6 -> "6"
            else -> "$level"
        }

    /** Swallows vendor-specific `MediaCodecInfo` exceptions query by query. */
    private inline fun <T : Any> safe(block: () -> T): T? =
        try {
            block()
        } catch (t: Throwable) {
            null
        }
}
