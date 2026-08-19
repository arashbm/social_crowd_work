from __future__ import annotations

import contextlib
import io
import itertools
import json
import random
import tempfile
import unittest
from pathlib import Path

from scripts.generate_comparison_manifest import (
    PAIRS_PER_RUN,
    GeneratorError,
    batch_capacities,
    build_manifest,
    main,
    optimize_batches,
    read_posts,
    sample_pairs,
    unrank_pair,
)


class GenerateComparisonManifestTest(unittest.TestCase):
    def test_unranks_every_pair_in_lexicographic_order(self) -> None:
        expected = list(itertools.combinations(range(8), 2))
        actual = [unrank_pair(rank, 8) for rank in range(len(expected))]
        self.assertEqual(actual, expected)

    def test_samples_unique_pairs_reproducibly(self) -> None:
        first = sample_pairs(100, 250, random.Random(42))
        second = sample_pairs(100, 250, random.Random(42))

        self.assertEqual(first, second)
        self.assertEqual(len(first), len(set(first)))
        self.assertTrue(all(left < right for left, right in first))

    def test_rejects_more_comparisons_than_possible(self) -> None:
        with self.assertRaisesRegex(GeneratorError, "only 6 unique pairs"):
            sample_pairs(4, 7, random.Random(1))

    def test_batches_use_40_pairs_per_full_run(self) -> None:
        self.assertEqual(batch_capacities(81), [PAIRS_PER_RUN, PAIRS_PER_RUN, 1])

    def test_manifest_contains_one_questionnaire_task_per_pair(self) -> None:
        posts = [{"id": index, "text": f"Post {index}"} for index in range(30)]
        pairs = sample_pairs(len(posts), 45, random.Random(12))
        batches = optimize_batches(pairs, random.Random(12), restarts=3, swap_attempts=500)
        manifest = build_manifest(
            posts,
            batches,
            "comparison-example-v1",
            "comparison-example-v1",
            "anxiety-comparison.v2",
            12,
            len(pairs),
            random.Random(12),
        )

        runs = manifest["conditions"][0]["runs"]
        self.assertEqual([len(run["tasks"]) for run in runs], [40, 5])
        self.assertEqual(manifest["format_version"], "3")
        self.assertNotIn("instructions_key", manifest["conditions"][0])

        variants = manifest["conditions"][0]["variants"]
        self.assertEqual(variants["generator_version"], "3")
        self.assertEqual(variants["pairs_per_full_run"], 40)
        self.assertEqual(variants["questionnaire_key"], "anxiety-comparison.v2")
        self.assertNotIn("tasks_per_full_run", variants)
        self.assertNotIn("prompts_per_pair", variants)

        emitted_pairs: set[tuple[int, int]] = set()
        for run in runs:
            self.assertEqual(
                [task["position"] for task in run["tasks"]],
                list(range(1, len(run["tasks"]) + 1)),
            )

            for task in run["tasks"]:
                self.assertEqual(task["questionnaire_key"], "anxiety-comparison.v2")
                self.assertNotIn("prompt_key", task)
                left = task["stimuli"]["post_a"]["id"]
                right = task["stimuli"]["post_b"]["id"]
                emitted_pairs.add(tuple(sorted((left, right))))

        self.assertEqual(emitted_pairs, set(pairs))

    def test_manifest_includes_instructions_key_when_supplied(self) -> None:
        posts = [{"id": index, "text": f"Post {index}"} for index in range(2)]
        batches = optimize_batches([(0, 1)], random.Random(4), 1, 0)

        manifest = build_manifest(
            posts,
            batches,
            "comparison-example-v1",
            "comparison-example-v1",
            "anxiety-comparison.v2",
            4,
            1,
            random.Random(4),
            "participant-instructions.v1",
        )

        self.assertEqual(
            manifest["conditions"][0]["instructions_key"],
            "participant-instructions.v1",
        )

    def test_reads_jsonl_and_preserves_complete_post_objects(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "posts.jsonl"
            path.write_text(
                '{"context_chains":[{"chain_text":"First"}],"source":{"id":1}}\n\n'
                '{"context_chains":[{"chain_text":"Second"}],"label":"example"}\n',
                encoding="utf-8",
            )

            self.assertEqual(
                read_posts(path),
                [
                    {
                        "context_chains": [{"chain_text": "First"}],
                        "source": {"id": 1},
                        "text": "First",
                    },
                    {
                        "context_chains": [{"chain_text": "Second"}],
                        "label": "example",
                        "text": "Second",
                    },
                ],
            )

    def test_reports_invalid_jsonl_line(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "posts.jsonl"
            path.write_text(
                '{"context_chains":[{"chain_text":"Valid"}]}\n{"text":}\n',
                encoding="utf-8",
            )

            with self.assertRaisesRegex(GeneratorError, r"posts\.jsonl:2: invalid JSON"):
                read_posts(path)

    def test_cli_requires_questionnaire_key(self) -> None:
        with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(io.StringIO()):
            main(
                [
                    "posts.jsonl",
                    "manifest.json",
                    "--comparisons",
                    "1",
                    "--condition-key",
                    "comparison-example-v1",
                ]
            )

        self.assertEqual(raised.exception.code, 2)

    def test_cli_summary_reports_one_task_per_pair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "posts.jsonl"
            output_path = Path(directory) / "manifest.json"
            input_path.write_text(
                "\n".join(
                    json.dumps(
                        {"id": index, "context_chains": [{"chain_text": f"Post {index}"}]}
                    )
                    for index in range(10)
                ),
                encoding="utf-8",
            )
            stderr = io.StringIO()

            with contextlib.redirect_stderr(stderr):
                result = main(
                    [
                        str(input_path),
                        str(output_path),
                        "--comparisons",
                        "4",
                        "--condition-key",
                        "comparison-example-v1",
                        "--questionnaire-key",
                        "anxiety-comparison.v2",
                        "--instructions-key",
                        "participant-instructions.v1",
                        "--seed",
                        "7",
                        "--restarts",
                        "1",
                        "--swap-attempts",
                        "0",
                    ]
                )

            self.assertEqual(result, 0)
            self.assertIn("4 unique pairs as 4 tasks", stderr.getvalue())
            manifest = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(
                manifest["conditions"][0]["instructions_key"],
                "participant-instructions.v1",
            )


if __name__ == "__main__":
    unittest.main()
