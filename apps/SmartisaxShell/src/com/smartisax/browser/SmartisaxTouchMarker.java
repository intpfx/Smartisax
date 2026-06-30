package com.smartisax.browser;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.view.ViewTreeObserver;
import android.widget.FrameLayout;
import java.lang.ref.WeakReference;
import java.util.Locale;
import org.json.JSONException;
import org.json.JSONObject;

final class SmartisaxTouchMarker {
    static final String MODE = "touch-photon-marker";
    static final String DRAW_SYNC_MODE = "marker-draw-synced-capture-boost";
    static final String DRAW_URGENT_MODE = "draw-urgent-input-frame-boost";
    static final String PRESENTATION_TAIL_MODE = "marker-visible-tail-presentation-cadence";

    private static final Object LOCK = new Object();
    private static final int[] COLORS = {
            Color.rgb(255, 0, 255),
            Color.rgb(0, 229, 255),
            Color.rgb(255, 224, 0),
            Color.rgb(0, 255, 128)
    };
    private static final int MARKER_VISIBLE_BURST_FRAMES = 4;
    private static final long MARKER_VISIBLE_MS = 1200L;
    private static WeakReference<MarkerView> markerRef = new WeakReference<MarkerView>(null);
    private static long generation;
    private static long lastShownElapsedMs;
    private static long lastVisibleUntilElapsedMs;
    private static int lastColor = COLORS[0];
    private static int lastLeft;
    private static int lastTop;
    private static int lastWidth;
    private static int lastHeight;
    private static int lastDisplayWidth = 1080;
    private static int lastDisplayHeight = 2340;
    private static int lastInputX;
    private static int lastInputY;
    private static String lastType = "";
    private static long lastDrawGeneration;
    private static long lastDrawnElapsedMs;
    private static long lastDrawLatencyMs;
    private static long drawBoostRequests;
    private static long drawBoostBurstFrames;

    private SmartisaxTouchMarker() {
    }

    static void attach(FrameLayout root) {
        if (root == null) {
            return;
        }
        MarkerView marker = new MarkerView(root.getContext());
        int size = Math.max(96, Math.round(56 * root.getResources().getDisplayMetrics().density));
        int margin = Math.max(12, Math.round(12 * root.getResources().getDisplayMetrics().density));
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(size, size);
        params.gravity = Gravity.TOP | Gravity.LEFT;
        params.leftMargin = margin;
        params.topMargin = margin;
        root.addView(marker, params);
        synchronized (LOCK) {
            markerRef = new WeakReference<MarkerView>(marker);
            lastWidth = size;
            lastHeight = size;
            lastLeft = margin;
            lastTop = margin;
            lastDisplayWidth = Math.max(1, root.getResources().getDisplayMetrics().widthPixels);
            lastDisplayHeight = Math.max(1, root.getResources().getDisplayMetrics().heightPixels);
        }
        marker.post(new Runnable() {
            @Override
            public void run() {
                marker.updateRegion();
            }
        });
    }

    static void detach() {
        MarkerView marker;
        synchronized (LOCK) {
            marker = markerRef.get();
            markerRef = new WeakReference<MarkerView>(null);
        }
        if (marker != null) {
            marker.clear();
        }
    }

    static JSONObject flash(String type, long inputSeq, int inputX, int inputY) throws JSONException {
        final MarkerView marker;
        final long nextGeneration;
        final int color;
        final long shownElapsedMs = SystemClock.elapsedRealtime();
        synchronized (LOCK) {
            generation += 1;
            nextGeneration = generation;
            color = COLORS[(int) (nextGeneration % COLORS.length)];
            lastColor = color;
            lastShownElapsedMs = shownElapsedMs;
            lastVisibleUntilElapsedMs = shownElapsedMs + MARKER_VISIBLE_MS;
            lastInputX = inputX;
            lastInputY = inputY;
            lastType = type == null ? "" : type;
            marker = markerRef.get();
        }
        if (marker != null) {
            marker.show(nextGeneration, color, type, inputSeq, inputX, inputY, shownElapsedMs);
        }
        return statusJson();
    }

    static JSONObject statusJson() throws JSONException {
        long now = SystemClock.elapsedRealtime();
        JSONObject json = new JSONObject();
        synchronized (LOCK) {
            json.put("mode", MODE);
            json.put("supported", markerRef.get() != null);
            json.put("generation", generation);
            json.put("visible", now <= lastVisibleUntilElapsedMs);
            json.put("shownElapsedMs", lastShownElapsedMs);
            json.put("visibleUntilElapsedMs", lastVisibleUntilElapsedMs);
            json.put("type", lastType);
            json.put("drawSync", DRAW_SYNC_MODE);
            json.put("drawUrgentBoost", DRAW_URGENT_MODE);
            json.put("presentationTailCadence", PRESENTATION_TAIL_MODE);
            json.put("visibleMs", MARKER_VISIBLE_MS);
            json.put("lastDrawGeneration", lastDrawGeneration);
            json.put("lastDrawnElapsedMs", lastDrawnElapsedMs);
            json.put("lastDrawLatencyMs", lastDrawLatencyMs);
            json.put("drawBoostRequests", drawBoostRequests);
            json.put("drawBoostBurstFrames", drawBoostBurstFrames);
            json.put("inputX", lastInputX);
            json.put("inputY", lastInputY);
            json.put("displayWidth", lastDisplayWidth);
            json.put("displayHeight", lastDisplayHeight);
            JSONObject region = new JSONObject();
            region.put("left", lastLeft);
            region.put("top", lastTop);
            region.put("width", lastWidth);
            region.put("height", lastHeight);
            json.put("region", region);
            json.put("color", colorJson(lastColor));
        }
        return json;
    }

    private static void rememberDrawSyncedBoost(long drawGeneration, long shownElapsedMs,
            long drawnElapsedMs, int burstFrames) {
        synchronized (LOCK) {
            lastDrawGeneration = drawGeneration;
            lastDrawnElapsedMs = drawnElapsedMs;
            lastDrawLatencyMs = Math.max(0L, drawnElapsedMs - shownElapsedMs);
            drawBoostRequests += 1;
            drawBoostBurstFrames += Math.max(0, burstFrames);
        }
    }

    private static JSONObject colorJson(int color) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("argb", String.format(Locale.US, "#%08X", color));
        json.put("r", Color.red(color));
        json.put("g", Color.green(color));
        json.put("b", Color.blue(color));
        return json;
    }

    private static void rememberRegion(MarkerView view) {
        if (view == null) {
            return;
        }
        int[] location = new int[2];
        view.getLocationOnScreen(location);
        View root = view.getRootView();
        synchronized (LOCK) {
            lastLeft = Math.max(0, location[0]);
            lastTop = Math.max(0, location[1]);
            lastWidth = Math.max(1, view.getWidth());
            lastHeight = Math.max(1, view.getHeight());
            if (root != null && root.getWidth() > 0 && root.getHeight() > 0) {
                lastDisplayWidth = root.getWidth();
                lastDisplayHeight = root.getHeight();
            }
        }
    }

    static final class MarkerView extends View {
        private final Handler handler = new Handler(Looper.getMainLooper());
        private final Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ringPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Runnable hide = new Runnable() {
            @Override
            public void run() {
                active = false;
                invalidate();
            }
        };
        private boolean active;
        private long activeGeneration;
        private long visibleUntilElapsedMs;
        private int activeColor = COLORS[0];
        private int inputX;
        private int inputY;
        private String activeType = "";
        private boolean drawBoostArmed;
        private ViewTreeObserver.OnDrawListener drawBoostListener;

        MarkerView(android.content.Context context) {
            super(context);
            setWillNotDraw(false);
            setClickable(false);
            setFocusable(false);
            ringPaint.setStyle(Paint.Style.STROKE);
            ringPaint.setStrokeWidth(Math.max(3f, getResources().getDisplayMetrics().density * 2f));
            ringPaint.setColor(Color.WHITE);
        }

        void show(final long generation, final int color, final String type, final long seq,
                final int x, final int y, final long shownElapsedMs) {
            post(new Runnable() {
                @Override
                public void run() {
                    updateRegion();
                    active = true;
                    activeGeneration = generation;
                    activeColor = color;
                    activeType = type == null ? "" : type;
                    inputX = x;
                    inputY = y;
                    visibleUntilElapsedMs = shownElapsedMs + MARKER_VISIBLE_MS;
                    handler.removeCallbacks(hide);
                    handler.postDelayed(hide, MARKER_VISIBLE_MS);
                    armDrawSyncedBoost(generation, shownElapsedMs);
                    invalidate();
                }
            });
        }

        private void armDrawSyncedBoost(final long generation, final long shownElapsedMs) {
            removeDrawBoostListener();
            drawBoostArmed = true;
            final ViewTreeObserver.OnDrawListener[] listenerRef = new ViewTreeObserver.OnDrawListener[1];
            ViewTreeObserver.OnDrawListener listener = new ViewTreeObserver.OnDrawListener() {
                @Override
                public void onDraw() {
                    if (!drawBoostArmed || activeGeneration != generation) {
                        return;
                    }
                    drawBoostArmed = false;
                    final long drawnElapsedMs = SystemClock.elapsedRealtime();
                    rememberDrawSyncedBoost(
                            generation,
                            shownElapsedMs,
                            drawnElapsedMs,
                            MARKER_VISIBLE_BURST_FRAMES);
                    SmartisaxWebRtcRuntime.requestUrgentInputFrameBoost("touch-marker-drawn-urgent");
                    SmartisaxWebRtcRuntime.requestInputFrameBoostBurst(
                            "touch-marker-drawn-burst-presentation-tail", MARKER_VISIBLE_BURST_FRAMES);
                    post(new Runnable() {
                        @Override
                        public void run() {
                            if (drawBoostListener == listenerRef[0]) {
                                removeDrawBoostListener();
                            }
                        }
                    });
                }
            };
            listenerRef[0] = listener;
            drawBoostListener = listener;
            ViewTreeObserver observer = getViewTreeObserver();
            if (observer != null && observer.isAlive()) {
                observer.addOnDrawListener(listener);
            }
        }

        private void removeDrawBoostListener() {
            drawBoostArmed = false;
            ViewTreeObserver.OnDrawListener listener = drawBoostListener;
            drawBoostListener = null;
            if (listener == null) {
                return;
            }
            ViewTreeObserver observer = getViewTreeObserver();
            if (observer != null && observer.isAlive()) {
                try {
                    observer.removeOnDrawListener(listener);
                } catch (IllegalStateException ignored) {
                }
            }
        }

        void clear() {
            post(new Runnable() {
                @Override
                public void run() {
                    handler.removeCallbacks(hide);
                    removeDrawBoostListener();
                    active = false;
                    invalidate();
                }
            });
        }

        void updateRegion() {
            rememberRegion(this);
        }

        @Override
        protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            updateRegion();
        }

        @Override
        protected void onDetachedFromWindow() {
            removeDrawBoostListener();
            super.onDetachedFromWindow();
        }

        @Override
        protected void onSizeChanged(int w, int h, int oldw, int oldh) {
            super.onSizeChanged(w, h, oldw, oldh);
            updateRegion();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (!active || SystemClock.elapsedRealtime() > visibleUntilElapsedMs) {
                return;
            }
            int width = getWidth();
            int height = getHeight();
            fillPaint.setStyle(Paint.Style.FILL);
            fillPaint.setColor(activeColor);
            canvas.drawRect(0, 0, width, height, fillPaint);
            canvas.drawRect(2, 2, width - 2, height - 2, ringPaint);
            fillPaint.setColor(Color.BLACK);
            float centerX = width * 0.5f;
            float centerY = height * 0.5f;
            canvas.drawCircle(centerX, centerY, Math.max(6f, Math.min(width, height) * 0.16f), fillPaint);
            fillPaint.setColor(Color.WHITE);
            canvas.drawCircle(centerX, centerY, Math.max(3f, Math.min(width, height) * 0.07f), fillPaint);
        }
    }
}
