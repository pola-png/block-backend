package com.xapzap.app

import android.content.Context
import android.graphics.Typeface
import android.graphics.Color
import android.util.TypedValue
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import com.google.android.gms.ads.nativead.AdChoicesView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class NativeAdFactorySimple(
    private val context: Context,
    private val methodChannel: MethodChannel?
) : GoogleMobileAdsPlugin.NativeAdFactory {
    private val activeAds = java.util.concurrent.ConcurrentHashMap<String, NativeAd>()

    init {
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pauseAdVideo" -> {
                    val adId = call.argument<String>("adId")
                    if (adId != null) {
                        val ad = activeAds[adId]
                        ad?.mediaContent?.videoController?.pause()
                    }
                    result.success(null)
                }
                "playAdVideo" -> {
                    val adId = call.argument<String>("adId")
                    if (adId != null) {
                        val ad = activeAds[adId]
                        ad?.mediaContent?.videoController?.play()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun createNativeAd(nativeAd: NativeAd, customOptions: MutableMap<String, Any>?): NativeAdView {
        val adId = customOptions?.get("adId") as? String
        if (adId != null) {
            activeAds[adId] = nativeAd
        }
        val surfaceColor = resolveThemeColor(android.R.attr.colorBackground, Color.WHITE)
        val onSurfaceColor = resolveThemeColor(android.R.attr.textColorPrimary, Color.BLACK)
        val onSurfaceVariantColor = resolveThemeColor(android.R.attr.textColorSecondary, Color.DKGRAY)
        val primaryColor = resolveThemeColor(android.R.attr.colorAccent, Color.parseColor("#1DA1F2"))

        val adView = NativeAdView(context)
        adView.setBackgroundColor(Color.TRANSPARENT)
        adView.setPadding(0, 0, 0, 0)

        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(surfaceColor)
            setPadding(0, 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val topRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val iconView = ImageView(context).apply {
            layoutParams = LinearLayout.LayoutParams(72, 72).also {
                it.rightMargin = 16
            }
            scaleType = ImageView.ScaleType.CENTER_CROP
        }

        val headlineView = TextView(context).apply {
            text = nativeAd.headline ?: ""
            typeface = Typeface.DEFAULT_BOLD
            textSize = 15f
            setTextColor(onSurfaceColor)
        }

        val bodyView = TextView(context).apply {
            visibility = if (nativeAd.body != null) View.VISIBLE else View.GONE
            text = nativeAd.body ?: ""
            textSize = 14f
            setTextColor(onSurfaceVariantColor)
        }

        val ctaButton = Button(context).apply {
            text = nativeAd.callToAction ?: "Learn more"
            isAllCaps = false
            setBackgroundColor(primaryColor)
            setTextColor(idealTextColorFor(primaryColor))
        }

        val mediaView = MediaView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).also {
                it.topMargin = 12
                it.bottomMargin = 12
            }
        }

        val adChoicesView = AdChoicesView(context)

        nativeAd.icon?.drawable?.let { drawable ->
            iconView.setImageDrawable(drawable)
        }
        mediaView.setMediaContent(nativeAd.mediaContent)

        topRow.addView(iconView)
        topRow.addView(
            headlineView,
            LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            ),
        )

        container.addView(topRow)
        container.addView(adChoicesView)
        container.addView(mediaView)
        container.addView(bodyView)
        container.addView(ctaButton)

        adView.iconView = iconView
        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.callToActionView = ctaButton
        adView.mediaView = mediaView
        adView.adChoicesView = adChoicesView
        adView.addView(container)

        adView.setNativeAd(nativeAd)

        val mediaContent = nativeAd.mediaContent
        val hasVideo = mediaContent?.hasVideoContent() ?: false
        val aspectRatio = mediaContent?.aspectRatio ?: 0.0f

        if (adId != null && methodChannel != null) {
            val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
            mainHandler.post {
                methodChannel.invokeMethod(
                    "onAdMediaInfo",
                    mapOf(
                        "adId" to adId,
                        "hasVideo" to hasVideo,
                        "aspectRatio" to aspectRatio.toDouble()
                    )
                )
            }
        }

        return adView
    }

    private fun resolveThemeColor(attr: Int, fallback: Int): Int {
        val typedValue = TypedValue()
        val resolved = context.theme.resolveAttribute(attr, typedValue, true)
        if (!resolved) return fallback
        return if (typedValue.resourceId != 0) {
            context.getColor(typedValue.resourceId)
        } else {
            typedValue.data
        }
    }

    private fun idealTextColorFor(backgroundColor: Int): Int {
        return if (ColorUtils.calculateLuminance(backgroundColor) > 0.5) {
            Color.BLACK
        } else {
            Color.WHITE
        }
    }
}
