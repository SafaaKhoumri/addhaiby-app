import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // ✅ Initialiser Firebase côté natif UNIQUEMENT s'il ne l'est pas déjà.
    // (Flutter l'initialise déjà côté Dart via Firebase.initializeApp ;
    //  ce garde-fou évite le double-init qui faisait crasher l'app.)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // ✅ Enregistrer l'app auprès d'APNs pour recevoir un token
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ Quand APNs renvoie le token, le donner à Firebase Messaging.
  // C'est CE pont qui manquait : sans lui, subscribeToTopic échoue sur iOS.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // ✅ En cas d'échec d'enregistrement APNs (utile pour diagnostiquer)
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ Échec enregistrement APNs : \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}