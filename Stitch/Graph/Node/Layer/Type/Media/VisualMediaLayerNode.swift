//
//  ImageNode.swift
//  Stitch
//
//  Created by Christian J Clampitt on 4/22/21.
//

import Foundation
import SwiftUI
import StitchSchemaKit

struct VisualMediaLayerView: View {    
    @Bindable var document: StitchDocumentViewModel
    @Bindable var graph: GraphState
    @Bindable var viewModel: LayerViewModel
    
    let isPinnedViewRendering: Bool
    let parentSize: CGSize
    let parentDisablesPosition: Bool
    let parentIsScrollableGrid: Bool
    
    var layerInputType: LayerInputPort {
        switch viewModel.layer {
        case .image:
            return .image
        case .video:
            return .video
        default:
            fatalErrorIfDebug()
            return .image
        }
    }

    var body: some View {
        Group {
            switch self.viewModel.mediaObject {
            case .image(let image):
                ImageLayerView(document: document,
                               graph: graph,
                               viewModel: viewModel,
                               image: image, 
                               isPinnedViewRendering: isPinnedViewRendering,
                               parentSize: parentSize,
                               parentDisablesPosition: parentDisablesPosition,
                               parentIsScrollableGrid: parentIsScrollableGrid)
            case .video(let video):
                VideoLayerView(document: document,
                               graph: graph,
                               viewModel: viewModel,
                               video: video,
                               isPinnedViewRendering: isPinnedViewRendering,
                               parentSize: parentSize,
                               parentDisablesPosition: parentDisablesPosition,
                               parentIsScrollableGrid: parentIsScrollableGrid)
            default:
                // MARK: can't be EmptyView for the onChange below doesn't get called!
                Color.clear
            }
        }
    }
}

struct ImageLayerView: View {
    @Bindable var document: StitchDocumentViewModel
    @Bindable var graph: GraphState
    @Bindable var viewModel: LayerViewModel
    let image: UIImage
    
    let isPinnedViewRendering: Bool
    let parentSize: CGSize
    let parentDisablesPosition: Bool
    let parentIsScrollableGrid: Bool

    var body: some View {
        PreviewImageLayer(
            document: document,
            graph: graph,
            layerViewModel: viewModel,
            isPinnedViewRendering: isPinnedViewRendering,
            interactiveLayer: viewModel.interactiveLayer,
            image: image,
            position: viewModel.position.getPosition ?? .zero,
            rotationX: viewModel.rotationX.asCGFloat,
            rotationY: viewModel.rotationY.asCGFloat,
            rotationZ: viewModel.rotationZ.asCGFloat,
            size: viewModel.size.getSize ?? DEFAULT_PREVIEW_IMAGE_SIZE,
            opacity: viewModel.opacity.getNumber ?? defaultOpacityNumber,
            fitStyle: viewModel.fitStyle.getFitStyle ?? .defaultMediaFitStyle,
            scale: viewModel.scale.getNumber ?? defaultScaleNumber,
            anchoring: viewModel.anchoring.getAnchoring ?? .defaultAnchoring,
            blurRadius: viewModel.blurRadius.getNumber ?? .zero,
            blendMode: viewModel.blendMode.getBlendMode ?? .defaultBlendMode,
            brightness: viewModel.brightness.getNumber ?? .defaultBrightnessForLayerEffect,
            colorInvert: viewModel.colorInvert.getBool ?? .defaultColorInvertForLayerEffect,
            contrast: viewModel.contrast.getNumber ?? .defaultContrastForLayerEffect,
            hueRotation: viewModel.hueRotation.getNumber ?? .defaultHueRotationForLayerEffect,
            saturation: viewModel.saturation.getNumber ?? .defaultSaturationForLayerEffect,
            pivot: viewModel.pivot.getAnchoring ?? .defaultPivot,
            shadowColor: viewModel.shadowColor.getColor ?? .defaultShadowColor,
            shadowOpacity: viewModel.shadowOpacity.getNumber ?? .defaultShadowOpacity,
            shadowRadius: viewModel.shadowRadius.getNumber ?? .defaultShadowOpacity,
            shadowOffset: viewModel.shadowOffset.getPosition ?? .defaultShadowOffset,
            parentSize: parentSize,
            parentDisablesPosition: parentDisablesPosition,
            parentIsScrollableGrid: parentIsScrollableGrid,
            isClipped: viewModel.isClipped.getBool ?? false)
    }
}

struct VideoLayerView: View {
    @Bindable var document: StitchDocumentViewModel
    @Bindable var graph: GraphState
    @Bindable var viewModel: LayerViewModel
    @State var video: StitchVideoImportPlayer
    
    let isPinnedViewRendering: Bool
    let parentSize: CGSize
    let parentDisablesPosition: Bool
    let parentIsScrollableGrid: Bool

    var body: some View {
        PreviewVideoLayer(
            document: document,
            graph: graph,
            layerViewModel: viewModel,
            isPinnedViewRendering: isPinnedViewRendering,
            interactiveLayer: viewModel.interactiveLayer,
            videoPlayer: video,
            position: viewModel.position.getPosition ?? .zero,
            rotationX: viewModel.rotationX.asCGFloat,
            rotationY: viewModel.rotationY.asCGFloat,
            rotationZ: viewModel.rotationZ.asCGFloat,
            size: viewModel.size.getSize ?? DEFAULT_PREVIEW_IMAGE_SIZE,
            opacity: viewModel.opacity.getNumber ?? 0.8,
            videoFitStyle: viewModel.fitStyle.getFitStyle ?? .defaultMediaFitStyle,
            scale: viewModel.scale.getNumber ?? defaultScaleNumber,
            anchoring: viewModel.anchoring.getAnchoring ?? .defaultAnchoring,
            blurRadius: viewModel.blurRadius.getNumber ?? .zero,
            blendMode: viewModel.blendMode.getBlendMode ?? .defaultBlendMode,
            brightness: viewModel.brightness.getNumber ?? .defaultBrightnessForLayerEffect,
            colorInvert: viewModel.colorInvert.getBool ?? .defaultColorInvertForLayerEffect,
            contrast: viewModel.contrast.getNumber ?? .defaultContrastForLayerEffect,
            hueRotation: viewModel.hueRotation.getNumber ?? .defaultHueRotationForLayerEffect,
            saturation: viewModel.saturation.getNumber ?? .defaultSaturationForLayerEffect,
            pivot: viewModel.pivot.getAnchoring ?? .defaultPivot,
            shadowColor: viewModel.shadowColor.getColor ?? .defaultShadowColor,
            shadowOpacity: viewModel.shadowOpacity.getNumber ?? .defaultShadowOpacity,
            shadowRadius: viewModel.shadowRadius.getNumber ?? .defaultShadowOpacity,
            shadowOffset: viewModel.shadowOffset.getPosition ?? .defaultShadowOffset,
            parentSize: parentSize,
            parentDisablesPosition: parentDisablesPosition,
            parentIsScrollableGrid: parentIsScrollableGrid,
            isClipped: viewModel.isClipped.getBool ?? false,
            volume: viewModel.volume.getNumber ?? StitchVideoImportPlayer.DEFAULT_VIDEO_PLAYER_VOLUME
        )
    }
}
