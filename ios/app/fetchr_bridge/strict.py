import json
import math
import re

_LONE_SURROGATE = re.compile("[\ud800-\udfff]")


def _clean(value):
    if isinstance(value, str):
        # json.loads already joins valid pairs into one code point, so any surrogate left is unpaired.
        return _LONE_SURROGATE.sub("�", value)
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, dict):
        return {_clean(key): _clean(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_clean(item) for item in value]
    return value


def dumps(value):
    # Swift's JSONSerialization rejects NaN, Infinity and unpaired surrogates, which Python writes.
    return json.dumps(_clean(value), allow_nan=False)
