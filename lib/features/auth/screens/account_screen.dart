import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/push_notification_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Map<String, dynamic>? _profileData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() {
          _profileData = doc.data();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _displayName =>
      _profileData?['fullName'] ?? _profileData?['name'] ?? 'User';

  String get _businessName => _profileData?['businessName'] ?? '';

  String get _phone {
    final user = FirebaseAuth.instance.currentUser;
    final phone = user?.phoneNumber ?? '';
    return phone.startsWith('+91') ? phone.substring(3) : phone;
  }

  String get _avatarLetter =>
      _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U';

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.yellow),
                )
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      // ── HEADER ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new,
                                  color: AppColors.navy,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Text(
                              'Account',
                              style: TextStyle(
                                color: AppColors.navy,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── PROFILE CARD ──
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GestureDetector(
                          onTap: () async {
                            await Navigator.pushNamed(
                              context,
                              AppRoutes.editProfile,
                            );
                            _loadProfile();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: AppColors.yellow,
                                    shape: BoxShape.circle,
                                    image:
                                        (_profileData?['photoUrl'] != null &&
                                            (_profileData!['photoUrl']
                                                    as String)
                                                .isNotEmpty)
                                        ? DecorationImage(
                                            image: NetworkImage(
                                              _profileData!['photoUrl']
                                                  as String,
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child:
                                      (_profileData?['photoUrl'] != null &&
                                          (_profileData!['photoUrl'] as String)
                                              .isNotEmpty)
                                      ? null
                                      : Center(
                                          child: Text(
                                            _avatarLetter,
                                            style: const TextStyle(
                                              color: AppColors.navy,
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _displayName,
                                        style: const TextStyle(
                                          color: AppColors.navy,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (_businessName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _businessName,
                                          style: const TextStyle(
                                            color: AppColors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.phone_outlined,
                                            color: AppColors.grey,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '+91 $_phone',
                                            style: const TextStyle(
                                              color: AppColors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.yellow.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Edit',
                                    style: TextStyle(
                                      color: AppColors.yellowDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── MY ACTIVITY ──
                      _sectionHeader('My Activity'),
                      _menuGroup([
                        _menuItem(
                          icon: Icons.receipt_long_outlined,
                          iconColor: const Color(0xFF4B7BFF),
                          label: 'My Requests',
                          subtitle: 'Track and manage service requests',
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.myRequests,
                          ),
                        ),
                        _menuItem(
                          icon: Icons.shield_outlined,
                          iconColor: AppColors.green,
                          label: 'AMC Plans',
                          subtitle: 'View active and past AMC contracts',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.amc),
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // ── ACCOUNT SETTINGS ──
                      _sectionHeader('Account'),
                      _menuGroup([
                        _menuItem(
                          icon: Icons.person_outline,
                          iconColor: const Color(0xFF9B6BFF),
                          label: 'My Profile',
                          subtitle: 'Edit your personal & business info',
                          onTap: () async {
                            await Navigator.pushNamed(
                              context,
                              AppRoutes.editProfile,
                            );
                            _loadProfile();
                          },
                        ),
                        _menuItem(
                          icon: Icons.location_on_outlined,
                          iconColor: AppColors.red,
                          label: 'Manage Addresses',
                          subtitle: 'Add or update your saved addresses',
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.manageAddresses,
                          ),
                        ),
                        _menuItem(
                          icon: Icons.settings_outlined,
                          iconColor: AppColors.grey,
                          label: 'Settings',
                          subtitle: 'Notifications, preferences & more',
                          onTap: () {},
                          comingSoon: true,
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // ── SUPPORT ──
                      _sectionHeader('Support'),
                      _menuGroup([
                        _menuItem(
                          icon: Icons.currency_rupee_outlined,
                          iconColor: AppColors.yellowDark,
                          label: 'My Refund Requests',
                          subtitle: 'Track the status of your refund requests',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.myRefundRequests),
                        ),
                        _menuItem(
                          icon: Icons.support_agent_outlined,
                          iconColor: AppColors.red,
                          label: 'My Support Tickets',
                          subtitle: 'Track issues you\'ve reported',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.mySupportTickets),
                        ),
                        _menuItem(
                          icon: Icons.phone_in_talk_outlined,
                          iconColor: AppColors.green,
                          label: 'Contact Us',
                          subtitle: 'Call or WhatsApp our team',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.contactUs),
                        ),
                        _menuItem(
                          icon: Icons.info_outline,
                          iconColor: const Color(0xFF4B7BFF),
                          label: 'About The Signage Surgeon',
                          subtitle: 'Our story, version & legal',
                          onTap: () =>
                              Navigator.pushNamed(context, AppRoutes.aboutUs),
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // ── LOGOUT ──
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GestureDetector(
                          onTap: () => _confirmLogout(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.red.withOpacity(0.25),
                                width: 1,
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.logout,
                                  color: AppColors.red,
                                  size: 22,
                                ),
                                SizedBox(width: 14),
                                Text(
                                  'Log Out',
                                  style: TextStyle(
                                    color: AppColors.red,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.grey,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _menuGroup(List<Widget> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          return Column(
            children: [
              items[i],
              if (i < items.length - 1)
                const Divider(
                  height: 1,
                  color: AppColors.greyLight,
                  indent: 56,
                  endIndent: 0,
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool comingSoon = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (comingSoon)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SOON',
                  style: TextStyle(
                    color: AppColors.grey,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              )
            else
              const Icon(
                Icons.chevron_right,
                color: AppColors.greyLight,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.greyLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.logout, color: AppColors.red, size: 36),
            const SizedBox(height: 14),
            const Text(
              'Log Out?',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You will need to log in again with your mobile number.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey, fontSize: 13),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context); // close sheet
                  NotificationService.instance.stop();
                  await PushNotificationService.instance.clearToken();
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRoutes.login,
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'YES, LOG OUT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}