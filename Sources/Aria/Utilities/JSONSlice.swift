import Foundation

/// Safely extract the substring spanning the first `open` delimiter through the
/// last `close` delimiter — the common "pull the JSON object/array out of chatty
/// model output" pattern.
///
/// Returns nil when either delimiter is missing OR when they appear out of order
/// (a stray `}` before the first `{`, e.g. `"] text ["`). The naive
/// `s[first...last]` form traps with "Range requires lowerBound <= upperBound"
/// on such input, which is a crash on adversarial/garbled model output — this
/// helper degrades to nil instead so callers fall through to their empty path.
enum JSONSlice {
    static func between(_ s: String, open: Character, close: Character) -> String? {
        guard let start = s.firstIndex(of: open),
              let end = s.lastIndex(of: close),
              start <= end else { return nil }
        return String(s[start...end])
    }
}
