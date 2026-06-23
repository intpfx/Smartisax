package com.smartisax.browser;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Point;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Bundle;
import android.os.IBinder;
import android.os.Parcel;
import android.os.Process;
import java.io.IOException;
import java.lang.reflect.Method;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxProjectionCapture {
    private static final String SERVICE_NAME = "media_projection";
    private static final String DESCRIPTOR = "android.media.projection.IMediaProjectionManager";
    private static final String RAW_BINDER_ROUTE = "raw-binder-transact-media-projection";
    private static final int TRANSACTION_HAS_PROJECTION_PERMISSION = 1;
    private static final int TRANSACTION_CREATE_PROJECTION = 2;
    private static final int TYPE_SCREEN_CAPTURE = 0;

    private SmartisaxProjectionCapture() {
    }

    static JSONObject probe(Context context, Point display) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("ok", true);
        json.put("backend", "mediaprojection-texture");
        json.put("goal", "1080p30-minimum-1080p60-default");
        json.put("source", "MediaProjection VirtualDisplay to WebRTC SurfaceTextureHelper");
        json.put("copyPath", "no Java Bitmap copy; no ARGB to I420 loop");
        json.put("tokenRoute", RAW_BINDER_ROUTE);
        json.put("display", displayJson(display));
        json.put("classes", classesJson());
        JSONObject permission = new JSONObject();
        try {
            permission.put("hasProjectionPermission", hasProjectionPermission(context));
            permission.put("binderCreateProjection", "available");
            permission.put("route", RAW_BINDER_ROUTE);
        } catch (Throwable t) {
            permission.put("hasProjectionPermission", false);
            permission.put("binderCreateProjection", "failed");
            permission.put("error", t.toString());
        }
        json.put("permission", permission);
        try {
            MediaProjection projection = createMediaProjection(context);
            json.put("createProjection", "ok");
            json.put("mediaProjectionClass", projection.getClass().getName());
            try {
                projection.stop();
            } catch (RuntimeException ignored) {
            }
        } catch (Throwable t) {
            json.put("createProjection", "failed");
            json.put("createProjectionError", t.toString());
        }
        return json;
    }

    static MediaProjection createMediaProjection(Context context) throws IOException {
        try {
            Object token = createProjectionToken(context);
            MediaProjection projection = mediaProjectionFromIntent(context, token);
            if (projection != null) {
                return projection;
            }
            throw new IOException("media_projection_intent_returned_null");
        } catch (IOException e) {
            throw e;
        } catch (Throwable t) {
            throw new IOException("create_media_projection_failed", t);
        }
    }

    static boolean hasProjectionPermission(Context context) throws Exception {
        IBinder manager = projectionManagerBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(DESCRIPTOR);
            data.writeInt(Process.myUid());
            data.writeString(context.getPackageName());
            transactOrThrow(manager, TRANSACTION_HAS_PROJECTION_PERMISSION, data, reply);
            return reply.readInt() != 0;
        } finally {
            reply.recycle();
            data.recycle();
        }
    }

    private static Object createProjectionToken(Context context) throws Exception {
        IBinder manager = projectionManagerBinder();
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        IBinder token;
        try {
            data.writeInterfaceToken(DESCRIPTOR);
            data.writeInt(Process.myUid());
            data.writeString(context.getPackageName());
            data.writeInt(TYPE_SCREEN_CAPTURE);
            data.writeInt(1);
            transactOrThrow(manager, TRANSACTION_CREATE_PROJECTION, data, reply);
            token = reply.readStrongBinder();
        } finally {
            reply.recycle();
            data.recycle();
        }
        if (token == null) {
            throw new IOException("createProjection_returned_null");
        }
        return token;
    }

    private static IBinder projectionManagerBinder() throws Exception {
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        Method getService = serviceManager.getDeclaredMethod("getService", String.class);
        Object binder = getService.invoke(null, SERVICE_NAME);
        if (!(binder instanceof IBinder)) {
            throw new IOException("media_projection_service_binder_unavailable");
        }
        return (IBinder) binder;
    }

    private static void transactOrThrow(IBinder binder, int code, Parcel data, Parcel reply) throws Exception {
        if (!binder.transact(code, data, reply, 0)) {
            throw new IOException("media_projection_transact_" + code + "_returned_false");
        }
        reply.readException();
    }

    private static MediaProjection mediaProjectionFromIntent(Context context, Object token) {
        try {
            IBinder binder = projectionBinder(token);
            Intent intent = new Intent();
            Bundle extras = new Bundle();
            extras.putBinder("android.media.projection.extra.EXTRA_MEDIA_PROJECTION", binder);
            intent.putExtras(extras);
            MediaProjectionManager manager = (MediaProjectionManager) context.getSystemService(Context.MEDIA_PROJECTION_SERVICE);
            if (manager == null) {
                return null;
            }
            return manager.getMediaProjection(Activity.RESULT_OK, intent);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static IBinder projectionBinder(Object token) throws Exception {
        if (token instanceof IBinder) {
            return (IBinder) token;
        }
        throw new IOException("projection_token_is_not_binder");
    }

    private static JSONObject classesJson() throws JSONException {
        JSONObject json = new JSONObject();
        putClass(json, "MediaProjection", "android.media.projection.MediaProjection");
        putClass(json, "MediaProjectionManager", "android.media.projection.MediaProjectionManager");
        putClass(json, "IMediaProjectionManager", "android.media.projection.IMediaProjectionManager");
        putClass(json, "ServiceManager", "android.os.ServiceManager");
        putClass(json, "ScreenCapturerAndroid", "org.webrtc.ScreenCapturerAndroid");
        putClass(json, "SurfaceTextureHelper", "org.webrtc.SurfaceTextureHelper");
        return json;
    }

    private static void putClass(JSONObject json, String key, String name) throws JSONException {
        try {
            Class.forName(name);
            json.put(key, true);
        } catch (Throwable t) {
            json.put(key, false);
            json.put(key + "Error", t.toString());
        }
    }

    private static JSONObject displayJson(Point display) throws JSONException {
        JSONObject json = new JSONObject();
        int width = display == null ? 0 : display.x;
        int height = display == null ? 0 : display.y;
        json.put("width", width);
        json.put("height", height);
        JSONArray targets = new JSONArray();
        targets.put(targetJson("minimum", 1080, heightFor(width, height, 1080), 30));
        targets.put(targetJson("default", 1080, heightFor(width, height, 1080), 60));
        json.put("targets", targets);
        return json;
    }

    private static JSONObject targetJson(String label, int width, int height, int fps) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("label", label);
        json.put("width", width);
        json.put("height", height);
        json.put("fps", fps);
        return json;
    }

    private static int heightFor(int displayWidth, int displayHeight, int width) {
        if (displayWidth <= 0 || displayHeight <= 0) {
            return 2340;
        }
        return even(Math.round(width * (displayHeight / (float) displayWidth)));
    }

    private static int even(int value) {
        return value % 2 == 0 ? value : value + 1;
    }
}
