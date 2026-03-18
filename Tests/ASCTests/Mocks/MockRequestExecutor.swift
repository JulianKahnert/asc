import AppStoreConnect_Swift_SDK
import Foundation

/// A stub that matches each incoming URLRequest against a list of route
/// handlers and returns the first matching response.  This replaces the
/// real network layer so that tests exercise the full SDK JSON decoding
/// pipeline without hitting the network.
final class MockRequestExecutor: RequestExecutor, @unchecked Sendable {

    /// A single route entry: when the predicate returns `true` for a
    /// request, the associated response data and status code are returned.
    struct Route: @unchecked Sendable {
        let predicate: @Sendable (URLRequest) -> Bool
        let statusCode: Int
        let data: Data
    }

    private var routes: [Route] = []

    /// Register a route that matches when the URL path contains a given
    /// substring **and** the HTTP method matches.
    func register(
        path pathSubstring: String,
        method: String = "GET",
        statusCode: Int = 200,
        json: String
    ) {
        routes.append(Route(
            predicate: { request in
                let urlPath = request.url?.path ?? ""
                let httpMethod = request.httpMethod ?? "GET"
                return urlPath.contains(pathSubstring) && httpMethod == method
            },
            statusCode: statusCode,
            data: Data(json.utf8)
        ))
    }

    /// Register a route with a fully custom predicate.
    func register(
        predicate: @escaping @Sendable (URLRequest) -> Bool,
        statusCode: Int = 200,
        json: String
    ) {
        routes.append(Route(
            predicate: predicate,
            statusCode: statusCode,
            data: Data(json.utf8)
        ))
    }

    // MARK: - RequestExecutor

    func execute(_ urlRequest: URLRequest, completion: @escaping (Result<Response<Data>, Swift.Error>) -> Void) {
        for route in routes {
            if route.predicate(urlRequest) {
                let response = Response<Data>(
                    requestURL: urlRequest.url,
                    statusCode: route.statusCode,
                    rateLimit: nil,
                    data: route.data
                )
                completion(.success(response))
                return
            }
        }

        // No route matched -- return a 404 so tests fail clearly.
        let response = Response<Data>(
            requestURL: urlRequest.url,
            statusCode: 404,
            rateLimit: nil,
            data: Data("{\"errors\":[{\"detail\":\"No mock route matched: \(urlRequest.url?.absoluteString ?? "?")\"}]}".utf8)
        )
        completion(.success(response))
    }

    func download(_ urlRequest: URLRequest, completion: @escaping (Result<Response<URL>, Swift.Error>) -> Void) {
        completion(.failure(URLError(.unsupportedURL)))
    }
}
