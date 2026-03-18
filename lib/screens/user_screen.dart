import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  @override
  Widget build(BuildContext context) {
    // If not logged in, show login screen
    if (!AuthService.isLoggedIn) {
      return LoginScreen(
        onLoginSuccess: () {
          setState(() {}); // Refresh to show profile
        },
      );
    }

    // If logged in, show profile
    return _buildProfileView();
  }

  Widget _buildProfileView() {
      final user = AuthService.currentUser!;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // 1. Profile Avatar (First letter of Name)
            CircleAvatar(
              radius: 50,
              backgroundColor: AppColors.primary,
              child: Text(
                // FIX: Use 'name' instead of 'username' or 'full_name'
                (user['name'] ?? 'U')[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 2. User Name Display
            Text(
              // FIX: Use 'name'
              user['name'] ?? 'User',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            // 3. Email Display
            Text(
              // FIX: Use 'email' (This matches login.php line 92)
              user['email'] ?? '',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 24),

            // 4. Account Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACCOUNT INFO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // FIX ALL KEYS BELOW:
                    _buildInfoRow(Icons.person, 'Username', user['name'] ?? 'N/A'),
                    const Divider(),
                    _buildInfoRow(Icons.email, 'Email', user['email'] ?? 'N/A'),
                    const Divider(),
                    _buildInfoRow(Icons.phone, 'Phone', user['contact'] ?? 'Not set'),
                  ],
                ),
              ),
            ),
            
          // ... (Rest of the file remains unchanged)

          const SizedBox(height: 16),

          // Settings Card
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bluetooth, color: AppColors.primary),
                  title: const Text('Bluetooth'),
                  subtitle: const Text('Manage connections'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bluetooth settings coming soon...')),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications, color: AppColors.primary),
                  title: const Text('Notifications'),
                  subtitle: const Text('Configure alerts'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notification settings coming soon...')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Logout Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _handleLogout(),
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('Logout', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              AuthService.logout();
              setState(() {}); // Refresh to show login
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}