import 'package:demo_krdpass_auth/widgets/jwt_decoder.dart';

class CitizenIdentity {
  final String firstName;
  final String secondName;
  final String thirdName;
  final String surname;
  final String fullName;
  final String email;
  final String upn;
  final String sub;
  final String did;
  final String? birthdate;
  final String? sex;
  final String? idp;
  final String? profilePicUrl;

  const CitizenIdentity({
    required this.firstName,
    required this.secondName,
    required this.thirdName,
    required this.surname,
    required this.fullName,
    required this.email,
    required this.upn,
    required this.sub,
    required this.did,
    this.birthdate,
    this.sex,
    this.idp,
    this.profilePicUrl,
  });

  factory CitizenIdentity.fromTokens({
    required String? idToken,
    required String? accessToken,
    required Map<String, dynamic>? userInfo,
  }) {
    final Map<String, dynamic> idClaims = idToken != null
        ? JwtDecoder.decodePayload(idToken) ?? {}
        : {};

    // Helper to extract value from active claims (UserInfo > ID Token)
    dynamic getClaim(String key) {
      if (userInfo != null && userInfo.containsKey(key)) {
        return userInfo[key];
      }
      return idClaims[key];
    }

    final String firstName = getClaim('citizen_first') as String? ?? '';
    final String secondName = getClaim('citizen_second') as String? ?? '';
    final String thirdName = getClaim('citizen_third') as String? ?? '';
    final String surname = getClaim('citizen_surname') as String? ?? '';

    final parts = [
      firstName,
      secondName,
      thirdName,
      surname,
    ].where((s) => s.isNotEmpty).join(' ');

    final String fullName = parts.isNotEmpty
        ? parts
        : (getClaim('upn') as String? ?? 'Citizen User');

    final String email =
        getClaim('email') as String? ??
        getClaim('upn') as String? ??
        'No email';

    final String upn = getClaim('upn') as String? ?? 'N/A';
    final String sub = getClaim('sub') as String? ?? 'N/A';
    final String did = getClaim('did') as String? ?? 'N/A';
    final String? birthdate = getClaim('birthdate') as String?;
    final String? sex = getClaim('sex_at_birth') as String?;
    final String? idp = getClaim('idp') as String?;
    final String? profilePicUrl =
        getClaim('citizen_profile_picture') as String?;

    return CitizenIdentity(
      firstName: firstName,
      secondName: secondName,
      thirdName: thirdName,
      surname: surname,
      fullName: fullName,
      email: email,
      upn: upn,
      sub: sub,
      did: did,
      birthdate: birthdate,
      sex: sex,
      idp: idp,
      profilePicUrl: profilePicUrl,
    );
  }
}
