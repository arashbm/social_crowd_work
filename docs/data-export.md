# Data Export

Assigned tasks are exported as newline-delimited JSON. Each line is a self-contained analysis record containing condition variants, import provenance, the run and task, raw stimuli, participant identity and consent metadata, and an optional response.

Every task assigned to a participant is included. An unanswered task has `"response": null`, while an explicit skip has a response object with `"choice": "skip"`.

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
