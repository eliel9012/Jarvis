"""Benchmark do LLM local via API OpenAI-compatible (127.0.0.1:1234)."""
import json
import time
import sys

import httpx

BASE_URL = "http://127.0.0.1:1234/v1"
MODEL = "qwen/qwen3.5-9b"
SYSTEM_PROMPT = (
    "Você é Jarvis, um assistente pessoal local. "
    "Responda em português brasileiro, de forma natural e concisa. "
    "Apresente-se em uma frase."
)


def benchmark(model: str, prompt: str, max_tokens: int = 128) -> dict:
    url = f"{BASE_URL}/chat/completions"
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": max_tokens,
        "reasoning_effort": "none",
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    started = time.perf_counter()
    first_token_at = None
    chunks = 0
    text = []
    usage = None
    with httpx.Client(timeout=600) as client:
        with client.stream("POST", url, json=payload) as resp:
            resp.raise_for_status()
            for line in resp.iter_lines():
                if not line or not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                obj = json.loads(data)
                choices = obj.get("choices") or []
                if first_token_at is None and choices:
                    first_token_at = time.perf_counter()
                if choices:
                    chunks += 1
                    delta = choices[0].get("delta", {})
                    piece = delta.get("content") or delta.get("reasoning_content")
                    if piece:
                        text.append(piece)
                if "usage" in obj:
                    usage = obj["usage"]
    total = time.perf_counter() - started
    ttft = first_token_at - started if first_token_at else None
    gen_tokens = len("".join(text).split()) if text else 0
    if usage and usage.get("completion_tokens"):
        gen_tokens = usage["completion_tokens"]
    return {
        "model": model,
        "prompt_tokens": usage.get("prompt_tokens", 0) if usage else None,
        "generated_tokens": gen_tokens,
        "ttft_s": round(ttft, 3) if ttft else None,
        "total_s": round(total, 3),
        "gen_tokens_per_s": round(gen_tokens / total, 2) if total else None,
        "response": "".join(text)[:120],
    }


def main():
    results = []
    for model in sys.argv[1:] or [MODEL]:
        print(f"\n>>> {model}", flush=True)
        print("cold start (load, se aplicável)...", flush=True)
        r = benchmark(model, "Qual é o estado do sistema?")
        results.append(r)
        print(json.dumps(r, ensure_ascii=False, indent=2))
    out = {"timestamp": time.time(), "backend": BASE_URL, "results": results}
    with open("../../Benchmarks/llm.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
