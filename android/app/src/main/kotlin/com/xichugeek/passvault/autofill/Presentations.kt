package com.xichugeek.passvault.autofill

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.app.slice.Slice
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.autofill.InlinePresentation
import android.widget.RemoteViews
import android.widget.inline.InlinePresentationSpec
import androidx.annotation.RequiresApi
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import com.xichugeek.passvault.MainActivity
import com.xichugeek.passvault.R

/** 下拉菜单样式与键盘上方的内联建议样式 */
object Presentations {
    fun menu(context: Context, title: String, subtitle: String?): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.autofill_item)
        rv.setTextViewText(R.id.autofill_title, title)
        if (subtitle.isNullOrEmpty()) {
            rv.setViewVisibility(R.id.autofill_subtitle, android.view.View.GONE)
        } else {
            rv.setTextViewText(R.id.autofill_subtitle, subtitle)
        }
        return rv
    }

    @SuppressLint("RestrictedApi")
    @RequiresApi(Build.VERSION_CODES.R)
    fun inline(
        context: Context,
        spec: InlinePresentationSpec,
        title: String,
        subtitle: String?,
        isLock: Boolean,
    ): InlinePresentation? {
        val imeStyle = spec.style
        if (!UiVersions.getVersions(imeStyle).contains(UiVersions.INLINE_UI_VERSION_1)) return null
        // 内联建议需要一个长按时打开的 PendingIntent（用于归属显示）
        val attribution = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val icon = Icon.createWithResource(
            context,
            if (isLock) R.drawable.ic_autofill_lock else R.drawable.ic_autofill_key
        ).setTintBlendMode(android.graphics.BlendMode.DST)
        val b = InlineSuggestionUi.newContentBuilder(attribution)
            .setTitle(title)
            .setStartIcon(icon)
            .setContentDescription(title)
        if (!subtitle.isNullOrEmpty()) b.setSubtitle(subtitle)
        val slice: Slice = b.build().slice
        return InlinePresentation(slice, spec, false)
    }
}
