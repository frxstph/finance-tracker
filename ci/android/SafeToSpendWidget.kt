package ph.patrick.finance_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar

// Home screen widget: Safe to spend ("₱650" + "a day"), the date it's from,
// the payday countdown and the next bill due. The app writes the data
// (MainActivity "updateWidget"); the countdown is worked out here so it
// stays right between app opens. Narrow widgets (2×2) get a compact layout.
class SafeToSpendWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, appWidgetManager, id))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        appWidgetManager.updateAppWidget(
            appWidgetId,
            build(context, appWidgetManager, appWidgetId)
        )
    }

    companion object {
        const val PREFS = "finance_widget"

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, SafeToSpendWidget::class.java)
            )
            for (id in ids) {
                manager.updateAppWidget(id, build(context, manager, id))
            }
        }

        private fun build(
            context: Context,
            manager: AppWidgetManager,
            id: Int
        ): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val minWidth = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 300)
            val small = minWidth in 1..249
            val views = RemoteViews(
                context.packageName,
                if (small) R.layout.safe_to_spend_widget_small
                else R.layout.safe_to_spend_widget
            )
            val big = prefs.getString("big", null)
            val color = when (prefs.getString("tone", "green")) {
                "red" -> 0xFFB3261E.toInt()
                "orange" -> 0xFFA65300.toInt()
                else -> 0xFF1F6B45.toInt()
            }
            if (big == null) {
                views.setTextViewText(R.id.widget_big, "Open the app")
                views.setTextViewText(R.id.widget_suffix, "")
                views.setTextColor(R.id.widget_big, 0xFF17211B.toInt())
            } else {
                views.setTextViewText(R.id.widget_big, big)
                views.setTextViewText(R.id.widget_suffix, prefs.getString("suffix", "") ?: "")
                views.setTextColor(R.id.widget_big, color)
                views.setTextColor(R.id.widget_suffix, color)
            }
            val payday = paydayText(prefs.getString("payday", null))
            views.setTextViewText(R.id.widget_payday, payday)
            views.setViewVisibility(
                R.id.widget_payday,
                if (payday.isEmpty()) View.GONE else View.VISIBLE
            )
            if (!small) {
                views.setTextViewText(R.id.widget_date, prefs.getString("date", "") ?: "")
                val next = prefs.getString("nextDue", null)
                views.setTextViewText(R.id.widget_next, next ?: "")
                views.setViewVisibility(
                    R.id.widget_next,
                    if (next == null) View.GONE else View.VISIBLE
                )
            }
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
