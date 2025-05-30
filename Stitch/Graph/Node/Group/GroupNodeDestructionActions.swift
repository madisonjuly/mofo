//
//  GroupNodeDestructionActions.swift
//  Stitch
//
//  Created by Christian J Clampitt on 7/22/22.
//

import Foundation
import SwiftUI
import StitchSchemaKit

// DELETING OR UNGROUPING A NODE UI GROUPING

// Group node deletion needs to remove the group node state plus all nodes inside the group
struct GroupNodeDeletedAction: StitchDocumentEvent {
    let groupNodeId: GroupNodeId

    func handle(state: StitchDocumentViewModel) {
        log("GroupNodeDeletedAction called: groupNodeId: \(groupNodeId)")
        let graph = state.visibleGraph
        graph.deleteCanvasItem(.node(groupNodeId.asNodeId),
                               document: state)
        
        // TODO: APRIL 11: should not be necessary anymore? since causes a persistence change
         graph.updateGraphData(state)
        
        state.encodeProjectInBackground()
    }
}

// We uncreated a node-ui-group node via the graph (as opposed to the sidebar).
// We remove the node-ui-grouping but keep
struct GroupNodeUncreated: StitchDocumentEvent {

    let groupId: GroupNodeId // the group that was deleted

    func handle(state: StitchDocumentViewModel) {
        log("GroupNodeUncreated called for groupId: \(groupId)")
        state.visibleGraph
            .handleGroupNodeUncreated(groupId.asNodeId,
                                      groupNodeFocused: state.groupNodeFocused?.groupNodeId,
                                      document: state)
        state.encodeProjectInBackground()
    }
}

struct SelectedGroupNodesUncreated: StitchDocumentEvent {
    
    func handle(state: StitchDocumentViewModel) {
        let graph = state.visibleGraph
        
        graph.getSelectedCanvasItems(groupNodeFocused: state.groupNodeFocused?.groupNodeId)
            .forEach { (canvasItem: CanvasItemViewModel) in
            if (canvasItem.nodeDelegate?.isGroupNode ?? false),
               case let .node(nodeId) = canvasItem.id {
                graph.handleGroupNodeUncreated(nodeId,
                                               groupNodeFocused: state.groupNodeFocused?.groupNodeId,
                                               document: state)
            }
        }
        
        state.encodeProjectInBackground()
    }
}

extension GraphState {
    // Removes a group node from state, but not its children.
    // Inserts new edges (connections) where necessary,
    // to compensate for the destruction of the GroupNode's input and output splitter nodes.
    @MainActor
    func handleGroupNodeUncreated(_ uncreatedGroupNodeId: NodeId,
                                  groupNodeFocused: NodeId?,
                                  document: StitchDocumentViewModel) {
        let newGroupId = groupNodeFocused
        
        // Deselect
        self.resetSelectedCanvasItems()

        // Update nodes to map to new group id
        self.getCanvasItems()
            .filter { $0.parentGroupNodeId == uncreatedGroupNodeId }
            .forEach { canvasItem in
                // If this canvas item was a group-splitter-node,
                // completely delete it.
                if let nodeId = canvasItem.nodeDelegate?.id,
                   let node = self.getNode(nodeId),
                   node.splitterType?.isGroupSplitter ?? false {
                    // Recreate edges if splitter contains upstream and downstream edges
                    self.insertEdgesAfterGroupUncreated(for: node)
                    
                    // Delete splitter input/output nodes here
                    // Can ignore undo effects since that's only for media nodes
                    let _ = self.deleteNode(id: node.id, document: document)
                    return
                }
                
                // Else, just assign the ungrouped canvas item to the current traversal level.
                else {
                    canvasItem.parentGroupNodeId = newGroupId
                }
                
                self.selectCanvasItem(canvasItem.id)
        }

        // Delete group node
        // NOTE: CANNOT USE `GraphState.deleteNode` because that deletes the group node's children as well
        self.visibleNodesViewModel.nodes.removeValue(forKey: uncreatedGroupNodeId)
        
        // TODO: APRIL 11: should not be necessary anymore? since causes a persistence change
        guard let document = self.documentDelegate else {
            fatalErrorIfDebug()
            return
        }
        self.updateGraphData(document)
        
        // Process and encode changes
        self.encodeProjectInBackground()
    }
}

extension GraphState {
    // Recreate edges if splitter contains upstream and downstream edges
    @MainActor
    func insertEdgesAfterGroupUncreated(for splitterNode: NodeViewModel) {
        guard splitterNode.splitterType?.isGroupSplitter ?? false else {
            fatalErrorIfDebug()
            return
        }

        let splitterOutputCoordinate = NodeIOCoordinate(portId: .zero,
                                                        nodeId: splitterNode.id)

        guard let upstreamOutput = splitterNode.getInputRowObserver(for: .portIndex(0))?.upstreamOutputCoordinate,
              let downstreamInputsFromSplitter = self.connections.get(splitterOutputCoordinate) else {
            // Nothing to do if no upstream output or downstream inputs
            return
        }

        downstreamInputsFromSplitter.forEach { inputId in
            guard let inputObserver = self.getInputObserver(coordinate: inputId) else {
                return
            }

            // Sets new edges for each connected input
            inputObserver.upstreamOutputCoordinate = upstreamOutput
        }
    }
}
