package com.smartisax.browser;

import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.IBinder;
import android.os.Parcel;
import android.provider.Settings;
import android.webkit.JavascriptInterface;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONException;
import org.json.JSONObject;

public final class ShellBridge {
    private static final String KP = "/system/bin/kp";
    private static final String ADB_DESCRIPTOR = "android.debug.IAdbManager";
    private static final String CURRENT_WIFI_BSSID_SENTINEL = "__smartisax_current_wifi__";
    private static final int ADB_ALLOW_WIRELESS_DEBUGGING = 4;
    private static final int ADB_DENY_WIRELESS_DEBUGGING = 5;
    private static final int ADB_GET_WIRELESS_PORT = 10;
    private static final Pattern PORT_PATTERN = Pattern.compile("0000([0-9a-fA-F]{4})");
    private final Context context;

    private static final String STATUS_SCRIPT =
            "echo enabled=$(settings get global adb_wifi_enabled 2>/dev/null); "
                    + "echo ip=$(ip -o -4 addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1); "
                    + "echo bssid=$(cmd wifi status 2>/dev/null | sed -n 's/.*BSSID: \\([^,]*\\).*/\\1/p' | head -n1); "
                    + "echo raw=$(service call adb 10 2>/dev/null)";

    public ShellBridge(Context context) {
        this.context = context;
    }

    @JavascriptInterface
    public String getWirelessAdbStatus() {
        return statusJson(null);
    }

    @JavascriptInterface
    public String enableWirelessAdb() {
        ActionResult result = tryEnablePrivileged(CURRENT_WIFI_BSSID_SENTINEL);
        if (result.exitCode != 0) {
            ActionResult privileged = result;
            ActionResult root = runRootAction(
                    "bssid=$(cmd wifi status 2>/dev/null | sed -n 's/.*BSSID: \\([^,]*\\).*/\\1/p' | head -n1); "
                            + "if [ -z \"$bssid\" ]; then echo error=no_wifi_bssid; exit 2; fi; "
                            + "service call adb 4 i32 1 s16 \"$bssid\" >/dev/null; "
                            + "settings put global adb_wifi_enabled 1; "
                            + "sleep 3; "
                            + "echo enabled_bssid=$bssid");
            result = new ActionResult(
                    root.backend,
                    root.exitCode,
                    "privileged[" + privileged.exitCode + "] " + privileged.output
                            + "\nroot[" + root.exitCode + "] " + root.output);
        }
        return statusJson(result);
    }

    @JavascriptInterface
    public String disableWirelessAdb() {
        ActionResult result = tryDisablePrivileged();
        if (result.exitCode != 0) {
            ActionResult privileged = result;
            ActionResult root = runRootAction(
                    "service call adb 5 >/dev/null 2>&1 || true; "
                            + "settings put global adb_wifi_enabled 0; "
                            + "sleep 1; "
                            + "echo disabled=1");
            result = new ActionResult(
                    root.backend,
                    root.exitCode,
                    "privileged[" + privileged.exitCode + "] " + privileged.output
                            + "\nroot[" + root.exitCode + "] " + root.output);
        }
        return statusJson(result);
    }

    @JavascriptInterface
    public String getPortalStatus() {
        return portalStatusJson("");
    }

    @JavascriptInterface
    public String enablePortal() {
        DevicePortalService.requestStart(context, "shell_enable");
        sleep(500);
        return portalStatusJson("start_requested");
    }

    @JavascriptInterface
    public String disablePortal() {
        Intent intent = new Intent(context, DevicePortalService.class);
        intent.setAction(DevicePortalService.ACTION_STOP);
        context.startService(intent);
        sleep(200);
        return portalStatusJson("stop_requested");
    }

    @JavascriptInterface
    public String enablePortalAutoStart() {
        DevicePortalService.setAutoStartEnabled(context, true);
        DevicePortalService.requestStart(context, "shell_autostart_enable");
        sleep(500);
        return portalStatusJson("autostart_enabled");
    }

    @JavascriptInterface
    public String disablePortalAutoStart() {
        DevicePortalService.setAutoStartEnabled(context, false);
        return portalStatusJson("autostart_disabled");
    }

    private String portalStatusJson(String action) {
        DevicePortalService.PortalSnapshot snapshot = DevicePortalService.snapshot();
        JSONObject json = new JSONObject();
        try {
            json.put("ok", true);
            json.put("action", action);
            json.put("running", snapshot.running);
            json.put("ip", snapshot.ip);
            json.put("port", snapshot.port);
            json.put("url", snapshot.url);
            json.put("pairingCode", snapshot.pairingCode);
            json.put("successfulPairs", snapshot.successfulPairs);
            json.put("startedAtMs", snapshot.startedAtMs);
            json.put("lastPairAtMs", snapshot.lastPairAtMs);
            json.put("startReason", snapshot.startReason);
            json.put("autoStartEnabled", DevicePortalService.isAutoStartEnabled(context));
            json.put("error", snapshot.error);
        } catch (JSONException ignored) {
        }
        return json.toString();
    }

    private String statusJson(ActionResult actionResult) {
        Status privilegedStatus = privilegedStatus();
        Status status = privilegedStatus;
        if (!privilegedStatus.ok) {
            Status rootStatus = rootStatus();
            status = new Status(
                    rootStatus.ok,
                    rootStatus.backend,
                    rootStatus.exitCode,
                    rootStatus.enabled,
                    rootStatus.ip,
                    rootStatus.bssid,
                    rootStatus.port,
                    rootStatus.rawPort,
                    "privileged[" + privilegedStatus.exitCode + "] " + privilegedStatus.log
                            + "\nroot[" + rootStatus.exitCode + "] " + rootStatus.log);
        }
        boolean active = status.enabled && status.port > 0 && status.ip.length() > 0;

        JSONObject json = new JSONObject();
        try {
            json.put("ok", status.ok);
            json.put("backend", status.backend);
            json.put("enabled", status.enabled);
            json.put("active", active);
            json.put("ip", status.ip);
            json.put("bssid", status.bssid);
            json.put("port", status.port);
            json.put("connect", active ? status.ip + ":" + status.port : "");
            json.put("rawPort", status.rawPort);
            json.put("statusExit", status.exitCode);
            json.put("actionExit", actionResult == null ? JSONObject.NULL : actionResult.exitCode);
            json.put("actionBackend", actionResult == null ? "" : actionResult.backend);
            json.put("action", actionResult == null ? "" : trimForUi(actionResult.output));
            json.put("log", trimForUi(status.log));
        } catch (JSONException ignored) {
        }
        return json.toString();
    }

    private Status privilegedStatus() {
        try {
            boolean enabled = Settings.Global.getInt(
                    context.getContentResolver(), "adb_wifi_enabled", 0) == 1;
            int port = getAdbWirelessPortPrivileged();
            String ip = wlanIpv4();
            String bssid = currentBssid();
            return new Status(true, "privileged", 0, enabled, ip, bssid, port, "direct", "");
        } catch (Exception e) {
            return new Status(false, "privileged", 125, false, "", "", 0, "", e.toString());
        }
    }

    private Status rootStatus() {
        ActionResult status = runRootAction(STATUS_SCRIPT);
        String enabled = valueFor(status.output, "enabled");
        String ip = valueFor(status.output, "ip");
        String bssid = valueFor(status.output, "bssid");
        String raw = valueFor(status.output, "raw");
        int port = parsePort(raw);
        return new Status(
                status.exitCode == 0,
                "root",
                status.exitCode,
                "1".equals(enabled),
                ip,
                bssid,
                port,
                raw,
                status.output);
    }

    private ActionResult tryEnablePrivileged(String bssid) {
        if (bssid.length() == 0) {
            return new ActionResult("privileged", 2, "missing wifi bssid");
        }
        try {
            allowWirelessDebugging(true, bssid);
            Settings.Global.putInt(context.getContentResolver(), "adb_wifi_enabled", 1);
            sleep(3000);
            return new ActionResult("privileged", 0, "enabled_bssid=" + bssid + " port=" + getAdbWirelessPortPrivileged());
        } catch (Exception e) {
            return new ActionResult("privileged", 125, e.toString());
        }
    }

    private ActionResult tryDisablePrivileged() {
        try {
            denyWirelessDebugging();
            Settings.Global.putInt(context.getContentResolver(), "adb_wifi_enabled", 0);
            sleep(1000);
            return new ActionResult("privileged", 0, "disabled=1");
        } catch (Exception e) {
            return new ActionResult("privileged", 125, e.toString());
        }
    }

    private int getAdbWirelessPortPrivileged() throws Exception {
        IBinder binder = adbBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(ADB_DESCRIPTOR);
            binder.transact(ADB_GET_WIRELESS_PORT, data, reply, 0);
            reply.readException();
            return reply.readInt();
        } finally {
            reply.recycle();
            data.recycle();
        }
    }

    private void allowWirelessDebugging(boolean alwaysAllow, String bssid) throws Exception {
        IBinder binder = adbBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(ADB_DESCRIPTOR);
            data.writeInt(alwaysAllow ? 1 : 0);
            data.writeString(bssid);
            binder.transact(ADB_ALLOW_WIRELESS_DEBUGGING, data, reply, 0);
            reply.readException();
        } finally {
            reply.recycle();
            data.recycle();
        }
    }

    private void denyWirelessDebugging() throws Exception {
        IBinder binder = adbBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(ADB_DESCRIPTOR);
            binder.transact(ADB_DENY_WIRELESS_DEBUGGING, data, reply, 0);
            reply.readException();
        } finally {
            reply.recycle();
            data.recycle();
        }
    }

    private IBinder adbBinder() throws Exception {
        Class<?> serviceManagerClass = Class.forName("android.os.ServiceManager");
        java.lang.reflect.Method getService = serviceManagerClass.getDeclaredMethod("getService", String.class);
        getService.setAccessible(true);
        IBinder binder = (IBinder) getService.invoke(null, "adb");
        if (binder == null) {
            throw new IllegalStateException("adb service not found");
        }
        return binder;
    }

    private String currentBssid() {
        String bssid = bssidFromWifiManager();
        if (bssid.length() > 0) {
            return bssid;
        }
        ActionResult status = runRootAction(
                "cmd wifi status 2>/dev/null | sed -n 's/.*BSSID: \\([^,]*\\).*/bssid=\\1/p' | head -n1");
        return valueFor(status.output, "bssid");
    }

    private String bssidFromWifiManager() {
        try {
            WifiManager wifiManager = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) {
                return "";
            }
            WifiInfo info = wifiManager.getConnectionInfo();
            if (info == null || info.getBSSID() == null) {
                return "";
            }
            String bssid = info.getBSSID().trim();
            if (bssid.length() == 0 || "02:00:00:00:00:00".equals(bssid)) {
                return "";
            }
            return bssid;
        } catch (Exception ignored) {
            return "";
        }
    }

    private static String wlanIpv4() {
        try {
            NetworkInterface wlan = NetworkInterface.getByName("wlan0");
            if (wlan == null) {
                return "";
            }
            for (InetAddress address : Collections.list(wlan.getInetAddresses())) {
                if (address instanceof Inet4Address && !address.isLoopbackAddress()) {
                    return address.getHostAddress();
                }
            }
        } catch (Exception ignored) {
        }
        return "";
    }

    private static ActionResult runRootAction(String script) {
        Process process = null;
        try {
            process = new ProcessBuilder(KP, "-c", script).redirectErrorStream(true).start();
            boolean finished = process.waitFor(10, TimeUnit.SECONDS);
            String output = readAll(process.getInputStream());
            if (!finished) {
                process.destroy();
                return new ActionResult("root", 124, output + "\ntimeout");
            }
            return new ActionResult("root", process.exitValue(), output);
        } catch (Exception e) {
            return new ActionResult("root", 125, e.toString());
        } finally {
            if (process != null) {
                process.destroy();
            }
        }
    }

    private static String readAll(InputStream stream) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[2048];
        int read;
        while ((read = stream.read(buffer)) != -1) {
            output.write(buffer, 0, read);
        }
        return new String(output.toByteArray(), StandardCharsets.UTF_8);
    }

    private static String valueFor(String text, String key) {
        String prefix = key + "=";
        String[] lines = text.split("\\r?\\n");
        for (String line : lines) {
            if (line.startsWith(prefix)) {
                return line.substring(prefix.length()).trim();
            }
        }
        return "";
    }

    private static int parsePort(String raw) {
        Matcher matcher = PORT_PATTERN.matcher(raw);
        if (!matcher.find()) {
            return 0;
        }
        try {
            return Integer.parseInt(matcher.group(1), 16);
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private static String trimForUi(String value) {
        if (value == null) {
            return "";
        }
        String trimmed = value.trim();
        if (trimmed.length() <= 1200) {
            return trimmed;
        }
        return trimmed.substring(0, 1200);
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static final class ActionResult {
        final String backend;
        final int exitCode;
        final String output;

        ActionResult(String backend, int exitCode, String output) {
            this.backend = backend;
            this.exitCode = exitCode;
            this.output = output == null ? "" : output;
        }
    }

    private static final class Status {
        final boolean ok;
        final String backend;
        final int exitCode;
        final boolean enabled;
        final String ip;
        final String bssid;
        final int port;
        final String rawPort;
        final String log;

        Status(
                boolean ok,
                String backend,
                int exitCode,
                boolean enabled,
                String ip,
                String bssid,
                int port,
                String rawPort,
                String log) {
            this.ok = ok;
            this.backend = backend;
            this.exitCode = exitCode;
            this.enabled = enabled;
            this.ip = ip == null ? "" : ip;
            this.bssid = bssid == null ? "" : bssid;
            this.port = port;
            this.rawPort = rawPort == null ? "" : rawPort;
            this.log = log == null ? "" : log;
        }
    }
}
