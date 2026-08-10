# Import Manifest

Experiment designs are imported as versioned JSON documents. Imports are validated in full before any records are written.

```json
{
  "format_version": "1",
  "conditions": [
    {
      "key": "comparison-en-pilot",
      "task_type": "comparison",
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
              "prompt_key": "a-versioned-prompt-key.v1",
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

Condition keys are global. Reusing a condition key requires an exact match of its task type and variants. Run keys are unique within a condition, including across separate import files. Task positions are positive integers and unique within a run.

Prompt keys must exist in `SocialCrowdWork.Prompts` and be compatible with the condition's task type.

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
