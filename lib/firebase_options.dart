import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAbJt1CwQfTT2UpDdiLViOBgioQlwIB-Bw',
    authDomain: 'addhaiby-de63d.firebaseapp.com',
    projectId: 'addhaiby-de63d',
    storageBucket: 'addhaiby-de63d.firebasestorage.app',
    messagingSenderId: '958041773009',
    appId: '1:958041773009:web:e348ba5e7fca6db6e486f0',
  );

static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'AIzaSyCXidNGJECXDwz6qRns9gDSHeV_4kjkLeQ',
  appId: '1:958041773009:android:729824a0c010e340e486f0', 
  messagingSenderId: '958041773009',
  projectId: 'addhaiby-de63d',
  storageBucket: 'addhaiby-de63d.firebasestorage.app',
);

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDRKtz51_ng4l-g0d8_e8tkEZLOhOxZKd8',
    appId: '1:958041773009:ios:40bb582d2726c777e486f0',
    messagingSenderId: '958041773009',
    projectId: 'addhaiby-de63d',
    storageBucket: 'addhaiby-de63d.firebasestorage.app',
    iosBundleId: 'com.example.addhaiby',
  );

}