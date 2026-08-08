"""STT local com Whisper (MLX) — uso: python transcribe.py audio.wav"""
import argparse
import json
import sys
import time

import soundfile as sf

from mlx_audio.stt.generate import generate_transcription

MODEL_DEFAULT = "mlx-community/whisper-large-v3-turbo-asr-fp16"


def transcribe(audio_path: str, model: str = MODEL_DEFAULT, language: str = "pt") -> dict:
    info = sf.info(audio_path)
    duration = info.duration
    started = time.perf_counter()
    segments = generate_transcription(
        model=model,
        audio=audio_path,
        output_path="-",
        format="txt",
        language=language,
        verbose=False,
    )
    processing_time = time.perf_counter() - started
    text = segments.text.strip() if getattr(segments, "text", None) else ""
    lang = getattr(segments, "language", language) or language
    return {
        "text": text,
        "language": lang,
        "duration": round(duration, 2),
        "processing_time": round(processing_time, 3),
        "rtf": round(processing_time / duration, 3) if duration else None,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("audio")
    parser.add_argument("--model", default=MODEL_DEFAULT)
    parser.add_argument("--language", default="pt")
    args = parser.parse_args()
    result = transcribe(args.audio, args.model, args.language)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
