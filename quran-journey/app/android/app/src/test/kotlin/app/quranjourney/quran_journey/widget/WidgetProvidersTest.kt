package app.quranjourney.quran_journey.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import org.robolectric.RuntimeEnvironment
import app.quranjourney.quran_journey.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.Calendar

/**
 * Renders the real widget layouts through the real providers with the
 * SharedPreferences keys the Flutter app writes (docs/CONTRACTS.md §4).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WidgetProvidersTest {
    private lateinit var context: Context
    private lateinit var awm: AppWidgetManager

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        awm = AppWidgetManager.getInstance(context)
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun writeSnapshot(sessionsJson: String, updatedAt: Long = System.currentTimeMillis()) {
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).edit()
            .putString("qj_brand", "The Quran Journey")
            .putString("qj_arabic", "ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ")
            .putString("qj_translation", "The Beneficent, the Merciful.")
            .putString("qj_translation_name", "Pickthall")
            .putString("qj_ref", "Al-Faatiha 1:3")
            .putString("qj_study_title", "Al-Faatiha 1:1–4")
            .putString("qj_study_link", "quranjourney://study/1-4")
            .putInt("qj_progress_permille", 250)
            .putString("qj_progress_label", "25.0% of the Quran · Surah 1 of 114")
            .putInt("qj_today_done", 1)
            .putInt("qj_today_total", 3)
            .putString("qj_sessions", sessionsJson)
            .putLong("qj_paused_until", 0L)
            .putLong("qj_updated_at", updatedAt)
            .commit()
    }

    private val sessions = """[{"label":"Morning","minutes":0,"enabled":true,"done":true},""" +
        """{"label":"Afternoon","minutes":1,"enabled":true,"done":false},""" +
        """{"label":"Evening","minutes":1439,"enabled":true,"done":false}]"""

    @Test
    fun smallWidgetShowsVerseReferenceAndProgress() {
        writeSnapshot(sessions)
        val ids = shadowOf(awm).createWidgets(SmallVerseWidgetProvider::class.java, R.layout.widget_small, 1)
        val v = shadowOf(awm).getViewFor(ids[0])
        assertEquals("Al-Faatiha 1:3", v.findViewById<TextView>(R.id.ref).text.toString())
        assertEquals("ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ", v.findViewById<TextView>(R.id.arabic).text.toString())
        assertEquals("The Beneficent, the Merciful.", v.findViewById<TextView>(R.id.translation).text.toString())
        assertEquals(250, v.findViewById<ProgressBar>(R.id.progress).progress)
    }

    @Test
    fun mediumWidgetShowsTodayAndNextSession() {
        writeSnapshot(sessions)
        val ids = shadowOf(awm).createWidgets(MediumStudyWidgetProvider::class.java, R.layout.widget_medium, 1)
        val v = shadowOf(awm).getViewFor(ids[0])
        assertEquals("Al-Faatiha 1:1–4", v.findViewById<TextView>(R.id.study_title).text.toString())
        assertEquals("1/3 today", v.findViewById<TextView>(R.id.today).text.toString())
        // Afternoon (00:01) is not done and its time has passed (unless the test runs at exactly 00:00).
        val next = v.findViewById<TextView>(R.id.next).text.toString()
        assertTrue(next, next == "Afternoon ready" || next.startsWith("Afternoon ·"))
        assertEquals("Al-Faatiha 1:3 · Pickthall", v.findViewById<TextView>(R.id.ref).text.toString())
    }

    @Test
    fun largeWidgetListsSessions() {
        writeSnapshot(sessions)
        val ids = shadowOf(awm).createWidgets(LargeJourneyWidgetProvider::class.java, R.layout.widget_large, 1)
        val v = shadowOf(awm).getViewFor(ids[0])
        assertEquals(View.VISIBLE, v.findViewById<View>(R.id.row0).visibility)
        assertEquals("Morning", v.findViewById<TextView>(R.id.row0_label).text.toString())
        assertEquals("Completed", v.findViewById<TextView>(R.id.row0_status).text.toString())
        assertEquals("23:59", v.findViewById<TextView>(R.id.row2_status).text.toString().let { if (it == "Ready") "23:59" else it })
        assertEquals("25.0% of the Quran · Surah 1 of 114", v.findViewById<TextView>(R.id.progress_label).text.toString())
    }

    @Test
    fun emptyStateBeforeFirstLaunch() {
        val ids = shadowOf(awm).createWidgets(SmallVerseWidgetProvider::class.java, R.layout.widget_small, 1)
        val v = shadowOf(awm).getViewFor(ids[0])
        assertEquals(context.getString(R.string.widget_empty), v.findViewById<TextView>(R.id.translation).text.toString())
        assertEquals(View.GONE, v.findViewById<View>(R.id.arabic).visibility)
    }

    @Test
    fun doneFlagsResetOnANewDay() {
        val yesterday = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }.timeInMillis
        writeSnapshot(sessions, updatedAt = yesterday)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        assertTrue(WidgetRender.sessions(prefs).none { it.done })
        assertEquals("0/3 today", WidgetRender.todayLabel(prefs))
    }

    @Test
    fun pausedRemindersAreShown() {
        writeSnapshot(sessions)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        prefs.edit().putLong("qj_paused_until", System.currentTimeMillis() + 86_400_000L).commit()
        assertEquals("Reminders paused", WidgetRender.nextLabel(prefs))
    }

    @Test
    fun allDoneShowsTodayComplete() {
        writeSnapshot("""[{"label":"Morning","minutes":420,"enabled":true,"done":true}]""")
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        assertEquals("Today complete", WidgetRender.nextLabel(prefs))
    }
}
