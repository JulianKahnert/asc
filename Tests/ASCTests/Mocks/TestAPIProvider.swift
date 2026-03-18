import AppStoreConnect_Swift_SDK
import Crypto
import Foundation

/// Creates a real `APIProvider` backed by a `MockRequestExecutor`.
///
/// A fresh P256 signing key is generated at test time so that
/// `APIConfiguration` can produce valid JWT tokens. The tokens are never
/// verified -- the mock executor ignores them -- but the SDK requires a
/// valid key to construct the configuration.
enum TestAPIProvider {

    /// Returns a tuple of `(APIProvider, MockRequestExecutor)` so that
    /// tests can register routes and then call command logic.
    static func make() throws -> (APIProvider, MockRequestExecutor) {
        // Generate a throwaway P256 private key and base64-encode its DER
        // representation, which is what the SDK's APIConfiguration expects.
        let privateKey = P256.Signing.PrivateKey()
        let derBase64 = privateKey.derRepresentation.base64EncodedString()

        let configuration = try APIConfiguration(
            issuerID: "00000000-0000-0000-0000-000000000000",
            privateKeyID: "TESTKEY123",
            privateKey: derBase64
        )

        let executor = MockRequestExecutor()
        let provider = APIProvider(configuration: configuration, requestExecutor: executor)
        return (provider, executor)
    }
}
