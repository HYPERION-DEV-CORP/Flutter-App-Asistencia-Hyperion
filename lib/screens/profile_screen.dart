// lib/screens/profile_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:signature/signature.dart';
import '../main.dart';
import '../services/user_profile_service.dart';
import 'create_permission_screen.dart';
import 'monthly_tareo_sign_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SignatureController _sigController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  String? _savedSignatureBase64;
  bool _loadingSig = true;
  bool _savingSig = false;
  bool _savingPass = false;

  @override
  void initState() {
    super.initState();
    _loadProfileSignature();
  }

  Future<void> _loadProfileSignature() async {
    try {
      final res = await UserProfileService.getProfileSignature(widget.userId);
      if (mounted) {
        setState(() => _savedSignatureBase64 = res['signatureBase64']);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSig = false);
    }
  }

  Future<void> _guardarFirmaPerfil() async {
    if (_sigController.isEmpty) {
      _showSnack('Por favor dibuje su firma en el recuadro antes de guardar.', Colors.orange);
      return;
    }

    setState(() => _savingSig = true);
    try {
      final Uint8List? bytes = await _sigController.toPngBytes();
      if (bytes == null) return;
      final base64Str = base64Encode(bytes);

      await UserProfileService.updateProfileSignature(
        userId: widget.userId,
        signatureBase64: base64Str,
      );

      _sigController.clear();
      if (mounted) setState(() => _savedSignatureBase64 = base64Str);
      _showSnack('Firma digital configurada correctamente en su perfil.', Colors.green.shade700);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _savingSig = false);
    }
  }

  Future<void> _cambiarContrasena() async {
    if (_currentPassCtrl.text.isEmpty || _newPassCtrl.text.length < 6) {
      _showSnack('Ingrese su contraseña actual y una nueva de mínimo 6 caracteres.', Colors.orange);
      return;
    }
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      _showSnack('La confirmación de la nueva contraseña no coincide.', Colors.orange);
      return;
    }

    setState(() => _savingPass = true);
    try {
      await UserProfileService.changePassword(
        userId: widget.userId,
        currentPassword: _currentPassCtrl.text,
        newPassword: _newPassCtrl.text,
      );
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      _showSnack('Contraseña actualizada correctamente.', Colors.green.shade700);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _savingPass = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    const storage = FlutterSecureStorage();

    bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Está seguro de que desea cerrar sesión en este dispositivo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await storage.deleteAll();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DniLoginScreen()),
            (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _sigController.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil de Empleado'),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Colors.indigo,
                child: Icon(Icons.person, size: 50, color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.userName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'ID: ${widget.userId}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Divider(),

            const ListTile(
              leading: Icon(Icons.business, color: Colors.indigo),
              title: Text('Empresa'),
              subtitle: Text('Hyperion Digital Security S.A.C.'),
            ),
            const ListTile(
              leading: Icon(Icons.schedule, color: Colors.indigo),
              title: Text('Horario de Trabajo'),
              subtitle: Text('09:00 AM - 06:00 PM (1h Refrigerio)'),
            ),

            const Divider(),

            // TARJETA TAREO SUNAFIL (FIN DE MES)
            Card(
              elevation: 0,
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.amber.shade700, width: 1),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.amber.shade800,
                  child: const Icon(Icons.draw, color: Colors.white, size: 20),
                ),
                title: Text(
                  'Tareo SUNAFIL (${now.month.toString().padLeft(2, '0')}/${now.year})',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amber.shade900),
                ),
                subtitle: const Text('Revisar registro mensual y firmar conformidad de cierre'),
                trailing: Icon(Icons.chevron_right, color: Colors.amber.shade900),
                onTap: () {
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
              ),
            ),

            const SizedBox(height: 10),

            // OPCIÓN PARA SOLICITAR PERMISOS Y PAPELETAS
            Card(
              elevation: 0,
              color: const Color(0xFF005F87).withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF005F87), width: 1),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF005F87),
                  child: Icon(Icons.assignment_add, color: Colors.white, size: 20),
                ),
                title: const Text(
                  'Solicitar Permiso / Papeleta',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF005F87)),
                ),
                subtitle: const Text('Descansos médicos, papeletas de salida y licencias con firma digital'),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF005F87)),
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreatePermissionScreen(userId: widget.userId),
                    ),
                  );

                  if (result == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Solicitud y papeleta enviada a RRHH correctamente.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
            ),

            const Divider(height: 32),

            // CONFIGURACIÓN DE FIRMA DIGITAL (MARCACIÓN DIARIA)
            const Text(
              'Firma Digital del Trabajador (Marcación Diaria)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Esta firma se estampará automáticamente en su registro diario de asistencia.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            if (_loadingSig)
              const Center(child: CircularProgressIndicator())
            else if (_savedSignatureBase64 != null && _savedSignatureBase64!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.teal),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      '✓ Firma registrada actualmente:',
                      style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Image.memory(base64Decode(_savedSignatureBase64!), height: 65),
                  ],
                ),
              ),

            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Signature(
                controller: _sigController,
                height: 140,
                backgroundColor: Colors.white,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _sigController.clear(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Limpiar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _savingSig ? null : _guardarFirmaPerfil,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade800,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(_savingSig ? 'Guardando...' : 'Guardar Firma'),
                ),
              ],
            ),

            const Divider(height: 32),

            // MODIFICAR CONTRASEÑA
            const Text(
              'Cambiar Contraseña',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _currentPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña Actual',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nueva Contraseña (mín. 6 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar Nueva Contraseña',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _savingPass ? null : _cambiarContrasena,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
              child: Text(_savingPass ? 'Actualizando...' : 'Actualizar Contraseña'),
            ),

            const SizedBox(height: 30),

            // Botón de Cerrar Sesión
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _cerrarSesion(context),
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  'Cerrar Sesión del Dispositivo',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}