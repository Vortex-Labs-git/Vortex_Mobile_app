import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/user_screen.dart';
import 'screens/about_screen.dart';
import 'services/auth_service.dart';

void main() async {
  // 1. Required for async code in main
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Check if user was logged in previously
  await AuthService.checkLoginStatus();
  
  // 3. Start App
  runApp(const VortaxLabsApp());
}

class VortaxLabsApp extends StatelessWidget {
  const VortaxLabsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vortex Labs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  final List<Widget> _pages = [
    const HomeScreen(),
    const UserScreen(),
    const AboutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF3F51B5),
        title: const Text(
          'Vortex Labs',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: () {
              // Switch to User tab
              setState(() => _currentIndex = 1);
            },
          ),
        ],
      ),
      body: _pages[_currentIndex],
      floatingActionButton: _currentIndex == 0 ? FloatingActionButton(
        backgroundColor: const Color(0xFF3F51B5),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Add Device feature coming soon!')),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: const Color(0xFF3F51B5),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'User',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info),
            label: 'About',
          ),
        ],
      ),
    );
  }
}