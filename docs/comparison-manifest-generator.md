# Comparison Manifest Generator

`scripts/generate_comparison_manifest.py` reads JSONL post objects and creates an import manifest for `worry.v1`, `restlessness.v1`, and `cognitive-disruption.v1`. Every input object must contain a non-empty string `text`; all other properties are preserved in the generated stimuli.

The requested comparisons are sampled uniformly without replacement from all possible unordered input-post pairs. Sampling happens before run construction. The generator then uses randomized greedy partitioning and improving pair swaps to reduce the number of unique posts shown in each run without changing the sampled pair set.

Each full run contains 40 pairs and 120 tasks. Every pair appears in three adjacent tasks, once for each prompt, with the same A/B orientation. The final run may be smaller.

```bash
python3 scripts/generate_comparison_manifest.py posts.jsonl manifest.json \
  --comparisons 1000 \
  --condition-key psychosocial-comparisons-v1 \
  --seed 20260813
```

If `--seed` is omitted, the script generates one and prints it to standard error. Reusing the same input order, arguments, Python version, and seed reproduces the manifest. Increase `--restarts` or `--swap-attempts` to spend more time reducing post replication. Use `--force` to replace an existing output file.

Validate and import the result with:

```bash
mix social_crowd_work.import --dry-run manifest.json
mix social_crowd_work.import manifest.json
```

The sampled set is an exact uniform sample of all possible pairs. Run membership is intentionally optimized, so an individual run is not itself an independent uniform sample of pairs.
