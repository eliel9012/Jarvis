# JARVIS

[🇺🇸 English](README.en.md) · [🇧🇷 Português](README.md)

Native macOS personal assistant — **100% local**. It listens, transcribes,
answers and speaks, all on this Mac, with no external APIs.

```
MICROPHONE → VAD → Whisper (MLX) → Qwen 3.5 9B → Kokoro Alex pt-BR (MLX) → speakers
```

## Architecture

```
~/Developer/Jarvis/
├── JarvisApp/            Native SwiftUI app (XcodeGen → .xcodeproj)
│   ├── JarvisApp/        Swift sources (MVVM)
│   │   ├── Views/        Animated orb, conversation, waveform, settings
│   │   ├── ViewModels/   JarvisViewModel (state machine)
│   │   ├── Managers/     Microphone, audio, backend, history, login
│   │   └── Services/     BackendClient (HTTP :8765), BackendManager
│   └── JarvisAppTests/   Unit tests
├── Backend/              Python ML pipeline
│   ├── llm/              test_llm.py (direct MLX benchmark)
│   ├── stt/              transcribe.py, benchmark.py
│   ├── tts/              synthesize.py (with voice cloning)
│   ├── api/              server.py (FastAPI on 127.0.0.1:8765)
│   └── scripts/          end_to_end.py (latency T0–T5)
├── Models/               Local Qwen MLX weights (Git-ignored)
├── Audio/{input,output,references}/
├── Logs/
├── Config/config.json    Models, ports, thresholds
├── Config/system_prompt.txt
└── Benchmarks/           llm.json, stt.json, tts.json, end_to_end.json
```

Flow: the app captures audio (AVFoundation, 16 kHz mono) and calls the local
services `POST /stt` → `POST /chat` → `POST /tts/stream`. The backend uses
Whisper MLX, Qwen 3.5 9B loaded in-process via MLX-LM, and Kokoro MLX. PCM is
played back as it arrives, without writing a TTS file in the normal flow. Typed
conversations, STT transcripts and assistant replies are stored locally as text
via SwiftData.

## Dependencies

| Layer | Technology | Repository |
|---|---|---|
| ML framework | MLX / MLX-LM / MLX-Audio | https://github.com/ml-explore/mlx · mlx-lm · https://github.com/Blaizzy/mlx-audio |
| STT | Whisper Large v3 Turbo (MLX) | https://github.com/Blaizzy/mlx-audio |
| LLM | Qwen 3.5 9B MLX 4-bit (loaded by the backend) | https://huggingface.co/lmstudio-community/Qwen3.5-9B-MLX-4bit |
| TTS | Kokoro 82M, male voice Alex pt-BR (MLX) | https://github.com/gabrimatic/kokoro-mlx · https://huggingface.co/mlx-community/Kokoro-82M-bf16 |
| LLM runtime | MLX-LM inside the Jarvis backend | https://github.com/ml-explore/mlx-lm |
| Backend | FastAPI + uvicorn | https://fastapi.tiangolo.com |

> Kokoro uses the native MLX implementation for Apple Silicon with the Brazilian
> male voice `pm_alex`. The backend warms the model at startup to avoid
> first-answer latency.

## Hugging Face models

| Role | Model | Size |
|---|---|---|
| LLM | `Models/Qwen3.5-9B-MLX-4bit` | 9B, MLX 4-bit; ~5.6 GB |
| STT | `mlx-community/whisper-large-v3-turbo-asr-fp16` | ~1.6 GB |
| TTS | `mlx-community/Kokoro-82M-bf16` | 82M; ~372 MB measured locally |

TTS/STT models live under `~/.cache/huggingface/hub/` (standard cache). The
backend loads weights directly through `mlx_lm.load`; it does not depend on LM
Studio, llama.cpp, Ollama or any external LLM API. On a fresh install, download
the weights once into the project-local directory:

```bash
cd ~/Developer/Jarvis
Backend/.venv/bin/hf download lmstudio-community/Qwen3.5-9B-MLX-4bit \
  --local-dir Models/Qwen3.5-9B-MLX-4bit
```

The Qwen template sets `enable_thinking: false`: for a voice assistant this
avoids internal reasoning before the answer. `Config/system_prompt.txt` is
always injected by the backend before history. By default Jarvis answers in one
or two sentences, up to ~35 words, no Markdown; longer answers remain available
when explicitly requested.

## Installation

Prerequisites: macOS 26+, Xcode 26+, Homebrew, uv.

```bash
# 1) Python backend
cd ~/Developer/Jarvis/Backend
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install -r requirements.txt

# 2) Local Qwen — only needed on first install
cd ~/Developer/Jarvis
Backend/.venv/bin/hf download lmstudio-community/Qwen3.5-9B-MLX-4bit \
  --local-dir Models/Qwen3.5-9B-MLX-4bit

# 3) JARVIS backend — loads Qwen, Whisper and Kokoro through MLX
cd ~/Developer/Jarvis/Backend/api
python server.py          # 127.0.0.1:8765

# 4) App (generates .xcodeproj and builds)
cd ~/Developer/Jarvis/JarvisApp
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project JarvisApp.xcodeproj -scheme JarvisApp -configuration Debug build
```

The app also starts the backend itself (BackendManager) if port 8765 is free —
opening a Terminal is not required.

## Usage

- **Microphone**: just speak; after voice is detected, local VAD closes ~800 ms
  of silence. The Stop button remains available.
- **Push to Talk**: hold `⌥ Space` to listen, release to process.
- **Text**: type in "Ask Jarvis..." and press Enter.
- **LLM**: local Qwen 3.5 9B, reasoning disabled to reduce latency.
- **Voice**: Kokoro 82M, male Alex (`pm_alex`) Brazilian Portuguese voice.
- **History**: typed messages, STT transcripts and replies are persisted
  locally with their origin.
- **Floating orb**: click the overlay icon at the top-right to hide the window
  and keep only the always-on-top orb. The small button reopens the full window.
- **Temporary audio**: microphone captures are deleted after transcription.
  Streaming speech creates no WAV file; the legacy endpoint cleans up its
  leftovers automatically.

### Motion & visual feedback

- The opening uses a native SwiftUI sequence of rings, orb and staggered letters.
- The orb visually distinguishes `Listening`, `Transcribing`, `Thinking`,
  `Generating voice` and `Speaking`, tracking real pipeline stages.
- The main window follows the dark reference UI: local status and models in the
  header, wide waveform, compact conversation, single composer.
- Curves, timelines and staggered entries were adapted from
  [GSAP](https://gsap.com/) techniques, without embedding JavaScript or web deps.
- macOS **Reduce Motion** simplifies the intro and pauses non-essential loops.

## Build & run

See above. Final product lands in
`DerivedData/JarvisApp-*/Build/Products/Debug/Jarvis.app` (arm64).

## Settings

- **General**: Start at Login, Speak responses, push-to-talk.
- **LLM**: model, temperature, max tokens.
- **Voice**: Kokoro Alex pt-BR and speed.
- **Transcription**: Whisper Turbo and language, no Apple Speech permission.
- **Privacy**: local processing ON, network OFF.
- **Advanced**: backend status, logs, models.

## Privacy

- All processing happens on this Mac.
- The app only talks to its own backend at `127.0.0.1:8765`.
- Qwen, Whisper and Kokoro are loaded directly from local files by MLX.
- Only external calls are **initial model downloads** during installation from:
  - `huggingface.co`, `cdn-lfs.huggingface.co` (models)
  - `github.com`, `pypi.org`, `files.pythonhosted.org` (code/packages)
- No audio ever leaves the device.
- Persistent history contains text and metadata only; temporary audio files are
  not kept after use.

## Troubleshooting

- **Backend offline**: `curl http://127.0.0.1:8765/health`. If the venv does not
  exist, run install step 1. See `~/Developer/Jarvis/Logs/backend.out.log`.
- **Slow/no LLM answer**: confirm `Models/Qwen3.5-9B-MLX-4bit` exists. First
  startup loads ~5.6 GB and compiles Metal kernels; later replies use the warmed
  model. Lower `max_tokens` if needed.
- **Microphone**: grant permission in System Settings → Privacy & Security →
  Microphone (bundle `com.local.jarvis`). macOS requires confirmation on first
  use. Jarvis no longer asks for Apple's separate Speech Recognition permission.
- **Permission reappears after rebuild**: local builds use ad-hoc signing and
  macOS may treat each new binary as a different app. Keep using the same
  installed Release copy or set an Apple Development identity in Xcode so the
  grant survives builds.
- **Mis-transcribed command**: Whisper turbo is accurate; in noisy scenes get
  closer to the mic and reduce ambient noise; VAD only closes after detecting
  speech.

## Clear models

```bash
rm -rf ~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo-asr-fp16
rm -rf ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16
```

## Swap the LLM

Edit `Config/config.json` → `llm.model_path` and restart the backend. The path
may be absolute or relative to the project root and must point to an MLX-LM
compatible model.

## Swap TTS

Edit `Config/config.json` → `tts.model`, `tts.voice` and `tts.language`. Bundled
Brazilian voices include `pm_santa`, `pm_alex` and `pf_dora`.

## Benchmarks

Numbers below were **measured** on this machine (M3 Max, 64 GB) with local
models already warmed. See `Benchmarks/*.json`.

| Stage | Measurement |
|---|---|
| Whisper STT (5 s) | RTF 0.13 |
| Whisper STT (10 s) | RTF 0.06 |
| Whisper STT (30 s) | RTF 0.02 |
| Qwen 3.5 9B LLM (warm, Qwen + Kokoro resident) | 18.7 tok/s; 38 tokens in 3.685 s |
| Kokoro Alex pt-BR TTS (warm) | 5.58 s audio in 0.151 s; RTF 0.027; 36.9× realtime |
| End-to-end | re-run after swapping the LLM |

To re-measure:

```bash
cd ~/Developer/Jarvis/Backend
source .venv/bin/activate
python llm/test_llm.py
python stt/benchmark.py
python tts/synthesize.py
python scripts/end_to_end.py
```

## Update

```bash
cd ~/Developer/Jarvis && git pull
cd Backend && source .venv/bin/activate && uv pip install -r requirements.txt
cd ../JarvisApp && xcodegen generate
```

## Roadmap (not implemented)

Wake word, tools, HomePod/AirPlay, vision, RAG, Home Assistant.

## Model licenses

Models may carry their own licenses. Kokoro is Apache 2.0; check the model cards
before redistributing weights or generated voices.
