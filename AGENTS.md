# AGENTS.md

Guide for AI agents (and humans) working in this repository.

## Overview

Jarvis is a **100% local** macOS voice assistant. Two halves:

1. **`JarvisApp/`** — native SwiftUI app (MVVM): captures mic audio, talks to the
   backend over HTTP, renders orb/waveform/conversation UI.
2. **`Backend/`** — Python FastAPI server (`127.0.0.1:8765`) running the ML
   pipeline entirely on-device via Apple MLX: Whisper Large v3 Turbo (STT) →
   Qwen 3.5 9B 4-bit (LLM) → Kokoro 82M `pm_alex` pt-BR (TTS).

Hard rule of the product: **no external APIs at runtime**. The only network
calls ever allowed are initial model downloads from Hugging Face during setup.
Never introduce code that calls cloud LLM/STT/TTS services.

## Essential commands

### Backend

```bash
cd Backend
uv venv --python 3.12 .venv && source .venv/bin/activate
uv pip install -r requirements.txt

cd api && python server.py                 # serves 127.0.0.1:8765
curl http://127.0.0.1:8765/health          # liveness check
```

Benchmarks (models must be warmed):

```bash
python llm/test_llm.py        # LLM tok/s
python stt/benchmark.py       # Whisper RTF
python tts/synthesize.py      # Kokoro RTF
python scripts/end_to_end.py  # full pipeline latency T0–T5
```

Results land in `Benchmarks/*.json`. Keep them updated when touching the
pipeline.

### App

```bash
cd JarvisApp
xcodegen generate                          # project.yml → JarvisApp.xcodeproj
xcodebuild -project JarvisApp.xcodeproj -scheme JarvisApp \
  -configuration Debug build               # or build/run from Xcode
```

Swift tests live in `JarvisAppTests/` (BackendClient, state transitions, model
parsing) — run via Xcode / `xcodebuild test`.

## Structure map

| Path | Contents |
|---|---|
| `JarvisApp/JarvisApp/ViewModels/JarvisViewModel.swift` | Central state machine (Listening → Transcribing → Thinking → Generating voice → Speaking) |
| `JarvisApp/JarvisApp/Managers/` | Microphone (AVFoundation), audio playback, backend lifecycle, history (SwiftData), launch-at-login, floating orb |
| `JarvisApp/JarvisApp/Services/BackendClient.swift` | HTTP client for `/stt`, `/chat`, `/tts/stream` |
| `JarvisApp/JarvisApp/Views/` | Orb, waveform, conversation, settings; GSAP-inspired motion without web deps |
| `Backend/api/server.py` | FastAPI app — all endpoints local-only |
| `Backend/{stt,llm,tts}/` | One concern per folder; benchmarks beside implementations |
| `Config/config.json` | Model paths, ports, thresholds (LLM/TTS swap point) |
| `Config/system_prompt.txt` | Injected by the backend before conversation history |
| `Models/` | Local Qwen weights — **git-ignored**, ~5.6 GB |

## Critical domain rules (do not break!)

1. **Local-only**: never add telemetry, cloud calls, or analytics. Network
   egress = model downloads only.
2. **Port 8765 on loopback only** — the backend binds `127.0.0.1`, never
   `0.0.0.0`.
3. Qwen template uses `enable_thinking: false`; keep it that way unless a
   setting exposes it deliberately (latency budget).
4. Default answer style: 1–2 sentences, ≤~35 words, no Markdown — enforced via
   system prompt + config, not hardcoded in Swift.
5. Streaming TTS plays PCM as it arrives; do not reintroduce temp WAV files in
   the normal flow. Mic captures are deleted right after transcription.
6. VAD closes after ~800 ms of silence once speech was detected; Stop button
   must always remain available mid-flow.
7. History persistence stores **text + metadata only** (SwiftData) — never raw
   audio.
8. The app auto-starts the backend (BackendManager) when port 8765 is free;
   keep that behavior working when refactoring startup.
9. Voice answers default to Kokoro `pm_alex` (pt-BR). Bundled voices:
   `pm_santa`, `pm_alex`, `pf_dora`. Swaps happen via `Config/config.json`,
   never hardcode models in Python/Swift.
10. Respect macOS **Reduce Motion** in all new animations.

## Repo policies

- `Models/`, `.venv/`, `Logs/`, `Audio/input|output` are git-ignored — never
  commit weights, logs or captured audio.
- Ad-hoc signing means macOS may re-prompt mic permission after every rebuild;
  don't "fix" this by adding entitlement hacks — document instead.
- Commits: conventional style, one topic per commit. PT-BR or EN messages both
  fine; keep READMEs bilingual in sync ([README.md](README.md) /
  [README.en.md](README.en.md)).
- When changing pipeline behavior, re-run the four benchmark scripts and commit
  refreshed `Benchmarks/*.json` together with the change.

## Canonical test fixtures

- Health probe: `curl 127.0.0.1:8765/health`
- Latency stages: `scripts/end_to_end.py` reports T0–T5 segments
- Swift unit tests: `BackendClientTests`, `StateTransitionTests`,
  `ModelParsingTests`

## Known open points

Roadmap (not implemented): wake word, tools/tool-protocol plumbing
(`ToolProtocol.swift` exists as a seed), HomePod/AirPlay output, vision, RAG,
Home Assistant integration.

> Tip for local dev identity: `git config --global user.name/user.email` —
> otherwise commits fall back to hostname-derived values.
