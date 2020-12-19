package app.peerwaya.video_trimmer.trimmer;

/*
 * Copyright (c) 2019 Taner Sener
 *
 * This file is part of FlutterFFmpeg.
 *
 * FlutterFFmpeg is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FlutterFFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with FlutterFFmpeg.  If not, see <http://www.gnu.org/licenses/>.
 */

import android.os.AsyncTask;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.arthenica.mobileffmpeg.FFmpeg;

import java.util.Arrays;

import io.flutter.plugin.common.MethodChannel;

/**
 * Asynchronous task which performs {@link FFmpeg#execute(String[])} method invocations.
 *
 * @author Taner Sener
 * @since 0.1.0
 */
public class FlutterFFmpegExecuteAsyncArgumentsTask extends AsyncTask<String, Integer, Integer> {
    public static final String LIBRARY_NAME = "videotrimmer-ffmpeg";
    private Handler handler;
    private final MethodChannel.Result result;
    private final String[] arguments;

    FlutterFFmpegExecuteAsyncArgumentsTask(final String[] arguments, final MethodChannel.Result result) {
        this.arguments = arguments;
        this.result = result;
        handler = new Handler(Looper.getMainLooper());
    }

    @Override
    protected Integer doInBackground(final String... dummyString) {

        Log.d(LIBRARY_NAME, String.format("Running FFmpeg with arguments: %s.", Arrays.toString(arguments)));

        int rc = FFmpeg.execute(arguments);

        Log.d(LIBRARY_NAME, String.format("FFmpeg exited with rc: %d", rc));

        return rc;
    }

    @Override
    protected void onPostExecute(final Integer rc) {
        handler.post(() -> result.success(rc));
    }

}