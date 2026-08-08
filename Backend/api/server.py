"""Backend unificado JARVIS — FastAPI em 127.0.0.1:8765 (100% local).

Endpoints:
  GET  /health
  GET  /models
  POST /stt          (upload wav)
  POST /chat         {messages: [{role, content}]}
  POST /tts          {text, speed, ref_audio?, ref_text?}
  POST /tts/stream   {text, speed, ref_audio?, ref_text?} -> NDJSON/PCM16
  POST /conversation (upload wav -> STT -> LLM -> TTS)
"""
import base64
import json
import os
import re
import shutil
import threading
import time
import unicodedata
import uuid
from pathlib import Path

import httpx
import numpy as np
import soundfile as sf
import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

CONFIG_PATH = Path(__file__).resolve().parent.parent.parent / "Config" / "config.json"
PROJECT_ROOT = CONFIG_PATH.parent.parent
SYSTEM_PROMPT_PATH = PROJECT_ROOT / "Config" / "system_prompt.txt"
OUTPUT_DIR = PROJECT_ROOT / "Audio" / "output"

with open(CONFIG_PATH) as f:
    CONFIG = json.load(f)

LLM = CONFIG["llm"]
LLM_MODEL = LLM["model"]
STT_CFG = CONFIG["stt"]
TTS_CFG = CONFIG["tts"]

SYSTEM_PROMPT = "Você é Jarvis, um assistente pessoal local."
if SYSTEM_PROMPT_PATH.exists():
    SYSTEM_PROMPT = SYSTEM_PROMPT_PATH.read_text().strip()

app = FastAPI(title="Jarvis Local Backend", version="0.1.4")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

_stt_model = None
_tts_model = None
_tts_model_id = None
_tts_warmed = False
_tts_warmup_error = None

# Os modelos MLX globais não são thread-safe. STT/LLM e TTS usam locks separados:
# isso impede duas gerações do mesmo modelo de se misturarem, mas permite aquecer
# o TTS em segundo plano sem bloquear uma transcrição ou resposta da LLM.
_pipeline_lock = threading.Lock()
_tts_lock = threading.Lock()

HTTP_TIMEOUT = httpx.Timeout(600.0, connect=10.0)


def load_stt():
    global _stt_model
    if _stt_model is None:
        from mlx_audio.stt.utils import load_model as load_stt_model

        print(f"[stt] carregando {STT_CFG['model']} ...")
        _stt_model = load_stt_model(model_path=STT_CFG["model"])
    return _stt_model


def load_tts(model_id: str):
    global _tts_model, _tts_model_id
    if _tts_model is None or _tts_model_id != model_id:
        print(f"[tts] carregando {model_id} ...")
        if is_kokoro_tts(model_id):
            from kokoro_mlx import KokoroTTS

            _tts_model = KokoroTTS.from_pretrained(model_id)
        else:
            from mlx_audio.tts.utils import load_model as load_tts_model

            _tts_model = load_tts_model(model_path=model_id)
        _tts_model_id = model_id
    return _tts_model


def is_kokoro_tts(model_id: str | None = None) -> bool:
    return (
        TTS_CFG.get("provider") == "kokoro_mlx"
        or "kokoro" in (model_id or TTS_CFG.get("model", "")).lower()
    )


def configured_tts_reference() -> tuple[str | None, str | None]:
    value = TTS_CFG.get("ref_audio")
    if not value:
        return None, TTS_CFG.get("ref_text")
    path = Path(os.path.expanduser(value))
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    return str(path), TTS_CFG.get("ref_text")


def tts_token_budget(text: str) -> int:
    return min(420, max(180, int(len(text) * 2.2)))


def estimate_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def run_stt(audio_path: str) -> dict:
    from mlx_audio.stt.generate import generate_transcription

    model = load_stt()
    info = sf.info(audio_path)
    started = time.perf_counter()
    segments = generate_transcription(
        model=model,
        audio=audio_path,
        output_path="-",
        format="txt",
        language=STT_CFG.get("language", "pt"),
        verbose=False,
    )
    processing_time = time.perf_counter() - started
    text = segments.text.strip() if getattr(segments, "text", None) else ""
    return {
        "text": text,
        "language": getattr(segments, "language", STT_CFG.get("language", "pt")),
        "duration": round(info.duration, 2),
        "processing_time": round(processing_time, 3),
        "rtf": round(processing_time / info.duration, 3) if info.duration else None,
    }


def normalize_tts_text(text: str) -> str:
    """Remove marcação que não deve ser pronunciada e compacta espaços."""
    text = re.sub(r"```(?:\w+)?\s*(.*?)```", r"\1", text, flags=re.DOTALL)
    text = re.sub(r"\[([^\]]+)]\([^)]+\)", r"\1", text)
    text = re.sub(r"^\s{0,3}(?:#{1,6}|[-+*])\s+", "", text, flags=re.MULTILINE)
    text = re.sub(r"[`*_~>]", "", text)
    # Emojis/símbolos pictográficos podem fazer o Qwen3-TTS entrar em geração
    # longa ou vazia. O conteúdo textual continua intacto no histórico/UI.
    text = "".join(
        character
        for character in text
        if unicodedata.category(character) not in {"Cs", "So"}
    )
    return re.sub(r"\s+", " ", text).strip()


def split_tts_text(text: str, max_chars: int = 160) -> list[str]:
    """Quebra em frases curtas; frases grandes são divididas por palavras."""
    cleaned = normalize_tts_text(text)
    if not cleaned:
        return []

    units = re.split(r"(?<=[.!?…;:])\s+", cleaned)
    pieces: list[str] = []
    for unit in units:
        words = unit.split()
        current = ""
        for word in words:
            candidate = f"{current} {word}".strip()
            if current and len(candidate) > max_chars:
                pieces.append(current)
                current = word
            else:
                current = candidate
        if current:
            pieces.append(current)

    chunks: list[str] = []
    current = ""
    for piece in pieces:
        candidate = f"{current} {piece}".strip()
        if current and len(candidate) > max_chars:
            chunks.append(current)
            current = piece
        else:
            current = candidate
    if current:
        chunks.append(current)
    return chunks


def _generate_tts_chunk(
    generate_audio,
    model,
    text: str,
    out_dir: Path,
    prefix: str,
    speed: float,
    ref_audio,
    ref_text,
    depth: int = 0,
    retry: int = 0,
) -> list[Path]:
    # Qwen3-TTS produz cerca de 12,5 tokens de áudio por segundo. O limite
    # dinâmico impede o loop de 1.200 tokens/96 s observado em textos longos.
    # O piso anterior de 100 tokens causava falsos positivos até em "Bom dia!".
    base_tokens = tts_token_budget(text)
    max_tokens = min(560, int(base_tokens * (1.45 if retry else 1.0)))
    output = out_dir / f"{prefix}.wav"
    generate_audio(
        text=text,
        model=model,
        output_path=str(out_dir),
        file_prefix=prefix,
        audio_format="wav",
        join_audio=True,
        verbose=False,
        max_tokens=max_tokens,
        temperature=TTS_CFG.get("temperature", 0.55),
        speed=speed,
        ref_audio=ref_audio,
        ref_text=ref_text,
        lang_code=TTS_CFG.get("language", "Portuguese"),
        instruct=TTS_CFG.get("instruct"),
    )
    if not output.exists():
        raise HTTPException(500, "TTS não gerou áudio")

    duration = sf.info(output).duration
    token_limit_duration = max_tokens / 12.5
    hit_token_limit = duration >= token_limit_duration * 0.92
    if hit_token_limit and len(text) > 72 and depth < 2:
        output.unlink(missing_ok=True)
        smaller = split_tts_text(text, max_chars=max(40, len(text) // 2))
        if len(smaller) > 1:
            generated: list[Path] = []
            for index, chunk in enumerate(smaller):
                generated.extend(
                    _generate_tts_chunk(
                        generate_audio,
                        model,
                        chunk,
                        out_dir,
                        f"{prefix}_{index:02d}",
                        speed,
                        ref_audio,
                        ref_text,
                        depth + 1,
                    )
                )
            return generated
    if hit_token_limit and retry == 0:
        output.unlink(missing_ok=True)
        return _generate_tts_chunk(
            generate_audio,
            model,
            text,
            out_dir,
            prefix,
            speed,
            ref_audio,
            ref_text,
            depth,
            retry=1,
        )
    if hit_token_limit:
        output.unlink(missing_ok=True)
        raise HTTPException(500, "TTS atingiu o limite de geração antes de concluir a fala")
    return [output]


def cleanup_orphaned_audio(max_age_seconds: float = 3600) -> int:
    """Remove WAVs temporários abandonados por encerramentos inesperados."""
    if not OUTPUT_DIR.exists():
        return 0
    cutoff = time.time() - max_age_seconds
    removed = 0
    for path in OUTPUT_DIR.glob("*.wav"):
        is_generated = path.stem.isdigit() or path.name.startswith("in_")
        if not is_generated:
            continue
        try:
            if path.stat().st_mtime <= cutoff:
                path.unlink(missing_ok=True)
                removed += 1
        except OSError:
            continue
    return removed


def _join_and_normalize_audio(paths: list[Path], destination: Path) -> float:
    audio_parts: list[np.ndarray] = []
    sample_rate: int | None = None
    for path in paths:
        audio, rate = sf.read(path, dtype="float32", always_2d=True)
        if sample_rate is None:
            sample_rate = rate
        elif rate != sample_rate:
            raise HTTPException(500, "TTS gerou blocos com taxas de amostragem diferentes")
        if audio_parts:
            audio_parts.append(np.zeros((int(rate * 0.12), audio.shape[1]), dtype=np.float32))
        audio_parts.append(audio)

    if not audio_parts or sample_rate is None:
        raise HTTPException(500, "TTS não gerou áudio utilizável")
    joined = np.concatenate(audio_parts, axis=0)
    rms = float(np.sqrt(np.mean(np.square(joined))))
    if rms > 1e-5:
        gain = min(8.0, 0.10 / rms)
        joined *= gain
        peak = float(np.max(np.abs(joined)))
        if peak > 0.95:
            joined *= 0.95 / peak
    sf.write(destination, joined, sample_rate, subtype="PCM_16")
    return len(joined) / sample_rate


def run_tts(text: str, model_id: str, speed: float = 1.0, ref_audio=None, ref_text=None) -> dict:
    if is_kokoro_tts(model_id):
        return run_kokoro_tts(text, model_id, speed)

    from mlx_audio.tts.generate import generate_audio

    model = load_tts(model_id)
    configured_audio, configured_text = configured_tts_reference()
    ref_audio = ref_audio or configured_audio
    ref_text = ref_text or configured_text
    removed = cleanup_orphaned_audio()
    if removed:
        print(f"[tts] removidos {removed} WAVs órfãos do cache")
    prefix = f"{time.time_ns()}"
    out_dir = OUTPUT_DIR / "gen" / prefix
    out_dir.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    final = OUTPUT_DIR / f"{prefix}.wav"
    chunks = split_tts_text(text)
    if not chunks:
        raise HTTPException(400, "Texto vazio para TTS")
    generated: list[Path] = []
    try:
        for index, chunk in enumerate(chunks):
            generated.extend(
                _generate_tts_chunk(
                    generate_audio,
                    model,
                    chunk,
                    out_dir,
                    f"{prefix}_{index:02d}",
                    speed,
                    ref_audio,
                    ref_text,
                )
            )
        duration = _join_and_normalize_audio(generated, final)
    except Exception:
        final.unlink(missing_ok=True)
        raise
    finally:
        for path in generated:
            path.unlink(missing_ok=True)
        shutil.rmtree(out_dir, ignore_errors=True)
    total = time.perf_counter() - started
    return {
        "text": text,
        "audio_path": str(final),
        "audio_duration_s": round(duration, 2),
        "total_s": round(total, 3),
        "rtf": round(total / duration, 3) if duration else None,
        "chunks": len(chunks),
    }


def run_kokoro_tts(text: str, model_id: str, speed: float = 1.0) -> dict:
    """Compatibilidade com o endpoint WAV; o app usa /tts/stream."""
    chunks = split_tts_text(text, max_chars=220)
    if not chunks:
        raise HTTPException(400, "Texto vazio para TTS")
    removed = cleanup_orphaned_audio()
    if removed:
        print(f"[tts] removidos {removed} WAVs órfãos do cache")

    model = load_tts(model_id)
    sample_rate = int(TTS_CFG.get("sample_rate", 24_000))
    started = time.perf_counter()
    generated = []
    for chunk in chunks:
        result = model.generate(
            chunk,
            voice=TTS_CFG.get("voice", "pm_alex"),
            speed=speed,
            sample_rate=sample_rate,
            language=TTS_CFG.get("language", "pt-br"),
        )
        generated.append(np.asarray(result.audio, dtype=np.float32).reshape(-1))
    joined = np.concatenate(generated)
    prefix = f"{time.time_ns()}"
    final = OUTPUT_DIR / f"{prefix}.wav"
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    sf.write(final, np.clip(joined, -0.95, 0.95), sample_rate, subtype="PCM_16")
    total = time.perf_counter() - started
    duration = len(joined) / sample_rate
    return {
        "text": text,
        "audio_path": str(final),
        "audio_duration_s": round(duration, 2),
        "total_s": round(total, 3),
        "rtf": round(total / duration, 3) if duration else None,
        "chunks": len(chunks),
    }


def _stream_event(payload: dict) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


def stream_tts_audio(
    text: str,
    model_id: str,
    speed: float = 1.0,
    ref_audio: str | None = None,
    ref_text: str | None = None,
):
    """Entrega PCM16 mono em NDJSON assim que cada bloco do modelo fica pronto."""
    if is_kokoro_tts(model_id):
        yield from stream_kokoro_audio(text, model_id, speed)
        return

    cleaned = normalize_tts_text(text)
    configured_audio, configured_text = configured_tts_reference()
    ref_audio = ref_audio or configured_audio
    ref_text = ref_text or configured_text
    started = time.perf_counter()
    generation = None
    total_samples = 0
    sample_rate = 0
    gain = None

    try:
        with _tts_lock:
            model = load_tts(model_id)
            sample_rate = int(model.sample_rate)
            yield _stream_event({"type": "ready", "sample_rate": sample_rate})
            generation = model.generate(
                text=cleaned,
                speed=speed,
                lang_code=TTS_CFG.get("language", "Portuguese"),
                ref_audio=ref_audio,
                ref_text=ref_text,
                instruct=TTS_CFG.get("instruct"),
                temperature=TTS_CFG.get("temperature", 0.55),
                max_tokens=tts_token_budget(cleaned),
                stream=True,
                streaming_interval=TTS_CFG.get("streaming_interval", 0.32),
                verbose=False,
            )
            for result in generation:
                audio = np.array(result.audio, dtype=np.float32).reshape(-1)
                if not audio.size:
                    continue
                if gain is None:
                    rms = float(np.sqrt(np.mean(np.square(audio))))
                    gain = min(4.0, 0.10 / rms) if rms > 1e-5 else 1.0
                normalized = np.clip(audio * gain, -0.95, 0.95)
                pcm = (normalized * 32767.0).astype("<i2").tobytes()
                total_samples += audio.size
                yield _stream_event(
                    {
                        "type": "audio",
                        "sample_rate": sample_rate,
                        "pcm_s16le": base64.b64encode(pcm).decode("ascii"),
                    }
                )

        if not total_samples:
            yield _stream_event({"type": "error", "detail": "TTS não gerou áudio"})
            return
        total = time.perf_counter() - started
        duration = total_samples / sample_rate
        yield _stream_event(
            {
                "type": "done",
                "audio_duration_s": round(duration, 3),
                "total_s": round(total, 3),
                "rtf": round(total / duration, 3) if duration else None,
            }
        )
    except GeneratorExit:
        raise
    except Exception as error:
        yield _stream_event({"type": "error", "detail": f"TTS falhou: {error}"})
    finally:
        if generation is not None:
            generation.close()
        model = _tts_model
        decoder = getattr(getattr(model, "speech_tokenizer", None), "decoder", None)
        if decoder is not None and hasattr(decoder, "reset_streaming_state"):
            decoder.reset_streaming_state()


def stream_kokoro_audio(text: str, model_id: str, speed: float = 1.0):
    """Gera frases curtas com Kokoro e entrega cada uma diretamente ao player."""
    chunks = split_tts_text(text, max_chars=220)
    if not chunks:
        yield _stream_event({"type": "error", "detail": "Texto vazio para TTS"})
        return

    sample_rate = int(TTS_CFG.get("sample_rate", 24_000))
    started = time.perf_counter()
    total_samples = 0
    try:
        with _tts_lock:
            model = load_tts(model_id)
            yield _stream_event({"type": "ready", "sample_rate": sample_rate})
            for chunk in chunks:
                result = model.generate(
                    chunk,
                    voice=TTS_CFG.get("voice", "pm_alex"),
                    speed=speed,
                    sample_rate=sample_rate,
                    language=TTS_CFG.get("language", "pt-br"),
                )
                audio = np.asarray(result.audio, dtype=np.float32).reshape(-1)
                if not audio.size:
                    continue
                pcm = (np.clip(audio, -0.95, 0.95) * 32767.0).astype("<i2").tobytes()
                total_samples += audio.size
                yield _stream_event(
                    {
                        "type": "audio",
                        "sample_rate": sample_rate,
                        "pcm_s16le": base64.b64encode(pcm).decode("ascii"),
                    }
                )
        if not total_samples:
            yield _stream_event({"type": "error", "detail": "TTS não gerou áudio"})
            return
        total = time.perf_counter() - started
        duration = total_samples / sample_rate
        yield _stream_event(
            {
                "type": "done",
                "audio_duration_s": round(duration, 3),
                "total_s": round(total, 3),
                "rtf": round(total / duration, 3) if duration else None,
            }
        )
    except GeneratorExit:
        raise
    except Exception as error:
        yield _stream_event({"type": "error", "detail": f"TTS falhou: {error}"})


def warm_tts_streaming() -> None:
    """Carrega modelo e kernels Metal antes da primeira pergunta."""
    global _tts_warmed, _tts_warmup_error
    time.sleep(0.5)
    generation = None
    try:
        with _tts_lock:
            model = load_tts(TTS_CFG["model"])
            if is_kokoro_tts(TTS_CFG["model"]):
                model.generate(
                    "Pronto.",
                    voice=TTS_CFG.get("voice", "pm_alex"),
                    sample_rate=int(TTS_CFG.get("sample_rate", 24_000)),
                    language=TTS_CFG.get("language", "pt-br"),
                )
            else:
                ref_audio, ref_text = configured_tts_reference()
                generation = model.generate(
                    text="Pronto.",
                    lang_code=TTS_CFG.get("language", "Portuguese"),
                    ref_audio=ref_audio,
                    ref_text=ref_text,
                    instruct=TTS_CFG.get("instruct"),
                    temperature=TTS_CFG.get("temperature", 0.55),
                    max_tokens=80,
                    stream=True,
                    streaming_interval=TTS_CFG.get("streaming_interval", 0.32),
                    verbose=False,
                )
                next(generation, None)
            _tts_warmed = True
            print("[tts] streaming aquecido")
    except Exception as error:
        _tts_warmup_error = str(error)
        print(f"[tts] falha no aquecimento: {error}")
    finally:
        if generation is not None:
            generation.close()
        model = _tts_model
        decoder = getattr(getattr(model, "speech_tokenizer", None), "decoder", None)
        if decoder is not None and hasattr(decoder, "reset_streaming_state"):
            decoder.reset_streaming_state()


@app.on_event("startup")
def schedule_tts_warmup() -> None:
    threading.Thread(target=warm_tts_streaming, daemon=True).start()


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(default_factory=list)
    model: str | None = None
    max_tokens: int | None = None
    temperature: float | None = None


class TTSRequest(BaseModel):
    text: str
    model: str | None = None
    speed: float = 1.0
    ref_audio: str | None = None
    ref_text: str | None = None


class ConversationStore:
    """Histórico em memória com compactação antes do limite da LLM."""

    def __init__(self):
        self.turns: list[dict] = []
        self.threshold = LLM.get("context_compaction_threshold", 28000)

    def add(self, user: str, assistant: str):
        self.turns.append({"role": "user", "content": user})
        self.turns.append({"role": "assistant", "content": assistant})
        self.compact()

    def compact(self):
        total = estimate_tokens(SYSTEM_PROMPT) + sum(
            estimate_tokens(t["content"]) for t in self.turns
        )
        while total > self.threshold and len(self.turns) > 4:
            dropped = self.turns.pop(0)
            dropped2 = self.turns.pop(0) if self.turns and self.turns[0]["role"] == "assistant" else None
            total = estimate_tokens(SYSTEM_PROMPT) + sum(
                estimate_tokens(t["content"]) for t in self.turns
            )
            print(f"[conversation] compactado: removida 1 troca (tokens agora ~{total})")

    def messages(self) -> list[dict]:
        msgs = [{"role": "system", "content": SYSTEM_PROMPT}]
        msgs.extend(self.turns)
        return msgs


store = ConversationStore()


def chat_llm(messages: list[dict], model: str | None, max_tokens: int | None, temperature: float | None) -> dict:
    url = f"{LLM['base_url']}/chat/completions"
    payload = {
        "model": model or LLM_MODEL,
        "messages": messages,
        "max_tokens": max_tokens or LLM.get("max_tokens", 1024),
        "temperature": temperature if temperature is not None else LLM.get("temperature", 0.7),
        "reasoning_effort": LLM.get("reasoning_effort", "none"),
        "stream": False,
    }
    started = time.perf_counter()
    try:
        with httpx.Client(timeout=HTTP_TIMEOUT) as client:
            r = client.post(url, json=payload)
            r.raise_for_status()
            data = r.json()
    except httpx.HTTPError as e:
        raise HTTPException(502, f"LLM indisponível: {e}")
    latency = time.perf_counter() - started
    msg = data["choices"][0]["message"]
    content = msg.get("content") or ""
    reasoning = msg.get("reasoning_content")
    return {
        "content": content.strip(),
        "reasoning": (reasoning or "").strip(),
        "latency_s": round(latency, 3),
        "usage": data.get("usage"),
    }


@app.get("/health")
def health():
    llm_ok = False
    try:
        with httpx.Client(timeout=5.0) as client:
            r = client.get(f"{LLM['base_url']}/models")
            llm_ok = r.status_code == 200
    except Exception:
        pass
    return {
        "status": "ok" if llm_ok else "degraded",
        "local": True,
        "llm": {"online": llm_ok, "base_url": LLM["base_url"]},
        "stt": {"model": STT_CFG["model"], "loaded": _stt_model is not None},
        "tts": {
            "model": TTS_CFG["model"],
            "loaded": _tts_model is not None,
            "warmed": _tts_warmed,
            "warmup_error": _tts_warmup_error,
            "voice": TTS_CFG.get("voice"),
        },
        "timestamp": time.time(),
    }


@app.get("/models")
def models():
    try:
        with httpx.Client(timeout=5.0) as client:
            r = client.get(f"{LLM['base_url']}/models")
            llm_models = r.json().get("data", []) if r.status_code == 200 else []
    except Exception:
        llm_models = []
    return {
        "llm": {
            "model": LLM_MODEL,
            "available": [m.get("id") for m in llm_models],
        },
        "stt": STT_CFG["model"],
        "tts": {
            "model": TTS_CFG["model"],
            "language": TTS_CFG.get("language", "pt-br"),
            "voice": TTS_CFG.get("voice"),
        },
    }


@app.post("/stt")
def stt(file: UploadFile = File(...)):
    tmp = OUTPUT_DIR / f"in_{uuid.uuid4().hex}.wav"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    with open(tmp, "wb") as f:
        shutil.copyfileobj(file.file, f)
    try:
        with _pipeline_lock:
            return run_stt(str(tmp))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"STT falhou: {e}")
    finally:
        tmp.unlink(missing_ok=True)


@app.post("/chat")
def chat(req: ChatRequest):
    try:
        with _pipeline_lock:
            return chat_llm(
                [m.model_dump() for m in req.messages] or store.messages(),
                req.model,
                req.max_tokens,
                req.temperature,
            )
    except HTTPException:
        raise


@app.post("/tts")
def tts(req: TTSRequest):
    model_id = req.model or TTS_CFG["model"]
    try:
        with _tts_lock:
            return run_tts(req.text, model_id, req.speed, req.ref_audio, req.ref_text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"TTS falhou: {e}")


@app.post("/tts/stream")
def tts_stream(req: TTSRequest):
    if not normalize_tts_text(req.text):
        raise HTTPException(400, "Texto vazio para TTS")
    model_id = req.model or TTS_CFG["model"]
    return StreamingResponse(
        stream_tts_audio(req.text, model_id, req.speed, req.ref_audio, req.ref_text),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
    )


@app.post("/conversation")
def conversation(file: UploadFile = File(...), mode: str = "quality", speed: float = 1.0):
    tmp = OUTPUT_DIR / f"in_{uuid.uuid4().hex}.wav"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    with open(tmp, "wb") as f:
        shutil.copyfileobj(file.file, f)
    t0 = time.perf_counter()
    try:
        with _pipeline_lock:
            transcript = run_stt(str(tmp))
            user_text = transcript["text"].strip()
            if not user_text:
                raise HTTPException(422, "Nenhuma fala detectada no áudio")
            store.add(user_text, "")
            messages = store.messages()
            llm = chat_llm(messages, LLM_MODEL, None, None)
            store.turns[-1]["content"] = llm["content"]
        with _tts_lock:
            audio = run_tts(llm["content"], TTS_CFG["model"], speed)
        return {
            "transcript": user_text,
            "response": llm["content"],
            "reasoning": llm["reasoning"],
            "audio_path": audio["audio_path"],
            "audio_duration_s": audio["audio_duration_s"],
            "latency_s": round(time.perf_counter() - t0, 3),
            "llm_latency_s": llm["latency_s"],
            "tts_rtf": audio["rtf"],
            "stt_processing_s": transcript["processing_time"],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Pipeline falhou: {e}")
    finally:
        tmp.unlink(missing_ok=True)


if __name__ == "__main__":
    uvicorn.run(app, host=CONFIG["server"]["host"], port=CONFIG["server"]["port"])
