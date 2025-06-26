import Foundation
import SwiftDiagnostics

enum CaseAccessorsDiagnostic: String, DiagnosticMessage {
    case notAnEnum
    case noCases
    case invalidArguments

    var severity: DiagnosticSeverity {
        switch self {
        case .notAnEnum, .invalidArguments:
            return .error
        case .noCases:
            return .warning
        }
    }

    var message: String {
        switch self {
        case .notAnEnum:
            "'@CaseAccessors' can only be applied to 'enum'"
        case .noCases:
            "'@CaseAccessors' was applied to an enum without any cases. This has no effect."
        case .invalidArguments:
            "Invalid arguments, expected '@CaseAccessors(setters: true)'"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "CaseAccessorMacros", id: rawValue)
    }
}
