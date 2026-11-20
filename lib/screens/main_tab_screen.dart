// lib/screens/main_tab_screen.dart
import 'package:flutter/material.dart';
import '../services/user_profile_service.dart';
import 'attendance_screen.dart';
import 'create_permission_screen.dart';
import 'monthly_tareo_sign_screen.dart';
import 'profile_screen.dart';

class MainTabScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const MainTabScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      AttendanceScreen(userId: widget.userId, userName: widget.userName),
      CreatePermissionScreen(
        userId: widget.userId,
        onSuccess: () {
          if (mounted) {
            setState(() => _currentIndex = 0);
          }
        },
      ),
      ProfileScreen(userId: widget.userId, userName: widget.userName),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingMonthlySignOff();
    });
  }

  Future<void> _checkPendingMonthlySignOff() async {
    final now = DateTime.now();
    // Mostrar recordatorio a fin de mes (a partir del día 28)
    if (now.day < 28) return;

    try {
      final res = await UserProfileService.getMonthlyTareo(
        userId: widget.userId,
        year: now.year,
        month: now.month,
      );
      final closingSig = res['closingSignOff']?['closingSignature'];
      if ((closingSig == null || closingSig.toString().isEmpty) && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Firma Mensual de Tareo SUNAFIL'),
            content: const Text(
              'Estamos en cierre de mes. Por favor revise su Registro de Asistencia SUNAFIL y ejecute nuevamente su firma digital de conformidad.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Más tarde'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MonthlyTareoSignScreen(
                        userId: widget.userId,
                        year: now.year,
                        month: now.month,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade800,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Revisar y Firmar'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.indigo.shade800,
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.touch_app),
            label: 'Asistencia',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_add),
            label: 'Permisos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Mi Perfil',
          ),
        ],
      ),
    );
  }
}