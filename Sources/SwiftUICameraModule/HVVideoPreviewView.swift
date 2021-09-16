//
//  File.swift
//  
//
//  Created by apple on 13.07.21.
//

import SwiftUI
import AVFoundation

public struct HVVideoPreviewView: UIViewRepresentable {
    
    private var videoGravity: AVLayerVideoGravity
    private var cornerRadius: CGFloat?
    
    public class VideoPreviewView: UIView {
        public override class var layerClass: AnyClass {
            AVPlayerLayer.self
        }
        
        var videoPreviewLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }
    }
    
    let model: VideoPreviewModel
    
    public init(model: VideoPreviewModel, videoGravity: AVLayerVideoGravity = .resizeAspectFill, cornerRadius: CGFloat? = nil) {
        self.model = model
        self.videoGravity = videoGravity
        self.cornerRadius = cornerRadius
    }
    
    public func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        if let radius = cornerRadius {
            view.videoPreviewLayer.cornerRadius = radius
            view.clipsToBounds = true
        } else {
            view.videoPreviewLayer.cornerRadius = 0
            view.clipsToBounds = false
        }
        
        view.videoPreviewLayer.player = AVPlayer(url: model.url)
        model.player = view.videoPreviewLayer.player
        view.videoPreviewLayer.player?.actionAtItemEnd = .none
        view.videoPreviewLayer.videoGravity = self.videoGravity
        
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
    
    private var videoGravity: AVLayerVideoGravity
    private var cornerRadius: CGFloat?
    
    public class VideoPreviewView: UIView {
        public override class var layerClass: AnyClass {
             AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    let session: AVCaptureSession
    
    public init(session: AVCaptureSession, videoGravity: AVLayerVideoGravity = .resizeAspectFill, cornerRadius: CGFloat? = nil) {
        self.session = session
        self.videoGravity = videoGravity
        self.cornerRadius = cornerRadius
    }
    
    public func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        if let radius = cornerRadius {
            view.videoPreviewLayer.cornerRadius = radius
            view.clipsToBounds = true
        } else {
            view.clipsToBounds = false
        }
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.connection?.videoOrientation = .portrait
        view.videoPreviewLayer.videoGravity = self.videoGravity
        
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
