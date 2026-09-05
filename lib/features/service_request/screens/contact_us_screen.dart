import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  static const String _email1 = 'mail@thesignagesurgeon.com';
  static const String _email2 = 'signagesurgeon@gmail.com';
  static const String _phone = '+918141004505';
  static const String _phoneDisplay = '+91 81410 04505';

  static const String _youtube = 'https://www.youtube.com/@thesignagesurgeon';
  static const String _facebook = 'https://www.facebook.com/people/The-Signage-surgeon/61591978133154/';
  static const String _instagram = 'https://www.instagram.com/thesignagesurgeon/';

  static const String _officeAddress =
      '409, Harvy-Himalaya Complex, Tarun Nagar Part 2, Memnagar, Ahmedabad, Gujarat 380052';
  static const String _workshopAddress =
      'F-16, Ravi Estate, Opp. Gurudwara, Dhudheshwar Road, Shahibaug, Ahmedabad, Gujarat - 380004';

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _buildAppBar(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          _headerCard(),
          const SizedBox(height: 24),

          _sectionLabel('Get in Touch'),
          const SizedBox(height: 12),
          _contactTile(
            icon: Icons.email_outlined,
            label: 'Email',
            value: _email1,
            onTap: () => _launch('mailto:$_email1'),
          ),
          const SizedBox(height: 10),
          _contactTile(
            icon: Icons.email_outlined,
            label: 'Email (Alt.)',
            value: _email2,
            onTap: () => _launch('mailto:$_email2'),
          ),
          const SizedBox(height: 10),
          _contactTile(
            icon: Icons.phone_outlined,
            label: 'Call Us',
            value: _phoneDisplay,
            onTap: () => _launch('tel:$_phone'),
          ),

          const SizedBox(height: 28),
          _sectionLabel('Follow Us'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _socialCard(icon: Icons.play_circle_outline, label: 'YouTube', onTap: () => _launch(_youtube))),
              const SizedBox(width: 10),
              Expanded(child: _socialCard(icon: Icons.facebook_outlined, label: 'Facebook', onTap: () => _launch(_facebook))),
              const SizedBox(width: 10),
              Expanded(child: _socialCard(icon: Icons.camera_alt_outlined, label: 'Instagram', onTap: () => _launch(_instagram))),
            ],
          ),

          const SizedBox(height: 28),
          _sectionLabel('Visit Us'),
          const SizedBox(height: 12),
          _locationCard(
            icon: Icons.business_outlined,
            title: 'Office',
            address: _officeAddress,
          ),
          const SizedBox(height: 12),
          _locationCard(
            icon: Icons.build_outlined,
            title: 'Workshop',
            address: _workshopAddress,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.offWhite,
      elevation: 0,
      centerTitle: true,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navy, size: 16),
        ),
      ),
      title: const Text('Contact Us', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.yellow, Color(0xFFFFD54A)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.support_agent, color: AppColors.navy, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('We\'re here to help', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text('Reach out anytime — call, email, or visit us.', style: TextStyle(color: AppColors.navy, fontSize: 11.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _contactTile({required IconData icon, required String label, required String value, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.yellowDark, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.greyLight, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _socialCard({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.yellowDark, size: 24),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _locationCard({required IconData icon, required String title, required String address}) {
    return GestureDetector(
      onTap: () => _launch('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.yellowDark, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(address, style: const TextStyle(color: AppColors.grey, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, color: AppColors.greyLight, size: 16),
          ],
        ),
      ),
    );
  }
}