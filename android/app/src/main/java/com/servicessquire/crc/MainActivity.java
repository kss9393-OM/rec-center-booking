// Campus Recreation Center — Android app
// © 2026 Services Squire LLC. All rights reserved.
//
// A full-screen shell around the web app, plus what a browser can't do on its own:
//  - reads the Honeywell hardware scanner directly (Honeywell intent API), so scanning
//    works without changing any scanner settings; keyboard-wedge input still works too
//  - saves exported PDF/CSV files and passes to Downloads
//  - camera permission for camera scanning, vibration, keeping the screen on while scanning

package com.servicessquire.crc;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

public class MainActivity extends Activity {

    static final String START_URL = "https://kss9393-om.github.io/rec-center-booking/";
    static final String SITE_HOST = "kss9393-om.github.io";
    static final String SITE_PATH = "/rec-center-booking";

    // Honeywell intent API
    static final String HW_PACKAGE = "com.intermec.datacollectionservice";
    static final String HW_CLAIM = "com.honeywell.aidc.action.ACTION_CLAIM_SCANNER";
    static final String HW_RELEASE = "com.honeywell.aidc.action.ACTION_RELEASE_SCANNER";
    static final String HW_EXTRA_SCANNER = "com.honeywell.aidc.extra.EXTRA_SCANNER";
    static final String HW_EXTRA_PROFILE = "com.honeywell.aidc.extra.EXTRA_PROFILE";
    static final String HW_EXTRA_PROPERTIES = "com.honeywell.aidc.extra.EXTRA_PROPERTIES";
    static final String SCAN_ACTION = "com.servicessquire.crc.SCAN";

    private WebView web;
    private PermissionRequest pendingPermission;
    private boolean receiverOn = false;

    private final BroadcastReceiver scanReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            String data = intent.getStringExtra("data");
            if (data == null) {
                byte[] bytes = intent.getByteArrayExtra("dataBytes");
                if (bytes != null) data = new String(bytes);
            }
            if (data == null || web == null) return;
            String js = "window.__crcScan&&window.__crcScan(" + JSONObject.quote(data.trim()) + ")";
            web.evaluateJavascript(js, null);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        web = new WebView(this);
        web.setBackgroundColor(Color.WHITE);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUserAgentString(s.getUserAgentString() + " CRCApp/" + BuildConfig.VERSION_NAME);

        web.addJavascriptInterface(new Bridge(), "AndroidApp");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                String path = u.getPath() == null ? "" : u.getPath();
                if (SITE_HOST.equalsIgnoreCase(u.getHost()) && path.startsWith(SITE_PATH)) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception ignored) { }
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError err) {
                if (req.isForMainFrame()) showOffline();
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> {
                    boolean wantsCamera = false;
                    for (String r : request.getResources()) {
                        if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) wantsCamera = true;
                    }
                    if (!wantsCamera) { request.deny(); return; }
                    if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        request.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
                    } else {
                        pendingPermission = request;
                        requestPermissions(new String[]{Manifest.permission.CAMERA}, 1);
                    }
                });
            }
        });

        if (savedInstanceState != null) web.restoreState(savedInstanceState);
        else web.loadUrl(START_URL);
    }

    private void showOffline() {
        String html = "<!doctype html><html dir='rtl'><meta name='viewport' content='width=device-width,initial-scale=1'>"
                + "<body style='font-family:sans-serif;display:grid;place-items:center;height:90vh;margin:0;text-align:center;padding:24px;color:#111827'>"
                + "<div><h2 style='color:#0F5F4A'>لا يوجد اتصال</h2><p>تحقق من الاتصال بالإنترنت.</p><p style='color:#5B6576'>No internet connection.</p>"
                + "<button style='font-size:18px;padding:12px 28px;border-radius:10px;border:0;background:#0F5F4A;color:#fff' "
                + "onclick='AndroidApp.reload()'>إعادة المحاولة · Retry</button></div></body></html>";
        web.loadDataWithBaseURL(START_URL, html, "text/html", "utf-8", null);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (pendingPermission == null) return;
        if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) {
            pendingPermission.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
        } else {
            pendingPermission.deny();
        }
        pendingPermission = null;
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
        IntentFilter f = new IntentFilter(SCAN_ACTION);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(scanReceiver, f, Context.RECEIVER_EXPORTED);
        else registerReceiver(scanReceiver, f);
        receiverOn = true;
        claimScanner();
    }

    @Override
    protected void onPause() {
        releaseScanner();
        if (receiverOn) { try { unregisterReceiver(scanReceiver); } catch (Exception ignored) { } receiverOn = false; }
        web.onPause();
        super.onPause();
    }

    // On a Honeywell device: deliver scans to this app as broadcasts while it's in front.
    // On any other phone this broadcast simply has no receiver.
    private void claimScanner() {
        try {
            Bundle props = new Bundle();
            props.putBoolean("DPR_DATA_INTENT", true);
            props.putString("DPR_DATA_INTENT_ACTION", SCAN_ACTION);
            Intent i = new Intent(HW_CLAIM);
            i.setPackage(HW_PACKAGE);
            i.putExtra(HW_EXTRA_SCANNER, "dcs.scanner.imager");
            i.putExtra(HW_EXTRA_PROFILE, "CRC");
            i.putExtra(HW_EXTRA_PROPERTIES, props);
            sendBroadcast(i);
        } catch (Exception ignored) { }
    }

    private void releaseScanner() {
        try {
            Intent i = new Intent(HW_RELEASE);
            i.setPackage(HW_PACKAGE);
            sendBroadcast(i);
        } catch (Exception ignored) { }
    }

    /** Functions the web app can call as window.AndroidApp.*  */
    class Bridge {
        @JavascriptInterface
        public String version() { return BuildConfig.VERSION_NAME; }

        @JavascriptInterface
        public void reload() { runOnUiThread(() -> web.loadUrl(START_URL)); }

        @JavascriptInterface
        public void keepScreenOn(final boolean on) {
            runOnUiThread(() -> {
                if (on) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            });
        }

        @JavascriptInterface
        public void vibrate(long ms) {
            try {
                Vibrator v = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                if (v == null) return;
                if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE));
                else v.vibrate(ms);
            } catch (Exception ignored) { }
        }

        /** Save a file the page generated (base64) to the device's Downloads folder. */
        @JavascriptInterface
        public boolean saveFile(String name, String mime, String base64) {
            try {
                String safe = name.replaceAll("[\\\\/:*?\"<>|]", "_");
                byte[] bytes = Base64.decode(base64, Base64.DEFAULT);
                if (Build.VERSION.SDK_INT >= 29) {
                    ContentValues cv = new ContentValues();
                    cv.put(MediaStore.MediaColumns.DISPLAY_NAME, safe);
                    cv.put(MediaStore.MediaColumns.MIME_TYPE, mime);
                    cv.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                    Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
                    if (uri == null) return false;
                    try (OutputStream os = getContentResolver().openOutputStream(uri)) { os.write(bytes); }
                } else {
                    File dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                    if (dir == null) return false;
                    try (FileOutputStream os = new FileOutputStream(new File(dir, safe))) { os.write(bytes); }
                }
                runOnUiThread(() -> Toast.makeText(MainActivity.this, getString(R.string.saved) + ": " + safe, Toast.LENGTH_LONG).show());
                return true;
            } catch (Exception e) {
                return false;
            }
        }
    }
}
