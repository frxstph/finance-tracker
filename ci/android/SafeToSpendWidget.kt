package ph.patrick.finance_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.util.Calendar

// Home screen widget: Safe to spend, payday countdown, and the date the
// numbers are from. The app writes the data (MainActivity "updateWidget");
// the countdown is worked out here so it stays right between app opens.
class SafeToSpendWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context))
        }
    }

    companion object {
        const val PREFS = "finance_widget"

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, SafeToSpendWidget::class.java)
            )
            for (id in ids) {
                manager.updateAppWidget(id, build(context))
            }
        }

        private fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.safe_to_spend_widget)
            val headline = prefs.getString("headline", null)
            val hidden = prefs.getBoolean("hidden", false)
            val color = when (prefs.getString("tone", "green")) {
                "red" -> 0xFFB3261E.toInt()
                "orange" -> 0xFFA65300.toInt()
                else -> 0xFF1F6B45.toInt()
            }
            when {
                headline == null -> {
                    views.setTextViewText(R.id.widget_headline, "Open the app")
                    views.setTextColor(R.id.widget_headline, 0xFF17211B.toInt())
                }
                hidden -> {
                    views.setTextViewText(R.id.widget_headline, "Locked")
                    views.setTextColor(R.id.widget_headline, 0xFF17211B.toInt())
                }
                else -> {
                    views.setTextViewText(R.id.widget_headline, headline)
                    views.setTextColor(R.id.widget_headline, color)
                }
            }
            views.setTextViewText(
                R.id.widget_payday,
                paydayText(prefs.getString("payday", null))
            )
            views.setTextViewText(
                R.id.widget_asof,
                if (hidden) "Open to see Safe to spend"
                else prefs.getString("asOf", "") ?: ""
            )
            val open = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                    context,
                    1,
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            return views
        }

        // "Payday in 8 days" from a yyyy-MM-dd date.
        private fun paydayText(iso: String?): String {
            val parts = iso?.split("-") ?: return ""
            if (parts.size != 3) return ""
            val y = parts[0].toIntOrNull() ?: return ""
            val m = parts[1].toIntOrNull() ?: return ""
            val d = parts[2].toIntOrNull() ?: return ""
            val target = Calendar.getInstance()
            target.clear()
            target.set(y, m - 1, d)
            val today = Calendar.getInstance()
            today.set(Calendar.HOUR_OF_DAY, 0)
            today.set(Calendar.MINUTE, 0)
            today.set(Calendar.SECOND, 0)
            today.set(Calendar.MILLISECOND, 0)
            val days = Math.round(
                (target.timeInMillis - today.timeInMillis) / 86400000.0
            ).toInt()
            return when {
                days < 0 -> ""
                days == 0 -> "Payday today"
                days == 1 -> "Payday tomorrow"
                else -> "Payday in $days days"
            }
        }
    }
}
