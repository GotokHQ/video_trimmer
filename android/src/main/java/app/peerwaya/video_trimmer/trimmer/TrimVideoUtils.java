package app.peerwaya.video_trimmer.trimmer;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.util.Log;

import androidx.annotation.NonNull;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;

import io.flutter.plugin.common.MethodChannel;

public class TrimVideoUtils {

    private static final String TAG = TrimVideoUtils.class.getSimpleName();

    public static  byte[] extractThumbnailWithResult(MethodChannel.Result result, @NonNull File src) throws IOException {
        FileInputStream fis = null;
        try {
            fis = new FileInputStream(src.getAbsolutePath());
            MediaMetadataRetriever mediaMetadataRetriever = new MediaMetadataRetriever();
            mediaMetadataRetriever.setDataSource(fis.getFD());
            Bitmap bitmap = mediaMetadataRetriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
            if (bitmap == null) {
                result.error("thumb_not_found", "Could not generate thumbnail for file", null);
                return null;
            }
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos);
            return baos.toByteArray();
        } finally {
            if (fis != null) {
                try {
                    fis.close();
                } catch (IOException ignore) {
                }
            }
        }

    }

    public static Bitmap extractThumbnail(Context context, Uri videoUri, long interval, int frameWidth, int frameHeight) {
        MediaMetadataRetriever mediaMetadataRetriever = new MediaMetadataRetriever();
        mediaMetadataRetriever.setDataSource(context, videoUri);
        Bitmap bitmap = mediaMetadataRetriever.getFrameAtTime(interval, MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
        if (bitmap != null) {
            Bitmap result = Bitmap.createBitmap(frameWidth, frameHeight, bitmap.getConfig());
            Canvas canvas = new Canvas(result);
            float scaleX = (float) frameWidth / (float) bitmap.getWidth();
            float scaleY = (float) frameHeight / (float) bitmap.getHeight();
            float scale = scaleX > scaleY ? scaleX : scaleY;
            int w = (int) (bitmap.getWidth() * scale);
            int h = (int) (bitmap.getHeight() * scale);
            Rect srcRect = new Rect(0, 0, bitmap.getWidth(), bitmap.getHeight());
            Rect destRect = new Rect((frameWidth - w) / 2, (frameHeight - h) / 2, w, h);
            canvas.drawBitmap(bitmap, srcRect, destRect, null);
            bitmap.recycle();
            bitmap = result;
        } else {
            bitmap = Bitmap.createBitmap(frameWidth, frameHeight, Bitmap.Config.ARGB_8888);
        }
        return bitmap;
    }

    public static void startTrim(@NonNull File src, @NonNull File dst, long startMs, long endMs, MethodChannel.Result result) {
        String start = convertSecondsToTime(startMs / 1000);
        String duration = convertSecondsToTime((endMs - startMs) / 1000);
        // String cmd = "-ss " + start + " -t " + duration + " -accurate_seek" + " -i " + src.getAbsolutePath() + " -codec copy -avoid_negative_ts 1 " + dst.getAbsolutePath();
        // Log.d(TAG, String.format("FFmpeg command: %s", cmd));
        String[] commands = new String[]{ "-ss", start,"-t",duration,"-accurate_seek","-i",src.getAbsolutePath(),"-codec", "copy", "-avoid_negative_ts", "1",dst.getAbsolutePath()};
        // Log.d(TAG, String.format("FFmpeg command: %s", commands));
        FlutterFFmpegExecuteAsyncArgumentsTask task = new FlutterFFmpegExecuteAsyncArgumentsTask(commands, result);
        task.execute("dummy-trigger");
    }

    private static String convertSecondsToTime(long seconds) {
        String timeStr = null;
        int hour = 0;
        int minute = 0;
        int second = 0;
        if (seconds <= 0) {
            return "00:00";
        } else {
            minute = (int) seconds / 60;
            if (minute < 60) {
                second = (int) seconds % 60;
                timeStr = "00:" + unitFormat(minute) + ":" + unitFormat(second);
            } else {
                hour = minute / 60;
                if (hour > 99) return "99:59:59";
                minute = minute % 60;
                second = (int) (seconds - hour * 3600 - minute * 60);
                timeStr = unitFormat(hour) + ":" + unitFormat(minute) + ":" + unitFormat(second);
            }
        }
        return timeStr;
    }

    private static String unitFormat(int i) {
        String retStr = null;
        if (i >= 0 && i < 10) {
            retStr = "0" + Integer.toString(i);
        } else {
            retStr = "" + i;
        }
        return retStr;
    }
}
