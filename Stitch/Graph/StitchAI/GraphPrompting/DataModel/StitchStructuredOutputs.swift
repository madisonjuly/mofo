//
//  StructuredOutputs.swift
//  Stitch
//
//  Created by Elliot Boschwitz on 2/16/25.
//

import SwiftUI
import StitchSchemaKit
import SwiftyJSON

extension StitchAIManager {
    static let structuredOutputs = StitchAIStructuredOutputsPayload()
    
    static func printStructuredOutputsSchema() {
        do {
            let schema = try structuredOutputs.printSchema()
            print(schema)
        } catch {
            print("Failed to print schema:", error)
        }
    }
}

struct StitchAIStructuredOutputsPayload: OpenAISchemaDefinable, Encodable {
    var defs = StitchAIStructuredOutputsDefinitions()
    var schema = StitchAIStructuredOutputsSchema()
    
    func printSchema() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "Failed to encode schema"
    }
}

struct StitchAIStructuredOutputsSchema: OpenAISchemaCustomizable {
    static let title = "VisualProgrammingActions"
    
    var properties = StitchAIStepsSchema()
    
    var schema = OpenAISchema(type: .object,
                              required: ["steps"],
                              additionalProperties: false,
                              title: Self.title)
}

struct StitchAIStructuredOutputsDefinitions: Encodable {
    // Step actions
    let AddNodeAction = StepStructuredOutputs(StepActionAddNode.self)
    let ConnectNodesAction = StepStructuredOutputs(StepActionConnectionAdded.self)
    let ChangeValueTypeAction = StepStructuredOutputs(StepActionChangeValueType.self)
    let SetInputAction = StepStructuredOutputs(StepActionSetInput.self)
    let SidebarGroupCreatedAction = StepStructuredOutputs(StepActionLayerGroupCreated.self)
    
    // Types
    let NodeID = OpenAISchema(type: .string,
                              description: "The unique identifier for the node (UUID)")
    
    let NodeIdSet = OpenAISchema(type: .array,
                                description: "Array of node UUIDs",
                                items: OpenAIGeneric(types: [OpenAISchema(type: .string)]))
    
    let NodeName = OpenAISchemaEnum(values: NodeKind.getAiNodeDescriptions().map(\.nodeKind))
    
    let ValueType = OpenAISchemaEnum(values:
                                        NodeType.allCases
        .filter { $0 != .none }
        .map { $0.asLLMStepNodeType }
    )
    
    let LayerPorts = OpenAISchemaEnum(values: LayerInputPort.allCases
        .map { $0.asLLMStepPort }
    )
}

struct StitchAIStepsSchema: Encodable {
    let steps = OpenAISchema(type: .array,
                             description: "The actions taken to create a graph",
                             items: OpenAIGeneric(refs: [
                                .init(ref: "AddNodeAction"),
                                .init(ref: "ConnectNodesAction"),
                                .init(ref: "ChangeValueTypeAction"),
                                .init(ref: "SetInputAction"),
                                .init(ref: "SidebarGroupCreatedAction")
                             ])
    )
}

struct StepStructuredOutputs: OpenAISchemaCustomizable {
    var properties: StitchAIStepSchema
    var schema: OpenAISchema
    
    init<T>(_ stepActionType: T.Type) where T: StepActionable {
        let requiredProps = T.structuredOutputsCodingKeys.map { $0.rawValue }
        
        self.properties = T.createStructuredOutputs()
        self.schema = .init(type: .object,
                            required: requiredProps,
                            additionalProperties: false)
    }
    
    init(properties: StitchAIStepSchema,
         schema: OpenAISchema) {
        self.properties = properties
        self.schema = schema
    }
}

struct StitchAIStepSchema: Encodable {
    var stepType: StepType
    var nodeId: OpenAISchema? = nil
    var nodeName: OpenAISchemaRef? = nil
    var port: OpenAIGeneric? = nil
    var fromPort: OpenAISchema? = nil
    var fromNodeId: OpenAISchema? = nil
    var toNodeId: OpenAISchema? = nil
    var value: OpenAIGeneric? = nil
    var valueType: OpenAISchemaRef? = nil
    var children: OpenAISchemaRef? = nil
    
    func encode(to encoder: Encoder) throws {
        // Reuses coding keys from Step struct
        var container = encoder.container(keyedBy: Step.CodingKeys.self)
        
        let stepTypeSchema = OpenAISchema(type: .string,
                                          const: self.stepType.rawValue)
        
        try container.encode(stepTypeSchema, forKey: .stepType)
        try container.encodeIfPresent(nodeId, forKey: .nodeId)
        try container.encodeIfPresent(nodeName, forKey: .nodeName)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encodeIfPresent(fromPort, forKey: .fromPort)
        try container.encodeIfPresent(fromNodeId, forKey: .fromNodeId)
        try container.encodeIfPresent(toNodeId, forKey: .toNodeId)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(valueType, forKey: .valueType)
        try container.encodeIfPresent(children, forKey: .children)
    }
}
