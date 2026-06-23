package com.smartisax.browser;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class PortalBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) {
            return;
        }
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
            return;
        }
        if (!DevicePortalService.isAutoStartEnabled(context)) {
            return;
        }
        try {
            DevicePortalService.requestStart(context.getApplicationContext(), action);
        } catch (RuntimeException ignored) {
        }
    }
}
