import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: show session notifications in the foreground.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // A restored backup would bring back a deleted account's database. The
    // server holds the synced copy, so Documents needs no iCloud backup.
    if var documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? documents.setResourceValues(values)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ChapterFocus") {
      FocusChannel.register(messenger: registrar.messenger())
    }
  }
}

/// `chapter/focus` on iOS (docs/04 §5). iOS has no public API to turn Focus
/// or Do Not Disturb on or off, so `access` reports "unsupported" and the
/// DND methods are not implemented. Only keeping the screen awake works.
enum FocusChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "chapter/focus", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "access":
        result("unsupported")
      case "keepScreenOn":
        let args = call.arguments as? [String: Any]
        let on = args?["on"] as? Bool ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = on
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
