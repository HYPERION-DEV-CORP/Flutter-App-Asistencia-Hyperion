// lib/screens/forgot_password_screen.dart
import 'package:flutter/material.dart';
import '../services/user_profile_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();

  bool _codeSent = false;
  bool _isLoading = false;

  Future<void> _requestCode() async {
    final id = _identifierController.text.trim();
    if (id.isEmpty) {
      _showSnack('Ingrese su DNI o correo electrónico registrado.', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await UserProfileService.forgotPassword(id);
      setState(() => _codeSent = true);
      final devHint = res['devCode'] != null ? '\n(Código OTP: ${res['devCode']})' : '';
      _showSnack('${res['message']}$devHint', Colors.teal.shade700);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final newPass = _newPassController.text.trim();
    final confirmPass = _confirmPassController.text.trim();

    if (code.isEmpty || newPass.length < 6) {
      _showSnack('Ingrese el código de 6 dígitos y una clave de mínimo 6 caracteres.', Colors.orange);
      return;
    }
    if (newPass != confirmPass) {
      _showSnack('Las contraseñas no coinciden.', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await UserProfileService.resetPassword(
        identifier: _identifierController.text.trim(),
        code: code,
        newPassword: newPass,
      );
      _showSnack(res['message'] ?? 'Contraseña restablecida.', Colors.green.shade700);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 5)),
    );
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _codeController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar Contraseña'),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.lock_reset, size: 70, color: Colors.indigo.shade800),
            const SizedBox(height: 12),
            const Text(
              'Restablecimiento de Acceso',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ingrese su DNI o correo corporativo para recibir un código de verificación.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _identifierController,
              enabled: !_codeSent,
              decoration: const InputDecoration(
                labelText: 'DNI o Correo Electrónico',
                prefixIcon: Icon(Icons.person_search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (!_codeSent)
              ElevatedButton(
                onPressed: _isLoading ? null : _requestCode,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: Colors.indigo.shade800,
                  foregroundColor: Colors.white,
                ),
                child: Text(_isLoading ? 'Enviando código...' : 'Solicitar Código OTP'),
              )
            else ...[
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Código de Verificación (6 dígitos)',
                  prefixIcon: Icon(Icons.pin),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva Contraseña (mín. 6 caracteres)',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar Nueva Contraseña',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _resetPassword,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                child: Text(_isLoading ? 'Guardando...' : 'Restablecer Contraseña'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}