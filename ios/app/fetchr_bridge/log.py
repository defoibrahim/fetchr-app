def log(message):
    """Writes to os_log as com.defo.fetchr/python; a no-op on the host, where _fetchr does not exist."""
    try:
        import _fetchr
    except ImportError:
        return
    if hasattr(_fetchr, "log"):
        _fetchr.log(message)


class Silent:
    """A yt-dlp logger that drops everything."""

    def __getattr__(self, name):
        return lambda *args, **kwargs: None
