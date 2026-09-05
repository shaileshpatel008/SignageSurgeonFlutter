import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';

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
  Map<String, int> _requestCounts = {
    'inProgress': 0,
    'completed': 0,
    'amcActive': 0,
  };

  final PageController _bannerController = PageController();

  static const Color _bg = Color(0xFF0A1628);
  static const Color _card = Color(0xFF111F3A);

  final List<Map<String, dynamic>> _banners = [
    {
      'title': 'Need Repair?',
      'subtitle': 'We are here to fix it!',
      'cta': 'RAISE A REQUEST →',
      'bgColor': AppColors.yellow,
    },
    {
      'title': 'New Signage?',
      'subtitle': 'We design & install it!',
      'cta': 'GET A QUOTE →',
      'bgColor': AppColors.yellow,
    },
    {
      'title': 'AMC Plans',
      'subtitle': 'Protect your signage all year',
      'cta': 'EXPLORE PLANS →',
      'bgColor': AppColors.yellow,
    },
  ];

  final List<Map<String, dynamic>> _services = [
    {
      'icon': Icons.build_outlined,
      'label': 'REPAIRING',
      'sub': '',
      'comingSoon': false,
      'route': AppRoutes.createRequest,
      'arg': 'repairing',
    },
    {
      'icon': Icons.brush_outlined,
      'label': 'REBRANDING',
      'sub': '',
      'comingSoon': false,
      'route': AppRoutes.createRequest,
      'arg': 'rebranding',
    },
    {
      'icon': Icons.add_business_outlined,
      'label': 'NEW SIGNAGE',
      'sub': '',
      'comingSoon': false,
      'route': AppRoutes.createRequest,
      'arg': 'new_signage',
    },
    {
      'icon': Icons.cleaning_services_outlined,
      'label': 'SIGNAGE\nCLEANING',
      'sub': '',
      'comingSoon': false,
      'route': AppRoutes.createRequest,
      'arg': 'cleaning',
    },
    {
      'icon': Icons.shield_outlined,
      'label': 'AMC PLANS',
      'sub': 'Annual Maintenance\nContract',
      'comingSoon': false,
      'route': AppRoutes.amcPlans,
      'arg': null,
    },
    {
      'icon': Icons.storefront_outlined,
      'label': 'SIGN SHOPPY',
      'sub': 'Coming Soon',
      'comingSoon': true,
      'route': AppRoutes.comingSoon,
      'arg': null,
    },
  ];
@override
  void initState() {
    super.initState();
    _loadUserData();
    _autoScrollBanner();
  }
  void _autoScrollBanner() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      final next = (_currentBannerIndex + 1) % _banners.length;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
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
          _userName = data['name'] ?? data['businessName'] ?? '';
          _location = '${data['city'] ?? 'Ahmedabad'}, Gujarat';
        });
      }

      final requestsSnap = await FirebaseFirestore.instance
          .collection('service_requests')
          .where('userId', isEqualTo: user.uid)
          .get();

      int inProgress = 0, completed = 0;
      for (final r in requestsSnap.docs) {
        final status = r.data()['status'] ?? '';
        if (status == 'completed')
          completed++;
        else if (status != 'cancelled')
          inProgress++;
      }

      final amcSnap = await FirebaseFirestore.instance
          .collection('amc_contracts')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'active')
          .get();

      if (mounted) {
        setState(() {
          _requestCounts = {
            'inProgress': inProgress,
            'completed': completed,
            'amcActive': amcSnap.docs.length,
          };
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildBanner(),
                      const SizedBox(height: 28),
                      _buildServicesSection(),
                      const SizedBox(height: 28),
                      _buildMyRequestsSection(),
                      const SizedBox(height: 28),
                      _buildAmcReminders(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
        floatingActionButton: FloatingActionButton(
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.serviceRequest),
          backgroundColor: AppColors.yellow,
          elevation: 6,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: _bg, size: 32),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  // ─── TOP BAR ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.menu, color: Colors.white, size: 26),
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
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(' 👋', style: TextStyle(fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: _showLocationPicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: AppColors.yellow,
                        size: 13,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _location,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Stack(
            children: [
              _topIconBtn(Icons.notifications_outlined, () {}),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.yellow,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
            child: CircleAvatar(
              radius: 19,
              backgroundColor: _card,
              child: Text(
                _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topIconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  // ─── BANNER ─────────────────────────────────────────────────────────────────

  Widget _buildBanner() {
    return Column(
      children: [
        SizedBox(
          height: 155,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _currentBannerIndex = i),
            itemBuilder: (_, index) => _bannerCard(_banners[index]),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _banners.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentBannerIndex == i ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _currentBannerIndex == i
                    ? AppColors.yellow
                    : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bannerCard(Map<String, dynamic> b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: b['bgColor'],
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 12, 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    b['title'],
                    style: const TextStyle(
                      color: _bg,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b['subtitle'],
                    style: TextStyle(
                      color: _bg.withOpacity(0.65),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.serviceRequest),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        b['cta'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Image.asset(
                'assets/images/mascot.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.storefront,
                  size: 80,
                  color: Color(0x330A1628),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SERVICES ────────────────────────────────────────────────────────────────

  Widget _buildServicesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Our Services',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _services.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (_, i) => _serviceCard(_services[i]),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, s['route'], arguments: s['arg']),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(s['icon'], color: AppColors.yellow, size: 30),
            const SizedBox(height: 10),
            Text(
              s['label'],
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                height: 1.4,
              ),
            ),
            if ((s['sub'] as String).isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                s['sub'],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: s['comingSoon']
                      ? const Color(0xFFFFA500)
                      : Colors.white38,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── MY REQUESTS ─────────────────────────────────────────────────────────────

  Widget _buildMyRequestsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Requests',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: _requestStatColumn(
                    icon: Icons.receipt_long_outlined,
                    iconColor: AppColors.yellow,
                    value: _requestCounts['inProgress']!.toString().padLeft(
                      2,
                      '0',
                    ),
                    label: 'In Progress',
                    valueColor: AppColors.yellow,
                  ),
                ),
                _verticalDivider(),
                Expanded(
                  child: _requestStatColumn(
                    icon: Icons.check_circle_outline,
                    iconColor: AppColors.green,
                    value: _requestCounts['completed']!.toString().padLeft(
                      2,
                      '0',
                    ),
                    label: 'Completed',
                    valueColor: AppColors.green,
                  ),
                ),
                _verticalDivider(),
                Expanded(
                  child: _requestStatColumn(
                    icon: Icons.shield_outlined,
                    iconColor: const Color(0xFF4B7BFF),
                    value: _requestCounts['amcActive']!.toString().padLeft(
                      2,
                      '0',
                    ),
                    label: 'AMC Active',
                    valueColor: const Color(0xFF4B7BFF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(width: 1, height: 60, color: Colors.white12);
  }

  Widget _requestStatColumn({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required Color valueColor,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  // ─── AMC REMINDERS ───────────────────────────────────────────────────────────

  Widget _buildAmcReminders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AMC Reminders',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('amc_contracts')
                .where('userId', isEqualTo: user.uid)
                .where('status', isEqualTo: 'active')
                .limit(3)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _amcEmptyState();
              }
              return Column(
                children: snapshot.data!.docs
                    .map(
                      (doc) =>
                          _amcReminderTile(doc.data() as Map<String, dynamic>),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _amcEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'No active AMC contracts yet',
        style: TextStyle(color: Colors.white38, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _amcReminderTile(Map<String, dynamic> data) {
    final siteName = data['siteName'] ?? 'Signage AMC';
    final nextVisit = data['nextVisitDate'] as Timestamp?;
    final daysLeft = nextVisit != null
        ? nextVisit.toDate().difference(DateTime.now()).inDays
        : null;

    final daysLabel = daysLeft != null ? 'In $daysLeft Days' : 'Scheduled';
    final daysColor = daysLeft != null && daysLeft <= 7
        ? AppColors.red
        : const Color(0xFF4B7BFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.yellow.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: AppColors.yellow,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  siteName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  nextVisit != null
                      ? 'Next Visit: ${_formatDateShort(nextVisit.toDate())}'
                      : 'Next visit TBD',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: daysColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              daysLabel,
              style: TextStyle(
                color: daysColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        ],
      ),
    );
  }

  String _formatDateShort(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // ─── BOTTOM NAV ──────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: _card,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      elevation: 12,
      child: SizedBox(
        height: 62,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_rounded, 'HOME', 0),
            _navItem(Icons.receipt_long_outlined, 'MY JOBS', 1),
            const SizedBox(width: 48),
            _navItem(Icons.shield_outlined, 'AMC', 2),
            _navItem(Icons.person_outline, 'PROFILE', 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedNavIndex = index);
        switch (index) {
          case 1:
            Navigator.pushNamed(context, AppRoutes.requests);
            break;
          case 2:
            Navigator.pushNamed(context, AppRoutes.amc);
            break;
          case 3:
            Navigator.pushNamed(context, AppRoutes.profile);
            break;
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isSelected ? AppColors.yellow : Colors.white38,
            size: 22,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.yellow : Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ─── LOCATION PICKER ─────────────────────────────────────────────────────────

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
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
              color: Colors.white24,
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
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.location_city, color: AppColors.yellow),
            title: const Text(
              'Ahmedabad',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            trailing: const Icon(
              Icons.check_circle,
              color: AppColors.yellow,
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
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
