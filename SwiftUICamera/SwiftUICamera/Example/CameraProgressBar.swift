//
//  CameraProgressBar.swift
//  SwiftUICamera
//
//  Created by apple on 13.07.21.
//

import SwiftUI

struct CameraProgressBar: View {
    
    @Binding var progress: Float
    
    init(progress: Binding<Float>) {
        self._progress = progress
    }
    
    var body: some View {
        
        ZStack {
            
            Circle()
                .foregroundColor(.white)
                .frame(width: 80, height: 80, alignment: .center)
            
            Circle()
                .stroke(lineWidth: 2.5)
                .opacity(0.3)
                .foregroundColor(Color.red)
                .frame(width: 65, height: 65, alignment: .center)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(min(self.progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundColor(Color.red)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear)
                .frame(width: 65, height: 65, alignment: .center)
        }
            
    }
}
