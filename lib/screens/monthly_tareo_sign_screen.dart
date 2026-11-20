// lib/screens/monthly_tareo_sign_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../services/user_profile_service.dart';

class MonthlyTareoSignScreen extends StatefulWidget {
  final String userId;
  final int year;
  final int month;

  const MonthlyTareoSignScreen({
    super.key,
    required this.userId,
    required this.year,
    required this.month,
  });

  @override
  State<MonthlyTareoSignScreen> createState() => _MonthlyTareoSignScreenState();
}

class _MonthlyTareoSignScreenState extends State<MonthlyTareoSignScreen> {
  final SignatureController _closingSigController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  JsonMap? _tareoData;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTareo();
  }

  Future<void> _loadTareo() async {
    setState(() => _loading = true);
    try {
      final res = await UserProfileService.getMonthlyTareo(
        userId: widget.userId,
        year: widget.year,
        month: widget.month,
      );
      if (mounted) setState(() => _tareoData = res);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewSignature() async {
    if (_closingSigController.isEmpty) {
      _showSnack('Por favor realice su firma nuevamente en el recuadro.', Colors.orange);
      return;
    }

    setState(() => _submitting = true);
    try {
      final Uint8List? bytes = await _closingSigController.toPngBytes();
      if (bytes == null) return;
      final base64Sig = base64Encode(bytes);

      final res = await UserProfileService.signMonthlyClosing(
        userId: widget.userId,
        year: widget.year,
        month: widget.month,
        closingSignatureBase64: base64Sig,
      );

      _closingSigController.clear();
      _showSnack(res['message'] ?? 'Tareo SUNAFIL firmado con éxito.', Colors.green.shade700);
      await _loadTareo();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    _closingSigController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = _tareoData?['header'] as JsonMap?;
    final rows = (_tareoData?['rows'] as List?) ?? [];
    final closingSig = _tareoData?['closingSignOff']?['closingSignature'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text('Tareo SUNAFIL - ${widget.month.toString().padLeft(2, '0')}/${widget.year}'),
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (header != null)
            Container(
              width: double.infinity,
              color: Colors.indigo.shade50,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    header['title'] ?? 'REGISTRO DE ASISTENCIA',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${header['employeeName']} • DNI: ${header['dni']}',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final r = rows[index] as JsonMap;
                final isRest = r['isSunday'] == true || r['isHoliday'] == true;
                return Container(
                  color: isRest ? Colors.grey.shade200 : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${r['dateFormatted']}\n${r['dayName']}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isRest ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          isRest
                              ? '-'
                              : 'Ing: ${r['checkIn']} | Sal: ${r['checkOut']}\nRef: ${r['lunchStart']} - ${r['lunchEnd']}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          r['observations'] ?? '',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isRest ? FontWeight.bold : FontWeight.w600,
                            color: isRest ? Colors.indigo.shade800 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: closingSig != null && closingSig.isNotEmpty
                ? Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified, color: Colors.teal, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Tareo Mensual Firmado y Conformado',
                      style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(6),
                  color: Colors.white,
                  child: Image.memory(base64Decode(closingSig), height: 60),
                ),
              ],
            )
                : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Conformidad de Fin de Mes — Ejecute nuevamente su firma:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Nota: Debe realizar una nueva firma manuscrita (no se reutiliza la del perfil).',
                  style: TextStyle(fontSize: 10.5, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.indigo.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Signature(
                    controller: _closingSigController,
                    height: 105,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _closingSigController.clear(),
                      child: const Text('Limpiar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _submitNewSignature,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade800,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.draw, size: 18),
                      label: Text(_submitting ? 'Firmando...' : 'Confirmar y Firmar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}