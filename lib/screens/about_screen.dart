import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          // Logo / Icon Container
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EAF6), // Light indigo background
              shape: BoxShape.circle,
            ),
            // CHANGED: Simple Gear Icon (No stars)
            child: const Icon(
              Icons.settings, 
              size: 80,
              color: Color(0xFF3F51B5), // Indigo color
            ),
          ),
          const SizedBox(height: 24),
          
          // CHANGED: Fixed Typo "Vortex"
          const Text(
            'Vortex Labs',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3F51B5),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Version Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFC5CAE9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Version 1.0.0',
              style: TextStyle(
                color: Color(0xFF3F51B5),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          const Text(
            'Motorized Valve Control System',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Text(
            'Monitor and control your motorized valves remotely via Bluetooth.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          
          const SizedBox(height: 40),
          
          // Feature List
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50], // Very light grey
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildFeatureRow(Icons.bluetooth, 'Bluetooth Connectivity'),
                const SizedBox(height: 16),
                _buildFeatureRow(Icons.speed, 'Real-time Monitoring'),
                const SizedBox(height: 16),
                _buildFeatureRow(Icons.schedule, 'Scheduled Operations'),
                const SizedBox(height: 16),
                _buildFeatureRow(Icons.notifications_active, 'Smart Alerts'),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Copyright
          const Text(
            '© 2025 Vortex Labs',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Helper widget to build the feature rows

// Helper widget to build the feature rows
  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF3F51B5)),
        const SizedBox(width: 16),
        // FIX: Wrapped Text in Expanded to prevent overflow
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 16),
            overflow: TextOverflow.ellipsis, // Adds "..." if it's still too long
          ),
        ),
      ],
    );
  }
}