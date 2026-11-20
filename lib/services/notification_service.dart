// lib/services/notification_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'iso_attendance_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static const int _startLunchAlertId = 100;
  static const int _preventiveAlertId = 101;
  static const int _endLunchAlertId = 102;
  static const int _deadlineLunchWarningId = 103;

  static const String _channelId = 'refrigerio_channel';
  static const String actionMarkLunchEnd = 'ACTION_MARK_LUNCH_END';
  static const String actionOpenLunchStart = 'ACTION_OPEN_LUNCH_START';

  /// Notifica a la UI (AttendanceScreen) cuando se marca LUNCH_END desde la notificación
  static final ValueNotifier<String?> lunchEndStatusMessage =
  ValueNotifier<String?>(null);

  static (int, int) _parseHHMM(String raw, int defaultH, int defaultM) {
    final parts = raw.split(':');
    if (parts.length < 2) return (defaultH, defaultM);
    final h = int.tryParse(parts[0]) ?? defaultH;
    final m = int.tryParse(parts[1]) ?? defaultM;
    return (h, m);
  }

  /// Convierte DateTime.weekday (Lun=1 ... Dom=7) al formato JS/BD (Dom=0, Lun=1 ... Sáb=6)
  static int _toDbWeekday(int dartWeekday) => dartWeekday == 7 ? 0 : dartWeekday;

  /// Inicializa zonas horarias, permisos y el listener de clic en la notificación
  static Future<void> init({
    Future<void> Function()? onMarkLunchEnd,
  }) async {
    if (kIsWeb) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Lima'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.actionId == actionMarkLunchEnd ||
            response.payload == actionMarkLunchEnd) {
          if (onMarkLunchEnd != null) {
            await onMarkLunchEnd();
          }
        }
      },
    );

    final launchDetails =
    await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails?.notificationResponse;
      if (response != null &&
          (response.actionId == actionMarkLunchEnd ||
              response.payload == actionMarkLunchEnd)) {
        if (onMarkLunchEnd != null) {
          await onMarkLunchEnd();
        }
      }
    }

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  /// Programa alertas dinámicas según la configuración guardada de la empresa
  static Future<void> programarAlertaInicioRefrigerio() async {
    if (kIsWeb) return;

    final config = await IsoAttendanceService.getSavedCompanyConfig();
    final lunchDays = List<int>.from(config['lunchDays'] ?? [1, 2, 3, 4, 5]);
    final windowStartStr = config['lunchWindowStart']?.toString() ?? '13:00';
    final windowEndStr = config['lunchWindowEnd']?.toString() ?? '13:30';

    final now = tz.TZDateTime.now(tz.local);

    if (!lunchDays.contains(_toDbWeekday(now.weekday))) {
      await cancelarAlertaInicioRefrigerio();
      return;
    }

    const startDetails = AndroidNotificationDetails(
      _channelId,
      'Control de Refrigerio',
      channelDescription:
      'Alertas de tiempo de descanso reglamentario de la jornada',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const warningDetails = AndroidNotificationDetails(
      _channelId,
      'Control de Refrigerio',
      channelDescription:
      'Alertas de tiempo de descanso reglamentario de la jornada',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
    );

    final (startH, startM) = _parseHHMM(windowStartStr, 13, 0);
    final (endH, endM) = _parseHHMM(windowEndStr, 13, 30);

    // 1. Notificación a la hora exacta de apertura de ventana
    final lunchStartToday = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      startH,
      startM,
    );

    if (lunchStartToday.isAfter(now)) {
      await _notifications.zonedSchedule(
        id: _startLunchAlertId,
        title: '🍽️ Hora de Refrigerio ($windowStartStr)',
        body:
        'Ya puedes registrar tu Inicio de Refrigerio (ventana permitida hasta las $windowEndStr).',
        scheduledDate: lunchStartToday,
        notificationDetails: const NotificationDetails(android: startDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: actionOpenLunchStart,
      );
    }

    // 2. Segundo recordatorio urgente 5 minutos antes del cierre de ventana
    final lunchEndToday = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      endH,
      endM,
    );
    final lunchWarningToday = lunchEndToday.subtract(const Duration(minutes: 5));

    if (lunchWarningToday.isAfter(now)) {
      await _notifications.zonedSchedule(
        id: _deadlineLunchWarningId,
        title: '⚠️ ¡Último aviso de Refrigerio!',
        body:
        'Aún no has registrado tu Inicio de Refrigerio. Quedan 5 minutos antes del cierre ($windowEndStr).',
        scheduledDate: lunchWarningToday,
        notificationDetails: const NotificationDetails(android: warningDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: actionOpenLunchStart,
      );
    }
  }

  /// Cancela ambas alertas de inicio de refrigerio
  static Future<void> cancelarAlertaInicioRefrigerio() async {
    if (kIsWeb) return;
    await _notifications.cancel(id: _startLunchAlertId);
    await _notifications.cancel(id: _deadlineLunchWarningId);
  }

  /// Programa alertas de fin de refrigerio según duración configurada (10 min antes y al cumplirse)
  static Future<void> programarAlertaFinRefrigerio({int? overrideDurationMinutes}) async {
    if (kIsWeb) return;

    final config = await IsoAttendanceService.getSavedCompanyConfig();
    final durationMinutes = overrideDurationMinutes ??
        (config['lunchDurationMinutes'] as num?)?.toInt() ??
        60;

    final now = tz.TZDateTime.now(tz.local);

    const preventiveDetails = AndroidNotificationDetails(
      _channelId,
      'Control de Refrigerio',
      channelDescription:
      'Alertas de tiempo de descanso reglamentario de la jornada',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const finalDetails = AndroidNotificationDetails(
      _channelId,
      'Control de Refrigerio',
      channelDescription:
      'Alertas de tiempo de descanso reglamentario de la jornada',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          actionMarkLunchEnd,
          'Marcar Fin de Refrigerio',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    // 1. Alerta preventiva 10 minutos antes de finalizar
    if (durationMinutes > 10) {
      await _notifications.zonedSchedule(
        id: _preventiveAlertId,
        title: '🍱 ¡Atención: Refrigerio por culminar!',
        body:
        'Faltan 10 minutos para culminar su refrigerio de $durationMinutes min. Recuerde marcar su retorno a tiempo.',
        scheduledDate: now.add(Duration(minutes: durationMinutes - 10)),
        notificationDetails: const NotificationDetails(android: preventiveDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }

    // 2. Notificación final al cumplirse el tiempo configurado
    await _notifications.zonedSchedule(
      id: _endLunchAlertId,
      title: '⏰ Tu refrigerio ($durationMinutes min) ha terminado',
      body:
      'Toca aquí o pulsa "Marcar Fin de Refrigerio" para registrar tu retorno ahora.',
      scheduledDate: now.add(Duration(minutes: durationMinutes)),
      notificationDetails: const NotificationDetails(android: finalDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: actionMarkLunchEnd,
    );
  }

  /// Cancela las alertas pendientes cuando el usuario ya marcó su Fin de Refrigerio
  static Future<void> cancelarAlertasRefrigerio() async {
    if (kIsWeb) return;
    await _notifications.cancel(id: _preventiveAlertId);
    await _notifications.cancel(id: _endLunchAlertId);
  }
}