import Flutter
import FirebaseMessaging
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let dormantAlarmChannelName = "com.harmonybyintent.harmony_user_app/dormant_alarm"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

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

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    if shouldSuppressForegroundPresentation(for: userInfo) {
      completionHandler([])
      return
    }

    completionHandler([.banner, .sound, .badge])
  }

  private func shouldSuppressForegroundPresentation(for userInfo: [AnyHashable: Any]) -> Bool {
    if let payload = userInfo["payload"] as? String,
       payload.hasPrefix("harmony_dormant:") {
      return true
    }

    if userInfo["event_id"] != nil {
      return true
    }

    if let type = userInfo["type"] as? String {
      let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if normalizedType == "dormant_playback" ||
        normalizedType == "event_reminder" ||
        normalizedType.hasPrefix("event_") {
        return true
      }
    }

    for value in userInfo.values {
      if let stringValue = value as? String,
         stringValue.contains("harmony_dormant:") {
        return true
      }
    }

    return false
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNS_REGISTER_ERROR: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
