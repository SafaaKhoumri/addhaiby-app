import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/prefs_service.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 Notification background : ${message.notification?.title}');
}

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const AddhaibyApp());
}

class AddhaibyApp extends StatelessWidget {
  const AddhaibyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: 'ADDHAIBY',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFFD4A017)),
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          cardColor: Colors.white,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD4A017),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF121212),
          cardColor: const Color(0xFF1E1E1E),
        ),
        themeMode: mode,
        home: const HomeScreen(),
      ),
    );
  }
}

class PriceEntry {
  final String date;
  final double buyPrice;
  final double sellPrice;
  final DateTime? createdAt;

  PriceEntry({
    required this.date,
    required this.buyPrice,
    required this.sellPrice,
    this.createdAt,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  bool _isBuy = true;
  int _selectedNav = 0;
  bool _isAdminLoggedIn = false;
  bool _isDarkMode = false;
  String _selectedLanguage = 'Français';
  List<PriceEntry> _goldHistoryAll = [];
  List<PriceEntry> _silverHistoryAll = [];

  // ✅ karat sélectionné (18 ou 24), défaut = 18
  int _selectedKarat = 18;

  Map<String, Map<String, double>> _prices = {
    'gold': {'buy': 0, 'sell': 0},
    'silver': {'buy': 0, 'sell': 0},
  };

  // ✅ Anciens prix pour calculer la tendance (flèche verte/rouge)
  Map<String, Map<String, double>> _prevPrices = {
    'gold': {'buy': -1, 'sell': -1},
    'silver': {'buy': -1, 'sell': -1},
  };

  List<PriceEntry> _goldHistory = [];
  List<PriceEntry> _silverHistory = [];
  bool _loading = true;
  DateTime? _filterDate;
  String? _adImageUrl;
  String? _adLinkUrl;
  bool _adActive = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _listenToPrices();
    _listenToHistory();
    _listenToAd();
  }

  void _loadPreferences() async {
    final prefs = await PrefsService.load();
    setState(() {
      _isDarkMode = prefs['isDarkMode'] as bool;
      _selectedLanguage = prefs['language'] as String;
      _isAdminLoggedIn = AuthService.isLoggedIn;
    });
    themeModeNotifier.value =
        _isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  void _toggleDarkMode(bool value) {
    setState(() => _isDarkMode = value);
    themeModeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    PrefsService.saveDarkMode(value);
  }

  void _listenToPrices() {
    FirebaseFirestore.instance
        .collection('prices')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final buy = (data['buy'] as num?)?.toDouble() ?? 0;
        final sell = (data['sell'] as num?)?.toDouble() ?? 0;
        setState(() {
          // Sauvegarder l'ancien prix avant mise à jour pour la flèche
          final oldBuy = _prices[doc.id]?['buy'] ?? -1;
          final oldSell = _prices[doc.id]?['sell'] ?? -1;
          if (oldBuy > 0) {
            _prevPrices[doc.id] = {'buy': oldBuy, 'sell': oldSell};
          }
          _prices[doc.id] = {'buy': buy, 'sell': sell};
          _loading = false;
        });
      }
    });
  }

  void _listenToHistory() {
    FirebaseFirestore.instance
        .collection('history')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      final gold = <PriceEntry>[];
      final silver = <PriceEntry>[];
      final goldAll = <PriceEntry>[];
      final silverAll = <PriceEntry>[];
      final now = DateTime.now();
      final limit = now.subtract(const Duration(days: 2));

      for (var doc in snapshot.docs) {
        final d = doc.data();
        DateTime? createdAt;
        final ts = d['createdAt'];
        if (ts is Timestamp) createdAt = ts.toDate();

        final entry = PriceEntry(
          date: d['date'] as String? ?? '',
          buyPrice: (d['buy'] as num?)?.toDouble() ?? 0,
          sellPrice: (d['sell'] as num?)?.toDouble() ?? 0,
          createdAt: createdAt,
        );

        if (d['metal'] == 'gold') {
          goldAll.add(entry);
        } else {
          silverAll.add(entry);
        }

        if (createdAt == null || createdAt.isAfter(limit)) {
          if (d['metal'] == 'gold') {
            gold.add(entry);
          } else {
            silver.add(entry);
          }
        }
      }
      setState(() {
        _goldHistory = gold;
        _silverHistory = silver;
        _goldHistoryAll = goldAll;
        _silverHistoryAll = silverAll;
      });
    });
  }

  void _listenToAd() {
    FirebaseFirestore.instance
        .collection('config')
        .doc('ad')
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        final img = (doc.data()?['imageUrl'] as String? ?? '')
            .replaceAll('"', '')
            .trim();
        final lnk = (doc.data()?['linkUrl'] as String? ?? '')
            .replaceAll('"', '')
            .trim();
        setState(() {
          _adImageUrl = img;
          _adLinkUrl = lnk;
          _adActive = doc.data()?['active'] as bool? ?? false;
        });
      }
    });
  }

  String get _metal => _selectedTab == 0 ? 'gold' : 'silver';

  // Prix de base 18k selon Buy/Sell
  double get _basePrice18k => _isBuy
      ? (_prices[_metal]!['buy'] ?? 0)
      : (_prices[_metal]!['sell'] ?? 0);

  // ✅ Prix affiché selon karat sélectionné
  double get _currentPrice {
    final base = _basePrice18k;
    return _selectedKarat == 24 ? base * 1.3333 : base;
  }

  // ✅ Comparaison avec la 2ème entrée de l'historique (entrée précédente réelle)
  // ✅ Flèche : compare prix actuel (Firestore prices) vs dernière entrée historique
  // Si live update en session → utilise _prevPrices
  // Sinon → compare prix actuel avec la 1ère entrée de l'historique complet
  bool? get _isPriceUp {
    final currRaw = _isBuy
        ? (_prices[_metal]?['buy'] ?? 0)
        : (_prices[_metal]?['sell'] ?? 0);
    final prevLive = _isBuy
        ? (_prevPrices[_metal]?['buy'] ?? -1)
        : (_prevPrices[_metal]?['sell'] ?? -1);

    double curr = _selectedKarat == 24 ? currRaw * 1.3333 : currRaw;
    double prev;

    if (prevLive > 0) {
      // Changement détecté en live dans cette session
      prev = _selectedKarat == 24 ? prevLive * 1.3333 : prevLive;
    } else {
      // Au lancement : comparer prix actuel vs 1ère entrée de l'historique complet
      final allHistory = _selectedTab == 0 ? _goldHistoryAll : _silverHistoryAll;
      if (allHistory.isEmpty) return null;
      final h0Raw = _isBuy ? allHistory[0].buyPrice : allHistory[0].sellPrice;
      prev = _selectedKarat == 24 ? h0Raw * 1.3333 : h0Raw;
      // Si le prix actuel == la 1ère entrée historique → pas de changement récent
      // Essayer avec la 2ème entrée
      if (curr == prev && allHistory.length >= 2) {
        final h1Raw = _isBuy ? allHistory[1].buyPrice : allHistory[1].sellPrice;
        prev = _selectedKarat == 24 ? h1Raw * 1.3333 : h1Raw;
      }
    }

    if (curr > prev) return true;
    if (curr < prev) return false;
    return null;
  }

  List<PriceEntry> get _currentHistory =>
      _selectedTab == 0 ? _goldHistory : _silverHistory;

  List<PriceEntry> get _filteredHistory {
    if (_filterDate == null) return _currentHistory;
    final allHistory =
        _selectedTab == 0 ? _goldHistoryAll : _silverHistoryAll;
    return allHistory.where((e) {
      if (e.createdAt == null) return false;
      return e.createdAt!.year == _filterDate!.year &&
          e.createdAt!.month == _filterDate!.month &&
          e.createdAt!.day == _filterDate!.day;
    }).toList();
  }

  Future<void> _pickFilterDate() async {
    final now = DateTime.now();
    final pick = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFD4A017),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (pick != null) setState(() => _filterDate = pick);
  }

  String _translate(String key) {
    if (_selectedLanguage == 'العربية') {
      switch (key) {
        case 'ADDHAIBY':                            return 'ADDHAIBY';
        case 'Accueil':                             return 'الرئيسية';
        case 'Acheter de l\'or':                    return 'شراء الذهب';
        case 'Paramètres':                          return 'الإعدادات';
        case 'Or (ذهب)':                            return 'ذهب';
        case 'Silver / Argent (فضة)':               return 'فضة';
        case 'Buy (شراء)':                          return 'شراء';
        case 'Sell (بيع)':                          return 'بيع';
        case 'Recent rates':                        return 'آخر الأسعار';
        case 'Filtrer par date':                    return 'تصفية حسب التاريخ';
        case 'Affichage des 2 derniers jours':      return 'عرض آخر يومين';
        case 'Aucun prix pour cette date':          return 'لا توجد أسعار لهذا التاريخ';
        case 'Aucun historique disponible':         return 'لا يوجد سجل متاح';
        case 'Voir tout':                           return 'عرض الكل';
        case 'Actuel':                              return 'الحالي';
        case 'Achat':                               return 'شراء';
        case 'Vente':                               return 'بيع';
        case 'Apparence':                           return 'المظهر';
        case 'Langue':                              return 'اللغة';
        case 'Admin':                               return 'مدير';
        case 'Ouvrir le panneau admin':             return 'فتح لوحة التحكم';
        case 'Modifier les prix':                   return 'تعديل الأسعار';
        case 'Gérer la publicité':                  return 'إدارة الإعلانات';
        case 'Se déconnecter':                      return 'تسجيل الخروج';
        case 'Jour':                                return 'نهار';
        case 'Nuit':                                return 'ليل';
        case 'Connexion Admin':                     return 'تسجيل دخول المدير';
        case 'Espace Publicitaire':                 return 'مساحة إعلانية';
        case 'Contactez-nous pour annoncer ici':    return 'اتصل بنا للإعلان هنا';
        case "Or d'occasion\npour investissement":  return 'ذهب مستعمل\nللاستثمار';
        case 'Bijoux en or':                        return 'مجوهرات ذهبية';
        case 'Bijoux en platine':                   return 'مجوهرات بلاتينية';
        case 'Bijoux en argent':                    return 'مجوهرات فضية';
        default: return key;
      }
    }
    return key;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          _isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: _selectedNav == 0
          ? _buildHomeBody()
          : _selectedNav == 1
              ? _buildBuyBody()
              : _buildSettingsBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeBody() {
    return Column(children: [
      _buildHeader(),
      Expanded(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFD4A017)))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMetalTabs(),
                      const SizedBox(height: 12),
                      _buildBuySellAndKaratRow(),
                      const SizedBox(height: 20),
                      _buildPriceCard(),
                      // ✅ Publicité EN HAUT (avant historique)
                      if (_adActive) ...[
                        const SizedBox(height: 20),
                        _buildAdBanner(),
                      ],
                      const SizedBox(height: 24),
                      // ✅ Filtre + historique EN BAS
                      _buildHistorySection(),
                      const SizedBox(height: 16),
                    ]),
              ),
      ),
    ]);
  }

  // ✅ Header avec "By سقيم" sous ADDHAIBY
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      color: const Color(0xFFD4A017),
      child: Column(
        children: [
          const Text(
            'ADDHAIBY',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          const Text(
            'By سقيم',
            style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w400,
                letterSpacing: 1),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMetalTabs() {
    return Row(children: [
      _chipTab(_translate('Or (ذهب)'), 0, _selectedTab,
          (i) => setState(() {
                _selectedTab = i;
                _selectedKarat = 18; // reset karat quand on change de métal
              }),
          const Color(0xFFD4A017)),
      const SizedBox(width: 10),
      _chipTab(_translate('Silver / Argent (فضة)'), 1, _selectedTab,
          (i) => setState(() {
                _selectedTab = i;
                _selectedKarat = 18;
              }),
          const Color(0xFFD4A017)),
    ]);
  }

  Widget _chipTab(String label, int index, int current, Function(int) onTap,
      Color color) {
    final selected = current == index;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color
              : (_isDarkMode ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
  }

  // ✅ Buy/Sell + boutons 18k/24k sur la même ligne
  Widget _buildBuySellAndKaratRow() {
    return Row(
      children: [
        _buySellChip(_translate('Buy (شراء)'), true),
        const SizedBox(width: 10),
        _buySellChip(_translate('Sell (بيع)'), false),
        const Spacer(),
        // Boutons 18k / 24k uniquement pour l'or
        if (_selectedTab == 0) ...[
          _karatBtn(18),
          const SizedBox(width: 8),
          _karatBtn(24),
        ],
      ],
    );
  }

  // ✅ Bouton karat 18k / 24k
  Widget _karatBtn(int karat) {
    final selected = _selectedKarat == karat;
    return GestureDetector(
      onTap: () => setState(() => _selectedKarat = karat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFD4A017)
              : (_isDarkMode ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD4A017)),
        ),
        child: Text(
          '${karat}k',
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFD4A017),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buySellChip(String label, bool isBuy) {
    final selected = _isBuy == isBuy;
    final color = isBuy ? Colors.green : Colors.red;
    return GestureDetector(
      onTap: () => setState(() => _isBuy = isBuy),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color
              : (_isDarkMode ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Row(children: [
          if (selected) const Icon(Icons.check, size: 14, color: Colors.white),
          if (selected) const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
      ),
    );
  }

  // ✅ Carte prix avec texte arabe modifié, taille agrandie, flèche tendance, badge karat
  Widget _buildPriceCard() {
    final isUp = _isPriceUp;

    String priceLabel;
    if (_selectedTab == 0) {
      // Or
      final karatLabel = _selectedKarat == 24 ? 'عيار 24' : 'عيار 18';
      if (_isBuy) {
        priceLabel =
            'سعر الذهب التقريبي لليوم ($karatLabel) حسب المنجرة هو';
      } else {
        priceLabel =
            'سعر بيع الذهب التقريبي لليوم ($karatLabel) حسب المنجرة هو';
      }
    } else {
      // Argent / Fضة
      if (_isBuy) {
        priceLabel = 'سعر الفضة التقريبي لليوم حسب المنجرة هو';
      } else {
        priceLabel = 'سعر بيع الفضة التقريبي لليوم حسب المنجرة هو';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _isDarkMode
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ✅ Texte agrandi (15) et plus visible
        Text(
          priceLabel,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _isDarkMode
                  ? Colors.grey.shade300
                  : Colors.grey.shade700),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _currentPrice.toStringAsFixed(2),
              style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: _isDarkMode
                      ? Colors.white
                      : const Color(0xFF1A1A1A)),
            ),
            const SizedBox(width: 10),
            // ✅ Flèche tendance : verte si hausse, rouge si baisse, grise si stable
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Icon(
                isUp == null
                    ? Icons.trending_flat
                    : (isUp! ? Icons.trending_up : Icons.trending_down),
                color: isUp == null
                    ? Colors.grey
                    : (isUp! ? Colors.green : Colors.red),
                size: 36,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text('MAD/g',
                style: TextStyle(
                    fontSize: 14,
                    color: _isDarkMode
                        ? Colors.grey.shade400
                        : Colors.grey)),
            const SizedBox(width: 8),
            // ✅ Badge karat affiché pour l'or
            if (_selectedTab == 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A017).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          const Color(0xFFD4A017).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${_selectedKarat}k',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4A017),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _buildHistorySection() {
    final displayed = _filteredHistory;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_translate('Recent rates'),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color:
                    _isDarkMode ? Colors.white : const Color(0xFF1A1A1A))),
        Text('${displayed.length} entrée(s)',
            style: TextStyle(
                fontSize: 12,
                color:
                    _isDarkMode ? Colors.grey.shade400 : Colors.grey)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _pickFilterDate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _filterDate != null
                    ? const Color(0xFFD4A017).withValues(alpha: 0.12)
                    : (_isDarkMode ? const Color(0xFF1E1E1E) : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _filterDate != null
                      ? const Color(0xFFD4A017)
                      : (_isDarkMode
                          ? Colors.grey.shade700
                          : Colors.grey.shade300),
                ),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today,
                    size: 16,
                    color: _filterDate != null
                        ? const Color(0xFFD4A017)
                        : (_isDarkMode
                            ? Colors.grey.shade400
                            : Colors.grey)),
                const SizedBox(width: 8),
                Text(
                  _filterDate != null
                      ? '${_filterDate!.day.toString().padLeft(2, '0')}/'
                          '${_filterDate!.month.toString().padLeft(2, '0')}/'
                          '${_filterDate!.year}'
                      : _translate('Filtrer par date'),
                  style: TextStyle(
                    color: _filterDate != null
                        ? const Color(0xFFD4A017)
                        : (_isDarkMode
                            ? Colors.grey.shade400
                            : Colors.grey),
                    fontWeight: _filterDate != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ]),
            ),
          ),
        ),
        if (_filterDate != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _filterDate = null),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child:
                  Icon(Icons.close, size: 16, color: Colors.red.shade400),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 10),
      if (_filterDate == null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.info_outline,
                size: 14, color: Colors.blue.shade400),
            const SizedBox(width: 6),
            Text(_translate('Affichage des 2 derniers jours'),
                style: TextStyle(
                    fontSize: 11, color: Colors.blue.shade600)),
          ]),
        ),
      if (_filterDate != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFD4A017).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.filter_list,
                size: 14, color: Color(0xFFD4A017)),
            const SizedBox(width: 6),
            Text(
              'Résultats pour le ${_filterDate!.day.toString().padLeft(2, '0')}/'
              '${_filterDate!.month.toString().padLeft(2, '0')}/'
              '${_filterDate!.year}',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFFD4A017)),
            ),
          ]),
        ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFD4A017).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Date',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF8B6914))),
              Row(children: [
                const Icon(Icons.arrow_downward,
                    size: 13, color: Colors.green),
                const SizedBox(width: 4),
                Text(_translate('Achat'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.green)),
                const SizedBox(width: 16),
                const Icon(Icons.arrow_upward,
                    size: 13, color: Colors.red),
                const SizedBox(width: 4),
                Text(_translate('Vente'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.red)),
              ]),
            ]),
      ),
      const SizedBox(height: 8),
      if (displayed.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12)),
          child: Center(
            child: Column(children: [
              Icon(Icons.search_off,
                  size: 40, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                _filterDate != null
                    ? _translate('Aucun prix pour cette date')
                    : _translate('Aucun historique disponible'),
                style: const TextStyle(color: Colors.grey),
              ),
              if (_filterDate != null)
                TextButton.icon(
                  onPressed: () => setState(() => _filterDate = null),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: Text(_translate('Voir tout'),
                      style: const TextStyle(fontSize: 12)),
                ),
            ]),
          ),
        )
      else
        ...displayed.map((e) => _buildHistoryRow(e, displayed)),
    ]);
  }

  // ✅ Lignes historique avec flèche tendance entre entrées
  Widget _buildHistoryRow(PriceEntry e, List<PriceEntry> list) {
    final idx = list.indexOf(e);
    final isLatest = idx == 0 && _filterDate == null;

    // Comparer avec l'entrée précédente dans la liste
    bool? buyTrend;
    bool? sellTrend;
    if (idx < list.length - 1) {
      final prev = list[idx + 1];
      if (e.buyPrice > prev.buyPrice) buyTrend = true;
      if (e.buyPrice < prev.buyPrice) buyTrend = false;
      if (e.sellPrice > prev.sellPrice) sellTrend = true;
      if (e.sellPrice < prev.sellPrice) sellTrend = false;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isLatest
            ? const Color(0xFFD4A017).withValues(alpha: 0.08)
            : (_isDarkMode ? const Color(0xFF1E1E1E) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: isLatest
            ? Border.all(
                color: const Color(0xFFD4A017).withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isLatest)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_translate('Actuel'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              Text(e.date,
                  style: TextStyle(
                      color: isLatest
                          ? const Color(0xFF8B6914)
                          : (_isDarkMode
                              ? Colors.grey.shade400
                              : Colors.grey),
                      fontSize: 13,
                      fontWeight: isLatest
                          ? FontWeight.w600
                          : FontWeight.normal)),
            ]),
            Row(children: [
              // Colonne Achat
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(children: [
                  // Flèche tendance achat (vert si hausse, rouge si baisse)
                  Icon(
                    buyTrend == null
                        ? Icons.arrow_downward
                        : (buyTrend ? Icons.arrow_upward : Icons.arrow_downward),
                    size: 13,
                    color: buyTrend == null
                        ? Colors.green
                        : (buyTrend ? Colors.green : Colors.red),
                  ),
                  Text(' ${e.buyPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.green)),
                ]),
                const Text('MAD/g',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
              const SizedBox(width: 16),
              // Colonne Vente
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(children: [
                  // Flèche tendance vente (vert si hausse, rouge si baisse)
                  Icon(
                    sellTrend == null
                        ? Icons.arrow_upward
                        : (sellTrend ? Icons.arrow_upward : Icons.arrow_downward),
                    size: 13,
                    color: sellTrend == null
                        ? Colors.red
                        : (sellTrend ? Colors.green : Colors.red),
                  ),
                  Text(' ${e.sellPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red)),
                ]),
                const Text('MAD/g',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
            ]),
          ]),
    );
  }

  Widget _buildAdBanner() {
    return GestureDetector(
      onTap: () async {
        if (_adLinkUrl != null && _adLinkUrl!.isNotEmpty) {
          final uri = Uri.tryParse(_adLinkUrl!);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
      child: Container(
        width: double.infinity,
        height: 130,
        decoration: BoxDecoration(
          color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
          border: Border.all(
              color: const Color(0xFFD4A017).withValues(alpha: 0.25),
              width: 1.2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: (_adImageUrl != null &&
                  _adImageUrl!.isNotEmpty &&
                  _adImageUrl!.startsWith('http'))
              ? Image.network(
                  _adImageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFD4A017)));
                  },
                  errorBuilder: (_, __, ___) => _adPlaceholder(),
                )
              : _adPlaceholder(),
        ),
      ),
    );
  }

  Widget _adPlaceholder() {
    return Container(
      color: const Color(0xFFFDF6E3),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.campaign,
            size: 40,
            color: const Color(0xFFD4A017).withValues(alpha: 0.45)),
        const SizedBox(height: 8),
        Text(_translate('Espace Publicitaire'),
            style: const TextStyle(
                color: Color(0xFFD4A017),
                fontWeight: FontWeight.w600,
                fontSize: 14)),
        Text(_translate('Contactez-nous pour annoncer ici'),
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ]),
    );
  }

  Widget _buildBuyBody() {
    final cats = [
      {
        'label': _translate("Or d'occasion\npour investissement"),
        'icon': Icons.savings
      },
      {'label': _translate('Bijoux en or'), 'icon': Icons.diamond},
      {
        'label': _translate('Bijoux en platine'),
        'icon': Icons.circle_outlined
      },
      {
        'label': _translate('Bijoux en argent'),
        'icon': Icons.radio_button_unchecked
      },
    ];

    return Column(children: [
      _buildHeader(),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: cats.map((c) => _buildCategoryCard(c)).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _socialBtn(
                    FontAwesomeIcons.facebookF,
                    const Color(0xFF1877F2),
                    "https://www.facebook.com/share/1Cm6RexgVS/?mibextid=wwXIfr"),
                const SizedBox(width: 24),
                _socialBtn(
                    FontAwesomeIcons.instagram,
                    const Color(0xFFE1306C),
                    "https://www.instagram.com/addhaiby?igsh=MWs4aG1qZmNrZXVncQ=="),
                const SizedBox(width: 24),
                _socialBtn(FontAwesomeIcons.whatsapp,
                    const Color(0xFF25D366), "https://wa.me/212678660346"),
              ],
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildCategoryCard(Map<String, dynamic> cat) {
    return Container(
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(cat['icon'] as IconData,
              size: 48, color: const Color(0xFFD4A017)),
          const SizedBox(height: 12),
          Text(
            cat['label'] as String,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialBtn(dynamic icon, Color color, String url) {
    return GestureDetector(
      onTap: () async {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: icon is IconData
              ? Icon(icon, color: Colors.white, size: 24)
              : FaIcon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildSettingsBody() {
    return Column(children: [
      _buildHeader(),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_translate('Apparence'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isDarkMode
                            ? Colors.white
                            : Colors.black87)),
                const SizedBox(height: 8),
                Row(children: [
                  _toggleBtn(_translate('Jour'), true),
                  const SizedBox(width: 8),
                  _toggleBtn(_translate('Nuit'), false),
                ]),
                const SizedBox(height: 20),
                Text(_translate('Langue'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isDarkMode
                            ? Colors.white
                            : Colors.black87)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: _isDarkMode
                              ? Colors.grey.shade700
                              : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8)),
                  child: DropdownButton<String>(
                    value: _selectedLanguage,
                    underline: const SizedBox(),
                    dropdownColor: _isDarkMode
                        ? const Color(0xFF1E1E1E)
                        : Colors.white,
                    style: TextStyle(
                        color: _isDarkMode
                            ? Colors.white
                            : Colors.black87),
                    items: const [
                      DropdownMenuItem(
                          value: 'Français', child: Text('Français')),
                      DropdownMenuItem(
                          value: 'العربية', child: Text('العربية')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedLanguage = value);
                        PrefsService.saveLanguage(value);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 30),
                Text(_translate('Admin'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isDarkMode
                            ? Colors.white
                            : Colors.black87)),
                const SizedBox(height: 12),
                if (!_isAdminLoggedIn)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showLoginDialog(context),
                      icon: const Icon(Icons.admin_panel_settings),
                      label: Text(_translate('Ouvrir le panneau admin')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B4513),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAdminPanel(context),
                      icon: const Icon(Icons.edit),
                      label: Text(_translate('Modifier les prix')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A017),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAdDialog(context),
                      icon: const Icon(Icons.campaign),
                      label: Text(_translate('Gérer la publicité')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () async {
                        await AuthService.signOut();
                        setState(() => _isAdminLoggedIn = false);
                        if (mounted) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(
                                content: Text('👋 Déconnecté'),
                                backgroundColor: Colors.grey),
                          );
                        }
                      },
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: Text(_translate('Se déconnecter'),
                          style:
                              const TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ]),
        ),
      ),
    ]);
  }

  Widget _toggleBtn(String label, bool isDay) {
    final isSelected = (isDay && !_isDarkMode) || (!isDay && _isDarkMode);
    return GestureDetector(
      onTap: () => _toggleDarkMode(!isDay),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFD4A017)
              : (_isDarkMode ? const Color(0xFF1E1E1E) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: _isDarkMode
                  ? Colors.grey.shade700
                  : Colors.grey.shade300),
        ),
        child: Row(children: [
          if (isSelected)
            const Icon(Icons.check, size: 14, color: Colors.white),
          if (isSelected) const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (_isDarkMode
                          ? Colors.white70
                          : Colors.black87),
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          backgroundColor:
              _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Column(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                  color: Color(0xFFD4A017), shape: BoxShape.circle),
              child: const Icon(Icons.admin_panel_settings,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(height: 8),
            Text(_translate('Connexion Admin'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isDarkMode
                        ? Colors.white
                        : Colors.black87)),
            const Text('ADDHAIBY',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(
                  color:
                      _isDarkMode ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              style: TextStyle(
                  color:
                      _isDarkMode ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(obscure
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () => setD(() => obscure = !obscure),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12))),
                ]),
              ),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailCtrl.text.trim();
                final pass = passCtrl.text;
                if (email.isEmpty || pass.isEmpty) {
                  setD(() =>
                      error = 'Veuillez remplir tous les champs.');
                  return;
                }
                setD(() => error = null);
                final errMsg = await AuthService.signIn(email, pass);
                if (errMsg != null) {
                  setD(() => error = errMsg);
                } else {
                  setState(() => _isAdminLoggedIn = true);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) _showAdminPanel(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A017),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Se connecter'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdminPanel(BuildContext context) {
    String selectedMetal = 'Or (gold)';
    final buyCtrl = TextEditingController(
        text: _prices['gold']!['buy']!.toStringAsFixed(2));
    final sellCtrl = TextEditingController(
        text: _prices['gold']!['sell']!.toStringAsFixed(2));
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          backgroundColor:
              _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Row(children: [
            const Icon(Icons.edit, color: Color(0xFFD4A017)),
            const SizedBox(width: 8),
            Text('Admin — Saisie des prix',
                style: TextStyle(
                    color: _isDarkMode
                        ? Colors.white
                        : Colors.black87)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: selectedMetal,
              dropdownColor:
                  _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              style: TextStyle(
                  color:
                      _isDarkMode ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Métal',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'Or (gold)', child: Text('Or (gold)')),
                DropdownMenuItem(
                    value: 'Argent (silver)',
                    child: Text('Argent (silver)')),
              ],
              onChanged: (val) {
                setD(() {
                  selectedMetal = val!;
                  final k =
                      val.contains('gold') ? 'gold' : 'silver';
                  buyCtrl.text =
                      _prices[k]!['buy']!.toStringAsFixed(2);
                  sellCtrl.text =
                      _prices[k]!['sell']!.toStringAsFixed(2);
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: buyCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(
                  color:
                      _isDarkMode ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: "Prix d'achat (MAD/g) — 18k",
                prefixIcon: const Icon(Icons.arrow_downward,
                    color: Colors.green),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sellCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(
                  color:
                      _isDarkMode ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                labelText: 'Prix de vente (MAD/g) — 18k',
                prefixIcon: const Icon(Icons.arrow_upward,
                    color: Colors.red),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            // ✅ Aperçu du prix 24k calculé automatiquement
            StatefulBuilder(builder: (ctx2, setD2) {
              buyCtrl.addListener(() => setD2(() {}));
              sellCtrl.addListener(() => setD2(() {}));
              final buy24 =
                  (double.tryParse(buyCtrl.text) ?? 0) * 1.3333;
              final sell24 =
                  (double.tryParse(sellCtrl.text) ?? 0) * 1.3333;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A017)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFD4A017)
                          .withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        '24k (calculé automatiquement × 1.3333)',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8B6914))),
                    const SizedBox(height: 4),
                    Text(
                      'Achat: ${buy24.toStringAsFixed(2)} MAD/g  |  Vente: ${sell24.toStringAsFixed(2)} MAD/g',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD4A017)),
                    ),
                  ],
                ),
              );
            }),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final k = selectedMetal.contains('gold')
                          ? 'gold'
                          : 'silver';
                      final buy =
                          double.tryParse(buyCtrl.text) ??
                              _prices[k]!['buy']!;
                      final sell =
                          double.tryParse(sellCtrl.text) ??
                              _prices[k]!['sell']!;
                      final now = DateTime.now();
                      final date =
                          '${now.day.toString().padLeft(2, '0')}/'
                          '${now.month.toString().padLeft(2, '0')}/'
                          '${now.year}  '
                          '${now.hour.toString().padLeft(2, '0')}:'
                          '${now.minute.toString().padLeft(2, '0')}';
                      setD(() => saving = true);
                      final db = FirebaseFirestore.instance;
                      await db
                          .collection('prices')
                          .doc(k)
                          .update({
                        'buy': buy,
                        'sell': sell,
                        'updatedAt': date,
                      });
                      await db.collection('history').add({
                        'metal': k,
                        'buy': buy,
                        'sell': sell,
                        'date': date,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      await NotificationService.sendPriceNotification(
                        metal: k,
                        buyPrice: buy,
                        sellPrice: sell,
                      );
                      setD(() => saving = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)
                            ?.showSnackBar(
                          const SnackBar(
                            content: Text(
                                '✅ Prix mis à jour et notification envoyée !'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(
                  saving ? 'Enregistrement...' : 'Enregistrer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A017),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdDialog(BuildContext context) {
    final rawImage = (_adImageUrl ?? '').replaceAll('"', '').trim();
    final rawLink = (_adLinkUrl ?? '').replaceAll('"', '').trim();
    final imageCtrl = TextEditingController(text: rawImage);
    final linkCtrl = TextEditingController(text: rawLink);
    bool adEnabled = _adActive;
    bool saving = false;
    bool showPreview = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          backgroundColor:
              _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Row(children: [
            const Icon(Icons.campaign, color: Color(0xFF4CAF50)),
            const SizedBox(width: 8),
            Text(_translate('Gérer la publicité'),
                style: TextStyle(
                    color: _isDarkMode
                        ? Colors.white
                        : Colors.black87)),
          ]),
          content: SingleChildScrollView(
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: adEnabled
                      ? Colors.green.shade50
                      : (_isDarkMode
                          ? const Color(0xFF2C2C2C)
                          : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: adEnabled
                          ? Colors.green.shade200
                          : (_isDarkMode
                              ? Colors.grey.shade700
                              : Colors.grey.shade300)),
                ),
                child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                                adEnabled
                                    ? 'Publicité activée'
                                    : 'Publicité désactivée',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: adEnabled
                                        ? Colors.green.shade700
                                        : (_isDarkMode
                                            ? Colors.white70
                                            : Colors.grey))),
                            Text(
                                "Visible sur l'écran d'accueil",
                                style: TextStyle(
                                    fontSize: 11,
                                    color: _isDarkMode
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade500)),
                          ]),
                      Switch(
                        value: adEnabled,
                        activeColor: Colors.green,
                        onChanged: (v) =>
                            setD(() => adEnabled = v),
                      ),
                    ]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: imageCtrl,
                keyboardType: TextInputType.url,
                style: TextStyle(
                    color: _isDarkMode
                        ? Colors.white
                        : Colors.black87),
                onChanged: (_) =>
                    setD(() => showPreview = false),
                decoration: InputDecoration(
                  labelText: "URL de l'image",
                  hintText: 'https://exemple.com/pub.jpg',
                  prefixIcon: const Icon(Icons.image_outlined,
                      color: Color(0xFFD4A017)),
                  suffixIcon: imageCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: Colors.grey),
                          onPressed: () {
                            imageCtrl.clear();
                            setD(() => showPreview = false);
                          })
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: linkCtrl,
                keyboardType: TextInputType.url,
                style: TextStyle(
                    color: _isDarkMode
                        ? Colors.white
                        : Colors.black87),
                decoration: InputDecoration(
                  labelText: 'Lien de redirection (clic)',
                  hintText: 'https://votresite.com',
                  prefixIcon: const Icon(Icons.link,
                      color: Color(0xFFD4A017)),
                  suffixIcon: linkCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: Colors.grey),
                          onPressed: () {
                            linkCtrl.clear();
                            setD(() {});
                          })
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              if (imageCtrl.text.trim().startsWith('http'))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        setD(() => showPreview = !showPreview),
                    icon: Icon(
                        showPreview
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFFD4A017)),
                    label: Text(
                        showPreview
                            ? 'Masquer aperçu'
                            : 'Voir aperçu',
                        style: const TextStyle(
                            color: Color(0xFFD4A017))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: Color(0xFFD4A017)),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (showPreview &&
                  imageCtrl.text.trim().startsWith('http')) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageCtrl.text.trim(),
                    height: 90,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox(
                          height: 90,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFFD4A017))));
                    },
                    errorBuilder: (_, __, ___) => Container(
                      height: 90,
                      color: Colors.grey.shade100,
                      child: const Center(
                          child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              color: Colors.grey),
                          SizedBox(height: 4),
                          Text('Image introuvable',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12)),
                        ],
                      )),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setD(() => saving = true);
                      await FirebaseFirestore.instance
                          .collection('config')
                          .doc('ad')
                          .set({
                        'imageUrl': imageCtrl.text.trim(),
                        'linkUrl': linkCtrl.text.trim(),
                        'active': adEnabled,
                        'updatedAt':
                            DateTime.now().toIso8601String(),
                      }, SetOptions(merge: true));
                      setD(() => saving = false);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)
                            ?.showSnackBar(SnackBar(
                          content: Text(adEnabled
                              ? '✅ Publicité activée !'
                              : '🚫 Publicité désactivée.'),
                          backgroundColor: adEnabled
                              ? Colors.green
                              : Colors.grey,
                        ));
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(
                  saving ? 'Enregistrement...' : 'Enregistrer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedNav,
      onTap: (i) => setState(() => _selectedNav = i),
      selectedItemColor: const Color(0xFFD4A017),
      unselectedItemColor:
          _isDarkMode ? Colors.grey.shade400 : Colors.grey,
      backgroundColor:
          _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      type: BottomNavigationBarType.fixed,
      items: [
        BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: _translate('Accueil')),
        BottomNavigationBarItem(
            icon: const Icon(Icons.store),
            label: _translate("Acheter de l'or")),
        BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: _translate('Paramètres')),
      ],
    );
  }
}