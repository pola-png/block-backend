package badmuscodehive.appldq

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    private val deviceModeChannel = "xapzap/device_mode"
    private var nativeFactory: NativeAdFactorySimple? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceModeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTvDevice" -> result.success(isTvDevice())
                    else -> result.notImplemented()
                }
            }
        val adsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xapzap/ads")
        nativeFactory = NativeAdFactorySimple(this, adsChannel)
        GoogleMobileAdsPlugin.registerNativeAdFactory(flutterEngine, "cardNative", nativeFactory!!)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "cardNative")
        nativeFactory = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun isTvDevice(): Boolean {
        val packageManager = applicationContext.packageManager
        val hasLeanback = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val hasTelevision = packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
        val hasFireTv = packageManager.hasSystemFeature("amazon.hardware.fire_tv")
        val hasLeanbackOnly = packageManager.hasSystemFeature("android.software.leanback_only")
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val isTelevisionMode =
            uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION

        return hasLeanback ||
            hasTelevision ||
            hasFireTv ||
            hasLeanbackOnly ||
            isTelevisionMode
    }
}
