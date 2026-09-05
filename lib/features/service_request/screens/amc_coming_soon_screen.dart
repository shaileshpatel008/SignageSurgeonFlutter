import 'package:flutter/material.dart';

class AmcComingSoonScreen extends StatelessWidget {
  const AmcComingSoonScreen({super.key});

  static const Color _bg     = Color(0xFF0A1628);
  static const Color _card   = Color(0xFF111F3A);
  static const Color _yellow = Color(0xFFFFD700);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AMC Plans',
          style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: const BoxDecoration(
                  color: _card,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined,
                    color: _yellow, size: 56),
              ),
              const SizedBox(height: 28),
              const Text(
                'AMC Plans',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Annual Maintenance Contract plans are coming soon. We\'ll notify you when they\'re available.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF8A9BB8), fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _yellow,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Go Back',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}