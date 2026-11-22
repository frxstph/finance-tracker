package ph.patrick.finance_tracker

import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is needed for fingerprint / face unlock
// (local_auth). The "finance_tracker/window" channel hides the app's
// preview in the recent-apps screen while App lock is on, without
// blocking screenshots (Android 13 and up).
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
                else -> result.notImplemented()
            }
        }
    }
}
