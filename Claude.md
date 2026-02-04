# Claude.md - Crane Project Documentation

## Project Overview

Crane is migration tool for SQL-based databases implemented in Swift, running on all platforms Swift supports.
It's inspired by [Flyway](https://github.com/flyway/flyway) but does not aim to be a one-to-one clone of it.

Crane uses plain SQL files to define migrations, like `v1.create_users.apply.sql` and `v1.create_users.undo.sql`.

The project is split into multiple repositories. [https://github.com/cranesql/crane](https://github.com/cranesql/crane)
contains the main library and an API to define so-called migration targets, i.e. the support for actual databases.
Implementations of this API are located in separate repositories, e.g.
[https://github.com/cranesql/crane-postgres-nio](https://github.com/cranesql/crane-postgres-nio).

## Code Formatting

This project uses [swift-format](https://github.com/apple/swift-format) to automatically format Swift code.

### Formatting Rules

- Nested types (enums, structs) should be defined **after** the init method, not before.
- Properties should be grouped together before methods and nested types.

## Documentation

Documentation comments should always end with a period.

## Notes for Claude

When asked about Flyway implementation details, always try to find answers by looking at the GitHub repository.
Make sure that Swift code you write is properly formatted using `swift-format`.
