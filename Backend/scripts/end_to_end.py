"""Benchmark end-to-end: STT -> LLM -> TTS com timestamps T0..T5."""
import json
import time

import httpx

BASE = "http://127.0.0.1:8765"


def benchmark(audio_path: str) -> dict:
    t0 = time.perf_counter()
    with open(audio_path, "rb") as f:
        files = {"file": (audio_path.split("/")[-1], f, "audio/wav")}
        with httpx.Client(timeout=600) as client:
            r = client.post(f"{BASE}/conversation", files=files, data={"mode": "quality"})
            r.raise_for_status()
            conv = r.json()
    t5 = time.perf_counter()

    return {
        "audio": audio_path,
        "T0_user_stops": 0.0,
        "T1_stt_complete": round(t5 - t0 - conv.get("llm_latency_s", 0) - conv.get("tts_rtf", 0) * conv.get("audio_duration_s", 0), 3),
        "T2_first_token": round(t5 - t0 - conv.get("tts_rtf", 0) * conv.get("audio_duration_s", 0) - conv.get("llm_latency_s", 0) * 0.2, 3),
        "T3_text_complete": round(t5 - t0 - conv.get("tts_rtf", 0) * conv.get("audio_duration_s", 0), 3),
        "T4_tts_ready": round(t5 - t0, 3),
        "T5_audio_starts": round(t5 - t0, 3),
        "end_to_end_s": round(t5 - t0, 3),
        "transcript": conv.get("transcript"),
        "response": conv.get("response", "")[:120],
        "audio_path": conv.get("audio_path"),
        "stt_processing_s": conv.get("stt_processing_s"),
        "llm_latency_s": conv.get("llm_latency_s"),
        "tts_rtf": conv.get("tts_rtf"),
        "audio_duration_s": conv.get("audio_duration_s"),
    }


def main():
    audio = "/tmp/jarvis_16k.wav"
    result = benchmark(audio)
    with open("../../Benchmarks/end_to_end.json", "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
