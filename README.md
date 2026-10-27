# Afterword

Free, local-first AI notes for meetings and job interviews.

Afterword records a call on your own computer, transcribes it locally with
[whisper.cpp](https://github.com/ggml-org/whisper.cpp), and turns the transcript into
organized notes using the template you pick. No bot joins the call, and it works the same
on Zoom, Google Meet, Microsoft Teams or anything else that plays through your speakers.

- **Free.** Transcription runs on your machine. Summaries use your own Claude API key, your
  Claude Code subscription, or a local model through Ollama for a fully free, offline setup.
- **Private.** Audio never leaves your computer. Only the transcript is sent, and only to
  the summarizer you choose (none if you use Ollama).
- **Plain files.** Every note is a markdown file with a small YAML header, so it works with
  Obsidian, Joplin or any editor. Joplin can also receive notes directly.
- **Me vs. them.** Your microphone and the call audio are recorded on separate tracks, so
  the transcript knows which words are yours without any guesswork.

## What you get

Here's part of the note from a short, made-up hiring manager interview. The
[full example note](docs/example-note.md) also has the role details, next steps, a
thank-you draft and the transcript.

> **How the answers landed**
>
> - **Your intro worked well.** It was short and concrete, and it had a clear
>   before-and-after ("seconds instead of the next morning"). When she asked about scale you
>   answered with real numbers right away. Keep this version.
> - **The production incident answer was the weakest part of the call.** It started with
>   filler ("Um, so, yeah, there was one time, I think..."), had no specifics, and moved the
>   credit and ownership away from you ("kind of a team thing, I don't remember all the
>   details honestly"). [...]
> - **The root cause answer was solid, but it came too late.** "A consumer was stuck on a bad
>   message, so we added a dead letter queue" is a good, clear answer. Lead with it next time
>   so she doesn't have to pull it out of you.

## Platform support

| | Recording | Transcription & notes |
|---|---|---|
| macOS 14.4+ | ✅ | ✅ |
| Linux | planned (PipeWire) | ✅ via `afterword import` |
| Windows | planned (WASAPI) | ✅ via `afterword import` |

Recording is the only part that's different on each operating system. Everywhere else, you
can record the call some other way and run `afterword import recording.m4a`.

## Install (macOS)

There are two ways to run Afterword on a Mac (macOS 14.4 or newer):

- **The menu bar app**, which carries everything it needs: Python, whisper.cpp, ffmpeg and
  the recorder. Nothing else to install. Download `Afterword.zip` from
  [Releases](https://github.com/valheru7/afterword/releases) when one is published for your
  version, or build it yourself (see [Menu bar app](#menu-bar-app-macos)). Apple Silicon only.
- **The command line**, installed from source as below.

### Command line from source

You need [Homebrew](https://brew.sh) and Xcode 26 or its command line tools
(`xcode-select --install`) to build the small recorder program.

```sh
brew install whisper.cpp ffmpeg uv
git clone https://github.com/valheru7/afterword.git
cd afterword
swift build -c release --package-path macos/afterword-capture
uv tool install --editable .
```

The first recording asks macOS for **Microphone** and **System Audio Recording** permission
for your terminal app. The first transcription downloads the Whisper model (~550 MB).

## Use

```sh
afterword record --template job-interview --title "Acme – hiring manager" --with "Dana Lee"
```

Press **Ctrl+C** when the call ends. Afterword transcribes, writes the notes, and prints
where they went. While recording, you can type quick notes into the session's `notes.md`
and they'll be included.

| Command | What it does |
|---|---|
| `afterword record` | Record, then write notes when you press Ctrl+C. Add `--mic-only` to record only yourself. |
| `afterword import FILE` | Write notes from any existing audio or video recording. |
| `afterword process SESSION_DIR` | Rewrite notes for a session, e.g. with `--template meeting`. Transcripts are reused. |
| `afterword templates` | List note templates. |
| `afterword config` | Show (`config show`) or change (`config set KEY VALUE`) settings. See [Configure](#configure). |

### Ask first

Recording laws differ. In many places everyone on a call has to agree to be recorded.
Afterword shows a reminder each time you record (`consent_reminder = false` turns it off).
A simple "Mind if I record so I can focus on you instead of my notes?" works. If anyone
says no, `--mic-only` still captures your side.

### Tips

- **Headphones are optional.** Without them your mic also hears the call through your
  speakers. Afterword compares your track with the clean call track and removes their words
  from yours (`src/afterword/echo.py`). Headphones still give the cleanest transcript.
- Everyone on the call side shares one "Them" track. The summarizer separates panel
  interviewers from context and the names you pass with `--with`.

### Menu bar app (macOS)

If you'd rather not keep a terminal open, there's a small menu bar app. It brings its own
copy of the `afterword` command, Python, whisper.cpp, ffmpeg and the recorder, so it works on
a Mac with none of them installed. To build it you need Xcode 26 or its command line tools,
[uv](https://docs.astral.sh/uv/) and CMake (`brew install uv cmake`):

```sh
macos/Afterword/make-app.sh
open macos/Afterword/build/Afterword.app
```

The first build downloads pinned, checksummed copies of Python and FFmpeg's source, and
compiles whisper.cpp and FFmpeg, which takes a few minutes; later builds take seconds. The
app is ad-hoc signed for the Mac that built it. Their licenses are in
`Afterword.app/Contents/Resources/licenses`.

The Whisper model is too big to include (about 574 MB for the default). The menu offers to
download it before your first call; otherwise it downloads after the first recording. It's
shared with the command line, in `~/.cache/afterword/models`. Notes still need a notes writer:
Claude Code signed in, a Claude API key, or Ollama (see [Summarizers](#summarizers)).

To use the app's copy of the command in Terminal too (for `afterword process`, say), link it
onto your PATH: `ln -s /Applications/Afterword.app/Contents/Resources/afterword ~/.local/bin/afterword`.

Fill in the title, who's on the call and the template, then press **Record**. **Stop** does
the same as Ctrl+C. You get a notification when the notes are ready, and the menu lists your
recent notes. **Settings…** in the menu edits the same settings as the config file below
(folders, template, notes writer, Whisper, Joplin and after-note scripts) and saves each
change as you make it. The first recording asks for Microphone and System Audio Recording permission
for Afterword instead of your terminal. To start it at login, drag `Afterword.app` into
Applications and add it under System Settings → General → Login Items.

Quitting the app mid-call stops the recording and gives the notes up to two minutes to finish.
If they don't, the recording is kept and `afterword process SESSION_DIR` writes the notes
later. If the app crashes or is force quit, it can't stop the recording, so press Ctrl+C on
the `afterword record` process yourself or run `pkill -INT -f "afterword record"`.

Mac apps don't load your shell profile, so an `ANTHROPIC_API_KEY` exported in `~/.zshrc`
won't reach the app (the config file has no setting for it). The simplest fix is to sign in
once with `ant auth login`: the Claude API library then finds those credentials without any
environment variable. Otherwise, run `launchctl setenv ANTHROPIC_API_KEY "..."` and then
quit and reopen the app. An app started from Login Items starts before you can run that, so
it needs the same relaunch. The `claude-cli` and `ollama` summarizers need no key.

## Templates

| Template | For |
|---|---|
| `job-interview` | You're the candidate: people, questions asked, honest feedback on your answers, role details, next steps, and a thank-you draft. |
| `interview-recap` | For interviews you couldn't record. Talk through how it went in a voice memo right afterwards, then `afterword import memo.m4a --template interview-recap`. Same notes as `job-interview`, from your memory. |
| `meeting` | Summary, decisions, action items with owners, open questions. |
| `one-on-one` | Updates, feedback, career topics, follow-ups. |

A template is a markdown file of instructions. Add your own to
`~/.config/afterword/templates/`. A file there with the same `name` replaces a built-in one.

## Configure

Everything is optional. Change settings from the command line, which keeps your comments
and formatting, and keeps the file readable only by you since it can hold the Joplin token:

```sh
afterword config show                          # every setting, defaults included
afterword config set summarizer.provider ollama
afterword config set exporters '["joplin"]'    # lists are JSON arrays
afterword config test-joplin                   # check the Joplin token works
```

To keep a secret like the Joplin token out of your shell history, pass `-` as the value,
then paste the token and press Return and Ctrl+D: `afterword config set joplin.token -`.

Or create `~/.config/afterword/config.toml` yourself:

```toml
template = "job-interview"          # default template
notes_dir = "~/Afterword/notes"      # where notes are saved
sessions_dir = "~/Afterword/sessions" # recordings, transcripts, summaries
whisper_model = "large-v3-turbo-q5_0" # any ggml model name from whisper.cpp
language = "en"                       # or "auto"

[summarizer]
provider = "anthropic"   # "anthropic", "claude-cli" or "ollama"
model = ""               # blank = provider default

# Send each note to Joplin too
exporters = ["joplin"]

[joplin]
token = "..."            # Joplin → Settings → Web Clipper → Advanced options
notebook = "Interviews"

# Run your own scripts after each note. They get AFTERWORD_NOTE, AFTERWORD_SESSION_DIR
# and AFTERWORD_TITLE as environment variables.
after_note = ["~/bin/file-interview-note"]
```

### Summarizers

| Provider | Needs | Cost |
|---|---|---|
| `anthropic` | `ANTHROPIC_API_KEY` | Pay per use. Roughly a few cents to a quarter per hour-long call. |
| `claude-cli` | [Claude Code](https://claude.com/claude-code) signed in | Uses your Claude subscription. |
| `ollama` | [Ollama](https://ollama.com) running locally, plus a model (default `qwen3:14b`) | Free and offline. Bigger models write better notes. |

## Develop

```sh
uv sync
uv run pytest
```

The pieces, in the order a recording flows through them:

- `macos/afterword-capture/`: Swift helper that records the mic and system audio (Core Audio process taps) to separate files
- `src/afterword/capture/`: runs the platform's recorder
- `src/afterword/transcribe.py`: whisper.cpp, one track at a time, with voice activity detection
- `src/afterword/echo.py`: removes the call's voice from your mic track when you use speakers
- `src/afterword/transcript.py`: merges tracks into one speaker-labeled transcript
- `src/afterword/summarize/`: the prompt and the three providers
- `src/afterword/note.py`, `exporters/`: the markdown note and optional destinations

New exporters (Obsidian vault, Notion, …) and recorders for Linux and Windows are welcome.

## License

Copyright (c) 2026 Jerica Wilson. Licensed under GPL-3.0-or-later. You can use, change and share Afterword freely, but anything you distribute that builds on it must stay open source under the same license.
