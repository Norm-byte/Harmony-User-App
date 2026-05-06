import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Temporary diagnostic bypass: iOS launch crash is occurring inside
    // InAppWebViewFlutterPlugin registration before Flutter renders first frame.
    // Skipping global plugin registration here lets us verify base app boot.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
