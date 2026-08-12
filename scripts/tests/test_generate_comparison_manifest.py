from __future__ import annotations

import itertools
import json
import random
import tempfile
import unittest
from pathlib import Path

from scripts.generate_comparison_manifest import (
    PAIRS_PER_RUN,
    PROMPT_KEYS,
    GeneratorError,
    batch_capacities,
    build_manifest,
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

    def test_manifest_contains_three_adjacent_tasks_per_pair(self) -> None:
        posts = [{"id": index, "text": f"Post {index}"} for index in range(30)]
        pairs = sample_pairs(len(posts), 45, random.Random(12))
        batches = optimize_batches(pairs, random.Random(12), restarts=3, swap_attempts=500)
        manifest = build_manifest(
            posts,
            batches,
            "comparison-example-v1",
            "comparison-example-v1",
            12,
            len(pairs),
            random.Random(12),
        )

        runs = manifest["conditions"][0]["runs"]
        self.assertEqual([len(run["tasks"]) for run in runs], [120, 15])

        emitted_pairs: set[tuple[int, int]] = set()
        for run in runs:
            self.assertEqual(
                [task["position"] for task in run["tasks"]],
                list(range(1, len(run["tasks"]) + 1)),
            )

            for offset in range(0, len(run["tasks"]), len(PROMPT_KEYS)):
                triplet = run["tasks"][offset : offset + len(PROMPT_KEYS)]
                self.assertEqual({task["prompt_key"] for task in triplet}, set(PROMPT_KEYS))
                orientations = {
                    (task["stimuli"]["post_a"]["id"], task["stimuli"]["post_b"]["id"])
                    for task in triplet
                }
                self.assertEqual(len(orientations), 1)
                left, right = next(iter(orientations))
                emitted_pairs.add(tuple(sorted((left, right))))

        self.assertEqual(emitted_pairs, set(pairs))

    def test_reads_jsonl_and_preserves_complete_post_objects(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "posts.jsonl"
            path.write_text(
                '{"text":"First","source":{"id":1}}\n\n'
                '{"text":"Second","label":"example"}\n',
                encoding="utf-8",
            )

            self.assertEqual(
                read_posts(path),
                [
                    {"text": "First", "source": {"id": 1}},
                    {"text": "Second", "label": "example"},
                ],
            )

    def test_reports_invalid_jsonl_line(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "posts.jsonl"
            path.write_text('{"text":"Valid"}\n{"text":}\n', encoding="utf-8")

            with self.assertRaisesRegex(GeneratorError, r"posts\.jsonl:2: invalid JSON"):
                read_posts(path)


if __name__ == "__main__":
    unittest.main()
