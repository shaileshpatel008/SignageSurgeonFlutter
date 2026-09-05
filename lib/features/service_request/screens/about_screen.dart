import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
          _heroCard(),
          const SizedBox(height: 20),
          _statsRow(),
          const SizedBox(height: 28),

          _sectionLabel('Our Story'),
          const SizedBox(height: 12),
          _paragraphCard(
            'We noticed a simple problem: businesses struggled to find reliable signage service '
            'providers. So we built a platform that brings everything under one roof — verified '
            'experts, transparent pricing, and real-time tracking.\n\n'
            'We don\'t just fix signs, we protect your brand identity. That\'s The Signage Surgeon.',
          ),

          const SizedBox(height: 24),
          _sectionLabel('Our Vision'),
          const SizedBox(height: 12),
          _paragraphCard(
            'To become India\'s most trusted signage service ecosystem, delivering world-class '
            'solutions that help businesses create stronger, safer, and more impactful brand experiences.',
          ),

          const SizedBox(height: 24),
          _sectionLabel('Our Mission'),
          const SizedBox(height: 12),
          _paragraphCard(
            'To provide businesses with a complete, reliable, and technology-driven signage platform '
            'that simplifies design, manufacturing, installation, maintenance, and lifecycle management '
            'through one professional network.',
          ),

          const SizedBox(height: 24),
          _sectionLabel('Our Values'),
          const SizedBox(height: 12),
          _valuesGrid(),

          const SizedBox(height: 24),
          _sectionLabel('Why Businesses Trust Us'),
          const SizedBox(height: 12),
          _trustList(),

          const SizedBox(height: 24),
          _sectionLabel('Our Ecosystem'),
          const SizedBox(height: 12),
          _ecosystemCard(),

          const SizedBox(height: 28),
          _ctaCard(context),
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
      title: const Text('About Us', style: TextStyle(color: AppColors.navy, fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }

  Widget _heroCard() {
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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('More Than Signage.', style: TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
          Text('We Protect Your Brand Identity.', style: TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
          SizedBox(height: 10),
          Text(
            'Every sign tells a story — it welcomes customers, strengthens your brand, and represents '
            'your business every hour of every day. We don\'t just manufacture or repair signage; we '
            'make sure it keeps performing and representing you with confidence.',
            style: TextStyle(color: AppColors.navy, fontSize: 12.5, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final stats = [
      {'value': '20+', 'label': 'Years of\nExperience'},
      {'value': '5000+', 'label': 'Clients\nServed'},
      {'value': '100+', 'label': 'Multiple\nIndustries'},
    ];
    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: [
                Text(s['value']!, style: const TextStyle(color: AppColors.yellowDark, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(s['label']!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.3)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _paragraphCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Text(text, style: const TextStyle(color: AppColors.navy, fontSize: 13, height: 1.6)),
    );
  }

  Widget _valuesGrid() {
    final values = [
      {'icon': Icons.verified_outlined, 'title': 'Reliability', 'desc': 'We deliver what we promise, on time, every time.'},
      {'icon': Icons.workspace_premium_outlined, 'title': 'Quality', 'desc': 'High standards in service, materials and workmanship.'},
      {'icon': Icons.favorite_outline, 'title': 'Customer First', 'desc': 'Your satisfaction is at the heart of everything we do.'},
      {'icon': Icons.lightbulb_outline, 'title': 'Innovation', 'desc': 'Smart solutions for modern brand challenges.'},
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.05),
      itemBuilder: (_, i) {
        final v = values[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(v['icon'] as IconData, color: AppColors.yellowDark, size: 22),
              const SizedBox(height: 8),
              Text(v['title'] as String, style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(v['desc'] as String, style: const TextStyle(color: AppColors.grey, fontSize: 10.5, height: 1.4)),
            ],
          ),
        );
      },
    );
  }

  Widget _trustList() {
    final items = [
      '25+ Years of Branding & Creative Expertise',
      '20+ Years of In-House Signage Manufacturing',
      'Complete Design-to-Installation Solutions',
      'Professional Repair & Preventive Maintenance',
      'Dedicated AMC Programs for Businesses',
      'Corporate & Multi-Location Project Management',
      'Technology-Driven Service Management',
      'One Trusted Partner for the Complete Signage Lifecycle',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.yellowDark, size: 15),
              const SizedBox(width: 10),
              Expanded(child: Text(item, style: const TextStyle(color: AppColors.navy, fontSize: 12.5))),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _ecosystemCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Powered by Experience. Built for Excellence.', style: TextStyle(color: AppColors.grey, fontSize: 11, fontStyle: FontStyle.italic)),
          const SizedBox(height: 14),
          _ecosystemRow('Concept3 The Design Workshop', 'Brand Strategy • Design • Creative Communication • Project Management'),
          const Divider(color: AppColors.cardBorder, height: 22),
          _ecosystemRow('Just Stroke', 'In-House Manufacturing • Fabrication • Installation • Engineering'),
          const Divider(color: AppColors.cardBorder, height: 22),
          _ecosystemRow('The Signage Surgeon', 'Repair • Rebranding • New Signage • Cleaning • AMC • Sign Shoppy'),
        ],
      ),
    );
  }

  Widget _ecosystemRow(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.navy, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppColors.grey, fontSize: 11.5, height: 1.4)),
      ],
    );
  }

  Widget _ctaCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Want to Work With Us?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Let\'s talk about your signage project.', style: TextStyle(color: Color(0xFFB8C0CC), fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _launch('https://www.thesignagesurgeon.com/contact-us'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.navy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('GET IN TOUCH', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}