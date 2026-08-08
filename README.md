# JARVIS

Assistente pessoal nativo macOS — **100% local**. Ouve, transcreve, responde e fala, tudo neste Mac, sem nenhuma API externa.

```
MICROFONE → VAD → Whisper (MLX) → LLM local → Fish S2 Pro (MLX) → alto-falantes
```

## Arquitetura

```
~/Developer/Jarvis/
├── JarvisApp/            App SwiftUI nativo (XcodeGen → .xcodeproj)
│   ├── JarvisApp/        Fontes Swift (MVVM)
│   │   ├── Views/        Orb animado, conversa, waveform, settings
│   │   ├── ViewModels/   JarvisViewModel (máquina de estados)
│   │   ├── Managers/     Microfone, áudio, backend, histórico, login
│   │   └── Services/     BackendClient (HTTP :8765), BackendManager
│   └── JarvisAppTests/   Testes unitários
├── Backend/              Pipeline de ML em Python
│   ├── llm/              test_llm.py (benchmark via API :1234)
│   ├── stt/              transcribe.py, benchmark.py
│   ├── tts/              synthesize.py (com voice cloning)
│   ├── api/              server.py (FastAPI em 127.0.0.1:8765)
│   └── scripts/          end_to_end.py (latência T0–T5)
├── Models/               (reservado — modelos ficam no cache do HuggingFace)
├── Audio/{input,output,references}/
├── Logs/
├── Config/config.json    Modelos, portas, thresholds
├── Config/system_prompt.txt
└── Benchmarks/           llm.json, stt.json, tts.json, end_to_end.json
```

Fluxo: o app captura áudio (AVFoundation, 16 kHz mono), envia o WAV para o backend
`POST /conversation` que faz STT → LLM → TTS e devolve `{transcript, response, audio_path}`.
O app reproduz o áudio.

## Dependências

| Camada | Tecnologia | Repositório |
|---|---|---|
| Framework ML | MLX / MLX-LM / MLX-Audio | https://github.com/ml-explore/mlx · mlx-lm · https://github.com/Blaizzy/mlx-audio |
| STT | Whisper Large v3 Turbo (MLX) | https://github.com/Blaizzy/mlx-audio |
| LLM | Qwen (servido pela API local) | https://github.com/QwenLM/Qwen3.6 |
| TTS | Fish Audio S2 Pro (MLX) | https://github.com/fishaudio/fish-speech (PyTorch original) + conversão MLX em https://github.com/Blaizzy/mlx-audio |
| Servidor LLM | API OpenAI-compatible local (127.0.0.1:1234) | — |
| Backend | FastAPI + uvicorn | https://fastapi.tiangolo.com |

> O `mlx-audio` é a implementação canônica (Blaizzy). O `mlx-audio-plus`
> (DePasqualeOrg) é um fork não-oficial — **não** utilizado.
> O `fish-speech` original não tem suporte nativo a MLX; a porta MLX usada é a
> do `mlx-audio` (`mlx-community/fish-audio-s2-pro-*`).

## Modelos Hugging Face

| Função | Modelo | Tamanho |
|---|---|---|
| LLM Quality | `qwen/qwen3.6-35b-a3b` (via API :1234) | já carregado pelo servidor |
| LLM Fast | `qwen/qwen3.5-9b` (via API :1234) | já carregado pelo servidor |
| STT | `mlx-community/whisper-large-v3-turbo-asr-fp16` | ~1.6 GB |
| TTS Quality | `mlx-community/fish-audio-s2-pro-bf16` | ~11 GB |
| TTS Fast | `mlx-community/fish-audio-s2-pro-8bit` | ~6.7 GB |

Os modelos TTS/STT ficam em `~/Library/Caches/huggingface/hub/` (cache padrão).
O LLM é usado através do servidor OpenAI-compatible local na porta **1234**
(ex.: LM Studio / llama.cpp). A alternativa com `mlx_lm.server`:

```bash
mlx_lm.server --model mlx-community/Qwen3-14B-4bit --host 127.0.0.1 --port 8081
# então mude "base_url" em Config/config.json
```

## Instalação

Pré-requisitos: macOS 26+, Xcode 26+, Homebrew, uv.

```bash
# 1) Backend Python
cd ~/Developer/Jarvis/Backend
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install -r requirements.txt

# 2) Servidor LLM local (deixe rodando)
#    já ativo em http://127.0.0.1:1234 (você pode usar LM Studio)

# 3) Backend JARVIS
cd ~/Developer/Jarvis/Backend/api
python server.py          # 127.0.0.1:8765

# 4) App (gera o .xcodeproj e builda)
cd ~/Developer/Jarvis/JarvisApp
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project JarvisApp.xcodeproj -scheme JarvisApp -configuration Debug build
```

O app também inicia o backend sozinho (BackendManager) se a porta 8765 estiver
ociosa — não é obrigatório abrir o Terminal.

## Uso

- **Microfone**: fale e pare; o VAD (RMS) encerra após ~600 ms de silêncio.
- **Push to Talk**: segure `⌥ Space` para ouvir, solte para processar.
- **Texto**: digite em "Ask Jarvis..." e Enter.
- **Modos**: Quality (Qwen 3.6 35B) / Fast (Qwen 3.5 9B).
- **Voz de referência** (voice cloning): importe áudio em `Audio/references/`
  e configure em Settings → Voice → Reference Voice (com o transcript).

## Build & execução

Ver acima. O produto final fica em
`DerivedData/JarvisApp-*/Build/Products/Debug/Jarvis.app` (arm64).

## Settings

- **General**: Start at Login, Speak responses, push-to-talk.
- **LLM**: modo, temperature, max tokens, context size.
- **Voice**: Fish BF16 / 8-bit, velocidade, voz de referência.
- **Speech**: Whisper Turbo, idioma, threshold de VAD.
- **Privacy**: processamento local ON, rede OFF.
- **Advanced**: status do backend, logs, modelos.

## Privacidade

- Todo processamento acontece neste Mac.
- O app só fala com `127.0.0.1:8765` e o backend só com `127.0.0.1:1234`.
- Únicas chamadas externas são **downloads iniciais de modelos** durante a
  instalação, a partir de:
  - `huggingface.co`, `cdn-lfs.huggingface.co` (modelos)
  - `github.com`, `pypi.org`, `files.pythonhosted.org` (código/pacotes)
- Nenhum áudio sai do dispositivo.

## Troubleshooting

- **Backend offline**: `curl http://127.0.0.1:8765/health`. Se o venv não
  existir, rode a etapa 1 da instalação. Veja `~/Developer/Jarvis/Logs/backend.out.log`.
- **LLM lento / sem resposta**: a API da porta 1234 pode estar trocando modelos
  (cold load de 10–30 s). Mantenha o modelo Quality carregado, ou reduza
  `max_tokens` em `Config/config.json`.
- **Microfone**: dê permissão em System Settings → Privacy & Security →
  Microphone (o app usa o bundle `com.local.jarvis`).
- **Comando mal transcrito**: o Whisper turbo é preciso; se a cena for ruidosa,
  suba o VAD threshold em Settings → Speech.

## Limpar modelos

```bash
rm -rf ~/Library/Caches/huggingface/hub/models--mlx-community--whisper-large-v3-turbo-asr-fp16
rm -rf ~/Library/Caches/huggingface/hub/models--mlx-community--fish-audio-s2-pro-bf16
rm -rf ~/Library/Caches/huggingface/hub/models--mlx-community--fish-audio-s2-pro-8bit
```

## Trocar LLM

Edite `Config/config.json` → `llm.quality_model` / `llm.fast_model` e reinicie
o backend. O endpoint /models lista os modelos disponíveis na API local.

## Trocar TTS

Edite `Config/config.json` → `tts.quality_model` / `tts.fast_model`.

## Benchmark

Os números abaixo foram **medidos** nesta máquina (M3 Max, 64 GB), com a API
local já aquecida. Veja `Benchmarks/*.json`.

| Etapa | Medição |
|---|---|
| STT Whisper (5 s) | RTF 0.13 |
| STT Whisper (10 s) | RTF 0.06 |
| STT Whisper (30 s) | RTF 0.02 |
| LLM Quality (warm) | até ~45 tok/s, TTFT ~0.5 s |
| TTS Fish BF16 | RTF ~1.7 (pico ~11–15 GB RAM) |
| End-to-end | 3–33 s (dominado pelo LLM reasoning) |

Para re-medir:

```bash
cd ~/Developer/Jarvis/Backend
source .venv/bin/activate
python llm/test_llm.py
python stt/benchmark.py
python tts/synthesize.py
python scripts/end_to_end.py
```

## Atualizar

```bash
cd ~/Developer/Jarvis && git pull
cd Backend && source .venv/bin/activate && uv pip install -r requirements.txt
cd ../JarvisApp && xcodegen generate
```

## Próximas etapas (não implementadas)

Wake word, ferramentas (tools), HomePod/AirPlay, visão, RAG, Home Assistant.

## Licença dos modelos

Os modelos podem ter licenças próprias (ex.: Fish Audio S2 Pro é
pesquisa/não-comercial). Verifique o model card de cada um antes de redistribuir.
