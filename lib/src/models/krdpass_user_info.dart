import 'package:flutter/foundation.dart' show listEquals;

/// Falls back to an empty list when the claim is absent or not a list of strings.
List<String> _stringList(dynamic value) =>
    value is List && value.every((v) => v is String)
    ? value.cast<String>()
    : const [];

/// Null when the claim is absent, not a string, or blank: a blank claim means
/// "not provided", never ''. Returned untrimmed, matching Android.
String? _claim(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// Typed access to the standard OpenID Connect claims and the KRDPASS-specific
/// claims returned by the UserInfo endpoint.
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
    this.upns = const [],
    this.did,
    this.raw = const {},
  });

  /// Parses both the snake_case OIDC UserInfo response and the camelCase map
  /// from the native bridge. Throws [FormatException] when 'sub' is missing
  /// or invalid.
  factory KrdpassUserInfo.fromJson(Map<String, dynamic> json) {
    final sub = json['sub'];
    if (sub == null || sub is! String || sub.isEmpty) {
      throw const FormatException(
        'Invalid user info response: missing or empty sub field',
      );
    }

    // [snake] is the OIDC spelling where the bridge's camelCase one differs.
    String? claim(String camel, [String? snake]) =>
        _claim(json[camel] ?? json[snake]);

    final citizenProfilePicture = claim(
      'citizenProfilePicture',
      'citizen_profile_picture',
    );

    return KrdpassUserInfo(
      sub: sub,
      name: claim('name'),
      givenName: claim('givenName', 'given_name'),
      familyName: claim('familyName', 'family_name'),
      picture: claim('picture') ?? citizenProfilePicture,
      email: claim('email'),
      citizenFirst: claim('citizenFirst', 'citizen_first'),
      citizenSecond: claim('citizenSecond', 'citizen_second'),
      citizenThird: claim('citizenThird', 'citizen_third'),
      citizenSurname: claim('citizenSurname', 'citizen_surname'),
      citizenProfilePicture: citizenProfilePicture,
      birthdate: claim('birthdate'),
      sexAtBirth: claim('sexAtBirth', 'sex_at_birth'),
      upn: claim('upn'),
      upns: _stringList(json['upns']),
      did: claim('did'),
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

  final String? citizenFirst;

  final String? citizenSecond;

  final String? citizenThird;

  final String? citizenSurname;

  final String? citizenProfilePicture;

  final String? birthdate;

  final String? sexAtBirth;

  final String? upn;

  /// Must be stored; must never be displayed. Empty list when the claim is
  /// absent.
  final List<String> upns;

  final String? did;

  /// Raw claims map returned from the UserInfo endpoint.
  /// Use this to access any custom claims or non-standard fields.
  final Map<String, dynamic> raw;

  /// The full citizen name: the trimmed, non-blank parts joined with spaces.
  /// Null, not an empty string, when no part survives. All four SDKs agree.
  String? get citizenFullName {
    final parts = [
      citizenFirst,
      citizenSecond,
      citizenThird,
      citizenSurname,
    ].map((p) => p?.trim() ?? '').where((p) => p.isNotEmpty);
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  @override
  String toString() {
    return 'KrdpassUserInfo(sub: [REDACTED], name: [REDACTED])';
  }

  /// Value equality over the typed claims. [raw] is excluded: Dart maps compare
  /// by identity, so including it would make every parsed instance unequal.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KrdpassUserInfo &&
          runtimeType == other.runtimeType &&
          sub == other.sub &&
          name == other.name &&
          givenName == other.givenName &&
          familyName == other.familyName &&
          picture == other.picture &&
          email == other.email &&
          citizenFirst == other.citizenFirst &&
          citizenSecond == other.citizenSecond &&
          citizenThird == other.citizenThird &&
          citizenSurname == other.citizenSurname &&
          citizenProfilePicture == other.citizenProfilePicture &&
          birthdate == other.birthdate &&
          sexAtBirth == other.sexAtBirth &&
          upn == other.upn &&
          listEquals(upns, other.upns) &&
          did == other.did;

  @override
  int get hashCode => Object.hash(
    sub,
    name,
    givenName,
    familyName,
    picture,
    email,
    citizenFirst,
    citizenSecond,
    citizenThird,
    citizenSurname,
    citizenProfilePicture,
    birthdate,
    sexAtBirth,
    upn,
    Object.hashAll(upns),
    did,
  );
}
