import Benchmark

let benchmarks: @Sendable () -> Void = {
    fileSystemMigrationResolverBenchmarks()
}
