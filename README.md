# Crane

[![Unit Test](https://github.com/cranesql/crane/actions/workflows/unit-test.yaml/badge.svg)](https://github.com/cranesql/crane/actions/workflows/unit-test.yaml)
[![codecov](https://codecov.io/github/cranesql/crane/graph/badge.svg?token=A0XX6J11BL)](https://codecov.io/github/cranesql/crane)

A cross-platform SQL migration tool, inspired by [Flyway](https://github.com/flyway/flyway).

## Database support

Crane currently supports performing migrations on the following databases:

| Library | Status | Description |
| --- | --- | --- |
| [cranesql/crane-postgres-nio](https://github.com/cranesql/crane-postgres-nio) | 🟠 WIP | PostgreSQL support based on [vapor/postgres-nio](https://github.com/vapor/postgres-nio). |
| [cranesql/crane-grdb](https://github.com/cranesql/crane-grdb) | 🟠 WIP | SQLite support based on [groue/GRDB.swift](https://github.com/groue/GRDB.swift). |
| Your library? | ... | Please [open a PR](https://github.com/cranesql/crane/pulls) |
