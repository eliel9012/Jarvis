# JARVIS

Assistente pessoal nativo macOS — **100% local**. Ouve, transcreve, responde e fala, tudo neste Mac, sem nenhuma API externa.

```
MICROFONE → VAD → Whisper (MLX) → Qwen 3.5 9B → Kokoro Alex pt-BR (MLX) → alto-falantes
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
│   ├── llm/              test_llm.py (benchmark MLX direto)
│   ├── stt/              transcribe.py, benchmark.py
│   ├── tts/              synthesize.py (com voice cloning)
│   ├── api/              server.py (FastAPI em 127.0.0.1:8765)
│   └── scripts/          end_to_end.py (latência T0–T5)
├── Models/               Pesos locais do Qwen MLX (ignorados pelo Git)
├── Audio/{input,output,references}/
├── Logs/
├── Config/config.json    Modelos, portas, thresholds
├── Config/system_prompt.txt
└── Benchmarks/           llm.json, stt.json, tts.json, end_to_end.json
```

Fluxo: o app captura áudio (AVFoundation, 16 kHz mono) e chama os serviços locais
`POST /stt` → `POST /chat` → `POST /tts/stream`. O backend usa Whisper MLX, o
Qwen 3.5 9B no próprio processo por MLX-LM e Kokoro MLX. O PCM é reproduzido diretamente
enquanto chega, sem criar um arquivo TTS no fluxo normal. Conversas digitadas,
transcrições STT e respostas do assistente ficam salvas localmente como texto
pelo SwiftData.

## Dependências

| Camada | Tecnologia | Repositório |
|---|---|---|
| Framework ML | MLX / MLX-LM / MLX-Audio | https://github.com/ml-explore/mlx · mlx-lm · https://github.com/Blaizzy/mlx-audio |
| STT | Whisper Large v3 Turbo (MLX) | https://github.com/Blaizzy/mlx-audio |
| LLM | Qwen 3.5 9B MLX 4-bit (carregado no backend) | https://huggingface.co/lmstudio-community/Qwen3.5-9B-MLX-4bit |
| TTS | Kokoro 82M, voz masculina Alex pt-BR (MLX) | https://github.com/gabrimatic/kokoro-mlx · https://huggingface.co/mlx-community/Kokoro-82M-bf16 |
| Runtime LLM | MLX-LM dentro do backend Jarvis | https://github.com/ml-explore/mlx-lm |
| Backend | FastAPI + uvicorn | https://fastapi.tiangolo.com |

> O Kokoro usa a implementação MLX nativa para Apple Silicon e a voz brasileira
> masculina `pm_alex`. O backend aquece o modelo ao iniciar para evitar latência
> na primeira resposta.

## Modelos Hugging Face

| Função | Modelo | Tamanho |
|---|---|---|
| LLM | `Models/Qwen3.5-9B-MLX-4bit` | 9B, MLX 4-bit; ~5,6 GB |
| STT | `mlx-community/whisper-large-v3-turbo-asr-fp16` | ~1.6 GB |
| TTS | `mlx-community/Kokoro-82M-bf16` | 82M; ~372 MB no cache local medido |

Os modelos TTS/STT ficam em `~/.cache/huggingface/hub/` (cache padrão).
O backend carrega os pesos diretamente por `mlx_lm.load`; não depende de LM
Studio, llama.cpp, Ollama nem de uma API LLM. Em uma instalação nova, baixe os
pesos uma vez para o diretório local do projeto:

```bash
cd ~/Developer/Jarvis
Backend/.venv/bin/hf download lmstudio-community/Qwen3.5-9B-MLX-4bit \
  --local-dir Models/Qwen3.5-9B-MLX-4bit
```

O template do Qwen usa `enable_thinking: false`: para um assistente de voz, isso
evita raciocínio interno antes da resposta.
O `Config/system_prompt.txt` é sempre inserido pelo backend antes do histórico.
Por padrão, o Jarvis responde em uma ou duas frases, com até cerca de 35 palavras,
sem Markdown; respostas longas continuam disponíveis quando forem solicitadas.

## Instalação

Pré-requisitos: macOS 26+, Xcode 26+, Homebrew, uv.

```bash
# 1) Backend Python
cd ~/Developer/Jarvis/Backend
uv venv --python 3.12 .venv
source .venv/bin/activate
uv pip install -r requirements.txt

# 2) Qwen local — só é necessário na primeira instalação
cd ~/Developer/Jarvis
Backend/.venv/bin/hf download lmstudio-community/Qwen3.5-9B-MLX-4bit \
  --local-dir Models/Qwen3.5-9B-MLX-4bit

# 3) Backend JARVIS — carrega Qwen, Whisper e Kokoro por MLX
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

- **Microfone**: fale normalmente; depois de detectar voz, o VAD local encerra após ~800 ms de silêncio. O botão Parar continua disponível.
- **Push to Talk**: segure `⌥ Space` para ouvir, solte para processar.
- **Texto**: digite em "Pergunte ao Jarvis..." e pressione Enter.
- **LLM**: Qwen 3.5 9B local, com raciocínio desativado para reduzir a latência.
- **Voz**: Kokoro 82M, voz masculina Alex (`pm_alex`) em português brasileiro.
- **Histórico**: mensagens digitadas, transcrições STT e respostas são persistidas localmente com sua origem.
- **Orbe flutuante**: clique no ícone de sobreposição no canto superior direito para ocultar a janela e manter apenas o Jarvis sempre acima dos outros apps. O botão pequeno reabre a janela completa.
- **Áudio temporário**: capturas do microfone são apagadas após a transcrição. A fala em streaming não cria WAV; o endpoint legado apaga seus órfãos automaticamente.

### Movimento e feedback visual

- A abertura usa uma sequência nativa SwiftUI de anéis, orbe e letras escalonadas.
- O orbe diferencia visualmente `Ouvindo`, `Transcrevendo`, `Pensando`,
  `Gerando voz` e `Falando`, acompanhando as etapas reais do pipeline.
- A janela principal segue a interface escura de referência: status local e
  modelos no cabeçalho, waveform ampla, conversa compacta e composer único.
- As curvas, timelines e entradas em stagger foram adaptadas das técnicas do
  [GSAP](https://gsap.com/), sem incorporar JavaScript ou dependências web.
- A preferência **Reduzir Movimento** do macOS simplifica a abertura e pausa
  animações contínuas não essenciais.

## Build & execução

Ver acima. O produto final fica em
`DerivedData/JarvisApp-*/Build/Products/Debug/Jarvis.app` (arm64).

## Settings

- **General**: Start at Login, Speak responses, push-to-talk.
- **LLM**: modelo, temperature e max tokens.
- **Voice**: Kokoro Alex pt-BR e velocidade.
- **Transcrição**: Whisper Turbo e idioma, sem usar a permissão Speech da Apple.
- **Privacy**: processamento local ON, rede OFF.
- **Advanced**: status do backend, logs, modelos.

## Privacidade

- Todo processamento acontece neste Mac.
- O app só fala com o próprio backend em `127.0.0.1:8765`.
- Qwen, Whisper e Kokoro são carregados diretamente dos arquivos locais por MLX.
- Únicas chamadas externas são **downloads iniciais de modelos** durante a
  instalação, a partir de:
  - `huggingface.co`, `cdn-lfs.huggingface.co` (modelos)
  - `github.com`, `pypi.org`, `files.pythonhosted.org` (código/pacotes)
- Nenhum áudio sai do dispositivo.
- O histórico persistente contém somente texto e metadados; arquivos de áudio
  temporários não são mantidos depois de usados.

## Troubleshooting

- **Backend offline**: `curl http://127.0.0.1:8765/health`. Se o venv não
  existir, rode a etapa 1 da instalação. Veja `~/Developer/Jarvis/Logs/backend.out.log`.
- **LLM lento / sem resposta**: confirme que `Models/Qwen3.5-9B-MLX-4bit`
  existe. A primeira inicialização carrega ~5,6 GB e compila kernels Metal; as
  próximas respostas usam o modelo aquecido. Reduza `max_tokens` se necessário.
- **Microfone**: dê permissão em System Settings → Privacy & Security →
  Microphone (o app usa o bundle `com.local.jarvis`). O macOS exige essa
  confirmação na primeira utilização. O Jarvis não solicita mais a permissão
  separada de Reconhecimento de Fala da Apple.
- **Permissão reaparece após recompilar**: builds locais usam assinatura ad-hoc,
  e o macOS pode considerar cada novo binário outro app. Use sempre a mesma cópia
  Release instalada ou configure uma identidade Apple Development no Xcode para
  que a autorização sobreviva entre builds.
- **Comando mal transcrito**: o Whisper turbo é preciso; se a cena for ruidosa,
  aproxime-se do microfone e reduza ruído ambiente; o VAD só encerra depois de detectar fala.

## Limpar modelos

```bash
rm -rf ~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo-asr-fp16
rm -rf ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16
```

## Trocar LLM

Edite `Config/config.json` → `llm.model_path` e reinicie o backend. O caminho
pode ser absoluto ou relativo à raiz do projeto e deve apontar para um modelo
compatível com MLX-LM.

## Trocar TTS

Edite `Config/config.json` → `tts.model`, `tts.voice` e `tts.language`. As vozes
brasileiras incluídas são `pm_santa`, `pm_alex` e `pf_dora`.

## Benchmark

Os números abaixo foram **medidos** nesta máquina (M3 Max, 64 GB), com os modelos
locais já aquecidos. Veja `Benchmarks/*.json`.

| Etapa | Medição |
|---|---|
| STT Whisper (5 s) | RTF 0.13 |
| STT Whisper (10 s) | RTF 0.06 |
| STT Whisper (30 s) | RTF 0.02 |
| LLM Qwen 3.5 9B (warm, Qwen + Kokoro residentes) | 18,7 tok/s; 38 tokens em 3,685 s |
| TTS Kokoro Alex pt-BR (warm) | 5.58 s de áudio em 0.151 s; RTF 0.027; 36.9× tempo real |
| End-to-end | rode novamente após a troca da LLM |

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

Os modelos podem ter licenças próprias. O Kokoro é Apache 2.0; verifique os model
cards antes de redistribuir pesos ou vozes geradas.
