import Foundation

/// Errors that can occur during RTF conversion.
public enum RTFConversionError: Error, Sendable {
    /// Failed to generate RTF data from the attributed string.
    case failedToGenerateRTF

    /// Failed to parse RTF data into an attributed string.
    case failedToParseRTF

    /// The provided data is not valid RTF.
    case invalidRTFData
}
