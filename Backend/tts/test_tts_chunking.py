import base64
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

import server
from server import _generate_tts_chunk, normalize_tts_text, split_tts_text


class TTSTextTests(unittest.TestCase):
    def test_normalizes_markdown_for_speech(self):
        source = "## Olá 😊\n\nIsto é **importante**. Veja [o projeto](https://example.com)."
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

    def test_retries_short_generation_with_a_larger_budget(self):
        calls = []

        def fake_generate_audio(**kwargs):
            calls.append(kwargs["max_tokens"])
            output = Path(kwargs["output_path"]) / f"{kwargs['file_prefix']}.wav"
            if len(calls) == 1:
                duration = kwargs["max_tokens"] / 12.5 * 0.95
            else:
                duration = 1.0
            sf.write(output, np.zeros(int(24_000 * duration)), 24_000)

        with tempfile.TemporaryDirectory() as tmp:
            paths = _generate_tts_chunk(
                fake_generate_audio,
                object(),
                "Bom dia!",
                Path(tmp),
                "retry",
                1.0,
                None,
                None,
            )
            self.assertEqual(len(calls), 2)
            self.assertGreater(calls[1], calls[0])
            self.assertEqual(len(paths), 1)

    def test_streams_pcm_without_creating_a_wav(self):
        class Decoder:
            def __init__(self):
                self.reset_count = 0

            def reset_streaming_state(self):
                self.reset_count += 1

        class Model:
            sample_rate = 24_000

            def __init__(self):
                self.speech_tokenizer = SimpleNamespace(decoder=Decoder())
                self.kwargs = None

            def generate(self, **kwargs):
                self.kwargs = kwargs
                yield SimpleNamespace(audio=np.array([0.0, 0.1, -0.1], dtype=np.float32))

        model = Model()
        with patch.object(server, "load_tts", return_value=model), patch.object(
            server, "_tts_model", model
        ), patch.object(
            server, "is_kokoro_tts", return_value=False
        ):
            events = [
                json.loads(line)
                for line in server.stream_tts_audio("Bom dia.", "modelo-teste")
            ]

        self.assertEqual([event["type"] for event in events], ["ready", "audio", "done"])
        self.assertEqual(events[1]["sample_rate"], 24_000)
        self.assertGreater(len(base64.b64decode(events[1]["pcm_s16le"])), 0)
        self.assertTrue(model.kwargs["stream"])
        self.assertEqual(model.kwargs["streaming_interval"], 0.32)
        self.assertGreaterEqual(model.speech_tokenizer.decoder.reset_count, 1)

    def test_streams_kokoro_santa_in_brazilian_portuguese(self):
        class Model:
            def __init__(self):
                self.calls = []

            def generate(self, text, **kwargs):
                self.calls.append((text, kwargs))
                return SimpleNamespace(
                    audio=np.array([0.0, 0.15, -0.15], dtype=np.float32)
                )

        model = Model()
        with patch.object(server, "load_tts", return_value=model):
            events = [
                json.loads(line)
                for line in server.stream_tts_audio("Bom dia.", server.TTS_CFG["model"])
            ]

        self.assertEqual([event["type"] for event in events], ["ready", "audio", "done"])
        self.assertEqual(events[1]["sample_rate"], 24_000)
        self.assertEqual(model.calls[0][1]["voice"], "pm_santa")
        self.assertEqual(model.calls[0][1]["language"], "pt-br")
        self.assertGreater(len(base64.b64decode(events[1]["pcm_s16le"])), 0)


if __name__ == "__main__":
    unittest.main()
