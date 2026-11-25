package app.quranjourney.quran_journey.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import app.quranjourney.quran_journey.R
import es.antonborri.home_widget.HomeWidgetProvider

/** Medium (4x2): current study, featured verse, today's progress and next session. */
class MediumStudyWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_medium)
            WidgetRender.common(context, v, widgetData)
            val title = WidgetRender.str(widgetData, "qj_study_title")
            v.setTextViewText(R.id.study_title, if (title.isEmpty()) context.getString(R.string.brand_full) else title)
            val today = WidgetRender.todayLabel(widgetData)
            v.setViewVisibility(R.id.today, if (today.isEmpty()) View.GONE else View.VISIBLE)
            v.setTextViewText(R.id.today, today)
            val ref = WidgetRender.str(widgetData, "qj_ref")
            val tr = WidgetRender.str(widgetData, "qj_translation_name")
            v.setTextViewText(R.id.ref, if (ref.isEmpty()) "" else "$ref · $tr")
            v.setTextViewText(R.id.next, WidgetRender.nextLabel(widgetData))
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
