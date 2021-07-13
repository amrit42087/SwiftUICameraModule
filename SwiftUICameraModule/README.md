# SwiftUICameraModule

SwiftUICameraModule is a SwiftUI camera system designed for easy integration, customized media capture

# Overview

Before starting, ensure that permission keys have been added to your app's Info.plist.

<key>NSCameraUsageDescription</key>
<string>App uses the camera for video capture.</string>
<key>NSMicrophoneUsageDescription</key>
<string>App uses the microphone for audio capture.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>App saves videos to your library.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>App saves videos to your library.</string>

# Recording Video Clip

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

