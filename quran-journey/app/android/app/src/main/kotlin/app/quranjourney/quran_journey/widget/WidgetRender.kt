package app.quranjourney.quran_journey.widget

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import app.quranjourney.quran_journey.MainActivity
import app.quranjourney.quran_journey.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONArray
import java.util.Calendar

/** One enabled daily session as written by the app (docs/CONTRACTS.md §4). */
data class Session(val label: String, val minutes: Int, val done: Boolean)

/**
 * Reads the snapshot the Flutter app saves with home_widget and renders it.
 * The "next session" line is computed here from the device clock, so it stays
 * correct between app launches (widgets are refreshed at each session time by
 * HomeWidget.scheduleWidgetUpdates and every 30 minutes by the system).
 */
object WidgetRender {
    fun str(p: SharedPreferences, k: String): String = (p.all[k] as? String) ?: ""
    fun num(p: SharedPreferences, k: String): Long = (p.all[k] as? Number)?.toLong() ?: 0L

    fun sessions(p: SharedPreferences): List<Session> {
        val raw = str(p, "qj_sessions")
        if (raw.isEmpty()) return emptyList()
        return try {
            val a = JSONArray(raw)
            val stale = isFromEarlierDay(num(p, "qj_updated_at"))
            (0 until a.length()).map {
                val o = a.getJSONObject(it)
                // "done" flags belong to the day they were written on.
                Session(o.optString("label"), o.optInt("minutes"), !stale && o.optBoolean("done"))
            }.sortedBy { it.minutes }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun isFromEarlierDay(millis: Long): Boolean {
        if (millis <= 0) return true
        val then = Calendar.getInstance().apply { timeInMillis = millis }
        val now = Calendar.getInstance()
        return then.get(Calendar.YEAR) != now.get(Calendar.YEAR) ||
            then.get(Calendar.DAY_OF_YEAR) != now.get(Calendar.DAY_OF_YEAR)
    }

    fun nowMinutes(): Int {
        val c = Calendar.getInstance()
        return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
    }

    fun hm(m: Int) = String.format("%02d:%02d", m / 60, m % 60)

    fun nextLabel(p: SharedPreferences): String {
        val s = sessions(p)
        if (s.isEmpty()) return ""
        if (num(p, "qj_paused_until") > System.currentTimeMillis()) return "Reminders paused"
        val now = nowMinutes()
        val pending = s.filter { !it.done }
        if (pending.isEmpty()) return "Today complete"
        val ready = pending.firstOrNull { it.minutes <= now }
        if (ready != null) return "${ready.label} ready"
        val up = pending.first()
        return "${up.label} · ${hm(up.minutes)}"
    }

    fun todayLabel(p: SharedPreferences): String {
        val s = sessions(p)
        if (s.isEmpty()) return ""
        return "${s.count { it.done }}/${s.size} today"
    }

    fun clickIntent(context: Context, views: RemoteViews, link: String) {
        val uri = Uri.parse(if (link.isEmpty()) "quranjourney://today" else link)
        val pi = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
        views.setOnClickPendingIntent(R.id.root, pi)
    }

    fun common(context: Context, views: RemoteViews, p: SharedPreferences) {
        val arabic = str(p, "qj_arabic")
        val translation = str(p, "qj_translation")
        if (arabic.isEmpty()) {
            views.setViewVisibility(R.id.arabic, View.GONE)
        } else {
            views.setViewVisibility(R.id.arabic, View.VISIBLE)
            views.setTextViewText(R.id.arabic, arabic)
        }
        views.setTextViewText(
            R.id.translation,
            if (translation.isEmpty()) context.getString(R.string.widget_empty) else translation,
        )
        views.setProgressBar(R.id.progress, 1000, num(p, "qj_progress_permille").toInt().coerceIn(0, 1000), false)
        clickIntent(context, views, str(p, "qj_study_link"))
    }
}
