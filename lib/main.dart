// lib/main.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'config/api_config.dart';
import 'screens/main_tab_screen.dart';
import 'services/biometric_service.dart';
import 'services/iso_attendance_service.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'theme/hyperion_colors.dart';

Future<void> _registrarFinRefrigerioDesdeNotificacion() async {
  const storage = FlutterSecureStorage();
  final userId = await storage.read(key: 'user_id');
  if (userId == null || userId.isEmpty) return;

  final savedType = await storage.read(key: 'last_attendance_type');
  // Si el trabajador marcó con QR en la mañana, usamos BIOMETRIC_FINGERPRINT para validar geocerca GPS
  final attendanceType = (savedType == 'HOME_OFFICE')
      ? 'HOME_OFFICE'
      : 'BIOMETRIC_FINGERPRINT';

  try {
    final pos = await LocationService.obtenerUbicacionActual();
    final res = await IsoAttendanceService.postAttendance(
      userId: userId,
      type: attendanceType,
      actionType: 'LUNCH_END',
      lat: pos.latitude,
      lng: pos.longitude,
      biometricToken: 'notification_lunch_end_ok',
    );

    if (res['success'] == true) {
      await NotificationService.cancelarAlertasRefrigerio();
      NotificationService.lunchEndStatusMessage.value =
      'OK:${res['message'] ?? 'Fin de refrigerio registrado desde notificación'}';
    } else {
      NotificationService.lunchEndStatusMessage.value =
      'ERR:${res['message'] ?? 'No se pudo registrar el fin de refrigerio'}';
    }
  } catch (e) {
    NotificationService.lunchEndStatusMessage.value =
    'ERR:Error GPS al registrar fin de refrigerio: $e';
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init(
    onMarkLunchEnd: _registrarFinRefrigerioDesdeNotificacion,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hyperion Security - Asistencia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: HyperionColors.primaryNavy,
          primary: HyperionColors.primaryNavy,
          secondary: HyperionColors.cyanAccent,
        ),
        scaffoldBackgroundColor: HyperionColors.lightBackground,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: HyperionColors.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final userId = await _storage.read(key: 'user_id');
    final userName = await _storage.read(key: 'user_name');

    if (!mounted) return;

    if (userId != null && userName != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => BiometricLoginScreen(
            userId: userId,
            userName: userName,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DniLoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class DniLoginScreen extends StatefulWidget {
  const DniLoginScreen({super.key});

  @override
  State<DniLoginScreen> createState() => _DniLoginScreenState();
}

class _DniLoginScreenState extends State<DniLoginScreen> {
  final _dniController = TextEditingController();
  final _passController = TextEditingController();
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;

  Future<void> _login() async {
    final dni = _dniController.text.trim();
    final password = _passController.text.trim();

    if (dni.isEmpty || password.isEmpty) {
      _showMessage('Por favor ingrese su DNI y contraseña', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'dni': dni, 'password': password}),
      );

      final isJson =
          response.headers['content-type']?.contains('application/json') ?? false;

      if (isJson) {
        final resData = jsonDecode(response.body);

        if (response.statusCode == 200 && resData['success'] == true) {
          final userId = resData['user']['id'];
          final userName = resData['user']['name'];

          await _storage.write(key: 'user_id', value: userId);
          await _storage.write(key: 'user_name', value: userName);

          // Guardar configuración dinámica de refrigerio y jornadas de la empresa
          if (resData['companyConfig'] is Map<String, dynamic>) {
            await IsoAttendanceService.saveCompanyConfig(resData['companyConfig']);
          }

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MainTabScreen(
                userId: userId,
                userName: userName,
              ),
            ),
          );
        } else {
          _showMessage(resData['error'] ?? 'Credenciales inválidas', Colors.red);
        }
      } else {
        _showMessage(
          'Error de servidor (${response.statusCode}). Verifique la IP en ApiConfig.',
          Colors.red,
        );
      }
    } catch (e) {
      _showMessage('Error de conexión con la PC: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Icon(Icons.security, size: 80, color: Colors.indigo.shade800),
                const SizedBox(height: 16),
                const Text(
                  'Ingreso de Trabajador',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Enrolar Dispositivo para Asistencia'),
                const SizedBox(height: 30),
                TextField(
                  controller: _dniController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'DNI del Empleado',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                  onPressed: _login,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Colors.indigo.shade800,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Iniciar Sesión y Vincular'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BiometricLoginScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const BiometricLoginScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<BiometricLoginScreen> createState() => _BiometricLoginScreenState();
}

class _BiometricLoginScreenState extends State<BiometricLoginScreen> {
  final _storage = const FlutterSecureStorage();
  bool _syncing = false;

  Future<void> _autenticar() async {
    bool autenticado = kIsWeb ? true : await BiometricService.autenticarUsuario();
    if (autenticado) {
      setState(() => _syncing = true);
      // Sincroniza configuración actualizada de refrigerio antes de entrar
      await IsoAttendanceService.getTodayStatus(widget.userId);
      if (!mounted) return;
      setState(() => _syncing = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainTabScreen(
            userId: widget.userId,
            userName: widget.userName,
          ),
        ),
      );
    }
  }

  Future<void> _desvincular() async {
    await _storage.deleteAll();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DniLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint, size: 90, color: Colors.indigo.shade800),
              const SizedBox(height: 20),
              Text(
                'Bienvenido, ${widget.userName}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text('Confirme su identidad biométrica para continuar'),
              const SizedBox(height: 40),
              _syncing
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                onPressed: _autenticar,
                icon: const Icon(Icons.lock_open),
                label: const Text('Ingresar con Biometría'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _desvincular,
                child: const Text('Cerrar sesión / Cambiar DNI'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}