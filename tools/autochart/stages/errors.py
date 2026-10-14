"""Shared error type for the autochart pipeline stages. Standard library only (no imports), so stdlib-only
stage modules and their unit tests never pull in numpy / soundfile."""


class AutochartError(Exception):
    """A readable pipeline failure. autochart.py prints it as `AUTOCHART_ERROR <stage>: <message>`
    on stderr and exits with code 2. `code` is an optional stable error code (Phase 2.2.2 job protocol,
    the keys of AutochartJob.ERROR_TEXT); "" when the failure has no player-facing code."""

    def __init__(self, stage, message, code=""):
        super().__init__(f"{stage}: {message}")
        self.stage = stage
        self.message = message
        self.code = code
