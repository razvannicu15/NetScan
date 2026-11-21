package ro.netscan.netscan

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Color
import android.net.wifi.WifiManager
import android.widget.RemoteViews

/** Home-screen widget: Wi-Fi name + live signal, devices from the last scan. */
class NetScanWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) update(context, manager, id)
    }

    companion object {
        const val PREFS = "netscan_widget"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NetScanWidget::class.java))
            for (id in ids) update(context, manager, id)
        }

        @Suppress("DEPRECATION")
        fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.netscan_widget)

            var ssid: String? = null
            var rssi: Int? = null
            try {
                val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val info = wm.connectionInfo
                if (info != null && info.networkId != -1) {
                    ssid = info.ssid?.trim('"')
                    if (ssid == "<unknown ssid>" || ssid.isNullOrBlank()) ssid = null
                    val r = info.rssi
                    if (r < 0 && r > -127) rssi = r
                }
            } catch (e: Exception) {
            }

            val connected = rssi != null
            val title = when {
                ssid != null -> ssid
                connected -> prefs.getString("ssid", null) ?: "Wi-Fi"
                else -> prefs.getString("noWifi", "Wi-Fi off") ?: "Wi-Fi off"
            }
            views.setTextViewText(R.id.w_ssid, title)
            views.setTextViewText(R.id.w_signal, if (rssi != null) "$rssi dBm" else "")
            val color = when {
                rssi == null -> Color.GRAY
                rssi >= -60 -> Color.parseColor("#2E9E5B")
                rssi >= -72 -> Color.parseColor("#E08A00")
                else -> Color.parseColor("#D93025")
            }
            views.setInt(R.id.w_icon, "setColorFilter", color)
            views.setTextViewText(R.id.w_devices, prefs.getString("devices", "") ?: "")
            views.setTextViewText(R.id.w_time, prefs.getString("time", "") ?: "")

            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                val pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.w_root, pi)
            }
            manager.updateAppWidget(id, views)
        }
    }
}
