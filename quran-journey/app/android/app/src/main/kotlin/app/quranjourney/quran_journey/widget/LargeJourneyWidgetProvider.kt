package app.quranjourney.quran_journey.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import app.quranjourney.quran_journey.R
import es.antonborri.home_widget.HomeWidgetProvider

/** Large (4x4): current study, today's sessions, progress and a quick entry point. */
class LargeJourneyWidgetProvider : HomeWidgetProvider() {
    private val rows = listOf(
        Triple(R.id.row0, R.id.row0_label, Pair(R.id.row0_status, R.id.row0_mark)),
        Triple(R.id.row1, R.id.row1_label, Pair(R.id.row1_status, R.id.row1_mark)),
        Triple(R.id.row2, R.id.row2_label, Pair(R.id.row2_status, R.id.row2_mark)),
    )

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_large)
            WidgetRender.common(context, v, widgetData)
            val title = WidgetRender.str(widgetData, "qj_study_title")
            v.setTextViewText(R.id.study_title, if (title.isEmpty()) context.getString(R.string.brand_full) else title)
            v.setTextViewText(R.id.brand, WidgetRender.str(widgetData, "qj_brand").ifEmpty { context.getString(R.string.brand_full) }.uppercase())
            val ref = WidgetRender.str(widgetData, "qj_ref")
            v.setTextViewText(R.id.ref, if (ref.isEmpty()) "" else "$ref · ${WidgetRender.str(widgetData, "qj_translation_name")}")
            v.setTextViewText(R.id.progress_label, WidgetRender.str(widgetData, "qj_progress_label"))
            val sessions = WidgetRender.sessions(widgetData)
            val now = WidgetRender.nowMinutes()
            rows.forEachIndexed { i, (row, label, pair) ->
                val (status, mark) = pair
                val s = sessions.getOrNull(i)
                if (s == null) {
                    v.setViewVisibility(row, View.GONE)
                } else {
                    v.setViewVisibility(row, View.VISIBLE)
                    v.setTextViewText(label, s.label)
                    v.setTextViewText(mark, if (s.done) "✓" else "○")
                    v.setTextViewText(
                        status,
                        when {
                            s.done -> "Completed"
                            s.minutes <= now -> "Ready"
                            else -> WidgetRender.hm(s.minutes)
                        },
                    )
                }
            }
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
