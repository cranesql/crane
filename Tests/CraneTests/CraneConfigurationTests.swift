import Crane
import Testing

@Suite("CraneConfiguration")
struct CraneConfigurationTests {
    @Test
    func placeholder() async throws {
        print(CraneConfiguration())
    }
}
