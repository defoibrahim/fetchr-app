import errno
import socket

import yt_dlp

from fetchr_bridge import classify


def test_disk_full_is_no_storage():
    assert classify.hint(OSError(errno.ENOSPC, "x")) == "no_storage"


def test_permission_error_is_permission_denied():
    assert classify.hint(PermissionError()) == "permission_denied"


def test_eacces_is_permission_denied():
    assert classify.hint(OSError(errno.EACCES, "x")) == "permission_denied"


def test_dns_failure_is_network():
    assert classify.hint(socket.gaierror(8, "nodename nor servname provided, or not known")) == "network"


def test_gaierror_with_eacces_code_is_network():
    assert classify.hint(socket.gaierror(errno.EACCES, "EAI_PROTOCOL on Darwin")) == "network"


def test_connection_reset_errno_is_network():
    assert classify.hint(OSError(errno.ECONNRESET, "reset")) == "network"


def test_download_error_wrapping_timeout_is_network():
    try:
        raise TimeoutError()
    except TimeoutError as cause:
        exc = yt_dlp.utils.DownloadError("ERROR: timed out", exc_info=(type(cause), cause, cause.__traceback__))
    assert classify.hint(exc) == "network"


def test_cause_chain_is_walked():
    exc = RuntimeError("wrapper")
    exc.__cause__ = OSError(errno.ENOSPC, "x")
    assert classify.hint(exc) == "no_storage"


def test_value_error_has_no_hint():
    assert classify.hint(ValueError()) is None


def test_self_referencing_context_terminates():
    exc = ValueError()
    exc.__context__ = exc
    assert classify.hint(exc) is None
