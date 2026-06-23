package com.smartisax.browser;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.webkit.WebResourceRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public final class ShellActivity extends Activity {
    private String homeUrl;
    private WebView webView;
    private ShellBridge bridge;
    private boolean nativeBridgeAttached;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        homeUrl = "file:///android_asset/shell/index.html";

        WebView view = new WebView(this);
        webView = view;

        WebSettings settings = view.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        bridge = new ShellBridge(getApplicationContext());
        view.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                setBridgeForUrl(url);
                return false;
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                setBridgeForUrl(request == null || request.getUrl() == null ? "" : request.getUrl().toString());
                return false;
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                setBridgeForUrl(url);
                super.onPageStarted(view, url, favicon);
            }
        });
        view.setWebChromeClient(new WebChromeClient());

        setContentView(view);
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            if (nativeBridgeAttached) {
                webView.removeJavascriptInterface("SmartisaxNative");
                nativeBridgeAttached = false;
            }
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        WebView view = webView;
        if (view == null) {
            super.onBackPressed();
            return;
        }
        if (view.canGoBack()) {
            view.goBack();
            return;
        }
        if (!isShellUrl(view.getUrl())) {
            loadUrl(homeUrl);
            return;
        }
        moveTaskToBack(true);
    }

    private void handleIntent(Intent intent) {
        if (intent != null && Intent.ACTION_VIEW.equals(intent.getAction())) {
            String data = intent.getDataString();
            if (data != null && data.length() > 0) {
                loadUrl(data);
                return;
            }
        }
        loadUrl(homeUrl);
    }

    private void loadUrl(String url) {
        if (webView != null) {
            setBridgeForUrl(url);
            webView.loadUrl(url);
        }
    }

    private void setBridgeForUrl(String url) {
        if (webView == null) {
            return;
        }
        boolean allowNativeBridge = isShellUrl(url);
        if (allowNativeBridge && !nativeBridgeAttached) {
            webView.addJavascriptInterface(bridge, "SmartisaxNative");
            nativeBridgeAttached = true;
        } else if (!allowNativeBridge && nativeBridgeAttached) {
            webView.removeJavascriptInterface("SmartisaxNative");
            nativeBridgeAttached = false;
        }
    }

    private static boolean isShellUrl(String url) {
        return url != null && url.startsWith("file:///android_asset/shell/");
    }
}
