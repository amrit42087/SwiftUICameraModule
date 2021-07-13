//
//  File.swift
//  
//
//  Created by apple on 13.07.21.
//

import SwiftUI
import AVFoundation

public struct HVVideoPreviewView: UIViewRepresentable {
    
    public class VideoPreviewView: UIView {
        public override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }
        
        var videoPreviewLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }
    }
    
    let model: VideoPreviewModel
    
    public init(model: VideoPreviewModel) {
        self.model = model
    }
    
    public func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.cornerRadius = 0
        view.videoPreviewLayer.player = AVPlayer(url: model.url)
        model.player = view.videoPreviewLayer.player
        view.videoPreviewLayer.player?.actionAtItemEnd = .none
        DispatchQueue.main.async {
            view.videoPreviewLayer.player?.play()
        }
        return view
    }
    
    public func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        
        DispatchQueue.main.async {
            uiView.videoPreviewLayer.player?.play()
        }
    }
}

public struct CameraPreview: UIViewRepresentable {
    public class VideoPreviewView: UIView {
        public override class var layerClass: AnyClass {
             AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    let session: AVCaptureSession
    
    public init(session: AVCaptureSession) {
        self.session = session
    }
    
    public func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.cornerRadius = 0
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.connection?.videoOrientation = .portrait

        return view
    }
    
    public func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        
    }
}

struct CameraPreview_Previews: PreviewProvider {
    static var previews: some View {
        CameraPreview(session: AVCaptureSession())
            .frame(height: 300)
    }
}
