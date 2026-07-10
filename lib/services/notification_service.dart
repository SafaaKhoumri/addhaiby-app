import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

const String _projectId = 'addhaiby-de63d';
const String _topic     = 'price_updates';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // ── Initialisation au démarrage de l'app ──────────────────
  static Future<void> initialize() async {
    if (kIsWeb) return; // ← Skip tout sur le web

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Afficher les notifs même quand l'app est au premier plan (iOS)
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // IMPORTANT iOS : attendre que le token APNs soit prêt AVANT de s'abonner.
    String? apnsToken = await _messaging.getAPNSToken();
    int retries = 0;
    while (apnsToken == null && retries < 8) {
      await Future.delayed(const Duration(seconds: 1));
      apnsToken = await _messaging.getAPNSToken();
      retries++;
    }
    debugPrint('🍏 APNs Token : $apnsToken');

    try {
      await _messaging.subscribeToTopic(_topic);
      debugPrint('✅ Abonné au topic $_topic');
    } catch (e) {
      debugPrint('❌ Erreur subscribeToTopic : $e');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 Notification foreground : ${message.notification?.title}');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📲 App ouverte via notification : ${message.data}');
    });

    final token = await _messaging.getToken();
    debugPrint('📱 FCM Token : $token');
  }

  // ── Générer un token OAuth2 via le compte de service ──────
  static Future<String> _getAccessToken() async {
    final jsonStr = await rootBundle.loadString('assets/service_account.json');
    final jsonMap  = jsonDecode(jsonStr) as Map<String, dynamic>;

    final credentials = ServiceAccountCredentials.fromJson(jsonMap);
    final scopes      = ['https://www.googleapis.com/auth/firebase.messaging'];

    final client = await clientViaServiceAccount(credentials, scopes);
    final token  = client.credentials.accessToken.data;
    client.close();

    return token;
  }

  // ── Envoyer une notification à tous les abonnés ───────────
  // Retourne null si succès, sinon un message d'erreur (pour l'afficher).
  static Future<String?> sendPriceNotification({
    required String metal,
    required double buyPrice,
    required double sellPrice,
  }) async {
    final metalName = metal == 'gold' ? 'Or 🥇' : 'Argent 🥈';

    try {
      final accessToken = await _getAccessToken();

      final body = {
        'message': {
          'topic': _topic,
          'notification': {
            'title': '💰 Nouveau prix $metalName — ADDHAIBY',
            'body':  'Achat: ${buyPrice.toStringAsFixed(2)} MAD/g  •  '
                     'Vente: ${sellPrice.toStringAsFixed(2)} MAD/g',
          },
          'data': {
            'metal': metal,
            'buy':   buyPrice.toString(),
            'sell':  sellPrice.toString(),
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'price_channel',
              'color':      '#D4A017',
              'sound':      'default',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'sound': 'default',
                'badge': 1,
              },
            },
          },
        },
      };

      final response = await http.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
        ),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Notification envoyée avec succès');
        return null; // succès
      } else {
        final msg = 'HTTP ${response.statusCode} — ${response.body}';
        debugPrint('❌ Erreur FCM V1 : $msg');
        return msg;
      }
    } catch (e) {
      debugPrint('❌ Exception FCM : $e');
      return 'Exception: $e';
    }
  }
}

// ── Handler background (fonction top-level obligatoire) ───────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 Notification background : ${message.notification?.title}');
}