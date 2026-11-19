import Foundation

func mapErrors<T>(_ body: () async throws -> T) async throws -> T {
  do {
    return try await body()
  } catch {
    throw FetchrError.from(error)
  }
}
