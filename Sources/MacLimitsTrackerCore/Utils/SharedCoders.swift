import Foundation

extension JSONDecoder {
    /// Shared instance for default JSON decoding to avoid allocation overhead.
    public static let shared = JSONDecoder()

    /// Shared instance for JSON decoding with snake_case key strategy.
    public static let sharedSnakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
