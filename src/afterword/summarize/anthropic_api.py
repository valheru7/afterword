"""Summarize with the Claude API. Needs ANTHROPIC_API_KEY (or an `ant auth login` profile)."""

import anthropic

from afterword.summarize import SYSTEM_PROMPT, SummaryError, SummaryRequest

DEFAULT_MODEL = "claude-opus-5-5"


def summarize_with_anthropic(request: SummaryRequest, model: str) -> str:
    try:
        client = anthropic.Anthropic()
    except anthropic.AnthropicError as error:
        # No ANTHROPIC_API_KEY and no `ant auth login` profile: the client can't even start.
        raise SummaryError(
            "No Claude API key found. Set ANTHROPIC_API_KEY, sign in with `ant auth login`, "
            "or choose another notes writer in the app's Settings or with `afterword config set summarizer.provider`."
        ) from error
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
    except anthropic.AuthenticationError as error:
        raise SummaryError("The Claude API rejected the key. Set ANTHROPIC_API_KEY.") from error
    except anthropic.APIConnectionError as error:
        raise SummaryError("Couldn't reach the Claude API. Check your connection.") from error
    except anthropic.APIStatusError as error:
        raise SummaryError(f"Claude API error {error.status_code}: {error.message}") from error

    if message.stop_reason == "refusal":
        raise SummaryError("Claude declined to summarize this transcript.")
    text = "".join(block.text for block in message.content if block.type == "text").strip()
    if not text:
        raise SummaryError("Claude returned an empty summary.")
    return text
