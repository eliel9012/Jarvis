"""Benchmark STT: 5s, 10s, 30s de áudio."""
import json
import time

from transcribe import transcribe, MODEL_DEFAULT

DURATIONS = [5, 10, 30]


def main():
    results = []
    for d in DURATIONS:
        path = f"../../Audio/input/test_{d}s.wav"
        print(f"--- {d}s ---")
        r = transcribe(path, MODEL_DEFAULT)
        results.append({"duration_s": d, **r})
    out = {"timestamp": time.time(), "model": MODEL_DEFAULT, "results": results}
    with open("../../Benchmarks/stt.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(json.dumps(out, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
