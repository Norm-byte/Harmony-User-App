import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let dormantAlarmChannelName = "com.harmonybyintent.harmony_user_app/dormant_alarm"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: dormantAlarmChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "is_device_locked":
          // When protected data is unavailable, the device is currently locked.
          result(!UIApplication.shared.isProtectedDataAvailable)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
