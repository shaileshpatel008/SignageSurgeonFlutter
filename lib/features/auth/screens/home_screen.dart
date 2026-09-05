// lib/features/auth/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/push_notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentBannerIndex = 0;
  int _selectedNavIndex = 0;
  String _userName = '';
  String _location = 'Ahmedabad, Gujarat';

  final PageController _bannerController = PageController(initialPage: 1000);

  // ── Banner background color ─────────────────────────────────────────────
  // Change this ONE value to test different shades behind the banner PNGs.
  static const Color _bannerBgColor = Color(0xFFF6F7F9);

  // ── Service card icon background color ──────────────────────────────────
  static const Color _serviceIconBgColor = Color(0xFFFFC20F);

  final List<Map<String, dynamic>> _banners = [
    {
      'image': 'assets/images/banner_cleaning.png',
'route': AppRoutes.cleaningRequest,
      'arg': 'cleaning',
    },
    {
      'image': 'assets/images/banner_amc.png',
'route': AppRoutes.amcRequest,
      'arg': null,
    },
    {
      'image': 'assets/images/banner_signshoppy.png',
      'route': AppRoutes.signShoppy,
      'arg': null,
    },
  ];

  final List<Map<String, dynamic>> _services = [
    {
      'icon': Icons.build_outlined,
      'label': 'REPAIRING',
      'sub': 'Fix & repair existing\nsignage',
      'comingSoon': false,
      'route': AppRoutes.repairingRequest,
      'arg': null,
      'bgColor': _serviceIconBgColor,
      'iconColor': Colors.white,
    },
    {
      'icon': Icons.brush_outlined,
      'label': 'REBRANDING',
      'sub': 'Refresh your brand\nlook & signage',
      'comingSoon': false,
      'route': AppRoutes.rebrandingRequest,
      'arg': null,
      'bgColor': _serviceIconBgColor,
      'iconColor': Colors.white,
    },
    {
      'icon': Icons.add_business_outlined,
      'label': 'NEW SIGNAGE',
      'sub': 'Design & install\nnew signage',
      'comingSoon': false,
      'route': AppRoutes.newSignageRequest,
      'arg': null,
      'bgColor': _serviceIconBgColor,
      'iconColor': Colors.white,
    },
    {
      'icon': Icons.cleaning_services_outlined,
      'label': 'SIGNAGE\nCLEANING',
      'sub': 'Professional\ncleaning services',
      'comingSoon': false,
      'route': AppRoutes.cleaningRequest,
      'arg': null,
      'bgColor': _serviceIconBgColor,
      'iconColor': Colors.white,
    },
    {
      'icon': Icons.shield_outlined,
      'label': 'AMC PLANS',
      'sub': 'Annual Maintenance\nContract',
      'comingSoon': false,
      'route': AppRoutes.amcRequest,
      'arg': null,
      'bgColor': _serviceIconBgColor,
      'iconColor': Colors.white,
    },
    {
      'icon': Icons.storefront_outlined,
      'label': 'SIGN SHOPPY',
      'sub': 'Ready-made signage,\nready to order',
      'comingSoon': false,
      'route': AppRoutes.signShoppy,
      'arg': null,
      'bgColor': _serviceIconBgColor,
      'iconColor': Colors.white,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _autoScrollBanner();
    NotificationService.instance.start();
    PushNotificationService.instance.init();
  }

  void _autoScrollBanner() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;

      _bannerController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );

      _autoScrollBanner();
    });
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _userName =
              data['fullName'] ?? data['name'] ?? data['businessName'] ?? '';
          _location = '${data['city'] ?? 'Ahmedabad'}, Gujarat';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == 0) {
      setState(() => _selectedNavIndex = 0);
      return;
    }
    switch (index) {
      case 1:
        Navigator.pushNamed(context, AppRoutes.myRequests);
        break;
      case 2:
        Navigator.pushNamed(context, AppRoutes.amc);
        break;
      case 3:
        Navigator.pushNamed(context, AppRoutes.notifications);
        break;
      case 4:
        Navigator.pushNamed(context, AppRoutes.account);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.yellow, Color(0xFFFFD54A)],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildTopBar(),
                      const SizedBox(height: 16),
                      _buildBannerCardOnly(),
                      const SizedBox(height: 14),
                      _buildBannerDots(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                color: AppColors.offWhite,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Our Services",
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Container(
                      width: 32,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return _serviceCard(_services[index]);
                }, childCount: _services.length),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.68,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  // ─── TOP BAR ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: AppColors.navy,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Hello, ${_userName.isEmpty ? 'there' : _userName}',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(' 👋', style: TextStyle(fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 3),
                GestureDetector(
                  onTap: _showLocationPicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppColors.red,
                        size: 15,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _location,
                        style: TextStyle(
                          color: AppColors.navy.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.navy.withOpacity(0.6),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── BANNER ─────────────────────────────────────────────────────────────────
  // Images are 1074x466px (~2.305:1). Sized by aspect ratio, not fixed height,
  // so the banner art displays in full with no cropping or letterboxing.

  Widget _buildBannerCardOnly() {
    return AspectRatio(
      aspectRatio: 1074 / 466,
      child: PageView.builder(
        controller: _bannerController,
        onPageChanged: (index) {
          setState(() {
            _currentBannerIndex = index % _banners.length;
          });
        },
        itemBuilder: (_, index) {
          return _bannerCard(_banners[index % _banners.length]);
        },
      ),
    );
  }

  Widget _buildBannerDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _banners.length,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentBannerIndex == i ? 24 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: _currentBannerIndex == i
                ? AppColors.red
                : Colors.white.withOpacity(.65),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget _bannerCard(Map<String, dynamic> b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(
          context,
          b['route'] as String,
          arguments: b['arg'],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _bannerBgColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            b['image'] as String,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white24,
                size: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── SERVICES ────────────────────────────────────────────────────────────────

  Widget _serviceCard(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, s['route'], arguments: s['arg']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.withOpacity(.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 18,
              spreadRadius: -2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: s['bgColor'] as Color,
                shape: BoxShape.circle,
              ),
              child: Icon(s['icon'], color: s['iconColor'] as Color, size: 28),
            ),

            const SizedBox(height: 12),

            Text(
              s['label'],
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: .25,
              ),
            ),

            const SizedBox(height: 6),

            Expanded(
              child: Text(
                s['sub'],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: (s['comingSoon'] as bool)
                      ? AppColors.red
                      : AppColors.grey,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),

            if (s['comingSoon'] == true)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "SOON",
                  style: TextStyle(
                    color: AppColors.red,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── BOTTOM NAV ──────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    const items = [
      {'icon': Icons.home_rounded, 'label': 'HOME'},
      {'icon': Icons.receipt_long_outlined, 'label': 'MY REQUESTS'},
      {'icon': Icons.shield_outlined, 'label': 'AMC'},
      {'icon': Icons.notifications_outlined, 'label': 'ALERTS'},
      {'icon': Icons.person_outline, 'label': 'ACCOUNT'},
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: List.generate(items.length, (i) {
              final isSelected = _selectedNavIndex == i;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onNavTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        items[i]['icon'] as IconData,
                        color: isSelected ? AppColors.red : AppColors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i]['label'] as String,
                        style: TextStyle(
                          color: isSelected ? AppColors.red : AppColors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ─── LOCATION PICKER ─────────────────────────────────────────────────────────

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.greyLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select City',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.location_city, color: AppColors.red),
            title: const Text(
              'Ahmedabad',
              style: TextStyle(color: AppColors.navy, fontSize: 15),
            ),
            trailing: const Icon(
              Icons.check_circle,
              color: AppColors.red,
              size: 18,
            ),
            onTap: () {
              setState(() => _location = 'Ahmedabad, Gujarat');
              Navigator.pop(context);
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'More cities coming soon!',
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
