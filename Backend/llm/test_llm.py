"""Benchmark do Qwen carregado diretamente pelo MLX-LM."""

import json
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "Backend" / "api"))

from local_llm import LocalLLMEngine  # noqa: E402

CONFIG = json.loads((PROJECT_ROOT / "Config" / "config.json").read_text())
SYSTEM_PROMPT = (PROJECT_ROOT / "Config" / "system_prompt.txt").read_text().strip()
LLM_CONFIG = CONFIG["llm"]
MODEL_PATH = PROJECT_ROOT / LLM_CONFIG["model_path"]


def benchmark(engine: LocalLLMEngine, prompt: str, max_tokens: int = 128) -> dict:
    started = time.perf_counter()
    result = engine.generate(
        [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        max_tokens=max_tokens,
        temperature=0.0,
    )
    total = time.perf_counter() - started
    usage = result["usage"] or {}
    return {
        "model": LLM_CONFIG["model"],
        "provider": "mlx_lm",
        "prompt_tokens": usage.get("prompt_tokens"),
        "generated_tokens": usage.get("completion_tokens"),
        "total_s": round(total, 3),
        "gen_tokens_per_s": usage.get("generation_tokens_per_second"),
        "peak_memory_gb": usage.get("peak_memory_gb"),
        "response": result["content"],
    }


def main() -> None:
    engine = LocalLLMEngine(MODEL_PATH)
    results = []
    for label, prompt in (
        ("cold", "Qual é o estado do sistema?"),
        ("warm", "Resuma em uma frase o que você consegue fazer."),
    ):
        print(f"\n>>> {label}", flush=True)
        result = benchmark(engine, prompt)
        results.append({"run": label, **result})
        print(json.dumps(result, ensure_ascii=False, indent=2))

    output = {
        "timestamp": time.time(),
        "backend": "mlx_lm_in_process",
        "results": results,
    }
    (PROJECT_ROOT / "Benchmarks" / "llm.json").write_text(
        json.dumps(output, ensure_ascii=False, indent=2)
    )


if __name__ == "__main__":
    main()
