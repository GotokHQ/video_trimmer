package app.peerwaya.video_trimmer;

import android.Manifest;
import android.annotation.TargetApi;
import android.app.Activity;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.util.Log;
import android.util.SparseArray;

import androidx.annotation.NonNull;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import app.peerwaya.video_trimmer.trimmer.AndroidBmpUtil;
import app.peerwaya.video_trimmer.trimmer.BackgroundExecutor;
import app.peerwaya.video_trimmer.trimmer.TrimVideoUtils;
import app.peerwaya.video_trimmer.utils.Callback;
import app.peerwaya.video_trimmer.utils.PermissionUtils;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * VideoTrimmerPlugin
 */
public class VideoTrimmerPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
    private static final String TAG = VideoTrimmerPlugin.class.getSimpleName();
    private static final String PERMISSION_WRITE_EXTERNAL_STORAGE = Manifest.permission.WRITE_EXTERNAL_STORAGE;
    private static final String CHANNEL_NAME  = "github.com/peerwaya/gotok/video_trimmer";
    private Context context;
    private final SparseArray<FetchVideoThumbnail> tasks = new SparseArray<>();
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private MethodChannel channel;
    private int nextListenerHandle = 0;
    private Handler handler = new Handler(Looper.getMainLooper());
    private Activity mActivity;
    private BinaryMessenger messenger;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getFlutterEngine().getDartExecutor(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);
        messenger = flutterPluginBinding.getBinaryMessenger();
        context = flutterPluginBinding.getApplicationContext();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        messenger = null;
        context = null;
    }


    @Override
    public void onMethodCall(MethodCall call, Result result) {
        String method = call.method;
        if (method.equals("trimVideo")) {
            String inputFileS = call.argument("inputFile");
            String outputFileS = call.argument("outputFile");
            int startMs = call.argument("startMs");
            int endMs = call.argument("endMs");
            final File inputFile = new File(inputFileS);
            final File outputFile = new File(outputFileS);
            TrimVideoUtils.startTrim(inputFile, outputFile, startMs, endMs, result);
        } else if (method.equals("initVideoThumbsRequest")) {
            String videoFile = call.argument("videoFile");
            Uri uri = Uri.parse(videoFile);
            int handle = nextListenerHandle++;
            FetchVideoThumbnail fetchVideoThumbnailTask = new FetchVideoThumbnail(uri, handle, messenger, context);
            tasks.put(handle, fetchVideoThumbnailTask);
            result.success(handle);
        } else if (method.equals("startVideoThumbsRequest")) {
            int handle = call.argument("handle");
            FetchVideoThumbnail task = tasks.get(handle);
            if (task == null) {
                result.success(false);
                return;
            }
            int startMs = call.argument("startMs");
            int endMs = call.argument("endMs");
            int totalThumbsCount = call.argument("totalThumbsCount");
            double width = call.argument("width");
            double height = call.argument("height");
            task.executeOnExecutor(AsyncTask.THREAD_POOL_EXECUTOR, startMs, endMs, totalThumbsCount, (int) width, (int) height);
            result.success(true);
        } else if (method.equals("stopVideoThumbsRequest")) {
            int handle = call.argument("handle");
            FetchVideoThumbnail task = tasks.get(handle);
            if (task == null) {
                result.success(false);
                return;
            }
            task.cancel(true);
            result.success(true);
        } else if (method.equals("removeVideoThumbsRequest")) {
            int handle = call.argument("handle");
            FetchVideoThumbnail task = tasks.get(handle);
            if (task != null) {
                task.cancel(true);
                tasks.delete(handle);
            }
            result.success(true);
        } else if (method.equals("dispose")) {
            for (int i = 0; i < tasks.size(); i++) {
                FetchVideoThumbnail task = tasks.get(i);
                if (task != null) {
                    task.cancel(true);
                }
            }
            tasks.clear();
            result.success(null);
        } else if (method.equals("extractThumbnail")) {
            String videoFile = call.argument("inputFile");
            final File inputFile = new File(videoFile);
            double width = call.argument("width");
            double height = call.argument("height");
            BackgroundExecutor.execute(new BackgroundExecutor.Task("", 0L, "") {
                @Override
                public void execute() {
                    try {
                        Uri uri = Uri.parse(videoFile);
                        Bitmap bitmap = TrimVideoUtils.extractThumbnail(context, uri, 0, (int)width, (int)height);
                        ByteArrayOutputStream baos = new ByteArrayOutputStream();
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos);
                        handler.post(() -> {
                            Map<String, Object> arguments = new HashMap<>();
                            arguments.put("width", (int) width);
                            arguments.put("height", (int) height);
                            arguments.put("data", baos.toByteArray());
                            result.success(arguments);
                        });
                    } catch (final Throwable e) {
                        Thread.getDefaultUncaughtExceptionHandler().uncaughtException(Thread.currentThread(), e);
                        handler.post(() -> result.error("failed", "failed to extract thumbnail", null));
                    }
                }
            });
        } else if (method.equals("extractThumbnails")) {
            String videoFile = call.argument("inputFile");
            final File inputFile = new File(videoFile);
            double width = call.argument("width");
            double height = call.argument("height");
            int startMs = call.argument("startMs");
            int endMs = call.argument("endMs");
            int totalThumbsCount = call.argument("totalThumbsCount");
            Uri uri = Uri.parse(videoFile);
            BackgroundExecutor.execute(new BackgroundExecutor.Task("", 0L, "") {
                @Override
                public void execute() {
                    try {
                        final long interval = ((endMs - startMs) / (totalThumbsCount - 1) * 1000);
                        ArrayList<Map<String, Object>> thumbs = new ArrayList();
                        for (int i = 0; i < totalThumbsCount; ++i) {
                            try {
                                Bitmap bitmap = TrimVideoUtils.extractThumbnail(context, uri, i * interval, (int)width, (int)height);
                                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos);
                                Map<String, Object> thumb = new HashMap<>();
                                thumb.put("width", (int) width);
                                thumb.put("height", (int) height);
                                thumb.put("data", baos.toByteArray());
                                thumbs.add(thumb);
                            } catch (Exception e) {
                                e.printStackTrace();
                            }
                        }
                        handler.post(() -> {
                            result.success(thumbs);
                        });
                    } catch (final Throwable e) {
                        Thread.getDefaultUncaughtExceptionHandler().uncaughtException(Thread.currentThread(), e);
                        handler.post(() -> result.error("failed", "failed to extract thumbnail", null));
                    }
                }
            });
        }  else if (method.equals("saveToLibrary")) {
            String inputFile = call.argument("inputFile");
            File file = new File(inputFile);
            Log.d(TAG, "saveToLibrary called for file");
            BackgroundExecutor.execute(new BackgroundExecutor.Task("", 0L, "") {
                @Override
                public void execute() {
                    try {
                        saveToExternalStorage(file, result);
                    } catch (final Throwable e) {
                        Thread.getDefaultUncaughtExceptionHandler().uncaughtException(Thread.currentThread(), e);
                        handler.post(() -> result.error("failed", "failed to save video", null));
                    }
                }
            });
        } else {
            result.notImplemented();
        }
    }


    public void saveToExternalStorage(final File file, Result result) {
        final ArrayList<String> requestPermissions = new ArrayList<>();
        requestPermissions.add(PERMISSION_WRITE_EXTERNAL_STORAGE);
        requestPermissions(
                requestPermissions,
                /* successCallback */ new Callback() {
                    @Override
                    public void invoke(Object... args) {
                        List<String> grantedPermissions = (List<String>) args[0];
                        // If we fail to create either, destroy the other one and fail.
                        if (!grantedPermissions.contains(PERMISSION_WRITE_EXTERNAL_STORAGE)) {
                            Log.d(TAG, "failed_to_save_to_external:permission_not_granted:" + file.getName());
                            handler.post(() -> {
                                result.error(
                                        /* type */ "PermissionError",
                                        "Failed to save file", null);
                            });
                            return;
                        }
                        if (file != null) {
                            ContentValues values = new ContentValues(3);
                            values.put(MediaStore.Video.Media.TITLE, file.getName());
                            values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
                            values.put(MediaStore.Video.Media.DATA, file.getAbsolutePath());
                            values.put(MediaStore.Images.Media.DATE_ADDED, System.currentTimeMillis());
                            values.put(MediaStore.Images.Media.DATE_TAKEN, System.currentTimeMillis());
                            context.getContentResolver().insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
                            handler.post(() -> result.success(null));
                            Log.d(TAG, "saved_to_external:" + file.getName());
                        } else {
                            Log.d(TAG, "got null file");
                        }
                    }
                },
                /* errorCallback */ new Callback() {
                    @Override
                    public void invoke(Object... args) {
                        Log.d(TAG, "failed_to_save_to_external:permission_not_granted2:" + file.getName());
                        handler.post(() -> {
                            result.error(
                                    /* type */ "PermissionError",
                                    "Failed to save file", null);
                        });
                    }
                }
        );
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding activityPluginBinding) {
        mActivity = activityPluginBinding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        mActivity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding activityPluginBinding) {
        mActivity = activityPluginBinding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        // TODO: your plugin is no longer associated with an Activity.
        // Clean up references.
        mActivity = null;
    }

    public void requestPermissions(
            final ArrayList<String> permissions,
            final Callback successCallback,
            final Callback errorCallback) {
        PermissionUtils.Callback callback = new PermissionUtils.Callback() {
            @Override
            public void invoke(String[] permissions_, int[] grantResults) {
                List<String> grantedPermissions = new ArrayList<>();
                List<String> deniedPermissions = new ArrayList<>();

                for (int i = 0; i < permissions_.length; ++i) {
                    String permission = permissions_[i];
                    int grantResult = grantResults[i];

                    if (grantResult == PackageManager.PERMISSION_GRANTED) {
                        grantedPermissions.add(permission);
                    } else {
                        deniedPermissions.add(permission);
                    }
                }

                // Success means that all requested permissions were granted.
                for (String p : permissions) {
                    if (!grantedPermissions.contains(p)) {
                        // According to step 6 of the getUserMedia() algorithm
                        // "if the result is denied, jump to the step Permission
                        // Failure."
                        errorCallback.invoke(deniedPermissions);
                        return;
                    }
                }
                successCallback.invoke(grantedPermissions);
            }
        };

        PermissionUtils.requestPermissions(
                getActivity(),
                permissions.toArray(new String[permissions.size()]),
                callback);
    }

    public Activity getActivity() {
        return mActivity;
    }

    private static class FetchVideoThumbnail extends AsyncTask<Integer, Void, Void> {
        private final BinaryMessenger messenger;
        private int handle;
        private EventChannel.EventSink eventSink;
        private Uri mVideoUri;
        private Handler handler;
        private Context context;

        FetchVideoThumbnail(Uri videoUri, int handle, BinaryMessenger messenger, Context context) {
            this.handle = handle;
            this.mVideoUri = videoUri;
            this.messenger = messenger;
            registerEventChannel();
            handler = new Handler(Looper.getMainLooper());
            this.context = context;
        }

        private void registerEventChannel() {
            new EventChannel(
                    messenger, CHANNEL_NAME+"/thumbnailStream/" + this.handle)
                    .setStreamHandler(
                            new EventChannel.StreamHandler() {
                                @Override
                                public void onListen(Object arguments, EventChannel.EventSink eventSink) {
                                    FetchVideoThumbnail.this.eventSink = eventSink;
                                }

                                @Override
                                public void onCancel(Object arguments) {
                                    FetchVideoThumbnail.this.eventSink = null;
                                }
                            });
        }

        @TargetApi(Build.VERSION_CODES.ECLAIR)
        protected Void doInBackground(Integer... nums) {
            try {
                int startTime = nums[0];
                int endTime = nums[1];
                int totalThumbsCount = nums[2];
                int width = nums[3];
                int height = nums[4];
                MediaMetadataRetriever mediaMetadataRetriever = new MediaMetadataRetriever();
                mediaMetadataRetriever.setDataSource(context, mVideoUri);

                // Set thumbnail properties (Thumbs are squares)
                final int frameWidth = width;
                final int frameHeight = height;

                final long interval = ((endTime - startTime) / (totalThumbsCount - 1)) * 1000;

                for (int i = 0; i < totalThumbsCount; ++i) {
                    try {
                        Bitmap bitmap = TrimVideoUtils.extractThumbnail(context, mVideoUri, i * interval, frameWidth, frameHeight);
                        if (eventSink != null) {
                            byte[] data = AndroidBmpUtil.bitmapDataWithFileHeader(bitmap);
                            bitmap.recycle();
                            Map<String, Object> arguments = new HashMap<>();
                            arguments.put("handle", handle);
                            arguments.put("width", frameWidth);
                            arguments.put("height", frameHeight);
                            arguments.put("data", data);
                            arguments.put("eventType", "result");
                            handler.post(() -> {
                                if (eventSink != null) {
                                    eventSink.success(arguments);
                                }
                            });
                        }
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                }
                mediaMetadataRetriever.release();
            } catch (final Throwable e) {
                e.printStackTrace();
                Thread.getDefaultUncaughtExceptionHandler().uncaughtException(Thread.currentThread(), e);
            }
            return null;
        }

        protected void onPostExecute(Void v) {

        }
    }
}
