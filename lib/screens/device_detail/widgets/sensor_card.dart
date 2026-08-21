import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

import '../../../widgets/glass/glass.dart';

// =============================================================================
// SENSOR CARD
// =============================================================================
// Placeholder UI for the future sensor mode. The current implementation just
// shows a fake "Add sensor" panel and upper/lower limit fields. The Save
// button shows a dummy snackbar — no real persistence yet.
// =============================================================================

class SensorCard extends StatelessWidget {
  const SensorCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─────────────────────────────────────────────────────────────
            // Header
            // ─────────────────────────────────────────────────────────────
            const Text(
              'Sensor Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),

            const SizedBox(height: 16),

            // ─────────────────────────────────────────────────────────────
            // "+ Add sensor" placeholder box
            // ─────────────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '+ Add sensor',
                  style: TextStyle(color: GlassTokens.primary),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ─────────────────────────────────────────────────────────────
            // Upper limit field
            // ─────────────────────────────────────────────────────────────
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Upper limit')),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '80',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ─────────────────────────────────────────────────────────────
            // Lower limit field
            // ─────────────────────────────────────────────────────────────
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Lower limit')),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '60',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ─────────────────────────────────────────────────────────────
            // Save button (placeholder snackbar only)
            // ─────────────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sensor settings saved!')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
