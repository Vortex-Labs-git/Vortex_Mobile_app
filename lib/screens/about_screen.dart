import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const List<Map<String, String>> _values = [
    {
      'title': 'Innovation',
      'body':
          'Continuously developing smarter technologies to solve real-world challenges.',
    },
    {
      'title': 'Engineering Excellence',
      'body':
          'Building reliable, high-quality products with precision and performance.',
    },
    {
      'title': 'Local Empowerment',
      'body':
          'Supporting Sri Lanka\'s technological independence through locally developed solutions.',
    },
    {
      'title': 'Customer Success',
      'body':
          'Designing solutions that create measurable value for our customers.',
    },
    {
      'title': 'Sustainability',
      'body':
          'Developing technologies that promote efficient use of resources and long-term environmental responsibility.',
    },
    {
      'title': 'Integrity',
      'body':
          'Conducting business with honesty, transparency, and accountability.',
    },
    {
      'title': 'Versatility',
      'body':
          'Adapting our expertise to meet the evolving needs of agriculture, industry, and emerging technologies.',
    },
    {
      'title': 'Continuous Improvement',
      'body':
          'Learning, innovating, and evolving to stay ahead in a rapidly changing technological landscape.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    // Transparent: this tab sits on MainScreen's gradient backdrop.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        30 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // ── Logo, seated in a glass ring ──
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.45),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                boxShadow: GlassTokens.paneShadow(y: 12, blurRadius: 30),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.jpeg',
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: GlassTokens.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'logo',
                        style: TextStyle(
                          fontSize: 18,
                          color: GlassTokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

            const SizedBox(height: 28),

            // ── About Us Card ──
            _buildCard(
              icon: Icons.info_outline,
              title: 'About Us',
              body:
                  'VorteX Labs is an innovation-driven technology company based '
                  'in Sri Lanka, dedicated to developing intelligent automation '
                  'and IoT solutions for agriculture, industry, and beyond. We '
                  'build integrated hardware and software platforms that '
                  'simplify monitoring, control, and automation, helping '
                  'businesses operate more efficiently and intelligently.\n\n'
                  'With expertise spanning IoT, artificial intelligence, '
                  'embedded systems, PCB design and manufacturing, 3D printing, '
                  'and custom software development, we deliver scalable, '
                  'locally engineered solutions designed to meet the evolving '
                  'needs of modern industries while driving technological '
                  'innovation.',
            ),

            const SizedBox(height: 20),

            // ── Our Mission Card ──
            _buildCard(
              icon: Icons.build_outlined,
              title: 'Our Mission',
              body:
                  'To strengthen Sri Lanka\'s technological and economic growth '
                  'by developing innovative, locally engineered IoT, '
                  'automation, and AI solutions that reduce dependence on '
                  'imported technologies while empowering businesses through '
                  'smarter, more efficient operations.',
            ),

            const SizedBox(height: 20),

            // ── Our Vision Card ──
            _buildCard(
              icon: Icons.thumb_up_outlined,
              title: 'Our Vision',
              body:
                  'To become a globally recognized leader in automation and '
                  'intelligent technology, delivering sustainable, high-quality '
                  'solutions that transform agriculture, industry, and everyday '
                  'life through innovation developed in Sri Lanka.',
            ),

            const SizedBox(height: 20),

            // ── Our Values Card ──
            _buildValuesCard(),

            const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cardIcon(icon),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: GlassTokens.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: const TextStyle(
              fontSize: 15,
              color: GlassTokens.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Small tinted tile behind each section icon — keeps the headings anchored
  /// when the card is translucent.
  static Widget _cardIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: GlassTokens.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
      ),
      child: Icon(icon, color: GlassTokens.primary, size: 22),
    );
  }

  Widget _buildValuesCard() {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _cardIcon(Icons.star_outline),
              const SizedBox(width: 12),
              const Text(
                'Our Values',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: GlassTokens.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'At VorteX Labs, our work is guided by the principles that define '
            'who we are:',
            style: TextStyle(
              fontSize: 15,
              color: GlassTokens.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ..._values.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: GlassTokens.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 15,
                          color: GlassTokens.textSecondary,
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(
                            text: '${v['title']} – ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: GlassTokens.textPrimary,
                            ),
                          ),
                          TextSpan(text: v['body']),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}