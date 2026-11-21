package ro.netscan.netscan

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Wi-Fi details for NetScan (SSID, BSSID, signal, band, speed, security). */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val reqCode = 4711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netscan/wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestLocation" -> requestLocation(result)
                    "locationEnabled" -> result.success(locationEnabled())
                    "live" -> {
                        try {
                            result.success(live())
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    "tone" -> {
                        tone(call.argument<Int>("level") ?: 5)
                        result.success(null)
                    }
                    "scan" -> {
                        try {
                            result.success(scanResults(call.argument<Boolean>("trigger") ?: false))
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    "info" -> {
                        try {
                            result.success(wifiInfo())
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasLocation(): Boolean =
        Build.VERSION.SDK_INT < 23 ||
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestLocation(result: MethodChannel.Result) {
        if (hasLocation()) {
            result.success(true)
            return
        }
        pending?.success(false)
        pending = result
        requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            reqCode
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == reqCode) {
            pending?.success(
                grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            pending = null
        }
    }

    private fun locationEnabled(): Boolean {
        val lm = applicationContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled
        else lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ||
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    @Suppress("DEPRECATION")
    private fun wifiInfo(): HashMap<String, Any?> {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val i = wm.connectionInfo
        val d = wm.dhcpInfo
        val map = HashMap<String, Any?>()
        var ssid = i?.ssid?.trim('"')
        if (ssid == "<unknown ssid>" || ssid.isNullOrBlank()) ssid = null
        map["enabled"] = wm.isWifiEnabled
        map["hasLocation"] = hasLocation()
        map["ssid"] = ssid
        map["bssid"] = i?.bssid?.takeIf { it != "02:00:00:00:00:00" }
        map["rssi"] = i?.rssi
        map["linkSpeed"] = i?.linkSpeed
        map["frequency"] = i?.frequency
        if (Build.VERSION.SDK_INT >= 29) {
            map["txSpeed"] = i?.txLinkSpeedMbps
            map["rxSpeed"] = i?.rxLinkSpeedMbps
        }
        if (Build.VERSION.SDK_INT >= 30) map["standard"] = i?.wifiStandard
        if (Build.VERSION.SDK_INT >= 31) map["security"] = i?.currentSecurityType
        map["dns1"] = d?.dns1
        map["dns2"] = d?.dns2
        map["gateway"] = d?.gateway
        map["netmask"] = d?.netmask
        return map
    }

    @Suppress("DEPRECATION")
    private fun scanResults(trigger: Boolean): ArrayList<HashMap<String, Any?>> {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (trigger) {
            try {
                wm.startScan()
            } catch (e: Exception) {
            }
        }
        val out = ArrayList<HashMap<String, Any?>>()
        for (r in wm.scanResults) {
            val m = HashMap<String, Any?>()
            m["ssid"] = r.SSID
            m["bssid"] = r.BSSID
            m["level"] = r.level
            m["frequency"] = r.frequency
            m["caps"] = r.capabilities
            if (Build.VERSION.SDK_INT >= 23) {
                m["width"] = r.channelWidth
                m["center0"] = r.centerFreq0
            }
            if (Build.VERSION.SDK_INT >= 30) m["standard"] = r.wifiStandard
            out.add(m)
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun live(): HashMap<String, Any?> {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val i = wm.connectionInfo
        val m = HashMap<String, Any?>()
        var ssid = i?.ssid?.trim('"')
        if (ssid == "<unknown ssid>" || ssid.isNullOrBlank()) ssid = null
        m["ssid"] = ssid
        m["bssid"] = i?.bssid?.takeIf { it != "02:00:00:00:00:00" }
        m["rssi"] = i?.rssi
        m["frequency"] = i?.frequency
        m["linkSpeed"] = i?.linkSpeed
        return m
    }

    private var toneGen: ToneGenerator? = null
    private val tones = intArrayOf(
        ToneGenerator.TONE_DTMF_1, ToneGenerator.TONE_DTMF_2, ToneGenerator.TONE_DTMF_3,
        ToneGenerator.TONE_DTMF_4, ToneGenerator.TONE_DTMF_5, ToneGenerator.TONE_DTMF_6,
        ToneGenerator.TONE_DTMF_7, ToneGenerator.TONE_DTMF_8, ToneGenerator.TONE_DTMF_9
    )

    private fun tone(level: Int) {
        try {
            if (toneGen == null) toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 60)
            toneGen?.startTone(tones[(level - 1).coerceIn(0, 8)], 80)
        } catch (e: Exception) {
        }
    }

    override fun onDestroy() {
        toneGen?.release()
        toneGen = null
        super.onDestroy()
    }
}
