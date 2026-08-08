"""Backend unificado JARVIS — FastAPI em 127.0.0.1:8765 (100% local).

Endpoints:
  GET  /health
  GET  /models
  POST /stt          (upload wav)
  POST /chat         {messages: [{role, content}]}
  POST /tts          {text, speed, ref_audio?, ref_text?}
  POST /conversation (upload wav -> STT -> LLM -> TTS)
"""
import glob
import json
import os
import shutil
import time
import uuid
from pathlib import Path

import httpx
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
STT_CFG = CONFIG["stt"]
TTS_CFG = CONFIG["tts"]

SYSTEM_PROMPT = "Você é Jarvis, um assistente pessoal local."
if SYSTEM_PROMPT_PATH.exists():
    SYSTEM_PROMPT = SYSTEM_PROMPT_PATH.read_text().strip()

app = FastAPI(title="Jarvis Local Backend", version="0.1.0")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

_stt_model = None
_tts_model = None
_tts_model_id = None

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


def run_tts(text: str, model_id: str, speed: float = 1.0, ref_audio=None, ref_text=None) -> dict:
    from mlx_audio.tts.generate import generate_audio

    model = load_tts(model_id)
    out_dir = OUTPUT_DIR / "gen"
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"{time.time_ns()}"
    started = time.perf_counter()
    generate_audio(
        text=text,
        model=model,
        output_path=str(out_dir),
        file_prefix=prefix,
        audio_format="wav",
        verbose=False,
        speed=speed,
        ref_audio=ref_audio,
        ref_text=ref_text,
        lang_code="pt",
    )
    total = time.perf_counter() - started
    generated = glob.glob(str(out_dir / f"{prefix}_*.wav")) or glob.glob(str(out_dir / "audio_*.wav"))
    if not generated:
        raise HTTPException(500, "TTS não gerou áudio")
    final = OUTPUT_DIR / f"{prefix}.wav"
    shutil.move(generated[0], final)
    info = sf.info(final)
    return {
        "text": text,
        "audio_path": str(final),
        "audio_duration_s": round(info.duration, 2),
        "total_s": round(total, 3),
        "rtf": round(total / info.duration, 3) if info.duration else None,
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
    """Histórico em memória com compactação de contexto em 70k tokens."""

    def __init__(self):
        self.turns: list[dict] = []
        self.threshold = LLM.get("context_compaction_threshold", 70000)

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
        "model": model or LLM.get("quality_model"),
        "messages": messages,
        "max_tokens": max_tokens or LLM.get("max_tokens", 1024),
        "stream": False,
    }
    if temperature is not None:
        payload["temperature"] = temperature
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
        "tts": {"model": TTS_CFG["quality_model"], "loaded": _tts_model is not None},
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
            "quality": LLM["quality_model"],
            "fast": LLM["fast_model"],
            "available": [m.get("id") for m in llm_models],
        },
        "stt": STT_CFG["model"],
        "tts": {"quality": TTS_CFG["quality_model"], "fast": TTS_CFG["fast_model"]},
    }


@app.post("/stt")
async def stt(file: UploadFile = File(...)):
    tmp = OUTPUT_DIR / f"in_{uuid.uuid4().hex}.wav"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    with open(tmp, "wb") as f:
        shutil.copyfileobj(file.file, f)
    try:
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
    model_id = req.model or TTS_CFG["quality_model"]
    return run_tts(req.text, model_id, req.speed, req.ref_audio, req.ref_text)


@app.post("/conversation")
async def conversation(file: UploadFile = File(...), mode: str = "quality", speed: float = 1.0):
    tmp = OUTPUT_DIR / f"in_{uuid.uuid4().hex}.wav"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    with open(tmp, "wb") as f:
        shutil.copyfileobj(file.file, f)
    t0 = time.perf_counter()
    try:
        transcript = run_stt(str(tmp))
        user_text = transcript["text"].strip()
        if not user_text:
            raise HTTPException(422, "Nenhuma fala detectada no áudio")
        store.add(user_text, "")
        messages = store.messages()
        llm = chat_llm(messages, LLM["quality_model"] if mode == "quality" else LLM["fast_model"], None, None)
        store.turns[-1]["content"] = llm["content"]
        tts_model = TTS_CFG["quality_model"] if mode == "quality" else TTS_CFG["fast_model"]
        audio = run_tts(llm["content"], tts_model, speed)
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
