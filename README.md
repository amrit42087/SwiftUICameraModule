SwiftUICameraModule
==

SwiftUICameraModule is a SwiftUI camera system designed for easy integration, customized media capture

Overview
==

Before starting, ensure that permission keys have been added to your app's Info.plist.

NSCameraUsageDescription App uses the camera for video capture.
NSMicrophoneUsageDescription App uses the microphone for audio capture. 
NSPhotoLibraryAddUsageDescription App saves videos to your library. 
NSPhotoLibraryUsageDescription App saves videos to your library.

Recording Video Clip
import SwiftUICameraModule

Decleare CameraModel as following.

@StateObject var model = CameraModel(maxTime timer: .fifteen)

call model.configure() to start configuration.

call model.stop() whn remove configuration. ( usable for when showing another screen )

call self.model.handleCapture() for start and stop video recording.

Use CameraPreview(session: model.session) for showing camera output on screen.

Use HVVideoPreviewView(model: model.finalModel!) for showing playback screen.

Call model.saveLastVideo() to save last recorded video.

Call model.removeLastVideo() to delete last recorded video.

Call model.flipCamera() to change camera.

Call model.toggleFlash() to on/off flash.

# Swift PM
let package = Package(
    dependencies: [
        .Package(url: "https://github.com/amrit42087/SwiftUICameraModule.git", majorVersion: 0)
    ]
)



