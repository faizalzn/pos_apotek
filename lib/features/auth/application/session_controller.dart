import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';

/// Pengguna yang sedang masuk, atau `null` bila belum login.
class SessionController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void signIn(AppUser user) => state = user;

  void signOut() => state = null;

  /// Memperbarui data pengguna aktif (mis. setelah ganti nama).
  void refresh(AppUser user) {
    if (state?.id == user.id) state = user;
  }
}

final sessionProvider =
    NotifierProvider<SessionController, AppUser?>(SessionController.new);

/// Apakah pengguna aktif adalah Pemilik.
final isOwnerProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider)?.role == UserRole.owner,
);
