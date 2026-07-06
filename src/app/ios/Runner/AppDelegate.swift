import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let dormantAlarmChannelName = "com.harmonybyintent.harmony_user_app/dormant_alarm"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      // Ensure app media playback is audible during event overlays, even when
      // the iOS silent switch is enabled.
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [])
      try audioSession.setActive(true)
    } catch {
      NSLog("HARMONY_IOS_AUDIO_SESSION_ERROR: \(error.localizedDescription)")
    }

    GeneratedPluginRegistrant.register(with: self)

    // Scene-safe channel registration: do not rely on window/rootViewController
    // during didFinishLaunching on modern iOS lifecycle.
    if let registrar = self.registrar(forPlugin: "HarmonyDormantAlarmBridge") {
      let channel = FlutterMethodChannel(
        name: dormantAlarmChannelName,
        binaryMessenger: registrar.messenger()
      )

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "is_device_locked":
          // When protected data is unavailable, the device is currently locked.
          result(!UIApplication.shared.isProtectedDataAvailable)
        case "activate_playback_audio_session":
          do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            result(true)
          } catch {
            NSLog("HARMONY_IOS_AUDIO_SESSION_ERROR: \(error.localizedDescription)")
            result(FlutterError(code: "audio_session_error", message: error.localizedDescription, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
