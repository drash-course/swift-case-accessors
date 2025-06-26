import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct CaseAccessorsMacro: MemberMacro {
    init(setters: Bool) {}

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDeclaration = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: Syntax(attribute),
                message: CaseAccessorsDiagnostic.notAnEnum
            ))
            return []
        }

        // parse macro arguments
        var generateSetters = false
        if let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label?.text == "setters",
                   let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self)
                {
                    generateSetters = boolLiteral.literal.tokenKind == .keyword(.true)
                } else {
                    context.diagnose(Diagnostic(
                        node: Syntax(attribute),
                        message: CaseAccessorsDiagnostic.invalidArguments
                    ))
                }
            }
        }

        let members = enumDeclaration.memberBlock.members
        let caseDeclarations = members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
        let caseElements = caseDeclarations.flatMap(\.elements)

        if caseElements.isEmpty {
            context.diagnose(Diagnostic(
                node: Syntax(attribute),
                message: CaseAccessorsDiagnostic.noCases
            ))
            return []
        }

        return caseElements.map { caseElement in
            guard let parameters = caseElement.associatedValue?.parameters else {
                // case label
                return """
                var \(caseElement.identifier): Bool {
                    if case let .\(caseElement.identifier) = self {
                        return true
                    }
                    return false
                }
                """
            }

            let returnTypeSyntax: TypeSyntax

            if parameters.count == 1,
               let parameter = parameters.first,
               parameter.firstName == nil
            {
                if parameter.is(OptionalTypeSyntax.self) {
                    // case label(T?)
                    //            ^^   return type is `T?`
                    returnTypeSyntax = parameter.type
                } else if parameter.type.is(SomeOrAnyTypeSyntax.self) {
                    // case label(any P)
                    //            ^^^^^   return type is `(any P)?`
                    let parensGroup = TupleTypeSyntax(elements: TupleTypeElementListSyntax {
                        TupleTypeElementSyntax(type: parameter.type)
                    })
                    returnTypeSyntax = TypeSyntax(OptionalTypeSyntax(wrappedType: parensGroup))
                } else {
                    // case label(T)
                    //            ^   return type is `T?`
                    returnTypeSyntax = TypeSyntax(OptionalTypeSyntax(wrappedType: parameter.type))
                }


                let getter: DeclSyntax = """
                get {
                    if case let .\(caseElement.identifier)(param) = self {
                        return param
                    }
                    return nil
                }
                """

                let setter: DeclSyntax = if generateSetters { """
                set {
                    if let newValue {
                        self = .\(caseElement.identifier)(newValue)
                    } else {
                        assertionFailure("The @CaseAccessors generated setter for \(raw: enumDeclaration.name.text).\(raw: caseElement.identifier) expects that `newValue` is not nil")
                    }
                }
                """
                } else {
                    ""
                }

                return """
                var \(caseElement.identifier): \(returnTypeSyntax) {
                    \(getter)
                    \(setter)
                }
                """

            } else {
                // case label(name1: T1, name2: T2)
                //            ^^^^^^^^^^^^^^^^^^^^   return type is `(name1: T1, name2: T2)?`
                let tupleType = TupleTypeSyntax(
                    elements: TupleTypeElementListSyntax {
                        for parameter in parameters {
                            if let name = parameter.firstName, name.text != "_" {
                                TupleTypeElementSyntax(name: name, colon: .colonToken(), type: parameter.type)
                            } else {
                                TupleTypeElementSyntax(type: parameter.type)
                            }
                        }
                    }
                )
                returnTypeSyntax = TypeSyntax(OptionalTypeSyntax(wrappedType: tupleType))

                var paramNames: [String] = parameters.enumerated().map { index, parameter in
                    if let name = parameter.firstName, name.text != "_" {
                        name.text
                    } else {
                        "_p\(index)"
                    }
                }
                var joinedNames = paramNames.joined(separator: ", ")

                let getter: DeclSyntax = """
                get {
                    if case let .\(caseElement.identifier)(\(raw: joinedNames)) = self {
                        return (\(raw: joinedNames))
                    }
                    return nil
                }
                """

                var setter: DeclSyntax?
                if generateSetters {
                    // from        `case label(Int, name: Int)`
                    // generating  `.label(_p0, name: name)`
                    let caseExpression = FunctionCallExprSyntax(
                        calledExpression: MemberAccessExprSyntax(period: .periodToken(), name: caseElement.name),
                        leftParen: .leftParenToken(),
                        arguments: LabeledExprListSyntax {
                            for (index, parameter) in parameters.enumerated() {
                                if let name = parameter.firstName, name.text != "_" {
                                    LabeledExprSyntax(
                                        label: name,
                                        colon: .colonToken(),
                                        expression: IdentifierExprSyntax(identifier: name)
                                    )
                                } else {
                                    LabeledExprSyntax(
                                        expression: IdentifierExprSyntax(identifier: "_p\(raw: index)")
                                    )
                                }
                            }
                        },
                        rightParen: .rightParenToken(),
                    )
                    setter = """
                    set {
                        if let (\(raw: joinedNames)) = newValue {
                            self = \(caseExpression)
                        } else {
                            assertionFailure("The @CaseAccessors generated setter for \(raw: enumDeclaration.name.text).\(raw: caseElement.identifier) expects that `newValue` is not nil")
                        }
                    }
                    """
                }

                return """
                var \(caseElement.identifier): \(returnTypeSyntax) {
                    \(getter)
                    \(setter ?? "")
                }
                """
            }
        }
    }
}
