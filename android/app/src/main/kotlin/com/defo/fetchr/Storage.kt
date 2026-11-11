package com.defo.fetchr

import android.os.Environment
import android.os.StatFs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object Storage {
    // Host methods run on Main, and StatFs reads the filesystem.
    @Suppress("DEPRECATION")
    suspend fun freeSpaceBytes(): Long = withContext(Dispatchers.IO) {
        StatFs(Environment.getExternalStorageDirectory().path).availableBytes
    }
}
