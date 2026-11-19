"""YouTube's JS challenges solved in JavaScriptCore, which iOS ships, instead of a Deno or Node binary."""

import collections
import json
import time

from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeProvider,
    JsChallengeProviderError,
    JsChallengeProviderResponse,
    JsChallengeResponse,
    JsChallengeType,
    NChallengeOutput,
    SigChallengeOutput,
    register_preference,
    register_provider,
)
from yt_dlp.globals import supported_js_runtimes
from yt_dlp.utils._jsruntime import JsRuntime, JsRuntimeInfo

from .log import log

# The EJS solver prints its answer with console.log; JavaScriptCore has no console, so the prelude collects
# what stdout would have held (log, info, debug) and the epilogue makes it the script's completion value.
PRELUDE = (
    "var __out = [];\n"
    "globalThis.console = {log: (...a) => __out.push(a.join(\" \")), info: (...a) => __out.push(a.join(\" \")), "
    "debug: (...a) => __out.push(a.join(\" \")), warn: () => {}, error: () => {}};\n"
)
EPILOGUE = '\n;__out.join("\\n")'

solve_ms = collections.deque(maxlen=50)


class JavaScriptCoreRuntime(JsRuntime):
    def _info(self):
        return JsRuntimeInfo(name="javascriptcore", path="builtin", version="1", version_tuple=(1,), supported=True)


supported_js_runtimes.value["javascriptcore"] = JavaScriptCoreRuntime


def run_js(stdin):
    import _fetchr

    began = time.perf_counter()
    try:
        return _fetchr.js_eval(PRELUDE + stdin + EPILOGUE)
    finally:
        elapsed = round((time.perf_counter() - began) * 1000)
        solve_ms.append(elapsed)
        log(f"JS solve {elapsed} ms")


class FetchrJscPublicJCP(JsChallengeProvider):
    """Plan B: only yt-dlp's public provider API, with the EJS scripts from the yt_dlp_ejs package."""

    PROVIDER_NAME = "fetchr-jsc-public"
    PROVIDER_VERSION = "1"
    BUG_REPORT_LOCATION = "the Fetchr iOS app"
    _SUPPORTED_TYPES = [JsChallengeType.N, JsChallengeType.SIG]

    def is_available(self):
        try:
            import yt_dlp_ejs.yt.solver  # noqa: F401
        except ImportError:
            return False
        return True

    def _real_bulk_solve(self, requests):
        import yt_dlp_ejs.yt.solver as solver

        grouped = collections.defaultdict(list)
        for request in requests:
            grouped[request.input.player_url].append(request)
        for player_url, group in grouped.items():
            player = self._get_player(next((r.video_id for r in group), None), player_url)
            self.logger.info("Solving JS challenges using javascriptcore")
            data = {
                "type": "player",
                "player": player,
                "requests": [{"type": r.type.value, "challenges": r.input.challenges} for r in group],
                "output_preprocessed": False,
            }
            stdin = (
                f"{solver.lib()}\nObject.assign(globalThis, lib);\n{solver.core()}\n"
                f"console.log(JSON.stringify(jsc({json.dumps(data)})));\n"
            )
            output = json.loads(run_js(stdin))
            if output["type"] == "error":
                raise JsChallengeProviderError(output["error"])
            for request, reply in zip(group, output["responses"], strict=True):
                if reply["type"] == "error":
                    yield JsChallengeProviderResponse(request, None, reply["error"])
                    continue
                kind = NChallengeOutput if request.type is JsChallengeType.N else SigChallengeOutput
                yield JsChallengeProviderResponse(request, JsChallengeResponse(request.type, kind(reply["data"])))


# EJSBaseJCP is yt-dlp internals: a self-update may rename it or change how it calls the runtime.
try:
    from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
except ImportError:
    EJSBaseJCP = None

if EJSBaseJCP is not None and callable(getattr(EJSBaseJCP, "_run_js_runtime", None)):

    class FetchrJscJCP(EJSBaseJCP):
        PROVIDER_NAME = "fetchr-jsc"
        JS_RUNTIME_NAME = "javascriptcore"
        PROVIDER_VERSION = "1"
        BUG_REPORT_LOCATION = FetchrJscPublicJCP.BUG_REPORT_LOCATION
        _run_js_runtime = staticmethod(run_js)

else:
    FetchrJscJCP = None

ACTIVE_PLAN = "A" if FetchrJscJCP else "B"
_provider = register_provider(FetchrJscJCP or FetchrJscPublicJCP)


@register_preference(_provider)
def _preference(provider, requests):
    # Above every built-in provider (QuickJS is 850); the others need a binary iOS cannot run anyway.
    return 1000


log(f"JS challenge provider plan {ACTIVE_PLAN}")
