"""TTS local com Fish Audio S2 Pro (MLX) — uso: python synthesize.py --text "..." --output out.wav"""
import argparse
import glob
import json
import os
import resource
import time

import soundfile as sf

from mlx_audio.tts.generate import generate_audio

MODEL_DEFAULT = "mlx-community/fish-audio-s2-pro-bf16"


def synthesize(
    text: str,
    output_path: str,
    model: str = MODEL_DEFAULT,
    ref_audio: str = None,
    ref_text: str = None,
    speed: float = 1.0,
) -> dict:
    out_dir = os.path.abspath(os.path.join(os.path.dirname(output_path), "gen"))
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.perf_counter()
    generate_audio(
        text=text,
        model=model,
        output_path=out_dir,
        audio_format="wav",
        verbose=False,
        speed=speed,
        ref_audio=ref_audio,
        ref_text=ref_text,
        lang_code="pt",
    )
    total = time.perf_counter() - t0
    generated = glob.glob(os.path.join(out_dir, "audio_*.wav"))
    if not generated:
        raise RuntimeError("Nenhum áudio foi gerado pelo TTS")
    final = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(final), exist_ok=True)
    os.replace(generated[0], final)
    info = sf.info(final)
    audio_duration = info.duration
    peak_rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6  # MB (macOS)
    return {
        "model": model,
        "text": text,
        "audio_duration_s": round(audio_duration, 2),
        "total_s": round(total, 3),
        "rtf": round(total / audio_duration, 3) if audio_duration else None,
        "peak_rss_mb": round(peak_rss, 1),
        "output": final,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--text", default="Boa noite. Eu sou Jarvis.")
    parser.add_argument("--output", default="../../Audio/output/output.wav")
    parser.add_argument("--model", default=MODEL_DEFAULT)
    parser.add_argument("--ref-audio")
    parser.add_argument("--ref-text")
    parser.add_argument("--speed", type=float, default=1.0)
    args = parser.parse_args()
    result = synthesize(args.text, args.output, args.model, args.ref_audio, args.ref_text, args.speed)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    with open("../../Benchmarks/tts.json", "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
