package ro.netscan.netscan

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.LocationManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.telephony.CellIdentityNr
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrengthCdma
import android.telephony.CellSignalStrengthGsm
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.CellSignalStrengthTdscdma
import android.telephony.CellSignalStrengthWcdma
import android.telephony.TelephonyManager
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
                    "connection" -> {
                        try {
                            result.success(connection())
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    "cell" -> {
                        try {
                            result.success(cell())
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    "cellinfo" -> {
                        try {
                            result.success(cellInfo())
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    "compassStart" -> result.success(compassStart())
                    "compassStop" -> {
                        compassStop()
                        result.success(null)
                    }
                    "heading" -> result.success(azimuth)
                    "steps" -> result.success(steps)
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

    private var sensorManager: SensorManager? = null
    private var azimuth: Double? = null
    private val compassListener = object : SensorEventListener {
        override fun onSensorChanged(e: SensorEvent) {
            val rot = FloatArray(9)
            SensorManager.getRotationMatrixFromVector(rot, e.values)
            val o = FloatArray(3)
            SensorManager.getOrientation(rot, o)
            // Phone held upright in front of you: remap so the back camera axis is "forward".
            if (Math.abs(o[1]) > Math.toRadians(45.0)) {
                val r2 = FloatArray(9)
                SensorManager.remapCoordinateSystem(rot, SensorManager.AXIS_X, SensorManager.AXIS_Z, r2)
                SensorManager.getOrientation(r2, o)
            }
            azimuth = (Math.toDegrees(o[0].toDouble()) + 360.0) % 360.0
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    // Step detector from the accelerometer (no permission needed).
    // Adaptive: a slow baseline removes gravity / how the phone is held,
    // a fast filter follows the bounce of each step; peaks above a threshold
    // that adapts to how hard you walk count as steps.
    private var steps = 0
    private var lastStepAt = 0L
    private var baseline = 9.81
    private var fast = 0.0
    private var prev = 0.0
    private var rising = false
    private var peakAvg = 1.6
    private val stepListener = object : SensorEventListener {
        override fun onSensorChanged(e: SensorEvent) {
            val x = e.values[0].toDouble()
            val y = e.values[1].toDouble()
            val z = e.values[2].toDouble()
            val mag = Math.sqrt(x * x + y * y + z * z)
            baseline = baseline * 0.98 + mag * 0.02
            fast = fast * 0.7 + (mag - baseline) * 0.3
            val now = System.currentTimeMillis()
            if (fast > prev) {
                rising = true
            } else if (rising && fast < prev) {
                // local peak at `prev`
                rising = false
                val threshold = Math.max(0.9, peakAvg * 0.55)
                val dt = now - lastStepAt
                if (prev > threshold && dt > 280) {
                    steps++
                    lastStepAt = now
                    peakAvg = peakAvg * 0.8 + Math.min(prev, 6.0) * 0.2
                }
            }
            prev = fast
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    private fun compassStart(): Boolean {
        val sm = applicationContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        // Gyro-based rotation (no magnetometer): not disturbed by metal indoors.
        // Not north-referenced, which is fine for a relative map.
        val sensor = sm.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
            ?: sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: sm.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
            ?: return false
        sm.registerListener(compassListener, sensor, SensorManager.SENSOR_DELAY_GAME)
        sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let {
            sm.registerListener(stepListener, it, SensorManager.SENSOR_DELAY_GAME)
        }
        steps = 0
        sensorManager = sm
        return true
    }

    private fun compassStop() {
        sensorManager?.unregisterListener(compassListener)
        sensorManager?.unregisterListener(stepListener)
        sensorManager = null
        azimuth = null
    }

    override fun onDestroy() {
        compassStop()
        toneGen?.release()
        toneGen = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun connection(): HashMap<String, Any?> {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        var type = "none"
        if (Build.VERSION.SDK_INT >= 23) {
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
            if (caps != null) {
                type = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                    else -> "other"
                }
            }
        } else {
            val ni = cm.activeNetworkInfo
            if (ni != null && ni.isConnected) {
                type = when (ni.type) {
                    ConnectivityManager.TYPE_WIFI -> "wifi"
                    ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                    ConnectivityManager.TYPE_MOBILE -> "cellular"
                    else -> "other"
                }
            }
        }
        val m = HashMap<String, Any?>()
        m["type"] = type
        try {
            val tm = applicationContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            m["operator"] = tm.networkOperatorName
        } catch (e: Exception) {
        }
        return m
    }

    private fun cell(): HashMap<String, Any?> {
        val m = HashMap<String, Any?>()
        val tm = applicationContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        m["operator"] = tm.networkOperatorName
        if (Build.VERSION.SDK_INT >= 29) {
            val list = tm.signalStrength?.cellSignalStrengths ?: emptyList()
            val best = list.firstOrNull { it is CellSignalStrengthNr }
                ?: list.firstOrNull { it is CellSignalStrengthLte }
                ?: list.firstOrNull()
            if (best != null) {
                m["dbm"] = best.dbm
                m["level"] = best.level
                m["gen"] = when (best) {
                    is CellSignalStrengthNr -> "5G"
                    is CellSignalStrengthLte -> "4G"
                    is CellSignalStrengthWcdma, is CellSignalStrengthTdscdma -> "3G"
                    is CellSignalStrengthGsm, is CellSignalStrengthCdma -> "2G"
                    else -> null
                }
            }
        } else if (Build.VERSION.SDK_INT >= 28) {
            m["level"] = tm.signalStrength?.level
        }
        return m
    }

    @Suppress("DEPRECATION")
    private fun cellInfo(): HashMap<String, Any?> {
        val tm = applicationContext.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val m = HashMap<String, Any?>()
        m["operator"] = tm.networkOperatorName
        m["simOperator"] = tm.simOperatorName
        m["simCountry"] = tm.simCountryIso
        m["netCountry"] = tm.networkCountryIso
        m["mccmnc"] = tm.networkOperator
        m["roaming"] = tm.isNetworkRoaming
        m["hasLocation"] = hasLocation()
        if (Build.VERSION.SDK_INT >= 29) {
            val list = tm.signalStrength?.cellSignalStrengths ?: emptyList()
            for (s in list) {
                if (s is CellSignalStrengthNr) {
                    m["nrRsrp"] = s.ssRsrp
                    m["nrRsrq"] = s.ssRsrq
                    m["nrSinr"] = s.ssSinr
                    m["nrDbm"] = s.dbm
                } else if (s is CellSignalStrengthLte) {
                    m["lteRsrp"] = s.rsrp
                    m["lteRsrq"] = s.rsrq
                    m["lteSnr"] = s.rssnr
                    m["lteDbm"] = s.dbm
                }
            }
        }
        val cells = ArrayList<HashMap<String, Any?>>()
        if (hasLocation()) {
            try {
                tm.allCellInfo?.forEach { ci -> cellMap(ci)?.let { cells.add(it) } }
            } catch (e: Exception) {
            }
            if (Build.VERSION.SDK_INT >= 29) {
                try {
                    tm.requestCellInfoUpdate(mainExecutor, object : TelephonyManager.CellInfoCallback() {
                        override fun onCellInfo(cellInfo: MutableList<CellInfo>) {}
                    })
                } catch (e: Exception) {
                }
            }
        }
        m["cells"] = cells
        return m
    }

    private fun cellMap(ci: CellInfo): HashMap<String, Any?>? {
        val m = HashMap<String, Any?>()
        m["registered"] = ci.isRegistered
        if (ci is CellInfoLte) {
            val id = ci.cellIdentity
            val s = ci.cellSignalStrength
            m["type"] = "4G"
            m["ci"] = id.ci.toLong()
            m["tac"] = id.tac
            m["pci"] = id.pci
            m["arfcn"] = if (Build.VERSION.SDK_INT >= 24) id.earfcn else null
            if (Build.VERSION.SDK_INT >= 30) m["bands"] = id.bands.toList()
            if (Build.VERSION.SDK_INT >= 28) {
                m["mcc"] = id.mccString
                m["mnc"] = id.mncString
                m["op"] = id.operatorAlphaShort?.toString()
            }
            m["dbm"] = s.dbm
            m["level"] = s.level
            m["rsrp"] = s.rsrp
            m["rsrq"] = s.rsrq
            m["snr"] = s.rssnr
        } else if (Build.VERSION.SDK_INT >= 29 && ci is CellInfoNr) {
            val id = ci.cellIdentity as CellIdentityNr
            val s = ci.cellSignalStrength as CellSignalStrengthNr
            m["type"] = "5G"
            m["ci"] = id.nci
            m["tac"] = id.tac
            m["pci"] = id.pci
            m["arfcn"] = id.nrarfcn
            if (Build.VERSION.SDK_INT >= 30) m["bands"] = id.bands.toList()
            m["mcc"] = id.mccString
            m["mnc"] = id.mncString
            m["op"] = id.operatorAlphaShort?.toString()
            m["dbm"] = s.dbm
            m["level"] = s.level
            m["rsrp"] = s.ssRsrp
            m["rsrq"] = s.ssRsrq
            m["snr"] = s.ssSinr
        } else if (ci is CellInfoWcdma) {
            val id = ci.cellIdentity
            m["type"] = "3G"
            m["ci"] = id.cid.toLong()
            m["tac"] = id.lac
            m["pci"] = id.psc
            m["arfcn"] = if (Build.VERSION.SDK_INT >= 24) id.uarfcn else null
            if (Build.VERSION.SDK_INT >= 28) {
                m["mcc"] = id.mccString
                m["mnc"] = id.mncString
                m["op"] = id.operatorAlphaShort?.toString()
            }
            m["dbm"] = ci.cellSignalStrength.dbm
            m["level"] = ci.cellSignalStrength.level
        } else if (ci is CellInfoGsm) {
            val id = ci.cellIdentity
            m["type"] = "2G"
            m["ci"] = id.cid.toLong()
            m["tac"] = id.lac
            m["arfcn"] = if (Build.VERSION.SDK_INT >= 24) id.arfcn else null
            if (Build.VERSION.SDK_INT >= 28) {
                m["mcc"] = id.mccString
                m["mnc"] = id.mncString
                m["op"] = id.operatorAlphaShort?.toString()
            }
            m["dbm"] = ci.cellSignalStrength.dbm
            m["level"] = ci.cellSignalStrength.level
        } else {
            return null
        }
        return m
    }
}
