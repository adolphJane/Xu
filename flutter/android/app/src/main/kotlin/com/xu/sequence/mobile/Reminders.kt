package com.xu.sequence.mobile

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodCall
import org.json.JSONObject
import java.util.Calendar

internal class Reminders(private val context: Context) {
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val preferences = context.getSharedPreferences("reminders", Context.MODE_PRIVATE)

    fun configure(call: MethodCall): Boolean = synchronized(lock) {
        val daily = call.method == "dailyReviewNotification"
        val id = if (daily) "daily" else "anniversary-${call.argument<String>("id")
            ?: throw BridgeException("anniversary", "纪念日参数无效")}"
        if (call.argument<Boolean>("enabled") != true) {
            cancel(id)
            return true
        }
        if (!notifications.areNotificationsEnabled()) return false

        val reminder = JSONObject().put("daily", daily)
        if (daily) {
            reminder.put("hour", (call.argument<Int>("hour") ?: 18).coerceIn(0, 23))
            reminder.put("title", "每日复盘")
            reminder.put("body", "回顾今天完成的事项并整理日报。")
        } else {
            val date = AnniversaryDate.from(call)
                ?: throw BridgeException("anniversary", "纪念日日期无效")
            val days = (call.argument<Int>("reminderDays") ?: 0).coerceIn(0, 365)
            val privateName = call.argument<Boolean>("privacyMode") == true
            val title = call.argument<String>("title") ?: "纪念日"
            reminder.put("year", date.year)
            reminder.put("month", date.month)
            reminder.put("day", date.day)
            reminder.put("yearly", date.yearly)
            reminder.put("lunar", date.lunar)
            reminder.put("days", days)
            reminder.put("title", if (privateName) "重要日子即将到来" else "${title}即将到来")
            reminder.put(
                "body",
                if (privateName) "打开“序”查看倒计时和准备事项。" else "还有 $days 天，记得提前准备。",
            )
        }
        schedule(id, reminder)
        true
    }

    fun restore() = synchronized(lock) {
        for ((id, raw) in preferences.all) {
            if (raw is String) schedule(id, JSONObject(raw))
        }
    }

    fun deliver(id: String) = synchronized(lock) {
        val raw = preferences.getString(id, null) ?: return@synchronized
        val reminder = JSONObject(raw)
        if (reminder.optLong("fireTime") > System.currentTimeMillis()) return@synchronized
        if (notifications.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 ||
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED)
        ) {
            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                notifications.createNotificationChannel(
                    NotificationChannel(CHANNEL, "复盘与纪念日", NotificationManager.IMPORTANCE_DEFAULT),
                )
                Notification.Builder(context, CHANNEL)
            } else {
                Notification.Builder(context).setDefaults(Notification.DEFAULT_ALL)
            }
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            notifications.notify(
                id, 0, builder
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(reminder.getString("title"))
                    .setContentText(reminder.getString("body"))
                    .setVisibility(Notification.VISIBILITY_PRIVATE)
                    .setAutoCancel(true)
                    .setContentIntent(open)
                    .build(),
            )
        }
        schedule(id, reminder)
    }

    private fun schedule(id: String, reminder: JSONObject) {
        val fire = nextFire(reminder)
        if (fire == null) {
            cancel(id, dismiss = false)
            return
        }
        reminder.put("fireTime", fire)
        check(preferences.edit().putString(id, reminder.toString()).commit())
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire, pending(id))
    }

    private fun cancel(id: String, dismiss: Boolean = true) {
        check(preferences.edit().remove(id).commit())
        alarms.cancel(pending(id))
        if (dismiss) notifications.cancel(id, 0)
    }

    private fun pending(id: String): PendingIntent =
        PendingIntent.getBroadcast(
            context, 0,
            Intent(context, ReminderReceiver::class.java)
                .setAction(REMINDER_ACTION)
                .setData(Uri.Builder().scheme("xu-reminder").authority("local").appendPath(id).build()),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun nextFire(reminder: JSONObject): Long? {
        val now = System.currentTimeMillis()
        if (reminder.getBoolean("daily")) {
            return MobileDate.startOfDay(now).apply {
                set(Calendar.HOUR_OF_DAY, reminder.getInt("hour"))
                if (timeInMillis <= now) add(Calendar.DAY_OF_MONTH, 1)
            }.timeInMillis
        }

        val day = AnniversaryDate(
            reminder.getInt("year"),
            reminder.getInt("month"),
            reminder.getInt("day"),
            reminder.getBoolean("yearly"),
            reminder.getBoolean("lunar"),
        )
        val days = reminder.getInt("days")
        val reference = MobileDate.startOfDay(now).apply { add(Calendar.DAY_OF_MONTH, days) }
        repeat(2) {
            val occurrence = day.next(reference.timeInMillis) ?: return null
            val candidate = MobileDate.startOfDay(occurrence).apply {
                add(Calendar.DAY_OF_MONTH, -days)
                set(Calendar.HOUR_OF_DAY, 9)
            }.timeInMillis
            if (candidate > now) return candidate
            reference.add(Calendar.DAY_OF_MONTH, 1)
        }
        return null
    }

    companion object {
        const val REMINDER_ACTION = "com.xu.sequence.mobile.REMINDER"
        private const val CHANNEL = "xu-reminders"
        private val lock = Any()
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                val reminders = Reminders(context.applicationContext)
                when (intent.action) {
                    Reminders.REMINDER_ACTION -> intent.data?.lastPathSegment?.let(reminders::deliver)
                    Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED,
                    Intent.ACTION_TIMEZONE_CHANGED -> reminders.restore()
                }
            } finally {
                pending.finish()
            }
        }.start()
    }
}
