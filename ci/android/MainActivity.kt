package ph.patrick.finance_tracker

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is needed for fingerprint / face unlock
// (local_auth). The "finance_tracker/window" channel:
// - hidePreview: hides the app in the recent-apps screen while App lock is
//   on, without blocking screenshots (Android 13 and up)
// - updateWidget: data for the Safe to spend home screen widget
// - setReminders / notificationsAllowed / askNotifications: due date
//   reminders
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "finance_tracker/window"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hidePreview" -> {
                    val hide = call.arguments as? Boolean ?: false
                    if (Build.VERSION.SDK_INT >= 33) {
                        setRecentsScreenshotEnabled(!hide)
                    }
                    result.success(null)
                }
                "updateWidget" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    val edit = getSharedPreferences(SafeToSpendWidget.PREFS, MODE_PRIVATE).edit()
                    for (key in listOf("headline", "tone", "payday", "asOf")) {
                        val value = args[key] as? String
                        if (value == null) edit.remove(key) else edit.putString(key, value)
                    }
                    edit.putBoolean("hidden", args["hidden"] as? Boolean ?: false)
                    edit.apply()
                    SafeToSpendWidget.refresh(this)
                    result.success(null)
                }
                "setReminders" -> {
                    val items = (call.arguments as? List<*>)
                        ?.mapNotNull { it as? Map<*, *> }
                        ?: emptyList()
                    Reminders.replaceAll(this, items)
                    result.success(null)
                }
                "notificationsAllowed" -> {
                    val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    val granted = Build.VERSION.SDK_INT < 33 ||
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                        PackageManager.PERMISSION_GRANTED
                    result.success(granted && nm.areNotificationsEnabled())
                }
                "askNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7101)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
