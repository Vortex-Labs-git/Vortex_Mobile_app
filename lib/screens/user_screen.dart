import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';
import 'login/login_screen.dart';
import 'main/main_screen.dart';

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
          // Replace entire navigation stack with fresh MainScreen
          // This ensures HomeScreen re-initializes with WebSocket connected
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        },
      );
    }

    // If logged in, show profile
    return _buildProfileView();
  }

  Widget _buildProfileView() {
    final user = AuthService.currentUser!;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        // Clear the translucent bottom nav this tab scrolls under.
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // 1. Profile Avatar (First letter of Name)
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: GlassTokens.accentGradient,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: GlassTokens.primary.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Center(
              child: Text(
                // FIX: Use 'name' instead of 'username' or 'full_name'
                (user['name'] ?? 'U')[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
              color: GlassTokens.textPrimary,
            ),
          ),

          // 3. Email Display
          Text(
            // FIX: Use 'email' (This matches login.php line 92)
            user['email'] ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: GlassTokens.textSecondary,
            ),
          ),

          const SizedBox(height: 24),

          // 4. Account Info Card
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ACCOUNT INFO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: GlassTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                // FIX ALL KEYS BELOW:
                _buildInfoRow(Icons.person, 'Username', user['name'] ?? 'N/A'),
                _glassDivider(),
                _buildInfoRow(Icons.email, 'Email', user['email'] ?? 'N/A'),
                _glassDivider(),
                _buildInfoRow(Icons.phone, 'Phone', user['contact'] ?? 'Not set'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 5. Change Password Button
          GlassGhostButton(
            label: 'Change Password',
            icon: Icons.lock_outline,
            onPressed: _handleChangePassword,
          ),

          const SizedBox(height: 12),

          // 6. Logout Button
          GlassButton(
            label: 'Logout',
            icon: Icons.logout,
            color: GlassTokens.danger,
            onPressed: _handleLogout,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Hairline that reads as a seam in the glass rather than a grey rule.
  Widget _glassDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white.withValues(alpha: 0.55),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: GlassTokens.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
            ),
            child: Icon(icon, color: GlassTokens.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: GlassTokens.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    color: GlassTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleChangePassword() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    bool isLoading = false;
    String? errorText;

    showGlassDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return GlassDialog(
              title: 'Change Password',
              icon: Icons.lock_reset,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPasswordController,
                    obscureText: true,
                    decoration: glassInputDecoration(
                      labelText: 'Old Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: glassInputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_open_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: glassInputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: const Icon(Icons.check_circle_outline),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Color.lerp(GlassTokens.danger, Colors.black, 0.25),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                GlassButton(
                  label: 'Change Password',
                  fullWidth: false,
                  height: 44,
                  isLoading: isLoading,
                  onPressed: isLoading
                      ? null
                      : () async {
                          final oldPass = oldPasswordController.text.trim();
                          final newPass = newPasswordController.text.trim();
                          final confirmPass =
                              confirmPasswordController.text.trim();

                          // Validation
                          if (oldPass.isEmpty ||
                              newPass.isEmpty ||
                              confirmPass.isEmpty) {
                            setDialogState(
                                () => errorText = 'All fields are required');
                            return;
                          }
                          if (newPass.length < 6) {
                            setDialogState(() => errorText =
                                'New password must be at least 6 characters');
                            return;
                          }
                          if (newPass != confirmPass) {
                            setDialogState(() =>
                                errorText = 'New passwords do not match');
                            return;
                          }
                          if (newPass == oldPass) {
                            setDialogState(() => errorText =
                                'New password must differ from the old one');
                            return;
                          }

                          // Send request
                          setDialogState(() {
                            isLoading = true;
                            errorText = null;
                          });

                          final result = await AuthService.changePassword(
                              oldPass, newPass);

                          if (result['success'] == true) {
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['message'] ??
                                      'Password changed successfully'),
                                  backgroundColor: GlassTokens.success,
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isLoading = false;
                              errorText = result['message'] ??
                                  'Failed to change password';
                            });
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleLogout() {
    showGlassDialog(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: 'Logout',
        icon: Icons.logout,
        tint: GlassTokens.danger,
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          GlassButton(
            label: 'Logout',
            color: GlassTokens.danger,
            fullWidth: false,
            height: 44,
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              await AuthService.logout(); // Wait for logout to complete
              if (mounted) {
                // Replace entire navigation stack with fresh MainScreen
                // This ensures all pages (Home, User, etc.) rebuild with logged-out state
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}