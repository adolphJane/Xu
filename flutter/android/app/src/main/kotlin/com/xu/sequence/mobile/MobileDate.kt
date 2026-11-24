package com.xu.sequence.mobile

import android.icu.util.ChineseCalendar
import android.icu.util.Calendar as Lunar
import io.flutter.plugin.common.MethodCall
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.GregorianCalendar
import java.util.Locale

internal object MobileDate {
    private fun formatter() = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.ROOT).apply {
        isLenient = false
    }

    fun isoDate(timestamp: Long): String = formatter().format(Date(timestamp))

    fun parse(value: String?): Long? {
        if (value == null) return null
        val milliseconds = value.replace(Regex("(\\.\\d{3})\\d+Z$"), "$1Z")
        return try {
            formatter().parse(milliseconds)?.time
        } catch (_: java.text.ParseException) {
            null
        }
    }

    fun startOfDay(timestamp: Long): Calendar = Calendar.getInstance().apply {
        timeInMillis = timestamp
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
}

internal data class AnniversaryDate(
    val year: Int,
    val month: Int,
    val day: Int,
    val yearly: Boolean,
    val lunar: Boolean,
) {
    fun next(reference: Long = System.currentTimeMillis()): Long? {
        val source = date(year) ?: return null
        val today = MobileDate.startOfDay(reference)
        if (!yearly) return source.takeIf { it >= today.timeInMillis }
        val startYear = today.get(Calendar.YEAR)
        if (!lunar) {
            return (startYear..startYear + 8).firstNotNullOfOrNull { target ->
                date(target)?.takeIf { it >= today.timeInMillis }
            }
        }
        val chinese = ChineseCalendar().apply { timeInMillis = source }
        val lunarMonth = chinese.get(Lunar.MONTH)
        val lunarDay = chinese.get(Lunar.DAY_OF_MONTH)
        val leap = chinese.get(Lunar.IS_LEAP_MONTH)
        val until = (today.clone() as Calendar).apply { add(Calendar.YEAR, 20) }.timeInMillis
        while (today.timeInMillis <= until) {
            chinese.timeInMillis = today.timeInMillis
            if (chinese.get(Lunar.MONTH) == lunarMonth &&
                chinese.get(Lunar.DAY_OF_MONTH) == lunarDay &&
                chinese.get(Lunar.IS_LEAP_MONTH) == leap
            ) return today.timeInMillis
            today.add(Calendar.DAY_OF_MONTH, 1)
        }
        return null
    }

    private fun date(target: Int): Long? {
        if (target !in 1..9999) return null
        return try {
            GregorianCalendar().apply {
                clear()
                isLenient = false
                set(target, month - 1, day)
            }.timeInMillis
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    companion object {
        fun from(call: MethodCall): AnniversaryDate? {
            return AnniversaryDate(
                call.argument<Int>("year") ?: return null,
                call.argument<Int>("month") ?: return null,
                call.argument<Int>("day") ?: return null,
                call.argument<Boolean>("repeatYearly") == true,
                call.argument<Boolean>("lunar") == true,
            )
        }
    }
}
