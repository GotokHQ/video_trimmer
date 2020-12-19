package app.peerwaya.video_trimmer.trimmer;


import android.net.Uri;

public interface OnTrimVideoListener {

    void onTrimStarted();

    void getResult(final Uri uri);

    void cancelAction();

    void onError(final String message);
}