import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/glass/glass.dart';
import 'widgets/login_icon.dart';
import 'widgets/login_error.dart';
import 'widgets/login_username_field.dart';
import 'widgets/login_password_field.dart';
import 'widgets/login_button.dart';
import 'widgets/forgot_password_button.dart';

// =============================================================================
// LOGIN SCREEN
// =============================================================================
// Composes the login UI from small widgets in widgets/ and owns the screen
// state (controllers, loading flag, error message). Calls [onLoginSuccess]
// callback when authentication succeeds.
// =============================================================================

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ---------------------------------------------------------------------------
  // SECTION 1: STATE VARIABLES
  // ---------------------------------------------------------------------------

  // -- Text Controllers --
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // -- UI State Flags --
  bool _isLoading = false;

  // -- Error State --
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // SECTION 2: LIFECYCLE METHODS
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SECTION 3: LOGIN HANDLER
  // ---------------------------------------------------------------------------
  // Validates user input, calls AuthService.login(), and either fires the
  // success callback or shows an error message.
  // ---------------------------------------------------------------------------

  Future<void> _handleLogin() async {
    // Step 3.1: Read input values
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Step 3.2: Validate input is not empty
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter username and password';
      });
      return;
    }

    // Step 3.3: Show loading state, clear previous errors
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Step 3.4: Call authentication service
    final result = await AuthService.login(username, password);

    // Step 3.5: Hide loading state
    setState(() {
      _isLoading = false;
    });

    // Step 3.6: Handle login result
    if (result['success'] == true) {
      widget.onLoginSuccess();
    } else {
      setState(() {
        _errorMessage = result['message'] ?? 'Login failed';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // SECTION 4: BUILD METHOD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          // Clear the translucent bottom nav this tab sits behind.
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassCard(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 4.1  Header icon
                const LoginIcon(),

                const SizedBox(height: 28),

                // 4.2  Error banner (only when there is an error)
                if (_errorMessage != null) LoginError(message: _errorMessage!),

                // 4.3  Username field
                LoginUsernameField(controller: _usernameController),

                const SizedBox(height: 16),

                // 4.4  Password field
                LoginPasswordField(
                  controller: _passwordController,
                  onSubmitted: _handleLogin,
                ),

                const SizedBox(height: 24),

                // 4.5  Sign In button
                LoginButton(
                  isLoading: _isLoading,
                  onPressed: _handleLogin,
                ),

                const SizedBox(height: 8),

                // 4.6  Forgot password link
                const ForgotPasswordButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
