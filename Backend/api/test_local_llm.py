import unittest
from pathlib import Path

from local_llm import LocalLLMEngine, split_reasoning


class LocalLLMTests(unittest.TestCase):
    def test_missing_model_is_reported_without_loading_mlx(self):
        engine = LocalLLMEngine(Path("/modelo/inexistente"))

        self.assertFalse(engine.available)
        self.assertFalse(engine.loaded)

    def test_plain_response_has_no_reasoning(self):
        self.assertEqual(split_reasoning("Resposta curta."), ("Resposta curta.", ""))

    def test_reasoning_tags_are_separated(self):
        self.assertEqual(
            split_reasoning("<think>interno</think>Resposta."),
            ("Resposta.", "interno"),
        )


if __name__ == "__main__":
    unittest.main()
