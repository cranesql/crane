import ArgumentParser
import Crane
import CranePostgresNIO
import Logging

@main
struct Example: AsyncParsableCommand {
    func run() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .trace
            return handler
        }

        let migrator = Migrator(
            target: PostgresMigrationTarget(
                host: "localhost",
                username: "example",
                password: "example",
                database: "example"
            )
        )

        try await withThrowingDiscardingTaskGroup { group in
            group.addTask {
                try await migrator.run()
            }

            try await migrator.apply()
            group.cancelAll()
        }
    }
}
