//
//  StepTypeActions.swift
//  Stitch
//
//  Created by Christian J Clampitt on 1/30/25.
//

import Foundation
import SwiftUI

// See `StepType` enum
enum StepTypeAction: Equatable, Hashable, Codable {
    
    case addNode(StepActionAddNode)
    case connectNodes(StepActionConnectionAdded)
    case changeValueType(StepActionChangeValueType)
    case setInput(StepActionSetInput)
    case sidebarGroupCreated(StepActionLayerGroupCreated)
    
    var stepType: StepType {
        switch self {
        case .addNode:
            return StepActionAddNode.stepType
        case .connectNodes:
            return StepActionConnectionAdded.stepType
        case .changeValueType:
            return StepActionChangeValueType.stepType
        case .setInput:
            return StepActionSetInput.stepType
        case .sidebarGroupCreated:
            return StepActionLayerGroupCreated.stepType
        }
    }
    
    func toStep() -> Step {
        switch self {
        case .addNode(let x):
            return x.toStep
        case .connectNodes(let x):
            return x.toStep
        case .changeValueType(let x):
            return x.toStep
        case .setInput(let x):
            return x.toStep
        case .sidebarGroupCreated(let x):
            return x.toStep
        }
    }
    
    static func fromStep(_ action: Step) throws -> Self {
        let stepType = action.stepType
        switch stepType {
            
        case .addNode:
            let x = try StepActionAddNode.fromStep(action)
            return .addNode(x)
            
        case .connectNodes:
            let x = try StepActionConnectionAdded.fromStep(action)
            return .connectNodes(x)
            
        case .changeValueType:
            let x = try StepActionChangeValueType.fromStep(action)
            return .changeValueType(x)
            
        case .setInput:
            let x = try StepActionSetInput.fromStep(action)
            return .setInput(x)
            
        case .sidebarGroupCreated:
            let x = try StepActionLayerGroupCreated.fromStep(action)
            return .sidebarGroupCreated(x)
        }
    }
}

struct StepActionLayerGroupCreated: StepActionable {
    static let stepType: StepType = .sidebarGroupCreated
    
    var nodeId: NodeId
    var children: NodeIdSet
    
    var toStep: Step {
        Step(stepType: Self.stepType,
             nodeId: nodeId,
             children: children)
    }
    
    func remapNodeIds(nodeIdMap: [UUID : UUID]) -> StepActionLayerGroupCreated {
        var copy = self
        
        // Update the node id of the layer group itself...
        copy.nodeId = nodeIdMap.get(self.nodeId) ?? self.nodeId
        
        // ... and its children
        copy.children = copy.children.map({ (childId: NodeId) in
            if let newChildId = nodeIdMap.get(childId) {
                log("StepActionLayerGroupCreated: remapNodeIds: NEW newChildId: \(newChildId)")
                return newChildId
            } else {
                log("StepActionLayerGroupCreated: remapNodeIds: OLD childId: \(childId)")
                return childId
            }
        }).toSet
        
        return copy
    }
    
    static func fromStep(_ action: Step) throws -> Self {
        if let nodeId = action.nodeId?.value, let children = action.children {
            return .init(nodeId: nodeId, children: children)
        }
        throw StitchAIManagerError.stepDecoding(Self.stepType, action)
    }
    
    static func createStructuredOutputs() -> StitchAIStepSchema {
        .init(stepType: .sidebarGroupCreated,
              nodeId: OpenAISchema(type: .string),
              children: OpenAISchemaRef(ref: "NodeIdSet"))
    }
    
    static let structuredOutputsCodingKeys: Set<Step.CodingKeys> = [.stepType, .nodeId, .children]
    
    @MainActor
    func applyAction(document: StitchDocumentViewModel) throws {
        let layersSidebar = document.visibleGraph.layersSidebarViewModel
        layersSidebar.primary = Set(self.children) // Primarily select the group's chidlren
        layersSidebar.sidebarGroupCreated(id: self.nodeId) // Create the group
    }
    
    func removeAction(graph: GraphState, document: StitchDocumentViewModel) {
        let layersSidebar = document.visibleGraph.layersSidebarViewModel
        // `sidebarGroupUncreated` is expected to be called from a UI condition where user has 'primarily selected' a layer group
        layersSidebar.primary = Set([self.nodeId])
        layersSidebar.sidebarGroupUncreated()
    }
    
    func validate(createdNodes: inout [NodeId : PatchOrLayer]) throws {
        createdNodes.updateValue(.layer(.group), forKey: self.nodeId)
    }
}

extension Step {
    func convertToType() throws -> any StepActionable {
        let stepType = self.stepType
        switch stepType {
            
        case .addNode:
            return try StepActionAddNode.fromStep(self)

        case .connectNodes:
            return try StepActionConnectionAdded.fromStep(self)
        
        case .changeValueType:
            return try StepActionChangeValueType.fromStep(self)
        
        case .setInput:
            return try StepActionSetInput.fromStep(self)
        
        case .sidebarGroupCreated:
            return try StepActionLayerGroupCreated.fromStep(self)
        }
    }
}

extension Array where Element == any StepActionable {
    // Note: just some obvious validations; NOT a full validation; we can still e.g. create a connection from an output that doesn't exist etc.
    // nil = valid
    func validateLLMSteps() throws {
                
        // Need to update this *as we go*, so that we can confirm that e.g. connectNodes came after we created at least two different nodes
        var createdNodes = [NodeId: PatchOrLayer]()
        
        for step in self {
            try step.validate(createdNodes: &createdNodes)
        } // for step in self
        
        let (depthMap, hasCycle) = self.calculateAINodesAdjacency()
        
        if hasCycle {
            throw StitchAIManagerError
                .actionValidationError("Had cycle")
        }
        
        guard depthMap.isDefined else {
            throw StitchAIManagerError
                .actionValidationError("Could not topologically order the graph")
        }
    }
    
    func calculateAINodesAdjacency() -> (depthMap: DepthMap?,
                                         hasCycle: Bool) {
        let adjacency = AdjacencyCalculator()
        self.forEach {
            if let connectNodesAction = $0 as? StepActionConnectionAdded {
                adjacency.addEdge(from: connectNodesAction.fromNodeId, to: connectNodesAction.toNodeId)
            }
        }
        
        let (depthMap, hasCycle) = adjacency.computeDepth()
        
        if var depthMap = depthMap, !hasCycle {
            // If we did not have a cycle, also add those nodes which did not have a connection;
            // Node without connection = node with depth level 0
            self.nodesCreatedByLLMActions().forEach {
                if !depthMap.get($0).isDefined {
                    depthMap.updateValue(0, forKey: $0)
                }
            }
            return (depthMap, hasCycle)
            
        } else {
            return (depthMap, hasCycle)
        }
    }
}

typealias DepthMap = [UUID: Int]


// "Which properties from `Step` are actually needed by StepType = .addNode ?"

protocol StepActionable: Hashable, Codable {
    static var stepType: StepType { get }
        
    static func fromStep(_ action: Step) throws -> Self
    
    static func createStructuredOutputs() -> StitchAIStepSchema
    
    /// Lists each property tracked in OpenAI's structured outputs.
    static var structuredOutputsCodingKeys: Set<Step.CodingKeys> { get }
    
    var toStep: Step { get }
    
    @MainActor
    func applyAction(document: StitchDocumentViewModel) throws
    
    @MainActor
    func removeAction(graph: GraphState, document: StitchDocumentViewModel)
    
    func validate(createdNodes: inout [NodeId : PatchOrLayer]) throws
    
    /// Maps IDs to some new value.
    func remapNodeIds(nodeIdMap: [UUID: UUID]) -> Self
}

// See `createLLMStepAddNode`
struct StepActionAddNode: StepActionable {
    static let stepType: StepType = .addNode
    
    var nodeId: NodeId
    var nodeName: PatchOrLayer

    var toStep: Step {
        Step(stepType: Self.stepType,
             nodeId: nodeId,
             nodeName: nodeName)
    }
    
    func remapNodeIds(nodeIdMap: [UUID: UUID]) -> Self {
        var copy = self
        copy.nodeId = nodeIdMap.get(self.nodeId) ?? self.nodeId
        return copy
    }
    
    static func fromStep(_ action: Step) throws -> Self {
        if let nodeId = action.nodeId?.value,
           let nodeKind = action.nodeName {
            return .init(nodeId: nodeId,
                         nodeName: nodeKind)
        }
        throw StitchAIManagerError.stepDecoding(Self.stepType, action)
    }
    
    static func createStructuredOutputs() -> StitchAIStepSchema {
        .init(stepType: .addNode,
              nodeId: OpenAISchema(type: .string),
              nodeName: OpenAISchemaRef(ref: "NodeName")
        )
    }
    
    static let structuredOutputsCodingKeys: Set<Step.CodingKeys> = [.stepType, .nodeId, .nodeName]
    
    @MainActor
    func applyAction(document: StitchDocumentViewModel) throws {
        let _ = document.nodeInserted(choice: self.nodeName,
                                      nodeId: self.nodeId)
    }
    
    func removeAction(graph: GraphState,
                      document: StitchDocumentViewModel) {
        graph.deleteNode(id: self.nodeId,
                         document: document,
                         willDeleteLayerGroupChildren: true)
    }
    
    // TODO: what does `validate` mean here ? Are we "making x valid" or "determining whether x is valid" ?
    func validate(createdNodes: inout [NodeId : PatchOrLayer]) throws {
        createdNodes.updateValue(self.nodeName, forKey: self.nodeId)
    }
}

// See `createLLMStepConnectionAdded`
struct StepActionConnectionAdded: StepActionable {
    static let stepType = StepType.connectNodes
    
    // effectively the 'to port'
    let port: NodeIOPortType // integer or key path
    var toNodeId: NodeId
    
    let fromPort: Int //NodeIOPortType // integer or key path
    var fromNodeId: NodeId
    
    var toStep: Step {
        Step(
            stepType: Self.stepType,
            port: port,
            fromPort: fromPort,
            fromNodeId: fromNodeId,
            toNodeId: toNodeId
        )
    }
    
    func remapNodeIds(nodeIdMap: [UUID: UUID]) -> Self {
        var copy = self
        
        copy.toNodeId = nodeIdMap.get(self.toNodeId) ?? self.toNodeId
        copy.fromNodeId = nodeIdMap.get(self.fromNodeId) ?? self.fromNodeId

        return copy
    }
    
    static func fromStep(_ action: Step) throws -> Self {
        guard let fromNodeId = action.fromNodeId?.value,
              let toPort = action.port,
              let toNodeId = action.toNodeId?.value else {
            throw StitchAIManagerError.stepDecoding(Self.stepType, action)
        }

        // default to 0 for some legacy actions ?
        let fromPort = action.fromPort ?? 0
        
        return .init(port: toPort,
                     toNodeId: toNodeId,
                     fromPort: fromPort,
                     fromNodeId: fromNodeId)
    }
    
    static func createStructuredOutputs() -> StitchAIStepSchema {
        .init(stepType: .connectNodes,
              port: OpenAIGeneric(types: [OpenAISchema(type: .integer)],
                                  refs: [OpenAISchemaRef(ref: "LayerPorts")]),
              fromPort: OpenAISchema(type: .integer),
              fromNodeId: OpenAISchema(type: .string),
              toNodeId: OpenAISchema(type: .string)
        )
    }
    
    static let structuredOutputsCodingKeys: Set<Step.CodingKeys> = [.stepType, .port, .fromPort, .fromNodeId, .toNodeId]
    
    var inputPort: NodeIOCoordinate {
        .init(portType: self.port, nodeId: self.toNodeId)
    }
    
    @MainActor
    func applyAction(document: StitchDocumentViewModel) throws {
        let edge: PortEdgeData = PortEdgeData(
            from: .init(portType: .portIndex(self.fromPort), nodeId: self.fromNodeId),
            to: self.inputPort)
        
        let _ = document.visibleGraph.edgeAdded(edge: edge)
        
        // Create canvas node if destination is layer
        if let fromNodeLocation = document.visibleGraph.getNode(self.fromNodeId)?.nonLayerCanvasItem?.position,
           let destinationNode = document.visibleGraph.getNode(self.toNodeId),
           destinationNode.kind.isLayer {
            guard let layerInput = self.port.keyPath?.layerInput else {
                // fatalErrorIfDebug()
                throw StitchAIManagerError.actionValidationError("expected layer node keypath but got: \(self.port)")
            }
            
            var position = fromNodeLocation
            position.x += 200
            
            document.addLayerInputToCanvas(node: destinationNode,
                                           layerInput: layerInput,
                                           draggedOutput: nil,
                                           canvasHeightOffset: nil,
                                           position: position)
        }
    }
    
    func removeAction(graph: GraphState, document: StitchDocumentViewModel) {
        graph.removeEdgeAt(input: self.inputPort)
    }
    
    func validate(createdNodes: inout [NodeId : PatchOrLayer]) throws {
        let originNode = createdNodes.get(self.fromNodeId)
        let destinationNode = createdNodes.get(self.toNodeId)
        
        guard destinationNode.isDefined else {
            throw StitchAIManagerError
                .actionValidationError("ConnectNodes: Tried create a connection from node \(self.fromNodeId.debugFriendlyId) to \(self.toNodeId.debugFriendlyId), but the To Node does not yet exist")
        }
        
        guard let originNode = originNode else {
            throw StitchAIManagerError
                .actionValidationError("ConnectNodes: Tried create a connection from node \(self.fromNodeId.debugFriendlyId) to \(self.toNodeId.debugFriendlyId), but the From Node does not yet exist")
        }
        
        guard originNode.asNodeKind.isPatch else {
            throw StitchAIManagerError
                .actionValidationError("ConnectNodes: Tried create a connection from node \(self.fromNodeId.debugFriendlyId) to \(self.toNodeId.debugFriendlyId), but the From Node was a layer or group")
        }
    }
}

// See: `createLLMStepChangeValueType`
struct StepActionChangeValueType: StepActionable {
    static let stepType = StepType.changeValueType
    
    var nodeId: NodeId
    var valueType: NodeType
    
    var toStep: Step {
        Step(stepType: Self.stepType,
             nodeId: nodeId,
             valueType: valueType)
    }
    
    func remapNodeIds(nodeIdMap: [UUID: UUID]) -> Self {
        var copy = self
        
        copy.nodeId = nodeIdMap.get(self.nodeId) ?? self.nodeId

        return copy
    }
    
    static func fromStep(_ action: Step) throws -> Self {
        if let nodeId = action.nodeId?.value,
           let valueType = action.valueType {
            return .init(nodeId: nodeId,
                         valueType: valueType)
        }
        
        throw StitchAIManagerError.stepDecoding(Self.stepType, action)
    }
    
    static func createStructuredOutputs() -> StitchAIStepSchema {
        .init(stepType: .changeValueType,
              nodeId: OpenAISchema(type: .string),
              valueType: OpenAISchemaRef(ref: "ValueType")
        )
    }
    
    static let structuredOutputsCodingKeys: Set<Step.CodingKeys> = [.stepType, .nodeId, .valueType]
    
    @MainActor
    func applyAction(document: StitchDocumentViewModel) throws {
        // NodeType etc. for this patch was already validated in `[StepTypeAction].areValidLLMSteps`
        let _ = document.visibleGraph.nodeTypeChanged(nodeId: self.nodeId,
                                                      newNodeType: self.valueType,
                                                      activeIndex: document.activeIndex)
    }
    
    func removeAction(graph: GraphState, document: StitchDocumentViewModel) {
        // Do nothing, assume node will be removed
    }
    
    func validate(createdNodes: inout [NodeId : PatchOrLayer]) throws {
        guard let patch = createdNodes.get(self.nodeId)?.asNodeKind.getPatch else {
            throw StitchAIManagerError
                .actionValidationError("ChangeValueType: no patch for node \(self.nodeId.debugFriendlyId)")
        }
        
        guard patch.availableNodeTypes.contains(self.valueType) else {
            throw StitchAIManagerError
                .actionValidationError("ChangeValueType: invalid node type \(self.valueType.display) for patch \(patch.defaultDisplayTitle()) on node \(self.nodeId.debugFriendlyId)")
        }
    }
}

// See: `createLLMStepSetInput`
struct StepActionSetInput: StepActionable {
    static let stepType = StepType.setInput
    
    var nodeId: NodeId
    let port: NodeIOPortType // integer or key path
    var value: PortValue
    let valueType: NodeType
    
    // encoding
    var toStep: Step {
        Step(stepType: Self.stepType,
             nodeId: nodeId,
             port: port,
             value: value,
             valueType: value.toNodeType)
    }
    
    func remapNodeIds(nodeIdMap: [UUID: UUID]) -> Self {
        var copy = self
        
        copy.nodeId = nodeIdMap.get(self.nodeId) ?? self.nodeId
        
        if let interactionId = copy.value.getInteractionId?.asNodeId {
            let newId = nodeIdMap.get(interactionId) ?? interactionId
            copy.value = .assignedLayer(LayerNodeId(newId))
        }

        return copy
    }
    
    static func fromStep(_ action: Step) throws -> Self {
        if let nodeId = action.nodeId?.value,
           let port = action.port,
           let valueType = action.valueType,
           let value = action.value {
            return .init(nodeId: nodeId,
                         port: port,
                         value: value,
                         valueType: valueType)
        }
        
        throw StitchAIManagerError.stepDecoding(Self.stepType, action)
    }
    
    static func createStructuredOutputs() -> StitchAIStepSchema {
        .init(stepType: .setInput,
              nodeId: OpenAISchema(type: .string),
              port: OpenAIGeneric(types: [OpenAISchema(type: .integer)],
                                  refs: [OpenAISchemaRef(ref: "LayerPorts")]),
              value: OpenAIGeneric(types: [
                OpenAISchema(type: .number),
                OpenAISchema(type: .string),
                OpenAISchema(type: .boolean),
                OpenAISchema(type: .object)
              ]),
              valueType: OpenAISchemaRef(ref: "ValueType")
        )
    }
    
    static let structuredOutputsCodingKeys: Set<Step.CodingKeys> = [.stepType, .nodeId, .port, .value, .valueType]
    
    @MainActor
    func applyAction(document: StitchDocumentViewModel) throws {
        let graph = document.visibleGraph
        let inputCoordinate = InputCoordinate(portType: self.port,
                                              nodeId: self.nodeId)
        guard let input = graph.getInputObserver(coordinate: inputCoordinate) else {
            log("applyAction: could not apply setInput")
            // fatalErrorIfDebug()
            throw StitchAIManagerError.actionValidationError("Could not retrieve input \(inputCoordinate)")
        }
        
        // Use the common input-edit-committed function, so that we remove edges, block or unblock fields, etc.
        graph.inputEditCommitted(input: input,
                                 value: self.value,
                                 activeIndex: document.activeIndex)
    }
    
    func removeAction(graph: GraphState, document: StitchDocumentViewModel) {
        // Do nothing, assume node will be removed
    }
    
    func validate(createdNodes: inout [NodeId : PatchOrLayer]) throws {
        // node must exist
        guard createdNodes.get(self.nodeId).isDefined else {
            log("areLLMStepsValid: Invalid .setInput: \(self)")
            throw StitchAIManagerError
                .actionValidationError("SetInput: Node \(self.nodeId.debugFriendlyId) does not yet exist")
        }
    }
}
