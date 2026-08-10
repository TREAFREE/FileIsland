import Foundation

enum ConversionGroupKind: String, CaseIterable, Equatable, Sendable {
    case image
    case nativeVideo
    case fallbackVideo
    case unsupported
}

struct ConversionGroup: Identifiable, Equatable, Sendable {
    var id: ConversionGroupKind { kind }
    let kind: ConversionGroupKind
    let inputs: [BatchInput]
    let plan: ConversionPlan?

    var processCount: Int { plan?.inputs.count ?? 0 }
    var skippedCount: Int {
        guard kind != .unsupported else { return 0 }
        return max(0, inputs.count - processCount)
    }
}

struct BatchConversionRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let selections: [InputSelection]
    let outputDirectory: URL
    let groups: [ConversionGroup]

    init(
        id: UUID = UUID(),
        selections: [InputSelection],
        outputDirectory: URL,
        groups: [ConversionGroup]
    ) {
        self.id = id
        self.selections = selections
        self.outputDirectory = outputDirectory
        self.groups = groups
    }

    var executableGroups: [ConversionGroup] { groups.filter { $0.plan != nil } }
    var processCount: Int { groups.reduce(0) { $0 + $1.processCount } }
    var skippedCount: Int { groups.reduce(0) { $0 + $1.skippedCount } }
    var failClosedCount: Int { group(.unsupported).inputs.count }

    func group(_ kind: ConversionGroupKind) -> ConversionGroup {
        groups.first(where: { $0.kind == kind })
            ?? ConversionGroup(kind: kind, inputs: [], plan: nil)
    }
}
