package com.defo.fetchr

import android.app.Application

class FetchrApp : Application() {
    companion object {
        lateinit var downloads: DownloadRepository
            private set
    }

    override fun onCreate() {
        super.onCreate()
        YtDlp.start(this)
        downloads = DownloadRepository(this)
    }
}
