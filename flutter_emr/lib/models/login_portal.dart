/// Sign-in lane sent as **`portal`** (and **`role`**) on `POST …/auth/login/`.
enum LoginPortal {
  patient,
  doctor,
  administrator;

  String get apiValue => switch (this) {
        LoginPortal.patient => 'patient',
        LoginPortal.doctor => 'doctor',
        LoginPortal.administrator => 'administrator',
      };

  String get title => switch (this) {
        LoginPortal.patient => 'Patient',
        LoginPortal.doctor => 'Doctor',
        LoginPortal.administrator => 'Administrator',
      };

  /// Short label for tight layouts (e.g. phone login row).
  String get compactTitle => switch (this) {
        LoginPortal.patient => 'Patient',
        LoginPortal.doctor => 'Doctor',
        LoginPortal.administrator => 'Admin',
      };

  String get subtitle => switch (this) {
        LoginPortal.patient => 'Book care, records & visits',
        LoginPortal.doctor => 'Clinical & provider workspace',
        LoginPortal.administrator => 'Staff & system administration',
      };

  static LoginPortal? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw.toLowerCase().trim()) {
      case 'patient':
      case 'user':
        return LoginPortal.patient;
      case 'doctor':
      case 'provider':
      case 'physician':
        return LoginPortal.doctor;
      case 'admin':
      case 'administrator':
      case 'staff':
        return LoginPortal.administrator;
      default:
        return null;
    }
  }
}
