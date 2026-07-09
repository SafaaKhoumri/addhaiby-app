import Flutter
import UIKit
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ✅ Uniquement : demander à iOS de s'enregistrer auprès d'APNs.
    // On NE touche PAS au delegate de notification ni à FirebaseApp.configure()
    // (c'est ce qui faisait figer le démarrage sur Flutter 3.44).
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ On GARDE le système de plugins d'origine (celui qui se lance bien)
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // ✅ LE PONT ESSENTIEL : quand APNs renvoie le token, le donner à Firebase.
  // C'est la seule ligne qui manquait pour que subscribeToTopic marche.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}