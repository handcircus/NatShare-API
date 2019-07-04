package com.yusufolokoba.natshare;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Environment;
import android.os.StrictMode;
import android.provider.MediaStore;
import android.util.Log;
import android.webkit.MimeTypeMap;

import com.unity3d.player.UnityPlayer;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;

/**
 * NatShare
 * Created by yusuf on 4/16/18.
 */
public class NatShare {

    private final NatShareCallbacks callbackManager;

    public NatShare (NatShareDelegate delegate) {
        callbackManager = new NatShareCallbacks();
        callbackManager.setDelegate(delegate);
        UnityPlayer.currentActivity
            .getFragmentManager()
            .beginTransaction()
            .add(callbackManager, NatShareCallbacks.TAG)
            .commit();
    }

    public boolean shareText (String text) {
        final Intent intent = new Intent()
                .setAction(Intent.ACTION_SEND)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, text);
        callbackManager.startActivityForResult(Intent.createChooser(intent, "Share"), NatShareCallbacks.ACTIVITY_SHARE_TEXT);
        return true;
    }

    public boolean shareImage (byte[] pngData) {
        // Write image to file
        final File cachePath = new File(UnityPlayer.currentActivity.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "NatShare");
        final File file = new File(cachePath, "/share.png");
        cachePath.mkdirs();
        try {
            FileOutputStream stream = new FileOutputStream(file);
            stream.write(pngData);
            stream.close();
        } catch (IOException e) {
            e.printStackTrace();
            return false;
        }
        // Share
        final Intent intent = new Intent()
                .setAction(Intent.ACTION_SEND)
                .setType("image/png")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .putExtra(Intent.EXTRA_STREAM, Uri.fromFile(file));
        callbackManager.startActivityForResult(Intent.createChooser(intent, "Share"), NatShareCallbacks.ACTIVITY_SHARE_IMAGE);
        return true;
    }

    public boolean shareImageWithText (byte[] pngData, String text) {
        // Write image to file
        final File cachePath = new File(UnityPlayer.currentActivity.getExternalFilesDir(Environment.DIRECTORY_PICTURES), "NatShare");
        final File file = new File(cachePath, "/share.png");
        cachePath.mkdirs();
        try {
            FileOutputStream stream = new FileOutputStream(file);
            stream.write(pngData);
            stream.close();
        } catch (IOException e) {
            e.printStackTrace();
            return false;
        }
        // Share
        final Intent intent = new Intent()
                .setAction(Intent.ACTION_SEND)
                .setType("image/png")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .putExtra(Intent.EXTRA_STREAM, Uri.fromFile(file))
                .putExtra(Intent.EXTRA_TEXT, text);
        callbackManager.startActivityForResult(Intent.createChooser(intent, "Share"), NatShareCallbacks.ACTIVITY_SHARE_IMAGE);
        return true;
    }

    public boolean shareMedia (String path) {
        // Check that file exists
        final File file = new File(path);
        if (!file.exists())
            return false;
        // Get the MIME type
        final String extension = MimeTypeMap.getFileExtensionFromUrl(path);
        final String mimeType = extension != null ? MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) : "*/*";
        // Share
        final Intent intent = new Intent()
                .setAction(Intent.ACTION_SEND)
                .setType(mimeType)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .putExtra(Intent.EXTRA_STREAM, Uri.fromFile(file));
        callbackManager.startActivityForResult(Intent.createChooser(intent, "Share"), NatShareCallbacks.ACTIVITY_SHARE_MEDIA);
        return true;
    }

    public boolean shareMediaWithText (String path, String text) {
        // Check that file exists
        final File file = new File(path);
        if (!file.exists())
            return false;
        // Get the MIME type
        final String extension = MimeTypeMap.getFileExtensionFromUrl(path);
        final String mimeType = extension != null ? MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) : "*/*";
        // Share
        final Intent intent = new Intent()
                .setAction(Intent.ACTION_SEND)
                .setType(mimeType)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .putExtra(Intent.EXTRA_STREAM, Uri.fromFile(file))
                .putExtra(Intent.EXTRA_TEXT, text);
        callbackManager.startActivityForResult(Intent.createChooser(intent, "Share"), NatShareCallbacks.ACTIVITY_SHARE_MEDIA);
        return true;
    }

    public boolean saveImageToCameraRoll (byte[] pngData, String album) {
        // Write image to gallery folder
        final String galleryDirectory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM).getAbsolutePath();
        final File saveDirectory = new File(galleryDirectory + (!album.isEmpty() ? "/" + album : ""));
        final File file = new File(saveDirectory, System.nanoTime() + ".png");
        saveDirectory.mkdirs();
        try {
            final FileOutputStream stream = new FileOutputStream(file);
            stream.write(pngData);
            stream.close();
        } catch (IOException ex) {
            Log.e("Unity", "NatShare Error: Failed to save image to camera roll", ex);
            return false;
        }
        // Add to camera roll
        final Intent scanIntent = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(file));
        UnityPlayer.currentActivity.sendBroadcast(scanIntent);
        return true;
    }

    public boolean saveMediaToCameraRoll (String path, String album, boolean copy) {
        // Check that file exists
        final File file = new File(path);
        if (!file.exists())
            return false;
        // Copy file to gallery folder
        final String galleryDirectory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM).getAbsolutePath();
        final File saveDirectory = new File(galleryDirectory + (!album.isEmpty() ? "/" + album : ""));
        final File galleryFile = new File(saveDirectory, file.getName());
        saveDirectory.mkdirs();
        try {
            copyFile(file, galleryFile, copy);
        } catch (IOException ex) {
            Log.e("Unity", "NatShare Error: Failed to save media to camera roll", ex);
            return false;
        }
        final Intent scanIntent = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(galleryFile));
        UnityPlayer.currentActivity.sendBroadcast(scanIntent);
        return true;
    }

    public Object getThumbnail (String path, float time) {
        final class Thumbnail { ByteBuffer pixelBuffer; int width, height; boolean isLoaded () { return width > 0; } }
        // Load frame
        MediaMetadataRetriever retriever = new MediaMetadataRetriever();
        retriever.setDataSource(path);
        Bitmap rawFrame = retriever.getFrameAtTime((long)(time * 1e+6f));
        retriever.release();
        if (rawFrame == null)
            return new Thumbnail();
        // Invert
        final Matrix invert = new Matrix();
        invert.postScale(1, -1, rawFrame.getWidth() / 2.f, rawFrame.getHeight() / 2.f);
        Bitmap frame = Bitmap.createBitmap(rawFrame, 0, 0, rawFrame.getWidth(), rawFrame.getHeight(), invert, true);
        rawFrame.recycle();
        // Extract pixel data
        Thumbnail thumbnail = new Thumbnail();
        thumbnail.width = frame.getWidth();
        thumbnail.height = frame.getHeight();
        thumbnail.pixelBuffer = ByteBuffer.allocate(frame.getByteCount());
        frame.copyPixelsToBuffer(thumbnail.pixelBuffer);
        frame.recycle();
        return thumbnail;
    }

    private void copyFile (File src, File dst, boolean copy) throws IOException {
        InputStream is = null;
        OutputStream os = null;
        try {
            is = new FileInputStream(src);
            os = new FileOutputStream(dst);
            final byte[] buffer = new byte[1024];
            int length;
            while ((length = is.read(buffer)) > 0) os.write(buffer, 0, length);
        } finally {
            if (is != null) is.close();
            if (os != null) os.close();
        }
        if (!copy) src.delete();
    }

    static {
        // Disable the FileUriExposedException from being thrown on Android 24+
        StrictMode.VmPolicy.Builder builder = new StrictMode.VmPolicy.Builder();
        StrictMode.setVmPolicy(builder.build());
    }
}
