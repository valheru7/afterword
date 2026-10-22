"""Recording call audio. Only this part differs per operating system: everything after it
works on any platform, and `afterword import` handles recordings made some other way."""

import sys
from pathlib import Path

from afterword.session import Track


class CaptureError(Exception):
    pass


def record_until_stopped(directory: Path, include_call_audio: bool) -> list[Track]:
    """Records into `directory` until Ctrl+C, then returns the tracks it wrote."""
    if sys.platform == "darwin":
        from afterword.capture.macos import record_until_stopped as record_on_macos
        return record_on_macos(directory, include_call_audio)
    raise CaptureError(
        f"Recording isn't supported on {sys.platform} yet (Linux and Windows are planned). "
        "Record the call another way and run `afterword import <audio file>`."
    )
