"""Backend unificado JARVIS — FastAPI em 127.0.0.1:8765 (100% local).

Endpoints:
  GET  /health
  GET  /models
  POST /stt          (upload wav)
  POST /chat         {messages: [{role, content}]}
  POST /tts          {text, speed, ref_audio?, ref_text?}
  POST /conversation (upload wav -> STT -> LLM -> TTS)
"""
import json
import os
import re
import shutil
import threading
import time
import uuid
from pathlib import Path

import httpx
import numpy as np
import soundfile as sf
import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
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

app = FastAPI(title="Jarvis Local Backend", version="0.1.1")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

_stt_model = None
_tts_model = None
_tts_model_id = None

# STT/LLM/TTS rodam sobre modelos MLX (GPU/Metal) globais e não são thread-safe.
# /stt, /chat, /tts e /conversation agora rodam em threadpool (endpoints são `def`
# síncronos, de propósito, pra não travar /health) — sem esse lock, duas requests
# concorrentes corrompem/embaralham a saída do modelo (visto em produção: 5
# transcrições da mesma frase saindo intercaladas). /health nunca usa esse lock.
_pipeline_lock = threading.Lock()

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
        from mlx_audio.tts.utils import load_model as load_tts_model

        print(f"[tts] carregando {model_id} ...")
        _tts_model = load_tts_model(model_path=model_id)
        _tts_model_id = model_id
    return _tts_model


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
) -> list[Path]:
    # Qwen3-TTS produz cerca de 12,5 tokens de áudio por segundo. O limite
    # dinâmico impede o loop de 1.200 tokens/96 s observado em textos longos.
    max_tokens = min(260, max(100, int(len(text) * 1.45)))
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
        temperature=0.65,
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
    if hit_token_limit and len(text) > 48 and depth < 2:
        output.unlink(missing_ok=True)
        smaller = split_tts_text(text, max_chars=max(48, len(text) // 2))
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
    if hit_token_limit:
        output.unlink(missing_ok=True)
        raise HTTPException(500, "TTS atingiu o limite de geração antes de concluir a fala")
    return [output]


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
    from mlx_audio.tts.generate import generate_audio

    model = load_tts(model_id)
    out_dir = OUTPUT_DIR / "gen"
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"{time.time_ns()}"
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
    finally:
        for path in generated:
            path.unlink(missing_ok=True)
    total = time.perf_counter() - started
    return {
        "text": text,
        "audio_path": str(final),
        "audio_duration_s": round(duration, 2),
        "total_s": round(total, 3),
        "rtf": round(total / duration, 3) if duration else None,
        "chunks": len(chunks),
    }


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
        "tts": {"model": TTS_CFG["model"], "loaded": _tts_model is not None},
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
            "language": TTS_CFG.get("language", "Portuguese"),
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
        with _pipeline_lock:
            return run_tts(req.text, model_id, req.speed, req.ref_audio, req.ref_text)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"TTS falhou: {e}")


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
