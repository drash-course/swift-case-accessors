import Foundation
import SwiftDiagnostics

enum CaseAccessorsDiagnostic: String, DiagnosticMessage {
    case notAnEnum
    case noCases

    var severity: DiagnosticSeverity {
        switch self {
        case .notAnEnum:
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
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "CaseAccessorMacros", id: rawValue)
    }
}
