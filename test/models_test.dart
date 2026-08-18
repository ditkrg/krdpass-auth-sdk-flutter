import 'package:flutter_test/flutter_test.dart';
import 'package:krdpass_auth_flutter/krdpass_auth_flutter.dart';

void main() {
  group('KrdpassUserInfo.fromJson', () {
    test('accepts the snake_case OIDC shape', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'given_name': 'Ali',
        'family_name': 'Karim',
        'citizen_first': 'Ali',
        'citizen_second': 'Omer',
        'citizen_surname': 'Karim',
        'sex_at_birth': 'male',
        'citizen_profile_picture': 'https://cdn.example.com/a.png',
      });

      expect(info.sub, 'user-1');
      expect(info.givenName, 'Ali');
      expect(info.familyName, 'Karim');
      expect(info.sexAtBirth, 'male');
      expect(info.citizenFullName, 'Ali Omer Karim');
      // `picture` falls back to the citizen registry picture when absent.
      expect(info.picture, 'https://cdn.example.com/a.png');
    });

    test('accepts the camelCase bridge shape', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'givenName': 'Ali',
        'familyName': 'Karim',
        'citizenThird': 'Rashid',
      });

      expect(info.givenName, 'Ali');
      expect(info.familyName, 'Karim');
      expect(info.citizenThird, 'Rashid');
    });

    test('rejects a missing, empty or non-string sub', () {
      expect(
        () => KrdpassUserInfo.fromJson(const {'name': 'Ali'}),
        throwsFormatException,
      );
      expect(
        () => KrdpassUserInfo.fromJson(const {'sub': ''}),
        throwsFormatException,
      );
      expect(
        () => KrdpassUserInfo.fromJson(const {'sub': 42}),
        throwsFormatException,
      );
    });

    test('raw falls back to the whole payload and keeps unknown claims', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'some_future_claim': 'value',
      });

      expect(info.raw['some_future_claim'], 'value');
    });

    test('upns parses an array of strings', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'upns': ['old-upn-1', 'old-upn-2'],
      });

      expect(info.upns, ['old-upn-1', 'old-upn-2']);
    });

    test('upns defaults to an empty list when absent', () {
      final info = KrdpassUserInfo.fromJson(const {'sub': 'user-1'});

      expect(info.upns, isEmpty);
    });

    test('upns falls back to an empty list for a non-list value', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'upns': 'not-a-list',
      });

      expect(info.upns, isEmpty);
    });

    test(
      'upns falls back to an empty list for a list with non-string entries',
      () {
        final info = KrdpassUserInfo.fromJson(const {
          'sub': 'user-1',
          'upns': ['old-upn-1', 1],
        });

        expect(info.upns, isEmpty);
      },
    );

    // CAS sends '' for a claim it has no value for; Android reads those as null,
    // so an app branching on `upn == null` must see the same thing here.
    test('reads an empty string claim as null', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'upn': '',
        'email': '',
        'given_name': '',
      });

      expect(info.upn, isNull);
      expect(info.email, isNull);
      expect(info.givenName, isNull);
    });

    test('reads a whitespace-only claim as null', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'upn': '   ',
        'birthdate': '\t\n',
        'sexAtBirth': ' ',
      });

      expect(info.upn, isNull);
      expect(info.birthdate, isNull);
      expect(info.sexAtBirth, isNull);
    });

    test('keeps a padded claim untrimmed, the filter only drops blanks', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'upn': ' 1990123456 ',
      });

      expect(info.upn, ' 1990123456 ');
    });

    test('falls back to the citizen picture when picture is blank', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'picture': '  ',
        'citizen_profile_picture': 'https://cdn.example.com/a.png',
      });

      expect(info.picture, 'https://cdn.example.com/a.png');
    });

    // sub keeps its own rule: empty fails the parse, blank does not, matching
    // the other SDKs.
    test('accepts a whitespace-only sub', () {
      expect(KrdpassUserInfo.fromJson(const {'sub': ' '}).sub, ' ');
    });

    // Blank entries inside upns survive, matching Android; the list is stored,
    // never displayed.
    test('upns keeps blank entries', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'upns': ['old-upn-1', '', '  '],
      });

      expect(info.upns, ['old-upn-1', '', '  ']);
    });

    test('toString redacts the identifying claims', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'name': 'Ali Karim',
      });

      expect(info.toString(), isNot(contains('user-1')));
      expect(info.toString(), isNot(contains('Ali Karim')));
    });

    test('value equality covers the typed claims', () {
      const json = {'sub': 'user-1', 'given_name': 'Ali'};
      expect(
        KrdpassUserInfo.fromJson(json),
        equals(KrdpassUserInfo.fromJson(json)),
      );
      expect(
        KrdpassUserInfo.fromJson(json).hashCode,
        equals(KrdpassUserInfo.fromJson(json).hashCode),
      );
      expect(
        KrdpassUserInfo.fromJson(json),
        isNot(equals(KrdpassUserInfo.fromJson(const {'sub': 'user-2'}))),
      );
    });
  });

  group('KrdpassUserInfo.citizenFullName', () {
    test('joins all four parts when all are present', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'citizen_first': 'Ali',
        'citizen_second': 'Omer',
        'citizen_third': 'Rashid',
        'citizen_surname': 'Karim',
      });

      expect(info.citizenFullName, 'Ali Omer Rashid Karim');
    });

    test('drops null, empty and whitespace-only parts', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'citizen_first': 'Ali',
        'citizen_second': ' ',
        'citizen_third': '',
        'citizen_surname': 'Karim',
      });

      expect(info.citizenFullName, 'Ali Karim');
    });

    test('drops a whitespace-only part in every position', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'citizen_first': '  ',
        'citizen_second': 'Omer',
        'citizen_third': '\t',
        'citizen_surname': '\n',
      });

      expect(info.citizenFullName, 'Omer');
    });

    test('trims surrounding whitespace on every retained part', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'citizen_first': ' Ali ',
        'citizen_second': '  Aram  ',
        'citizen_third': 'Rashid',
        'citizen_surname': ' Karim',
      });

      expect(info.citizenFullName, 'Ali Aram Rashid Karim');
    });

    test('a padded middle part does not produce a double space', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'citizen_first': 'Ali',
        'citizen_second': ' Aram ',
        'citizen_surname': 'Karim',
      });

      expect(info.citizenFullName, 'Ali Aram Karim');
      expect(info.citizenFullName, isNot(contains('  ')));
    });

    test('is null, not an empty string, when no part survives', () {
      final info = KrdpassUserInfo.fromJson(const {
        'sub': 'user-1',
        'citizen_first': ' ',
        'citizen_surname': '',
      });

      expect(info.citizenFullName, isNull);
    });

    test('is null when the citizen claims are absent entirely', () {
      final info = KrdpassUserInfo.fromJson(const {'sub': 'user-1'});

      expect(info.citizenFullName, isNull);
    });
  });

  group('KrdpassConfig.validate', () {
    KrdpassConfig config(String clientId, String redirectUri) =>
        KrdpassConfig(clientId: clientId, redirectUri: redirectUri);

    test('accepts an HTTPS redirect URI with a host', () {
      expect(
        () => config('client', 'https://app.example.com/callback').validate(),
        returnsNormally,
      );
    });

    test('rejects an empty clientId', () {
      expect(
        () => config('', 'https://app.example.com/callback').validate(),
        throwsArgumentError,
      );
    });

    test('rejects an empty redirect URI', () {
      expect(() => config('client', '').validate(), throwsArgumentError);
    });

    test('rejects a non-HTTPS redirect URI', () {
      expect(
        () => config('client', 'http://app.example.com/callback').validate(),
        throwsStateError,
      );
      expect(
        () => config('client', 'myapp://callback').validate(),
        throwsStateError,
      );
    });

    test('rejects a redirect URI with no host', () {
      expect(
        () => config('client', 'https:///callback').validate(),
        throwsStateError,
      );
    });
  });
}
