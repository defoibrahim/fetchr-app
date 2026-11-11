/// What a download's card or row shows, from its status and stage.
enum DownloadCardState {
  preparing,
  downloading,
  merging,
  paused,
  queued,
  cancelled,
  failed,
  done,
}
