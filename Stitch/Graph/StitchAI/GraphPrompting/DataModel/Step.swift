//
//  Step.swift
//  Stitch
//
//  Created by Christian J Clampitt on 1/30/25.
//

import Foundation
import SwiftUI
import SwiftyJSON

/// Represents a single step/action in the visual programming sequence
struct Step: Hashable {
    var stepType: StepType        // Type of step (e.g., "add_node", "connect_nodes")
    var nodeId: StitchAIUUID?        // Identifier for the node
    var nodeName: PatchOrLayer?      // Display name for the node
    var port: NodeIOPortType?  // Port identifier (can be string or number)
    var fromPort: Int?  // Source port for connections
    var fromNodeId: StitchAIUUID?   // Source node for connections
    var toNodeId: StitchAIUUID?     // Target node for connections
    var value: PortValue? // Associated value data
    var valueType: NodeType?     // Type of the node
    var children: NodeIdSet? // Child nodes if this is a group
    
    init(stepType: StepType,
         nodeId: UUID? = nil,
         nodeName: PatchOrLayer? = nil,
         port: NodeIOPortType? = nil,
         fromPort: Int? = nil,
         fromNodeId: UUID? = nil,
         toNodeId: UUID? = nil,
         value: PortValue? = nil,
         valueType: NodeType? = nil,
         children: NodeIdSet? = nil) {
        self.stepType = stepType
        self.nodeId = .init(value: nodeId)
        self.nodeName = nodeName
        self.port = port
        self.fromPort = fromPort
        self.fromNodeId = .init(value: fromNodeId)
        self.toNodeId = .init(value: toNodeId)
        self.value = value
        self.valueType = valueType
        self.children = children
    }
}

extension Step: Identifiable {
    var id: Int { self.hashValue }
}

extension Step: Codable {
    enum CodingKeys: String, CodingKey {
        case stepType = "step_type"
        case nodeId = "node_id"
        case nodeName = "node_name"
        case port
        case fromPort = "from_port"
        case fromNodeId = "from_node_id"
        case toNodeId = "to_node_id"
        case value
        case valueType = "value_type"
        case children = "children"
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // `encodeIfPresent` cleans up JSON by removing properties
        try container.encodeIfPresent(stepType.rawValue, forKey: .stepType)
        try container.encodeIfPresent(nodeId, forKey: .nodeId)
        try container.encodeIfPresent(nodeName?.asNodeKind.asLLMStepNodeName, forKey: .nodeName)
        
        // Handle port encoding differently based on type
        if let portValue = port?.asLLMStepPort() {
            if let intValue = portValue as? Int {
                try container.encodeIfPresent(intValue, forKey: .port)
            } else if let stringValue = portValue as? String {
                try container.encodeIfPresent(stringValue, forKey: .port)
            }
        }
        
        try container.encodeIfPresent(fromPort, forKey: .fromPort)
        try container.encodeIfPresent(fromNodeId, forKey: .fromNodeId)
        try container.encodeIfPresent(toNodeId, forKey: .toNodeId)
        try container.encodeIfPresent(valueType?.asLLMStepNodeType, forKey: .valueType)
        try container.encodeIfPresent(children, forKey: .children)
    
        if let valueCodable = value?.anyCodable {
            try container.encodeIfPresent(valueCodable, forKey: .value)
        }
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let stepTypeString = try container.decode(String.self, forKey: .stepType)
        
        guard let stepType = StepType(rawValue: stepTypeString) else {
            throw StitchAIManagerError.stepActionDecoding(stepTypeString)
        }
        
        self.stepType = stepType
        self.nodeId = try container.decodeIfPresent(StitchAIUUID.self, forKey: .nodeId)
        self.fromNodeId = try container.decodeIfPresent(StitchAIUUID.self, forKey: .fromNodeId)
        self.toNodeId = try container.decodeIfPresent(StitchAIUUID.self, forKey: .toNodeId)
        self.fromPort = try container.decodeIfPresent(Int.self, forKey: .fromPort)
        
        if let nodeNameString = try container.decodeIfPresent(String.self, forKey: .nodeName) {
            self.nodeName = try .fromLLMNodeName(nodeNameString)
        }
        
        if let portString = try? container.decodeIfPresent(String.self, forKey: .port) {
            self.port = try NodeIOPortType(stringValue: portString)
        } else if let portInt = try? container.decodeIfPresent(Int.self, forKey: .port) {
            self.port = NodeIOPortType.portIndex(portInt)
        }
        
        // MARK: node type required for everything below this line
        guard let nodeTypeString = try container.decodeIfPresent(String.self, forKey: .valueType) else {
            return
        }
        let nodeType = try NodeType(llmString: nodeTypeString)
        self.valueType = nodeType
        
        self.children = try container.decodeIfPresent(NodeIdSet.self, forKey: .children)
        
        // Parse value given node type
        do {
            self.value = try PortValue(decoderContainer: container,
                                       type: nodeType)
        } catch {
            if stepType == .setInput {
                log("Stitch AI error decoding value for setInput action: \(error.localizedDescription)")
            }
            
            if let stitchAIError = error as? StitchAIManagerError {
                throw stitchAIError
            } else {
                throw StitchAIManagerError.portValueDecodingError(error.localizedDescription)
            }
        }
    }
}

extension StepActionable {
    var toPortCoordinate: NodeIOCoordinate? {
        let step = self.toStep
        
        guard let nodeId = step.nodeId ?? step.toNodeId,
              let port = step.port else { return nil }
        
        return .init(portType: port, nodeId: nodeId.value)
    }
}
