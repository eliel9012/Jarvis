import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

from server import _generate_tts_chunk, normalize_tts_text, split_tts_text


class TTSTextTests(unittest.TestCase):
    def test_normalizes_markdown_for_speech(self):
        source = "## Olá\n\nIsto é **importante**. Veja [o projeto](https://example.com)."
        self.assertEqual(
            normalize_tts_text(source),
            "Olá Isto é importante. Veja o projeto.",
        )

    def test_chunks_long_text_without_losing_words(self):
        source = " ".join([f"palavra{i}" for i in range(100)])
        chunks = split_tts_text(source, max_chars=80)
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(chunk) <= 80 for chunk in chunks))
        self.assertEqual(" ".join(chunks), normalize_tts_text(source))

    def test_subdivides_generation_that_hits_token_limit(self):
        def fake_generate_audio(**kwargs):
            output = Path(kwargs["output_path"]) / f"{kwargs['file_prefix']}.wav"
            max_duration = kwargs["max_tokens"] / 12.5
            duration = max_duration * 0.95 if len(kwargs["text"]) > 48 else 1.0
            sf.write(output, np.zeros(int(24_000 * duration)), 24_000)

        with tempfile.TemporaryDirectory() as tmp:
            paths = _generate_tts_chunk(
                fake_generate_audio,
                object(),
                "Esta frase propositalmente longa precisa ser subdividida para não atingir o limite do sintetizador.",
                Path(tmp),
                "teste",
                1.0,
                None,
                None,
            )
            self.assertGreater(len(paths), 1)
            self.assertTrue(all(path.exists() for path in paths))


if __name__ == "__main__":
    unittest.main()
