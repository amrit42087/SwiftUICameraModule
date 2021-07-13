//
//  File.swift
//  
//
//  Created by apple on 13.07.21.
//

import Foundation

class HVTimer<T> {

    let shortInterval: TimeInterval
    var data: T?
    let callback: (T?) -> Void
    
    var repeats: Bool = false
    var shortTimer: Foundation.Timer?
    
    init(short: TimeInterval = 0.75,
         data: T? = nil,
         repeats: Bool = false,
         callback: @escaping (T?) -> Void)
    {
        self.shortInterval = short
        self.data = data
        self.repeats = repeats
        self.callback = callback
    }
    
    func activate(_ data: T? = nil) {
        self.data = data
        shortTimer?.invalidate()
        shortTimer = Foundation.Timer.scheduledTimer(withTimeInterval: shortInterval, repeats: self.repeats)
            { [weak self] _ in self?.fire() }
    }
    
    func cancel() {
        shortTimer?.invalidate()
        shortTimer = nil
    }
    
    private func fire() {
        if !self.repeats {
            cancel()
        }
        callback(data)
    }
}
