"""Motor Qwen local em MLX, sem servidor ou API de terceiros."""

from pathlib import Path
from typing import Any


class LocalLLMEngine:
    def __init__(self, model_path: Path):
        self.model_path = model_path
        self.model: Any = None
        self.tokenizer: Any = None

    @property
    def loaded(self) -> bool:
        return self.model is not None and self.tokenizer is not None

    @property
    def available(self) -> bool:
        return self.model_path.exists()

    def load(self) -> tuple[Any, Any]:
        if not self.loaded:
            if not self.available:
                raise FileNotFoundError(f"Modelo MLX não encontrado: {self.model_path}")
            from mlx_lm import load

            print(f"[llm] carregando Qwen local de {self.model_path} ...")
            self.model, self.tokenizer = load(str(self.model_path))
            print("[llm] Qwen local carregado")
        return self.model, self.tokenizer

    def generate(
        self,
        messages: list[dict],
        max_tokens: int,
        temperature: float,
    ) -> dict:
        from mlx_lm import stream_generate
        from mlx_lm.sample_utils import make_sampler

        model, tokenizer = self.load()
        prompt = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=False,
        )
        pieces: list[str] = []
        final = None
        for response in stream_generate(
            model,
            tokenizer,
            prompt,
            max_tokens=max_tokens,
            sampler=make_sampler(temp=temperature, top_p=0.9),
        ):
            pieces.append(response.text)
            final = response

        content, reasoning = split_reasoning("".join(pieces))
        usage = None
        if final is not None:
            usage = {
                "prompt_tokens": final.prompt_tokens,
                "completion_tokens": final.generation_tokens,
                "total_tokens": final.prompt_tokens + final.generation_tokens,
                "generation_tokens_per_second": round(final.generation_tps, 2),
                "peak_memory_gb": round(final.peak_memory, 3),
            }
        return {"content": content, "reasoning": reasoning, "usage": usage}


def split_reasoning(text: str) -> tuple[str, str]:
    """Separa tags de pensamento caso um template futuro volte a emiti-las."""
    value = text.strip()
    if "</think>" not in value:
        return value, ""
    before, after = value.split("</think>", 1)
    reasoning = before.removeprefix("<think>").strip()
    return after.strip(), reasoning
