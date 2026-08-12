import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'due_reminders.dart';
import 'reminder_service.dart';

/// Implantation réelle des rappels : notifications LOCALES planifiées.
///
/// Aucun push, donc aucun Firebase — le greffon ne tire qu'AndroidX et gson.
/// L'appareil connaît les dates d'échéance ; il n'a besoin d'aucun serveur pour
/// compter les jours.
class LocalReminderSink implements ReminderSink {
  LocalReminderSink({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _pret = false;

  static const _canal = AndroidNotificationDetails(
    'echeances',
    'Rappels d’échéance',
    channelDescription: 'Vous prévient avant la date de retour d’un ouvrage.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  Future<void> _init() async {
    if (_pret) return;
    // Base de fuseaux embarquée : `zonedSchedule` exige un instant situé dans
    // un fuseau, et l'appareil peut voyager. Sans elle, un rappel planifié
    // avant un déplacement se déclencherait à la mauvaise heure.
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Silhouette dédiée, PAS l'icône de lanceur. Android ≥ 5 ne retient que
        // l'ALPHA d'une petite icône de notification et la peint en blanc :
        // `@mipmap/ic_launcher` étant une image opaque, son alpha est un
        // rectangle plein — la barre d'état affichait donc un carré blanc.
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );
    _pret = true;
  }

  @override
  Future<bool> ensurePermission() async {
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    // Android 13+ exige POST_NOTIFICATIONS. Un refus est une réponse
    // parfaitement valable : on le rend tel quel, on ne réinsiste pas.
    final ok = await android.requestNotificationsPermission();
    return ok ?? false;
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(Reminder r) async {
    await _init();
    await _plugin.zonedSchedule(
      id: r.id,
      title: r.title,
      body: r.body,
      scheduledDate: tz.TZDateTime.from(r.when, tz.local),
      notificationDetails: const NotificationDetails(android: _canal),
      // INEXACT et volontairement : une alarme exacte exige
      // SCHEDULE_EXACT_ALARM, une permission que les magasins scrutent et que
      // rien ne justifie ici. Un rappel d'échéance à quelques minutes près
      // rend exactement le même service, et ménage la batterie.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
