import Foundation

/// A one-line explanation of why a JSON file failed to load, suitable for showing to the user.
func describeLoadError(_ error: Error) -> String {
    guard let error = error as? DecodingError else { return error.localizedDescription }

    func location(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "" : "\(path): "
    }

    switch error {
    case .dataCorrupted(let context):
        let underlying = (context.underlyingError as NSError?)?
            .userInfo[NSDebugDescriptionErrorKey] as? String
        return location(context) + (underlying ?? context.debugDescription)
    case .keyNotFound(let key, let context):
        return location(context) + "missing \"\(key.stringValue)\""
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
        return location(context) + context.debugDescription
    @unknown default:
        return error.localizedDescription
    }
}
