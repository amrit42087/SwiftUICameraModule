//
//  ContentView.swift
//  SwiftUICamera
//
//  Created by apple on 16.07.21.
//

import SwiftUI
import SwiftUICameraModule

struct ContentView: View {
    
    @StateObject var model = CameraModel()
    @State var isChooseTimerActive: Bool = false

    var downloadButton: some View {
        Button(action: {
//            model.saveLastVideo()
            
            model.getLastVideoLocalUrl()
            
        }, label: {
            Circle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(width: 45, height: 45, alignment: .center)
                .overlay(
                    Image(systemName: "square.and.arrow.down")
                        .foregroundColor(.white))
        })
    }

    var crossPreviewButton: some View {
        Button(action: {
            model.removeLastVideo()
        }, label: {
            Circle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(width: 45, height: 45, alignment: .center)
                .overlay(
                    Image(systemName: "multiply")
                        .foregroundColor(.white))
        })
    }

    var timerButton: some View {
        Group {

            if !self.model.isRecording {

                RoundedRectangle(cornerRadius: 20)
                    .foregroundColor(Color.gray.opacity(0.2))
                    .overlay(
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.yellow)
                            Group {
                                if (self.model.currentTime == Timer.fifteen || isChooseTimerActive) {
                                    Text("\(Timer.fifteen.rawValue)s")
                                        .foregroundColor(self.model.currentTime == Timer.fifteen ? .yellow : .white)
                                        .onTapGesture {

                                            self.isChooseTimerActive.toggle()
                                            guard self.model.currentTime == .thirty else { return }
                                            self.model.toggleTimer()
                                        }
                                }

                                if (self.model.currentTime == Timer.thirty || isChooseTimerActive) {
                                    Text("\(Timer.thirty.rawValue)s")
                                        .foregroundColor(self.model.currentTime == Timer.thirty ? .yellow : .white)
                                        .onTapGesture {
                                            self.isChooseTimerActive.toggle()
                                            guard self.model.currentTime == .fifteen else { return }
                                            self.model.toggleTimer()
                                        }
                                }
                            }
                        }
                    )
                    .frame(width: self.isChooseTimerActive ? 120 : 80, height: 40, alignment: .center)
                    .onTapGesture {
                        self.isChooseTimerActive.toggle()
                    }
                    .padding(20)
            }
        }.animation(.easeInOut)
    }

    var flipCameraButton: some View {
        Button(action: {
            model.flipCamera()
        }, label: {
            Circle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(width: 45, height: 45, alignment: .center)
                .overlay(
                    Image(systemName: "camera.rotate.fill")
                        .foregroundColor(.white))
        })
    }

    var flashCameraButton: some View {

        Button(action: {
            model.toggleFlash()
        }, label: {

            Circle()
                .foregroundColor(Color.gray.opacity(0.2))
                .frame(width: 45, height: 45, alignment: .center)
                .overlay(
                    Image(systemName: model.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 20, weight: .medium, design: .default))
            )
        })
        .accentColor(model.isFlashOn ? .yellow : .white)
    }

    var body: some View {
        GeometryReader { reader in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                if model.finalModel != nil {
                    HVVideoPreviewView(model: model.finalModel!)
                        .overlay(
                            VStack {

                                HStack {
                                    crossPreviewButton

                                    Spacer()

                                    downloadButton
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                Spacer()
                            })
                } else {

                    CameraPreview(session: model.session)
                        .onAppear {
                            model.configure()
                        }
                        .onDisappear(perform: {
                            model.stop()
                        })
                        .alert(isPresented: $model.showAlertError, content: {
                            Alert(title: Text(model.alertError.title), message: Text(model.alertError.message), dismissButton: .default(Text(model.alertError.primaryButtonTitle), action: {
                                model.alertError.primaryAction?()
                            }))
                        })
                        .animation(.easeInOut)
                        .overlay(
                            VStack {

                                HStack {
                                    Spacer()
                                    timerButton
                                }

                                Spacer()

                                HStack {

                                    self.flashCameraButton

                                    Spacer()

                                    CameraProgressBar(progress: self.$model.progress)
                                        .frame(width: 80, height: 80, alignment: .center)
                                        .onTapGesture {
                                            self.model.handleCapture()
                                        }

                                    Spacer()

                                    flipCameraButton

                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                        )
                }
            }.statusBar(hidden: true)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
