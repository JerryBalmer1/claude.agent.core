# Plans

Structured plans live here. Each plan is a JSON file matching `schemas/plan.schema.json`.

Format (required):
- `id`: string
- `steps`: array of step objects (min 1)
- `expected_output`: string
- `skills_to_build`: array of skill names that don't exist yet (to be built)

Fail-first: the test in `tests/plan.failfirst.ps1` must fail before any plan validator exists.
