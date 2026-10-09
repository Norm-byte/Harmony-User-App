package com.harmonybyintent.harmony_user_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DormantRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pending = goAsync()
        Thread {
            try {
                DormantAlarmReceiver.restoreRegisteredAlarms(context.applicationContext)
            } finally {
                pending.finish()
            }
        }.start()
    }
}