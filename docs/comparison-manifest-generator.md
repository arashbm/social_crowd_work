# Comparison Manifest Generator

`scripts/generate_comparison_manifest.py` reads JSONL post objects and creates an import manifest for a specified questionnaire. Each input object must have a final `context_chains` entry whose `chain_text` is a non-empty string. That text is copied to the object's `text` property, and all other properties are preserved in the generated stimuli.

The requested comparisons are sampled uniformly without replacement from all possible unordered input-post pairs. Sampling happens before run construction. The generator then uses randomized greedy partitioning and improving pair swaps to reduce the number of unique posts shown in each run without changing the sampled pair set.

Each full run contains exactly 40 sampled pairs and 40 tasks/pages. Every pair appears in one task with the requested `questionnaire_key`. The generator balances A/B orientation within each run. The final run may be smaller.

```bash
python3 scripts/generate_comparison_manifest.py posts.jsonl manifest.json \
  --comparisons 1000 \
  --condition-key psychosocial-comparisons-v1 \
  --questionnaire-key psychosocial-comparisons.v1 \
  --instructions-key participant-instructions.v1 \
  --seed 20260813
```

`--questionnaire-key` is required and is written to every task and the generator metadata. `--instructions-key` is optional; when supplied, it is written to the condition as `instructions_key`, and when omitted that field is not emitted. The output uses manifest format version `3`. Manifest metadata also records generator version `3` and `pairs_per_full_run` as `40`.

If `--seed` is omitted, the script generates one and prints it to standard error. Reusing the same input order, arguments, Python version, and seed reproduces the manifest. Increase `--restarts` or `--swap-attempts` to spend more time reducing post replication. Use `--force` to replace an existing output file.

Validate and import the result with:

```bash
mix social_crowd_work.import --dry-run manifest.json
mix social_crowd_work.import manifest.json
```

The sampled set is an exact uniform sample of all possible pairs. Run membership is intentionally optimized, so an individual run is not itself an independent uniform sample of pairs.
