# Historical SwiftData fixtures

The sibling directories are real SQLite stores created with the frozen
`WeekflowSchemaV1`. `FixtureMigrationTests` copies and opens each store through
the production V2 migration plan, then compares complete canonical content.

Regenerate intentionally with:

```sh
WEEKFLOW_REGENERATE_V1_FIXTURES=1 swift test --filter generateHistoricalV1Fixtures
```
