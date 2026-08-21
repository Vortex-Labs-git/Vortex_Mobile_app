import 'package:flutter/material.dart';
import '../../theme/glass_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/glass/glass.dart';

// Tab screens
import '../home/home_screen.dart';
import '../user_screen.dart';
import '../about_screen.dart';
import '../manual_screen.dart';

// Local widgets
import 'widgets/main_app_bar.dart';
import 'widgets/main_bottom_nav.dart';
import 'widgets/add_device_fab.dart';

// =============================================================================
// MAIN SCREEN
// =============================================================================
// Top-level shell holding the 4 tabs (Home / User / Manual / About) inside an
// IndexedStack. Owns the current tab index, the FAB's add-device dialog, and
// the navigation between tabs. Each tab screen below the IndexedStack manages
// its own state independently.
// =============================================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // ---------------------------------------------------------------------------
  // SECTION 1: STATE VARIABLES
  // ---------------------------------------------------------------------------

  // -- Current tab index (0=Home, 1=User, 2=Manual, 3=About) --
  int _currentIndex = 0;

  // -- Tab screens kept alive by IndexedStack --
  final List<Widget> _pages = [
    const HomeScreen(),
    const UserScreen(),
    const ManualScreen(),
    const AboutScreen(),
  ];

  // ---------------------------------------------------------------------------
  // SECTION 2: ADD DEVICE DIALOG
  // ---------------------------------------------------------------------------
  // Triggered by the FAB on the Home tab. Currently a placeholder — captures
  // a name and shows a snackbar. Real backend hookup is still pending.

  void _showAddDeviceDialog(BuildContext context) {
    final nameController = TextEditingController();

    showGlassDialog(
      context: context,
      builder: (dialogContext) => GlassDialog(
        title: AppStrings.addDevice,
        icon: Icons.add_circle_outline,
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: glassInputDecoration(
            labelText: 'Device Name',
            hintText: 'e.g., Main Valve',
            prefixIcon: const Icon(Icons.label_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          GlassButton(
            label: 'Add',
            fullWidth: false,
            height: 44,
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Device "${nameController.text}" added!'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 3: BUILD METHOD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // GlassScaffold paints the gradient backdrop and lets the tab content
    // scroll under the translucent app bar and nav bar. Tab screens are
    // therefore transparent and must not add their own background.
    return GlassScaffold(
      // 3.1  Top app bar (person icon jumps to the User tab)
      appBar: MainAppBar(
        onPersonPressed: () => setState(() => _currentIndex = 1),
      ),

      // 3.2  Tab content (IndexedStack keeps all tabs alive)
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

      // 3.3  Add device FAB — only on Home tab
      floatingActionButton: _currentIndex == 0
          ? AddDeviceFab(
              onPressed: () => _showAddDeviceDialog(context),
            )
          : null,

      // 3.4  Bottom navigation
      bottomNavigationBar: MainBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}
