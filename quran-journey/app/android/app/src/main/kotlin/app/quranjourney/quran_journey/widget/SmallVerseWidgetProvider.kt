package app.quranjourney.quran_journey.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import app.quranjourney.quran_journey.R
import es.antonborri.home_widget.HomeWidgetProvider

/** Small (2x2): a verse from the current study, its reference and journey progress. */
class SmallVerseWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.widget_small)
            WidgetRender.common(context, v, widgetData)
            val ref = WidgetRender.str(widgetData, "qj_ref")
            v.setTextViewText(R.id.ref, if (ref.isEmpty()) context.getString(R.string.brand_full) else ref)
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
