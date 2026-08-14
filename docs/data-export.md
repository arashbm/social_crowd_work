# Data Export

Assigned task questions are exported as newline-delimited JSON using schema version `2`. Each line is a self-contained analysis record containing condition variants, import provenance, the run and task, raw stimuli, questionnaire and question identity, participant identity and consent metadata, and an optional response.

Every expected question in every assigned task is included. An unanswered question has `"response": null`, while an explicit skip has a response object with `"choice": "skip"`.

```sh
mix social_crowd_work.export results.jsonl
mix social_crowd_work.export --condition comparison-en-pilot results.jsonl
```

The reusable streaming API is suitable for a future authenticated admin download without loading the complete dataset into memory:

```elixir
SocialCrowdWork.Exports.reduce_jsonl(initial_accumulator, reducer,
  condition_key: "comparison-en-pilot"
)
```

Exports contain raw Prolific participant, study, and session identifiers. Treat generated files as sensitive research data and restrict access accordingly.

## Raw participant telemetry

Authenticated administrators can separately download participant telemetry from the Exports page. The raw telemetry export uses JSONL schema version `1`, with exactly one recorded client event per line plus its condition, run, participation, and optional task context. It includes no calculated or derived metrics.

Both all-condition and condition-specific downloads are available at `/admin/exports/participant-events/download`. These files also contain raw Prolific participant, study, and session identifiers and must be handled as sensitive research data.
