/// User information claims returned by the UserInfo endpoint.
///
/// This class provides typed access to standard OpenID Connect claims
/// and specific KRDPass claims found in the authentication response.
class KrdpassUserInfo {
  const KrdpassUserInfo({
    required this.sub,
    this.name,
    this.givenName,
    this.familyName,
    this.picture,
    this.email,
    this.citizenFirst,
    this.citizenSecond,
    this.citizenThird,
    this.citizenSurname,
    this.citizenProfilePicture,
    this.birthdate,
    this.sexAtBirth,
    this.upn,
    this.did,
    this.raw = const {},
  });

  /// Create [KrdpassUserInfo] from a JSON map.
  ///
  /// Throws [FormatException] if the required 'sub' field is missing or invalid.
  factory KrdpassUserInfo.fromJson(Map<String, dynamic> json) {
    // Validate required field with proper type checking
    final sub = json['sub'];
    if (sub == null || sub is! String || sub.isEmpty) {
      throw const FormatException(
        'Invalid user info response: missing or empty sub field',
      );
    }

    return KrdpassUserInfo(
      sub: sub,
      name: json['name'] as String?,
      givenName: json['given_name'] as String?,
      familyName: json['family_name'] as String?,
      picture: json['picture'] as String? ??
          json['citizen_profile_picture'] as String?,
      email: json['email'] as String?,
      citizenFirst: json['citizen_first'] as String?,
      citizenSecond: json['citizen_second'] as String?,
      citizenThird: json['citizen_third'] as String?,
      citizenSurname: json['citizen_surname'] as String?,
      citizenProfilePicture: json['citizen_profile_picture'] as String?,
      birthdate: json['birthdate'] as String?,
      sexAtBirth: json['sex_at_birth'] as String?,
      upn: json['upn'] as String?,
      did: json['did'] as String?,
      raw: json,
    );
  }

  /// Subject - Identifier for the End-User.
  final String sub;

  /// End-User's full name in displayable form including all name parts.
  final String? name;

  /// Given name(s) or first name(s) of the End-User.
  final String? givenName;

  /// Surname(s) or last name(s) of the End-User.
  final String? familyName;

  /// URL of the End-User's profile picture.
  final String? picture;

  /// End-User's preferred e-mail address (if granted by scope).
  final String? email;

  /// KRDPass Specific: Citizen's first name
  final String? citizenFirst;

  /// KRDPass Specific: Citizen's second name
  final String? citizenSecond;

  /// KRDPass Specific: Citizen's third name
  final String? citizenThird;

  /// KRDPass Specific: Citizen's surname
  final String? citizenSurname;

  /// KRDPass Specific: Profile picture URL specific to citizen registry
  final String? citizenProfilePicture;

  /// KRDPass Specific: Birthdate (ISO8601 format)
  final String? birthdate;

  /// KRDPass Specific: Sex at birth (e.g. 'male', 'female')
  final String? sexAtBirth;

  /// KRDPass Specific: Unique Personal Number
  final String? upn;

  /// KRDPass Specific: Decentralized Identifier
  final String? did;

  /// Raw claims map returned from the UserInfo endpoint.
  /// Use this to access any custom claims or non-standard fields.
  final Map<String, dynamic> raw;

  /// Helper to construct the full citizen name from known parts.
  String? get citizenFullName {
    final parts = [
      citizenFirst,
      citizenSecond,
      citizenThird,
      citizenSurname,
    ].where((p) => p != null && p.isNotEmpty);
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  @override
  String toString() {
    return 'KrdpassUserInfo(sub: [REDACTED], name: [REDACTED])';
  }
}
