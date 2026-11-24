package com.xu.sequence.mobile

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances
import io.flutter.plugin.common.MethodCall
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.TimeZone

internal class SystemCalendar(private val resolver: ContentResolver) {
    fun handle(call: MethodCall): Any {
        return when (call.method) {
            "calendarEvents" -> listEvents(call)
            "calendarCreate" -> saveEvent(call)
            "calendarDelete" -> {
                val id = (call.arguments as? String)?.toLongOrNull()
                    ?: throw BridgeException("calendar", "日历事件 ID 无效")
                resolver.delete(ContentUris.withAppendedId(Events.CONTENT_URI, id), null, null)
                true
            }
            else -> throw BridgeException("calendar", "未知的日历操作")
        }
    }

    private fun listEvents(call: MethodCall): List<Map<String, Any>> {
        val start = MobileDate.parse(call.argument<String>("start"))
        val end = MobileDate.parse(call.argument<String>("end"))
        if (start == null || end == null || start >= end) {
            throw BridgeException("calendar", "日期范围无效")
        }

        // An all-day instance is stored at UTC midnight even when its date is local.
        val dayMillis = 86_400_000L
        val uri = Instances.CONTENT_URI.buildUpon().apply {
            ContentUris.appendId(this, start - dayMillis)
            ContentUris.appendId(this, end + dayMillis)
        }.build()
        val fields = arrayOf(
            Instances.EVENT_ID, Events.TITLE, Instances.BEGIN, Instances.END,
            Calendars.CALENDAR_DISPLAY_NAME, Events.ALL_DAY, Events.AVAILABILITY,
        )
        return resolver.query(uri, fields, null, null, Instances.BEGIN)?.use { rows ->
            buildList {
                while (rows.moveToNext()) {
                    val allDay = rows.getInt(5) != 0
                    val begin = rows.getLong(2).let { if (allDay) allDayBoundary(it) else it }
                    val finish = rows.getLong(3).let { if (allDay) allDayBoundary(it) else it }
                    if (finish <= start || begin >= end) continue
                    add(
                        mapOf(
                            "id" to rows.getLong(0).toString(),
                            "title" to rows.getString(1).orEmpty(),
                            "start" to MobileDate.isoDate(begin),
                            "end" to MobileDate.isoDate(finish),
                            "calendarTitle" to rows.getString(4).orEmpty(),
                            "isAllDay" to allDay,
                            "isBusy" to (rows.getInt(6) != Events.AVAILABILITY_FREE),
                        ),
                    )
                }
            }
        } ?: throw BridgeException("calendar", "无法查询系统日程")
    }

    private fun allDayBoundary(utcMillis: Long): Long {
        val utc = GregorianCalendar(TimeZone.getTimeZone("UTC")).apply {
            timeInMillis = utcMillis
        }
        return GregorianCalendar().apply {
            clear()
            set(utc.get(Calendar.YEAR), utc.get(Calendar.MONTH), utc.get(Calendar.DAY_OF_MONTH))
        }.timeInMillis
    }

    private fun saveEvent(call: MethodCall): String {
        val title = call.argument<String>("title")
        val start = MobileDate.parse(call.argument<String>("start"))
        if (title == null || start == null) throw BridgeException("calendar", "日历事项参数无效")
        val minutes = (call.argument<Number>("minutes")?.toLong() ?: 30).coerceIn(1, 1440)
        val values = ContentValues().apply {
            put(Events.TITLE, title)
            put(Events.DTSTART, start)
            put(Events.DTEND, start + minutes * 60_000)
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
        }
        val linked = call.argument<String>("eventID")
        if (!linked.isNullOrEmpty()) {
            val id = linked.toLongOrNull() ?: throw BridgeException("calendarMissing", "原日历事件不存在")
            val changed = resolver.update(ContentUris.withAppendedId(Events.CONTENT_URI, id), values, null, null)
            if (changed == 0) throw BridgeException("calendarMissing", "原日历事件不存在")
            return id.toString()
        }
        values.put(Events.CALENDAR_ID, writableCalendar())
        val saved = resolver.insert(Events.CONTENT_URI, values)
            ?: throw BridgeException("calendar", "未能写入系统日历")
        return ContentUris.parseId(saved).toString()
    }

    private fun writableCalendar(): Long {
        return resolver.query(
            Calendars.CONTENT_URI,
            arrayOf(Calendars._ID, Calendars.IS_PRIMARY),
            "${Calendars.VISIBLE} = 1 AND ${Calendars.CALENDAR_ACCESS_LEVEL} >= ?",
            arrayOf(Calendars.CAL_ACCESS_CONTRIBUTOR.toString()),
            "${Calendars.IS_PRIMARY} DESC, ${Calendars._ID}",
        )?.use { rows -> if (rows.moveToFirst()) rows.getLong(0) else null }
            ?: throw BridgeException("calendar", "没有可写入的系统日历")
    }
}
