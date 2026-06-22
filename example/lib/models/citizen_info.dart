import 'package:demo_krdpass_auth/widgets/jwt_decoder.dart';

class CitizenInfo {
  final String? firstName;
  final String? secondName;
  final String? thirdName;
  final String? surname;
  final String? upn;
  final String? did;
  final String? birthdate;
  final String? sexAtBirth;
  final String? idp;
  final int? authTime;
  final String? sessionId;
  final String? profilePicture;

  const CitizenInfo({
    this.firstName,
    this.secondName,
    this.thirdName,
    this.surname,
    this.upn,
    this.did,
    this.birthdate,
    this.sexAtBirth,
    this.idp,
    this.authTime,
    this.sessionId,
    this.profilePicture,
  });

  String get fullName {
    final parts = [
      firstName,
      secondName,
      thirdName,
      surname,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.join(' ').trim();
  }

  String? get identityProvider {
    if (idp == null) return null;
    return idp!.replaceFirst('urn:krg:identity:', '');
  }

  static CitizenInfo? fromIdToken(String idToken) {
    final claims = JwtDecoder.decodePayload(idToken);
    if (claims == null) return null;

    return CitizenInfo(
      firstName: claims['citizen_first'] as String?,
      secondName: claims['citizen_second'] as String?,
      thirdName: claims['citizen_third'] as String?,
      surname: claims['citizen_surname'] as String?,
      upn: claims['upn'] as String?,
      did: claims['did'] as String?,
      birthdate: claims['birthdate'] as String?,
      sexAtBirth: claims['sex_at_birth'] as String?,
      idp: claims['idp'] as String?,
      authTime: claims['auth_time'] as int?,
      sessionId: claims['sid'] as String?,
      profilePicture: claims['citizen_profile_picture'] as String?,
    );
  }
}
