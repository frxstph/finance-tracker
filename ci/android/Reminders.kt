package ph.patrick.finance_tracker

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

// Due date reminders. The app sends the full list ({id, at, title, body});
// it's saved so the alarms can be set again after a restart.
object Reminders {
    private const val PREFS = "finance_reminders"
    private const val KEY = "items"
    const val CHANNEL = "due_reminders"

    fun replaceAll(context: Context, items: List<Map<*, *>>) {
        cancelSaved(context)
        val arr = JSONArray()
        for (item in items) {
            val id = (item["id"] as? Number)?.toInt() ?: continue
            val at = (item["at"] as? Number)?.toLong() ?: continue
            val o = JSONObject()
            o.put("id", id)
            o.put("at", at)
            o.put("title", item["title"] as? String ?: "")
            o.put("body", item["body"] as? String ?: "")
            arr.put(o)
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, arr.toString()).apply()
        scheduleSaved(context)
    }

    fun scheduleSaved(context: Context) {
        val now = System.currentTimeMillis()
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (o in saved(context)) {
            val at = o.optLong("at")
            if (at <= now) continue
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(context, o))
        }
    }

    private fun cancelSaved(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (o in saved(context)) {
            am.cancel(pending(context, o))
        }
    }

    private fun saved(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun pending(context: Context, o: JSONObject): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra("id", o.optInt("id"))
            .putExtra("title", o.optString("title"))
            .putExtra("body", o.optString("body"))
        return PendingIntent.getBroadcast(
            context,
            o.optInt("id"),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    Reminders.CHANNEL,
                    "Due date reminders",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val open = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val body = intent.getStringExtra("body") ?: ""
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, Reminders.CHANNEL)
        } else {
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(intent.getStringExtra("title") ?: "Due soon")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(intent.getIntExtra("id", 1), notification)
        } catch (e: SecurityException) {
            // Notifications were turned off.
        }
    }
}

// Alarms are cleared when the phone restarts or the app is updated: set
// them again from the saved list.
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.scheduleSaved(context)
    }
}
