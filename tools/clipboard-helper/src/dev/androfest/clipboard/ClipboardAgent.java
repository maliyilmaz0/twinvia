package dev.androfest.clipboard;

import android.content.ClipData;
import android.net.LocalServerSocket;
import java.net.Socket;
import java.net.InetSocketAddress;
import java.security.MessageDigest;
import java.security.SecureRandom;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.FileInputStream;
import android.system.Os;
import android.system.OsConstants;
import java.io.FileDescriptor;
import android.os.Binder;
import android.os.IBinder;
import android.os.Parcel;
import android.os.Process;
import org.json.JSONObject;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Shell-UID clipboard adapter. No remote networking, command execution or input injection. */
public final class ClipboardAgent {
    private static final String SHELL = "com.android.shell";
    private static final String LISTENER = "android.content.IOnPrimaryClipChangedListener";
    private static final int LIMIT = 128 * 1024;
    private final Object service;
    private final Method get, set, add, remove;
    private final int userId;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    private ClipboardAgent(int userId) throws Exception {
        this.userId = userId;
        IBinder binder = (IBinder) Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class).invoke(null, "clipboard");
        service = Class.forName("android.content.IClipboard$Stub").getMethod("asInterface", IBinder.class).invoke(null, binder);
        Class<?> listener = Class.forName(LISTENER);
        Class<?> api = Class.forName("android.content.IClipboard");
        // ABI verified on Android 16 / One UI 8. Fail closed on incompatible APIs.
        get = api.getMethod("getPrimaryClip", String.class, String.class, int.class, int.class);
        set = api.getMethod("setPrimaryClip", ClipData.class, String.class, String.class, int.class, int.class);
        add = api.getMethod("addPrimaryClipChangedListener", listener, String.class, String.class, int.class, int.class);
        remove = api.getMethod("removePrimaryClipChangedListener", listener, String.class, String.class, int.class, int.class);
    }

    private final class Session {
        final Socket socket;
        final DataOutputStream output;
        boolean enabled;
        String lastText;
        volatile boolean closed;
        Session(Socket socket) throws IOException { this.socket = socket; output = new DataOutputStream(socket.getOutputStream()); }
        synchronized void send(JSONObject value) throws IOException {
            byte[] bytes = value.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
            if (bytes.length > LIMIT) throw new IOException("Frame too large");
            output.writeInt(bytes.length); output.write(bytes); output.flush();
        }
        ClipData clip() throws Exception { return (ClipData)get.invoke(service, SHELL, null, userId, 0); }
        String text(ClipData clip) {
            if (clip == null || clip.getItemCount() == 0 || clip.getItemAt(0).getText() == null) return null;
            String value = clip.getItemAt(0).getText().toString();
            return value.isEmpty() || value.length() > 16384 ? null : value;
        }
        void changed() {
            if (closed || !enabled) return;
            try {
                ClipData clip = clip();
                String value = text(clip);
                boolean sensitive = clip != null && clip.getDescription().getExtras() != null &&
                        clip.getDescription().getExtras().getBoolean("android.content.extra.IS_SENSITIVE", false);
                if (value == null || sensitive) { lastText = null; return; }
                if (value.equals(lastText)) return;
                lastText = value;
                send(new JSONObject().put("kind", "changed").put("text", value));
            } catch (Exception failure) { close(); }
        }
        void command(JSONObject value) {
            if (closed) return;
            try {
                switch (value.getString("kind")) {
                    case "configure":
                        enabled = value.getBoolean("enabled");
                        // Baseline only: do not send historical clipboard content on connect/unlock.
                        lastText = enabled ? text(clip()) : null;
                        break;
                    case "set":
                        String id = value.getString("id");
                        String text = value.getString("text");
                        if (!enabled || text.isEmpty() || text.length() > 16384) throw new IOException("Clipboard unavailable");
                        lastText = text; // Suppress our own Binder callback.
                        set.invoke(service, ClipData.newPlainText("Twinvia", text), SHELL, null, userId, 0);
                        send(new JSONObject().put("kind", "applied").put("id", id));
                        break;
                    case "setImage": {
                        String imageId = value.getString("id");
                        android.net.Uri uri = android.net.Uri.parse(value.getString("uri"));
                        if (!enabled || !"content".equals(uri.getScheme()) ||
                                !("dev.androfest.android.clipboard".equals(uri.getAuthority()) ||
                                  "dev.androfest.android.pairingtest.clipboard".equals(uri.getAuthority())) ||
                                !uri.getPath().startsWith("/images/")) throw new IOException("Invalid image URI");
                        lastText = null;
                        ClipData imageClip = new ClipData(new android.content.ClipDescription("Twinvia image",
                            new String[]{"image/png"}), new ClipData.Item(uri));
                        set.invoke(service, imageClip, SHELL, null, userId, 0);
                        send(new JSONObject().put("kind", "applied").put("id", imageId));
                        break;
                    }
                    default: throw new IOException("Unknown command");
                }
            } catch (Exception failure) { close(); }
        }
        void close() { closed = true; try { socket.close(); } catch (IOException ignored) { } }
    }

    private void run(int targetUid) throws Exception {
        String name = "dev.androfest.clipboard." + targetUid;
        // Per-UID singleton. A second start cannot create another listener/echo loop.
        try (LocalServerSocket singleton = new LocalServerSocket(name + ".agent")) {
            System.out.println("Twinvia clipboard helper ready");
            String lastFailure = "";
            while (!Thread.currentThread().isInterrupted()) {
                Session session = null; Object listener = null;
                String phase = "connect";
                try {
                    JSONObject metadata = metadata(targetUid);
                    Socket socket = new Socket();
                    try {
                        socket.connect(new InetSocketAddress("127.0.0.1", metadata.getInt("port")), 3000);
                        socket.setSoTimeout(3000);
                        session = new Session(socket);
                        DataInputStream input = new DataInputStream(socket.getInputStream());
                        JSONObject challenge = read(input, 1024);
                        if (!"challenge".equals(challenge.getString("kind"))) throw new IOException("Invalid handshake");
                        String nonce = randomHex();
                        String appNonce = challenge.getString("nonce");
                        if (!appNonce.matches("[a-f0-9]{32}")) throw new IOException("Invalid nonce");
                        String secret = metadata.getString("secret");
                        session.send(new JSONObject().put("kind", "authenticate").put("nonce", nonce)
                                .put("proof", proof(secret, "androfest.clipboard.helper.v1\n"+appNonce+"\n"+nonce)));
                        JSONObject response = read(input, 1024);
                        String expected = proof(secret, "androfest.clipboard.app.v1\n"+appNonce+"\n"+nonce);
                        if (!"authenticated".equals(response.getString("kind")) || !MessageDigest.isEqual(
                                expected.getBytes(java.nio.charset.StandardCharsets.UTF_8), response.getString("proof").getBytes(java.nio.charset.StandardCharsets.UTF_8)))
                            throw new IOException("Invalid app authentication");
                        socket.setSoTimeout(0);
                    } catch (Exception failure) { socket.close(); throw failure; }
                    final Session current = session;
                    Binder callback = new Binder() {
                        @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
                            if (code == INTERFACE_TRANSACTION) { if (reply != null) reply.writeString(LISTENER); return true; }
                            if (code != FIRST_CALL_TRANSACTION) return false;
                            data.enforceInterface(LISTENER);
                            worker.execute(current::changed);
                            return true;
                        }
                    };
                    Class<?> type = Class.forName(LISTENER);
                    listener = Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[]{type}, (proxy, method, arguments) -> {
                        if (method.getName().equals("asBinder")) return callback;
                        if (method.getName().equals("dispatchPrimaryClipChanged")) { worker.execute(current::changed); return null; }
                        if (method.getName().equals("hashCode")) return System.identityHashCode(proxy);
                        if (method.getName().equals("equals")) return proxy == arguments[0];
                        return "Twinvia clipboard listener";
                    });
                    phase = "register-listener";
                    add.invoke(service, listener, SHELL, null, userId, 0);
                    phase = "clipboard-session";
                    current.send(new JSONObject().put("kind", "ready").put("version", 1));
                    DataInputStream input = new DataInputStream(socket.getInputStream());
                    while (!current.closed) {
                        int size = input.readInt();
                        if (size <= 0 || size > LIMIT) throw new IOException("Invalid frame");
                        byte[] bytes = new byte[size]; input.readFully(bytes);
                        JSONObject message = new JSONObject(new String(bytes, java.nio.charset.StandardCharsets.UTF_8));
                        worker.execute(() -> current.command(message));
                    }
                } catch (Exception failure) {
                    // Phase/class only; never exception messages or clipboard content.
                    String reason = phase + ":" + failure.getClass().getSimpleName();
                    if (failure.getCause() instanceof android.system.ErrnoException)
                        reason += ":errno=" + ((android.system.ErrnoException)failure.getCause()).errno;
                    if (!reason.equals(lastFailure)) { System.out.println("Clipboard waiting " + reason); lastFailure = reason; }
                } finally {
                    if (session != null) session.close();
                    if (listener != null) try { remove.invoke(service, listener, SHELL, null, userId, 0); } catch (Exception ignored) { }
                }
                Thread.sleep(1000);
            }
        }
    }

    private static JSONObject metadata(int uid) throws Exception {
        String path = "/data/local/tmp/androfest-clipboard-"+uid+".json";
        FileDescriptor fd = Os.open(path, OsConstants.O_RDONLY | OsConstants.O_NOFOLLOW, 0);
        try (FileInputStream input = new FileInputStream(fd)) {
            android.system.StructStat info = Os.fstat(fd);
            if (info.st_uid != 2000 || (info.st_mode & 077) != 0 || info.st_size > 1024) throw new SecurityException("Private shell metadata required");
            byte[] data = new byte[1025]; int count = input.read(data);
            if (count <= 0 || count > 1024) throw new IOException("Invalid metadata");
            JSONObject result = new JSONObject(new String(data, 0, count, java.nio.charset.StandardCharsets.UTF_8));
            if (result.getInt("uid") != uid || result.getInt("port") < 1024 || result.getInt("port") > 65535 ||
                    !result.getString("secret").matches("[a-f0-9]{64}")) throw new IOException("Invalid metadata");
            return result;
        }
    }
    private static JSONObject read(DataInputStream input, int limit) throws Exception {
        int size = input.readInt(); if (size <= 0 || size > limit) throw new IOException("Invalid frame");
        byte[] data = new byte[size]; input.readFully(data);
        return new JSONObject(new String(data, java.nio.charset.StandardCharsets.UTF_8));
    }
    private static String randomHex() {
        byte[] nonce = new byte[16]; new SecureRandom().nextBytes(nonce); StringBuilder result = new StringBuilder();
        for (byte b : nonce) result.append(String.format("%02x", b)); return result.toString();
    }
    private static String proof(String secret, String message) throws Exception {
        byte[] key = new byte[32]; for (int i=0; i<32; i++) key[i]=(byte)Integer.parseInt(secret.substring(i*2, i*2+2),16);
        Mac mac = Mac.getInstance("HmacSHA256"); mac.init(new SecretKeySpec(key, "HmacSHA256"));
        StringBuilder result = new StringBuilder(); for (byte b : mac.doFinal(message.getBytes(java.nio.charset.StandardCharsets.UTF_8))) result.append(String.format("%02x", b));
        return result.toString();
    }

    public static void main(String[] args) throws Exception {
        if (Process.myUid() != 2000 || args.length != 1) throw new SecurityException("Shell UID required");
        int uid = Integer.parseInt(args[0]);
        if (uid % 100000 < 10000) throw new IllegalArgumentException("Application UID required");
        new ClipboardAgent(uid / 100000).run(uid);
    }
}
