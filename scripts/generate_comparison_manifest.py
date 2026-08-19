#!/usr/bin/env python3
"""Generate an import manifest from a uniform sample of JSONL post pairs."""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import secrets
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

PAIRS_PER_RUN = 40

Post = dict[str, Any]
Pair = tuple[int, int]


class GeneratorError(ValueError):
    """Raised for invalid input or generation parameters."""


@dataclass
class Batch:
    pairs: list[Pair]
    post_counts: Counter[int]

    @classmethod
    def from_pairs(cls, pairs: Sequence[Pair]) -> Batch:
        counts: Counter[int] = Counter()
        for left, right in pairs:
            counts.update((left, right))
        return cls(list(pairs), counts)

    @property
    def unique_post_count(self) -> int:
        return len(self.post_counts)

    def replace(self, index: int, pair: Pair) -> None:
        old_pair = self.pairs[index]
        for post in old_pair:
            self.post_counts[post] -= 1
            if self.post_counts[post] == 0:
                del self.post_counts[post]
        self.pairs[index] = pair
        self.post_counts.update(pair)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Uniformly sample post pairs, cluster them into runs with few repeated "
            "posts, and emit an importable SocialCrowdWork manifest. Each full run "
            f"contains {PAIRS_PER_RUN} pairs and {PAIRS_PER_RUN} tasks."
        )
    )
    parser.add_argument("input", type=Path, help="JSONL file containing post objects")
    parser.add_argument("output", type=Path, help="output manifest JSON file")
    parser.add_argument("--comparisons", "-m", type=positive_int, required=True)
    parser.add_argument("--condition-key", required=True)
    parser.add_argument("--questionnaire-key", required=True)
    parser.add_argument(
        "--instructions-key",
        help="optional instruction set key to assign to the condition",
    )
    parser.add_argument(
        "--run-key-prefix",
        help="run key prefix; defaults to the condition key",
    )
    parser.add_argument(
        "--seed",
        type=int,
        help="integer seed; a random seed is generated and reported when omitted",
    )
    parser.add_argument(
        "--restarts",
        type=positive_int,
        default=16,
        help="randomized greedy optimization restarts (default: 16)",
    )
    parser.add_argument(
        "--swap-attempts",
        type=nonnegative_int,
        default=50_000,
        help="local-search swap attempts per restart (default: 50000)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace the output file if it already exists",
    )
    return parser.parse_args(argv)


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def nonnegative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must not be negative")
    return parsed


def read_posts(path: Path) -> list[Post]:
    posts: list[Post] = []

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise GeneratorError(f"cannot read {path}: {error}") from error

    for line_number, line in enumerate(lines, start=1):
        if not line.strip():
            continue

        try:
            post = json.loads(line, parse_constant=reject_json_constant)
        except (json.JSONDecodeError, GeneratorError) as error:
            raise GeneratorError(f"{path}:{line_number}: invalid JSON: {error}") from error

        if not isinstance(post, dict):
            raise GeneratorError(f"{path}:{line_number}: each line must be a JSON object")

        text = post["context_chains"][-1]["chain_text"]
        if not isinstance(text, str) or not text.strip():
            raise GeneratorError(
                f"{path}:{line_number}: text must be a non-empty string"
            )

        post["text"] = text
        posts.append(post)

    if len(posts) < 2:
        raise GeneratorError("the input must contain at least two valid posts")

    return posts


def reject_json_constant(value: str) -> None:
    raise GeneratorError(f"non-standard numeric value {value!r} is not allowed")


def sample_pairs(post_count: int, comparisons: int, rng: random.Random) -> list[Pair]:
    possible_pairs = math.comb(post_count, 2)
    if comparisons > possible_pairs:
        raise GeneratorError(
            f"requested {comparisons} comparisons, but {post_count} posts provide "
            f"only {possible_pairs} unique pairs"
        )

    ranks = rng.sample(range(possible_pairs), comparisons)
    return [unrank_pair(rank, post_count) for rank in ranks]


def unrank_pair(rank: int, post_count: int) -> Pair:
    """Map a lexicographic rank to one unordered pair without materializing all pairs."""
    low = 0
    high = post_count - 1

    while low < high:
        middle = (low + high + 1) // 2
        if pair_row_start(middle, post_count) <= rank:
            low = middle
        else:
            high = middle - 1

    left = low
    right = left + 1 + rank - pair_row_start(left, post_count)
    return left, right


def pair_row_start(left: int, post_count: int) -> int:
    return left * (2 * post_count - left - 1) // 2


def batch_capacities(pair_count: int) -> list[int]:
    full_runs, remainder = divmod(pair_count, PAIRS_PER_RUN)
    capacities = [PAIRS_PER_RUN] * full_runs
    if remainder:
        capacities.append(remainder)
    return capacities


def optimize_batches(
    pairs: Sequence[Pair],
    rng: random.Random,
    restarts: int,
    swap_attempts: int,
) -> list[Batch]:
    capacities = batch_capacities(len(pairs))
    best_batches: list[Batch] | None = None
    best_score: tuple[int, int, tuple[int, ...]] | None = None

    for _restart in range(restarts):
        batches = greedy_partition(pairs, capacities, rng)
        improve_by_swapping(batches, rng, swap_attempts)
        candidate_score = partition_score(batches)

        if best_score is None or candidate_score < best_score:
            best_batches = batches
            best_score = candidate_score

    if best_batches is None:
        raise GeneratorError("could not construct comparison runs")

    return best_batches


def greedy_partition(
    pairs: Sequence[Pair], capacities: Sequence[int], rng: random.Random
) -> list[Batch]:
    remaining = list(pairs)
    degrees = Counter(post for pair in remaining for post in pair)
    batches: list[Batch] = []

    for capacity in capacities:
        seed_window = max(1, len(remaining) // 4)
        seed_candidates = sorted(
            remaining,
            key=lambda pair: degrees[pair[0]] + degrees[pair[1]],
            reverse=True,
        )[:seed_window]
        seed = rng.choice(seed_candidates)
        selected = [seed]
        selected_posts = set(seed)
        remove_remaining_pair(remaining, degrees, seed)

        while len(selected) < capacity:
            best_cost = min(marginal_cost(selected_posts, pair) for pair in remaining)
            candidates = [
                pair
                for pair in remaining
                if marginal_cost(selected_posts, pair) == best_cost
            ]
            best_degree = max(degrees[pair[0]] + degrees[pair[1]] for pair in candidates)
            candidates = [
                pair
                for pair in candidates
                if degrees[pair[0]] + degrees[pair[1]] == best_degree
            ]
            pair = rng.choice(candidates)
            selected.append(pair)
            selected_posts.update(pair)
            remove_remaining_pair(remaining, degrees, pair)

        batches.append(Batch.from_pairs(selected))

    return batches


def marginal_cost(posts: set[int], pair: Pair) -> int:
    return int(pair[0] not in posts) + int(pair[1] not in posts)


def remove_remaining_pair(
    remaining: list[Pair], degrees: Counter[int], pair: Pair
) -> None:
    remaining.remove(pair)
    degrees.subtract(pair)


def improve_by_swapping(
    batches: list[Batch], rng: random.Random, attempts: int
) -> None:
    if len(batches) < 2:
        return

    stale_attempts = 0

    for _attempt in range(attempts):
        first_index, second_index = rng.sample(range(len(batches)), 2)
        first = batches[first_index]
        second = batches[second_index]
        first_pair_index = rng.randrange(len(first.pairs))
        second_pair_index = rng.randrange(len(second.pairs))
        first_pair = first.pairs[first_pair_index]
        second_pair = second.pairs[second_pair_index]

        old_score = local_score(first, second)
        first.replace(first_pair_index, second_pair)
        second.replace(second_pair_index, first_pair)
        new_score = local_score(first, second)

        if new_score < old_score:
            stale_attempts = 0
        else:
            first.replace(first_pair_index, first_pair)
            second.replace(second_pair_index, second_pair)
            stale_attempts += 1

        if stale_attempts >= 10_000:
            break


def local_score(first: Batch, second: Batch) -> tuple[int, int]:
    counts = (first.unique_post_count, second.unique_post_count)
    return sum(counts), max(counts)


def partition_score(batches: Sequence[Batch]) -> tuple[int, int, tuple[int, ...]]:
    counts = [batch.unique_post_count for batch in batches]
    return sum(counts), max(counts), tuple(sorted(counts, reverse=True))


def build_manifest(
    posts: Sequence[Post],
    batches: Sequence[Batch],
    condition_key: str,
    run_key_prefix: str,
    questionnaire_key: str,
    seed: int,
    comparisons: int,
    rng: random.Random,
    instructions_key: str | None = None,
) -> dict[str, Any]:
    validate_key("condition key", condition_key)
    validate_key("run key prefix", run_key_prefix)
    validate_key("questionnaire key", questionnaire_key)
    if instructions_key is not None:
        validate_key("instructions key", instructions_key)

    runs = [
        build_run(posts, batch, run_key_prefix, questionnaire_key, index, rng)
        for index, batch in enumerate(batches, start=1)
    ]

    condition = {
        "key": condition_key,
        "task_type": "comparison",
        "variants": {
            "generator": "generate_comparison_manifest.py",
            "generator_version": "3",
            "seed": seed,
            "sampled_pairs": comparisons,
            "pairs_per_full_run": PAIRS_PER_RUN,
            "questionnaire_key": questionnaire_key,
            "pair_sampling": "uniform_without_replacement",
            "run_partitioning": "minimum_post_replication_heuristic",
        },
        "runs": runs,
    }
    if instructions_key is not None:
        condition["instructions_key"] = instructions_key

    return {"format_version": "3", "conditions": [condition]}


def validate_key(label: str, value: str) -> None:
    if not value.strip():
        raise GeneratorError(f"{label} must not be blank")
    if len(value) > 255:
        raise GeneratorError(f"{label} must be at most 255 characters")


def build_run(
    posts: Sequence[Post],
    batch: Batch,
    run_key_prefix: str,
    questionnaire_key: str,
    run_number: int,
    rng: random.Random,
) -> dict[str, Any]:
    run_key = f"{run_key_prefix}-run-{run_number:04d}"
    validate_key("generated run key", run_key)
    pairs = list(batch.pairs)
    rng.shuffle(pairs)
    oriented_pairs = orient_pairs(pairs, rng)
    tasks = [
        {
            "position": position,
            "questionnaire_key": questionnaire_key,
            "stimuli": {
                "post_a": posts[post_a],
                "post_b": posts[post_b],
            },
        }
        for position, (post_a, post_b) in enumerate(oriented_pairs, start=1)
    ]

    return {"key": run_key, "tasks": tasks}


def orient_pairs(pairs: Sequence[Pair], rng: random.Random) -> list[Pair]:
    a_counts: Counter[int] = Counter()
    b_counts: Counter[int] = Counter()
    oriented: list[Pair] = []

    for left, right in pairs:
        forward_score = orientation_score(left, right, a_counts, b_counts)
        reverse_score = orientation_score(right, left, a_counts, b_counts)

        if forward_score < reverse_score:
            post_a, post_b = left, right
        elif reverse_score < forward_score:
            post_a, post_b = right, left
        else:
            post_a, post_b = (left, right) if rng.getrandbits(1) else (right, left)

        a_counts[post_a] += 1
        b_counts[post_b] += 1
        oriented.append((post_a, post_b))

    return oriented


def orientation_score(
    post_a: int,
    post_b: int,
    a_counts: Counter[int],
    b_counts: Counter[int],
) -> int:
    return abs(a_counts[post_a] + 1 - b_counts[post_a]) + abs(
        a_counts[post_b] - b_counts[post_b] - 1
    )


def write_manifest(path: Path, manifest: dict[str, Any], force: bool) -> None:
    if path.exists() and not force:
        raise GeneratorError(f"output already exists: {path} (use --force to replace it)")
    if not path.parent.is_dir():
        raise GeneratorError(f"output directory does not exist: {path.parent}")

    contents = json.dumps(manifest, ensure_ascii=False, indent=2, allow_nan=False) + "\n"

    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=path.parent, delete=False
        ) as temporary:
            temporary.write(contents)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, path)
    except OSError as error:
        raise GeneratorError(f"cannot write {path}: {error}") from error


def print_summary(
    posts: Sequence[Post], batches: Sequence[Batch], comparisons: int, seed: int
) -> None:
    unique_counts = [batch.unique_post_count for batch in batches]
    print(
        f"Generated {comparisons} unique pairs as {comparisons} tasks across "
        f"{len(batches)} runs from {len(posts)} source posts.",
        file=sys.stderr,
    )
    print(f"Seed: {seed}", file=sys.stderr)
    print(f"Unique posts per run: {unique_counts}", file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        seed = args.seed if args.seed is not None else secrets.randbelow(2**63)
        sampling_rng = random.Random(seed)
        posts = read_posts(args.input)
        pairs = sample_pairs(len(posts), args.comparisons, sampling_rng)
        batches = optimize_batches(
            pairs,
            sampling_rng,
            restarts=args.restarts,
            swap_attempts=args.swap_attempts,
        )
        run_key_prefix = args.run_key_prefix or args.condition_key
        manifest = build_manifest(
            posts,
            batches,
            args.condition_key,
            run_key_prefix,
            args.questionnaire_key,
            seed,
            args.comparisons,
            sampling_rng,
            args.instructions_key,
        )
        write_manifest(args.output, manifest, args.force)
        print_summary(posts, batches, args.comparisons, seed)
    except GeneratorError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
