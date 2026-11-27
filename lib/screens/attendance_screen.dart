// lib/screens/attendance_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../services/biometric_service.dart';
import '../services/iso_attendance_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../theme/hyperion_colors.dart';
import 'face_scanner_screen.dart';
import 'qr_scanner_screen.dart';
import 'register_home_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AttendanceScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;
  Timer? _clockTimer;

  // Permiso de trabajo remoto asignado por RRHH
  bool _isRemoteAllowed = false;

  // Acción seleccionada
  String _selectedActionType = 'CHECK_IN';

  // Control de marcaciones ya realizadas hoy
  bool _hasCheckIn = false;
  bool _hasLunchStart = false;
  bool _hasLunchEnd = false;
  bool _hasCheckOut = false;
  DateTime? _lunchStartTime;

  // Configuración dinámica sincronizada desde el panel de administración
  String _checkInStart = '06:00';
  String _checkInEnd = '11:59';
  String _lunchWindowStart = '13:00';
  String _lunchWindowEnd = '13:30';
  String _lunchReturnEnd = '16:59';
  int _lunchDurationMinutes = 60;
  String _checkOutStart = '18:00';
  List<int> _lunchDays = [1, 2, 3, 4, 5];

  /// Evalúa dinámicamente según los días configurados en la empresa (Dom=0, Lun=1 ... Sáb=6)
  bool get _esDiaConRefrigerio {
    final dartWeekday = DateTime.now().weekday;
    final dbWeekday = dartWeekday == 7 ? 0 : dartWeekday;
    return _lunchDays.contains(dbWeekday);
  }

  int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  int get _nowMinutes {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  // --- REGLAS DINÁMICAS DE HABILITACIÓN DE BOTONES SEGÚN HORA CONFIGURADA ---

  bool get _canEnableCheckIn {
    if (_hasCheckIn) return false;
    final nowMin = _nowMinutes;
    return nowMin >= _toMinutes(_checkInStart) && nowMin <= _toMinutes(_checkInEnd);
  }

  bool get _canEnableLunchStart {
    if (!_esDiaConRefrigerio || !_hasCheckIn || _hasLunchStart || _hasCheckOut) {
      return false;
    }
    final nowMin = _nowMinutes;
    return nowMin >= _toMinutes(_lunchWindowStart) && nowMin <= _toMinutes(_lunchWindowEnd);
  }

  bool get _canEnableLunchEnd {
    if (!_esDiaConRefrigerio || !_hasLunchStart || _hasLunchEnd || _hasCheckOut) {
      return false;
    }
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    if (_lunchStartTime != null) {
      final minReturnTime = _lunchStartTime!.add(Duration(minutes: _lunchDurationMinutes));
      if (now.isBefore(minReturnTime)) {
        return false;
      }
    }

    return nowMin <= _toMinutes(_lunchReturnEnd);
  }

  bool get _canEnableCheckOut {
    if (!_hasCheckIn || _hasCheckOut) return false;
    if (_hasLunchStart && !_hasLunchEnd) return false;

    final nowMin = _nowMinutes;
    final isSaturday = DateTime.now().weekday == DateTime.saturday;
    if (isSaturday) {
      return nowMin > _toMinutes(_checkInEnd);
    }
    return nowMin >= _toMinutes(_checkOutStart);
  }

  bool get _isSelectedPhaseActive {
    switch (_selectedActionType) {
      case 'CHECK_IN':
        return _canEnableCheckIn;
      case 'LUNCH_START':
        return _canEnableLunchStart;
      case 'LUNCH_END':
        return _canEnableLunchEnd;
      case 'CHECK_OUT':
        return _canEnableCheckOut;
      default:
        return false;
    }
  }

  /// Selecciona automáticamente el botón activo que corresponda según hora y estado
  void _sincronizarSeleccionPorHorario({bool force = false}) {
    if (!force && _isSelectedPhaseActive) return;

    if (_canEnableCheckIn) {
      _selectedActionType = 'CHECK_IN';
    } else if (_canEnableLunchStart) {
      _selectedActionType = 'LUNCH_START';
    } else if (_canEnableLunchEnd) {
      _selectedActionType = 'LUNCH_END';
    } else if (_canEnableCheckOut) {
      _selectedActionType = 'CHECK_OUT';
    } else {
      if (!_hasCheckIn) {
        _selectedActionType = 'CHECK_IN';
      } else if (_esDiaConRefrigerio && !_hasLunchStart) {
        _selectedActionType = 'LUNCH_START';
      } else if (_esDiaConRefrigerio && !_hasLunchEnd) {
        _selectedActionType = 'LUNCH_END';
      } else {
        _selectedActionType = 'CHECK_OUT';
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarConfiguracionYEstadoDia();
    NotificationService.lunchEndStatusMessage.addListener(_onNotificationLunchEnd);

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {
        _sincronizarSeleccionPorHorario();
      });
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    NotificationService.lunchEndStatusMessage.removeListener(_onNotificationLunchEnd);
    super.dispose();
  }

  void _onNotificationLunchEnd() {
    final payload = NotificationService.lunchEndStatusMessage.value;
    if (payload == null || !mounted) return;

    NotificationService.lunchEndStatusMessage.value = null;

    if (payload.startsWith('OK:')) {
      final msg = payload.substring(3);
      setState(() {
        _hasLunchEnd = true;
        _sincronizarSeleccionPorHorario(force: true);
      });
      _mostrarMensaje('¡Fin de Refrigerio Registrado!\n$msg', HyperionColors.successGreen);
    } else if (payload.startsWith('ERR:')) {
      final msg = payload.substring(4);
      _mostrarMensaje(msg, HyperionColors.dangerRed);
    }
  }

  void _aplicarConfiguracion(Map<String, dynamic> cfg) {
    _checkInStart = cfg['biometricCheckInStart']?.toString() ?? _checkInStart;
    _checkInEnd = cfg['biometricCheckInEnd']?.toString() ?? _checkInEnd;
    _lunchWindowStart = cfg['lunchWindowStart']?.toString() ?? _lunchWindowStart;
    _lunchWindowEnd = cfg['lunchWindowEnd']?.toString() ?? _lunchWindowEnd;
    _lunchReturnEnd = cfg['lunchReturnEnd']?.toString() ?? _lunchReturnEnd;
    _lunchDurationMinutes = (cfg['lunchDurationMinutes'] as num?)?.toInt() ?? _lunchDurationMinutes;
    _checkOutStart = cfg['biometricCheckOutStart']?.toString() ?? _checkOutStart;
    if (cfg['lunchDays'] is List) {
      _lunchDays = (cfg['lunchDays'] as List).map((e) => (e as num).toInt()).toList();
    }
    _sincronizarSeleccionPorHorario(force: true);
  }

  Future<void> _cargarConfiguracionYEstadoDia() async {
    setState(() => _isLoading = true);

    // 1. Cargar caché local primero
    final cached = await IsoAttendanceService.getSavedCompanyConfig();
    final cachedRemote = await IsoAttendanceService.getSavedRemoteAllowed();
    if (mounted) {
      setState(() {
        _aplicarConfiguracion(cached);
        _isRemoteAllowed = cachedRemote;
      });
    }

    // 2. Consultar backend para refrescar estado del día, permisos y configuración
    final res = await IsoAttendanceService.getTodayStatus(widget.userId);
    if (res['success'] == true && res['data'] != null) {
      final freshRemote = await IsoAttendanceService.getSavedRemoteAllowed();
      final freshConfig = res['data']['companyConfig'];
      if (mounted) {
        setState(() {
          _isRemoteAllowed = freshRemote;
          if (freshConfig is Map<String, dynamic>) {
            _aplicarConfiguracion(freshConfig);
          }
        });
      }

      final record = res['data']['record'];
      if (record != null && mounted) {
        if (record['type'] != null) {
          await _storage.write(key: 'last_attendance_type', value: record['type'].toString());
        }
        setState(() {
          _hasCheckIn = record['checkIn'] != null;
          _hasLunchStart = record['lunchStart'] != null;
          _hasLunchEnd = record['lunchEnd'] != null;
          _hasCheckOut = record['checkOut'] != null;
          _lunchStartTime = record['lunchStart'] != null
              ? DateTime.tryParse(record['lunchStart'].toString())?.toLocal()
              : null;
          _sincronizarSeleccionPorHorario(force: true);
        });

        if (_esDiaConRefrigerio && _hasCheckIn && !_hasLunchStart && !_hasCheckOut) {
          await NotificationService.programarAlertaInicioRefrigerio();
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String get _actionLabel {
    switch (_selectedActionType) {
      case 'CHECK_IN':
        return 'Entrada';
      case 'LUNCH_START':
        return 'Inicio Refrigerio';
      case 'LUNCH_END':
        return 'Fin Refrigerio';
      case 'CHECK_OUT':
        return 'Salida';
      default:
        return 'Marcación';
    }
  }

  bool _validarAccionPermitida() {
    if (!_esDiaConRefrigerio &&
        (_selectedActionType == 'LUNCH_START' || _selectedActionType == 'LUNCH_END')) {
      _mostrarMensaje('El día de hoy no cuenta con turno de refrigerio configurado.', Colors.orange);
      return false;
    }

    if (_selectedActionType != 'CHECK_IN' && !_hasCheckIn) {
      _mostrarMensaje('Debe registrar su ENTRADA antes de marcar refrigerio o salida.', Colors.orange);
      return false;
    }
    if (_selectedActionType == 'LUNCH_END' && !_hasLunchStart) {
      _mostrarMensaje('Debe registrar el INICIO DE REFRIGERIO primero.', Colors.orange);
      return false;
    }
    if (_selectedActionType == 'CHECK_OUT' && _hasLunchStart && !_hasLunchEnd) {
      _mostrarMensaje('Debe registrar el FIN DE REFRIGERIO antes de su salida.', Colors.orange);
      return false;
    }

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final isSaturday = now.weekday == DateTime.saturday;

    if (_selectedActionType == 'CHECK_IN') {
      final minIn = _toMinutes(_checkInStart);
      final maxIn = _toMinutes(_checkInEnd);
      if (nowMin < minIn || nowMin > maxIn) {
        _mostrarMensaje(
          'La marcación de ENTRADA solo está habilitada entre $_checkInStart y $_checkInEnd.',
          Colors.orange,
        );
        return false;
      }
    } else if (_selectedActionType == 'LUNCH_START') {
      final minLunch = _toMinutes(_lunchWindowStart);
      final maxLunch = _toMinutes(_lunchWindowEnd);
      if (nowMin < minLunch || nowMin > maxLunch) {
        _mostrarMensaje(
          'El INICIO DE REFRIGERIO solo está habilitado entre $_lunchWindowStart y $_lunchWindowEnd.',
          Colors.orange,
        );
        return false;
      }
    } else if (_selectedActionType == 'LUNCH_END') {
      if (_lunchStartTime != null) {
        final minReturnTime = _lunchStartTime!.add(Duration(minutes: _lunchDurationMinutes));
        if (now.isBefore(minReturnTime)) {
          final hh = minReturnTime.hour.toString().padLeft(2, '0');
          final mm = minReturnTime.minute.toString().padLeft(2, '0');
          _mostrarMensaje(
            'Debe cumplir sus $_lunchDurationMinutes min de refrigerio. Podrá marcar Fin Ref desde las $hh:$mm.',
            Colors.orange,
          );
          return false;
        }
      }
      final maxReturn = _toMinutes(_lunchReturnEnd);
      if (nowMin > maxReturn) {
        _mostrarMensaje(
          'El plazo máximo para marcar FIN DE REFRIGERIO era hasta las $_lunchReturnEnd.',
          Colors.orange,
        );
        return false;
      }
    } else if (_selectedActionType == 'CHECK_OUT') {
      if (isSaturday) {
        if (nowMin <= _toMinutes(_checkInEnd)) {
          _mostrarMensaje(
            'La marcación de SALIDA los sábados inicia después de las $_checkInEnd.',
            Colors.orange,
          );
          return false;
        }
      } else {
        final minOut = _toMinutes(_checkOutStart);
        if (nowMin < minOut) {
          _mostrarMensaje(
            'La marcación de SALIDA está habilitada a partir de las $_checkOutStart.',
            Colors.orange,
          );
          return false;
        }
      }
    }

    return true;
  }

  Future<void> _procesarMarcacion({
    required String type,
    String? qrContent,
    String? biometricToken,
  }) async {
    if (type == 'HOME_OFFICE' && !_isRemoteAllowed) {
      _mostrarMensaje(
        'Su perfil no tiene autorizado el Trabajo Remoto. Debe marcar dentro de una sede autorizada.',
        HyperionColors.dangerRed,
      );
      return;
    }

    if (!_validarAccionPermitida()) return;

    setState(() => _isLoading = true);

    try {
      final pos = await LocationService.obtenerUbicacionActual();

      final resultado = await IsoAttendanceService.postAttendance(
        userId: widget.userId,
        type: type,
        actionType: _selectedActionType,
        lat: pos.latitude,
        lng: pos.longitude,
        qrContent: qrContent,
        biometricToken: biometricToken,
      );

      if (resultado['success'] == true) {
        await _storage.write(key: 'last_attendance_type', value: type);

        final completedAction = _selectedActionType;
        final serverLunchDuration =
            (resultado['data']?['lunchDurationMinutes'] as num?)?.toInt() ?? _lunchDurationMinutes;

        if (mounted) {
          setState(() {
            _lunchDurationMinutes = serverLunchDuration;
            if (completedAction == 'CHECK_IN') {
              _hasCheckIn = true;
            } else if (completedAction == 'LUNCH_START') {
              _hasLunchStart = true;
              _lunchStartTime = DateTime.now();
            } else if (completedAction == 'LUNCH_END') {
              _hasLunchEnd = true;
            } else if (completedAction == 'CHECK_OUT') {
              _hasCheckOut = true;
            }
            _sincronizarSeleccionPorHorario(force: true);
          });
        }

        if (completedAction == 'CHECK_IN') {
          await NotificationService.programarAlertaInicioRefrigerio();
        } else if (completedAction == 'LUNCH_START') {
          await NotificationService.cancelarAlertaInicioRefrigerio();
          await NotificationService.programarAlertaFinRefrigerio(
            overrideDurationMinutes: serverLunchDuration,
          );
        } else if (completedAction == 'LUNCH_END') {
          await NotificationService.cancelarAlertasRefrigerio();
        } else if (completedAction == 'CHECK_OUT') {
          await NotificationService.cancelarAlertaInicioRefrigerio();
          await NotificationService.cancelarAlertasRefrigerio();
        }

        _mostrarMensaje(
          '¡Marcación Registrada!\n${resultado['message']}',
          HyperionColors.successGreen,
        );
      } else {
        _mostrarMensaje(
          resultado['message']?.toString() ?? 'Error al registrar marcación',
          HyperionColors.dangerRed,
        );
      }
    } catch (e) {
      _mostrarMensaje('Error al obtener coordenadas GPS: $e', HyperionColors.dangerRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _marcarConQR() async {
    if (!_validarAccionPermitida()) return;
    final qrResultado = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );
    if (qrResultado != null && qrResultado.isNotEmpty) {
      await _procesarMarcacion(type: 'PRESENTIAL_QR', qrContent: qrResultado);
    }
  }

  Future<void> _marcarConNFC() async {
    if (!_validarAccionPermitida()) return;
    if (kIsWeb) {
      _mostrarMensaje('El lector NFC no está disponible en navegador Web.', Colors.orange);
      return;
    }
    final isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      _mostrarMensaje('El Lector NFC no está activo en este dispositivo.', Colors.orange);
      return;
    }
    _mostrarMensaje('Aproxime la tarjeta o tag NFC al reverso del celular...', Colors.blue);
    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        NfcManager.instance.stopSession();
        await _procesarMarcacion(type: 'PRESENTIAL_NFC');
      },
    );
  }

  Future<void> _marcarConHuella() async {
    if (!_validarAccionPermitida()) return;
    if (kIsWeb) {
      _mostrarMensaje('La biometría nativa no está disponible en navegador Web.', Colors.orange);
      return;
    }
    final autenticado = await BiometricService.autenticarUsuario();
    if (autenticado) {
      await _procesarMarcacion(type: 'BIOMETRIC_FINGERPRINT', biometricToken: 'fingerprint_ok');
    } else {
      _mostrarMensaje('Autenticación por huella fallida', Colors.orange);
    }
  }

  Future<void> _marcarConRostro() async {
    if (!_validarAccionPermitida()) return;
    final fotoPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const FaceScannerScreen()),
    );
    if (fotoPath != null && fotoPath.isNotEmpty) {
      await _procesarMarcacion(type: 'FACIAL_RECOGNITION', biometricToken: 'facial_verified_ok');
    }
  }

  Future<void> _marcarHomeOffice() async {
    if (!_validarAccionPermitida()) return;
    await _procesarMarcacion(type: 'HOME_OFFICE');
  }

  void _mostrarMensaje(String text, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color, duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaturday = DateTime.now().weekday == DateTime.saturday;
    final bool phaseEnabled = _isSelectedPhaseActive;

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: HyperionColors.cyanAccent))
            : SingleChildScrollView(
          child: Column(
            children: [
              // 1. CABECERA BRANDING HYPERION DIGITAL SECURITY
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [HyperionColors.darkBackground, HyperionColors.primaryNavy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: HyperionColors.cyanAccent.withOpacity(0.5)),
                      ),
                      child: Image.asset(
                        'assets/images/Logo_Transparente.png',
                        height: 40,
                        width: 40,
                        errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.security, color: HyperionColors.cyanAccent, size: 36),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'HYPERION DIGITAL SECURITY',
                            style: TextStyle(
                              color: HyperionColors.cyanAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'Hola, ${widget.userName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _cargarConfiguracionYEstadoDia,
                      icon: const Icon(Icons.refresh, color: HyperionColors.cyanAccent),
                      tooltip: 'Sincronizar estado y horarios',
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Banner informativo de franjas horarias activas de la empresa
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: HyperionColors.primaryNavy.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: HyperionColors.primaryNavy.withOpacity(0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.schedule, size: 18, color: HyperionColors.primaryNavy),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _esDiaConRefrigerio
                                  ? 'Ingreso: $_checkInStart–$_checkInEnd | Refrigerio: $_lunchWindowStart–$_lunchWindowEnd (retorno hasta $_lunchReturnEnd, $_lunchDurationMinutes min) | Salida: desde $_checkOutStart.'
                                  : isSaturday
                                  ? 'Ingreso sábado: $_checkInStart–$_checkInEnd | Jornada continua sin refrigerio.'
                                  : 'Ingreso: $_checkInStart–$_checkInEnd | Salida: desde $_checkOutStart (jornada continua).',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HyperionColors.primaryNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 2. SELECTOR DE JORNADA DINÁMICO POR FRANJA HORARIA
                    const Text(
                      'FASE DE LA JORNADA',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: HyperionColors.primaryNavy,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),

                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment<String>(
                          value: 'CHECK_IN',
                          label: const Text('Entrada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          icon: const Icon(Icons.login, size: 16),
                          enabled: _canEnableCheckIn,
                        ),
                        ButtonSegment<String>(
                          value: 'LUNCH_START',
                          label: const Text('Ini. Ref', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          icon: const Icon(Icons.restaurant, size: 16),
                          enabled: _canEnableLunchStart,
                        ),
                        ButtonSegment<String>(
                          value: 'LUNCH_END',
                          label: const Text('Fin Ref', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          icon: const Icon(Icons.work_history, size: 16),
                          enabled: _canEnableLunchEnd,
                        ),
                        ButtonSegment<String>(
                          value: 'CHECK_OUT',
                          label: const Text('Salida', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          icon: const Icon(Icons.logout, size: 16),
                          enabled: _canEnableCheckOut,
                        ),
                      ],
                      selected: {_selectedActionType},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() => _selectedActionType = newSelection.first);
                      },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return phaseEnabled ? HyperionColors.primaryNavy : Colors.grey.shade300;
                          }
                          if (states.contains(WidgetState.disabled)) {
                            return Colors.grey.shade100;
                          }
                          return Colors.white;
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.selected)) {
                            return phaseEnabled ? HyperionColors.cyanAccent : Colors.grey.shade600;
                          }
                          if (states.contains(WidgetState.disabled)) {
                            return Colors.grey.shade400;
                          }
                          return const Color(0xFF334155);
                        }),
                      ),
                    ),

                    if (!phaseEnabled)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_clock, size: 16, color: Colors.amber.shade900),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _hasCheckOut
                                    ? 'Jornada de hoy completada.'
                                    : 'Fuera de la franja horaria habilitada para $_actionLabel.',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),
                    const Text(
                      'MÉTODOS DE AUTENTICACIÓN SECURE-ID',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: HyperionColors.primaryNavy,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 14),

                    _buildHyperionButton(
                      icon: Icons.qr_code_scanner,
                      label: 'Escanear QR Oficina',
                      sublabel: 'Acreditación presencial mediante tótem digital',
                      color: HyperionColors.primaryNavy,
                      enabled: phaseEnabled,
                      onPressed: _marcarConQR,
                    ),
                    const SizedBox(height: 12),

                    _buildHyperionButton(
                      icon: Icons.nfc,
                      label: 'Tarjeta Smart NFC',
                      sublabel: 'Aproximación con credencial corporativa',
                      color: const Color(0xFF0F766E),
                      enabled: phaseEnabled,
                      onPressed: _marcarConNFC,
                    ),
                    const SizedBox(height: 12),

                    _buildHyperionButton(
                      icon: Icons.fingerprint,
                      label: 'Huella Dactilar Criptográfica',
                      sublabel: 'Validación biométrica mediante sensor nativo',
                      color: const Color(0xFF0284C7),
                      enabled: phaseEnabled,
                      onPressed: _marcarConHuella,
                    ),
                    const SizedBox(height: 12),

                    _buildHyperionButton(
                      icon: Icons.face,
                      label: 'Reconocimiento Facial + Liveness',
                      sublabel: 'Escaneo facial con detección de parpadeo',
                      color: const Color(0xFF6D28D9),
                      enabled: phaseEnabled,
                      onPressed: _marcarConRostro,
                    ),

                    if (_isRemoteAllowed) ...[
                      const SizedBox(height: 12),
                      _buildHyperionButton(
                        icon: Icons.home_work_rounded,
                        label: 'Home Office Remoto (Geocerca)',
                        sublabel: 'Validación GPS en vivienda autorizada',
                        color: const Color(0xFFD97706),
                        enabled: phaseEnabled,
                        onPressed: _marcarHomeOffice,
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RegisterHomeScreen(userId: widget.userId),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          side: const BorderSide(color: HyperionColors.primaryNavy, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_location_alt, color: HyperionColors.primaryNavy),
                            SizedBox(width: 8),
                            Text(
                              'Registrar Nuevo Domicilio (Home Office)',
                              style: TextStyle(
                                color: HyperionColors.primaryNavy,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHyperionButton({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final effectiveColor = enabled ? color : Colors.grey;
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Card(
        elevation: enabled ? 2 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: effectiveColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: effectiveColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$label ($_actionLabel)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: enabled ? HyperionColors.darkBackground : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled ? Icons.arrow_forward_ios : Icons.lock_outline,
                  size: 14,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}