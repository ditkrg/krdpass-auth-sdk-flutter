/// User information claims returned by the UserInfo endpoint.
///
/// This class provides typed access to standard OpenID Connect claims
/// and specific KRDPASS claims found in the authentication response.
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
  /// Handles both the snake_case OIDC UserInfo response and the camelCase map
  /// returned by the native getUserInfo bridge.
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

    String? field(String camel, String snake) =>
        (json[camel] ?? json[snake]) as String?;

    final citizenProfilePicture = field(
      'citizenProfilePicture',
      'citizen_profile_picture',
    );

    return KrdpassUserInfo(
      sub: sub,
      name: json['name'] as String?,
      givenName: field('givenName', 'given_name'),
      familyName: field('familyName', 'family_name'),
      picture: (json['picture'] as String?) ?? citizenProfilePicture,
      email: json['email'] as String?,
      citizenFirst: field('citizenFirst', 'citizen_first'),
      citizenSecond: field('citizenSecond', 'citizen_second'),
      citizenThird: field('citizenThird', 'citizen_third'),
      citizenSurname: field('citizenSurname', 'citizen_surname'),
      citizenProfilePicture: citizenProfilePicture,
      birthdate: json['birthdate'] as String?,
      sexAtBirth: field('sexAtBirth', 'sex_at_birth'),
      upn: json['upn'] as String?,
      did: json['did'] as String?,
      raw: (json['raw'] as Map?) != null
          ? Map<String, dynamic>.from(json['raw'] as Map)
          : json,
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

  /// KRDPASS Specific: Citizen's first name
  final String? citizenFirst;

  /// KRDPASS Specific: Citizen's second name
  final String? citizenSecond;

  /// KRDPASS Specific: Citizen's third name
  final String? citizenThird;

  /// KRDPASS Specific: Citizen's surname
  final String? citizenSurname;

  /// KRDPASS Specific: Profile picture URL specific to citizen registry
  final String? citizenProfilePicture;

  /// KRDPASS Specific: Birthdate (ISO8601 format)
  final String? birthdate;

  /// KRDPASS Specific: Sex at birth (e.g. 'male', 'female')
  final String? sexAtBirth;

  /// KRDPASS Specific: Unique Personal Number
  final String? upn;

  /// KRDPASS Specific: Decentralized Identifier
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
