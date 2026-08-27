//
//  TelescopeSessionError.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.4, I-5.
//

/// Errors raised by Navi's own telescope-session code, distinct from `INDIMCPClientError`/
/// `DeviceControlError` (both from INDIMCPKit itself).
enum TelescopeSessionError: Error, CustomStringConvertible, Sendable {
    /// A single connect-cascade step (§4.4) didn't complete within its timeout. `INDIMCPClient`
    /// has no built-in request timeout, so this is Navi's own responsibility per I-5.
    case timedOut

    var description: String {
        switch self {
        case .timedOut: return "The telescope server didn't respond in time."
        }
    }
}
