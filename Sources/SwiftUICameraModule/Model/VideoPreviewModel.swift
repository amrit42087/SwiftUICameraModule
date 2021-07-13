//
//  File.swift
//  
//
//  Created by apple on 13.07.21.
//

import UIKit
import AVFoundation

public class VideoPreviewModel: NSObject, ObservableObject {
    
    let url: URL
    var player: AVPlayer? = nil
    
    public init(url: URL) {
        self.url = url
        super.init()
        addApplicationObservers()
    }
    
    deinit {
        removeApplicationObservers()
    }
    
    internal func addApplicationObservers() {
        //AVPlayerItemDidPlayToEndTime
        NotificationCenter.default.addObserver(self, selector: #selector(VideoPreviewModel.playerItemDidReachEnd), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(VideoPreviewModel.handleApplicationWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(VideoPreviewModel.handleApplicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    internal func removeApplicationObservers() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc func playerItemDidReachEnd(notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem {
            DispatchQueue.main.async {
                playerItem.seek(to: CMTime.zero, completionHandler: nil)
            }
        }
    }
    
    @objc internal func handleApplicationWillEnterForeground(_ notification: Notification) {
        DispatchQueue.main.async { self.player?.play() }
    }

    @objc internal func handleApplicationDidEnterBackground(_ notification: Notification) {
        DispatchQueue.main.async { self.player?.pause() }
    }
    
}
