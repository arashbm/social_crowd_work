# Import Manifest

Experiment designs are imported as versioned JSON documents. Format version `3` supports an optional condition instruction set. Imports are validated in full before any records are written.

```json
{
  "format_version": "3",
  "conditions": [
    {
      "key": "comparison-en-pilot",
      "task_type": "comparison",
      "instructions_key": "participant-instructions.v1",
      "variants": {
        "language": "en",
        "phase": "pilot"
      },
      "runs": [
        {
          "key": "run-001",
          "tasks": [
            {
              "position": 1,
              "questionnaire_key": "psychosocial-comparisons.v1",
              "stimuli": {
                "post_a": {
                  "text": "First post"
                },
                "post_b": {
                  "text": "Second post"
                }
              }
            }
          ]
        }
      ]
    }
  ]
}
```

`task_type` is either `comparison` or `binary_question`. Comparison stimuli contain exactly `post_a` and `post_b`; binary-question stimuli contain exactly `post`. Every post requires a non-empty string `text`, while all other post properties are preserved without interpretation.

`instructions_key` is optional. When present, it must identify a configured instruction set to show before the condition's tasks. Conditions that omit it begin with their tasks as before.

Condition keys are global. Reusing a condition key requires an exact match of its task type, variants, and instruction-set assignment. Run keys are unique within a condition, including across separate import files. Task positions must be contiguous from `1` within each run.

Questionnaire keys must exist in `SocialCrowdWork.Questionnaires` and be compatible with the condition's task type. A task stores its stimuli once; the questionnaire defines the ordered questions shown for those stimuli. For example, `psychosocial-comparisons.v1` asks the production worry, restlessness, and cognitive-disruption questions on one comparison task instead of representing that shared stimulus pair as three adjacent tasks.

The reusable API accepts file contents so both CLI and future web uploads use the same code:

```elixir
SocialCrowdWork.Imports.import_manifest(contents,
  filename: "pilot.json",
  dry_run: true
)
```

The command-line adapter is:

```sh
mix social_crowd_work.import --dry-run path/to/manifest.json
mix social_crowd_work.import path/to/manifest.json
```

Successful imports store a SHA-256 fingerprint of the exact file contents. Importing those exact contents again returns the original import batch without creating records.
