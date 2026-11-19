import errno
import socket

from yt_dlp.networking.exceptions import TransportError

_NETWORK_ERRNOS = {
    errno.ENETUNREACH,
    errno.ENETDOWN,
    errno.ECONNRESET,
    errno.ETIMEDOUT,
    errno.ECONNREFUSED,
    errno.EHOSTUNREACH,
}
_NETWORK_TYPES = (socket.gaierror, TimeoutError, ConnectionError, TransportError)
_MAX_HOPS = 8


def _chain(exc):
    seen = set()
    pending = [exc]
    while pending and len(seen) < _MAX_HOPS:
        current = pending.pop(0)
        if current is None or id(current) in seen:
            continue
        seen.add(id(current))
        yield current
        exc_info = getattr(current, "exc_info", None)
        if isinstance(exc_info, tuple) and len(exc_info) > 1:
            pending.append(exc_info[1])
        pending.append(current.__cause__)
        pending.append(current.__context__)


def _hint_of(exc):
    code = getattr(exc, "errno", None)
    if isinstance(exc, OSError) and code == errno.ENOSPC:
        return "no_storage"
    # Type first: Darwin reports getaddrinfo's EAI_PROTOCOL as gaierror(13), which is not EACCES.
    if isinstance(exc, _NETWORK_TYPES):
        return "network"
    if isinstance(exc, PermissionError) or code == errno.EACCES:
        return "permission_denied"
    if code in _NETWORK_ERRNOS:
        return "network"
    return None


def hint(exc):
    for current in _chain(exc):
        found = _hint_of(current)
        if found:
            return found
    return None
