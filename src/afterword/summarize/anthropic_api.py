"""Summarize with the Claude API. Needs ANTHROPIC_API_KEY (or an `ant auth login` profile)."""

import anthropic

from afterword.summarize import SYSTEM_PROMPT, SummaryError, SummaryRequest

DEFAULT_MODEL = "claude-opus-5-5"

CHOOSE_ANOTHER_WRITER = (
    "choose another notes writer in the app's Settings or with `afterword config set summarizer.provider`"
)
NO_API_KEY = f"No Claude API key found. Set ANTHROPIC_API_KEY, sign in with `ant auth login`, or {CHOOSE_ANOTHER_WRITER}."


def summarize_with_anthropic(request: SummaryRequest, model: str) -> str:
    try:
        client = anthropic.Anthropic()
    except anthropic.AnthropicError as error:
        # An `ant auth login` profile that can't be read stops the client from starting.
        # A missing key doesn't; it only shows up when the request is built, below.
        raise SummaryError(NO_API_KEY) from error
    try:
        # Streaming because an hour-long transcript plus detailed notes can outlast a
        # plain request's HTTP timeout.
        with client.beta.messages.stream(
            model=model or DEFAULT_MODEL,
            max_tokens=64000,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": request.user_prompt()}],
            output_config={"effort": "high"},
            # If a safety classifier wrongly declines a transcript, retry on a fallback model.
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        ) as stream:
            message = stream.get_final_message()
    except TypeError as error:
        # Newer SDKs (2.x) create the client without a key and only notice when building the
        # first request, with a plain TypeError rather than an AnthropicError. Matching on the
        # message is the only way to tell it from a real bug, which should still surface.
        if "Could not resolve authentication method" not in str(error):
            raise
        raise SummaryError(NO_API_KEY) from error
    except anthropic.AuthenticationError as error:
        raise SummaryError(f"The Claude API rejected the key. Check ANTHROPIC_API_KEY, or {CHOOSE_ANOTHER_WRITER}.") from error
    except anthropic.APIConnectionError as error:
        raise SummaryError("Couldn't reach the Claude API. Check your connection.") from error
    except anthropic.APIStatusError as error:
        raise SummaryError(f"Claude API error {error.status_code}: {error.message}") from error
    except anthropic.AnthropicError as error:
        # Anything else the SDK reports, like an `ant auth login` profile whose sign-in expired.
        raise SummaryError(f"Claude API error: {error}") from error

    if message.stop_reason == "refusal":
        raise SummaryError("Claude declined to summarize this transcript.")
    text = "".join(block.text for block in message.content if block.type == "text").strip()
    if not text:
        raise SummaryError("Claude returned an empty summary.")
    return text
