import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';



class MainLayout extends StatelessWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Calculate current index based on route
    final String location = GoRouterState.of(context).uri.toString();
    int currentIndex = 0;
    if (location.startsWith('/documents')) {
      currentIndex = 1;
    } else if (location.startsWith('/tools')) {
      currentIndex = 2;
    } else if (location.startsWith('/settings')) {
      currentIndex = 3;
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == 0) {
            context.go('/home');
          } else if (index == 1) {
            context.go('/documents');
          } else if (index == 2) {
            context.go('/tools');
          } else if (index == 3) {
            context.go('/settings');
          }
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insert_drive_file_outlined),
            activeIcon: Icon(Icons.insert_drive_file),
            label: 'Files',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            activeIcon: Icon(Icons.grid_view_rounded),
            label: 'Tools',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Me',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/scanner'),
        elevation: 4,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.camera_alt, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
