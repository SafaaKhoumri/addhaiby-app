import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Connexion admin avec email + mot de passe Firebase Auth
  static Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null; // succès, pas d'erreur
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Email ou mot de passe incorrect.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez plus tard.';
        case 'user-disabled':
          return 'Ce compte a été désactivé.';
        default:
          return 'Erreur de connexion : ${e.message}';
      }
    }
  }

  /// Déconnexion
  static Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Utilisateur actuellement connecté (null si non connecté)
  static User? get currentUser => _auth.currentUser;

  /// Stream pour écouter les changements d'état de connexion
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Vrai si un admin est connecté
  static bool get isLoggedIn => _auth.currentUser != null;
}