package dev.androfest.clipboardprobe;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.os.Bundle;
import android.widget.TextView;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;

/** Separate UID to verify actual copying/pasting while the bridge is in the background. */
public final class ProbeActivity extends Activity {
    private boolean pending;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView view = new TextView(this); view.setText("Twinvia automatic clipboard test"); setContentView(view);
        pending = true;
    }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); pending = true; getWindow().getDecorView().postDelayed(this::execute, 300); }
    @Override public void onWindowFocusChanged(boolean focus) { super.onWindowFocusChanged(focus); if (focus) getWindow().getDecorView().postDelayed(this::execute, 300); }
    private void execute() {
        if (!pending || !hasWindowFocus()) return;
        pending = false;
        try {
            ClipboardManager manager = getSystemService(ClipboardManager.class);
            String mode = getIntent().getStringExtra("mode");
            if ("copy".equals(mode)) {
                String text = getIntent().getStringExtra("text");
                if (text == null || !text.startsWith("androfest-test-") || text.length() > 16384) throw new IllegalArgumentException();
                manager.setPrimaryClip(ClipData.newPlainText("Twinvia test", text));
            }
            ClipData clip = manager.getPrimaryClip();
            CharSequence text = clip != null && clip.getItemCount() > 0 ? clip.getItemAt(0).getText() : null;
            String hash = "";
            if (text != null) {
                byte[] digest = MessageDigest.getInstance("SHA-256").digest(text.toString().getBytes(StandardCharsets.UTF_8));
                StringBuilder value = new StringBuilder(); for (byte b : digest) value.append(String.format("%02x", b)); hash = value.toString();
            }
            JSONObject result = new JSONObject().put("mode", mode).put("sha256", hash);
            if ("image".equals(mode) && clip != null && clip.getItemCount() == 1 && clip.getItemAt(0).getUri() != null) {
                try (java.io.InputStream input = getContentResolver().openInputStream(clip.getItemAt(0).getUri())) {
                    MessageDigest digest = MessageDigest.getInstance("SHA-256");
                    byte[] buffer = new byte[8192]; int count, total = 0;
                    while ((count = input.read(buffer)) != -1) { total += count; if (total > 20 * 1024 * 1024) throw new IllegalArgumentException(); digest.update(buffer, 0, count); }
                    StringBuilder value = new StringBuilder(); for (byte b : digest.digest()) value.append(String.format("%02x", b));
                    result.put("imageSha256", value.toString()).put("imageBytes", total)
                        .put("pngMime", clip.getDescription().hasMimeType("image/png"));
                }
            }
            Files.write(getFilesDir().toPath().resolve("result.json"), result.toString().getBytes(StandardCharsets.UTF_8));
        } catch (Exception ignored) { }
    }
}
