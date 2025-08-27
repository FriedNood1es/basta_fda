import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.center_focus_strong, size: 80, color: Colors.grey),
            const SizedBox(height: 40),
            const Text(
              'Welcome to basta:FDA',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text('A product scanner App'),
            const SizedBox(height: 30),
            Placeholder(fallbackHeight: 100, fallbackWidth: 100), // App Logo placeholder
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15)),
              child: const Text('Get Started', style: TextStyle(fontSize: 18)),
            )
          ],
        ),
      ),
    );
  }
}
