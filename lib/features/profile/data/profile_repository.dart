import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/core/api/engine_call.dart';

/// The signed-in user's own profile.
///
/// Everything here is scoped to the caller by their token, so no user id is
/// passed: `/me` is always "whoever this request is authenticated as". Reading
/// *another* player's public identity is [PlayerRepository]'s job.
class ProfileRepository {
  ProfileRepository(this._api);

  final MeApi _api;

  /// The caller's own profile, including the private fields (email) that the
  /// public [Player] projection omits.
  Future<Profile> getProfile() => engineData(() => _api.getProfile());

  /// Changes the caller's username: the unique, charset-constrained handle.
  ///
  /// Throws an [EngineException] with [ErrorCode.usernameTaken] or
  /// [ErrorCode.usernameInvalid]; both are field-level form errors rather than
  /// failures to report generically.
  Future<String> updateUsername(String username) async {
    final body = await engineData(
      () => _api.updateUsername(
        usernameUpdate: UsernameUpdate(username: username),
      ),
    );
    return body.username;
  }

  /// Changes the caller's display name: the free-form label shown beside their
  /// moves. Not unique: two players may share one, which is what the username
  /// disambiguates.
  Future<String> updateDisplayName(String displayName) async {
    final body = await engineData(
      () => _api.updateDisplayName(
        displayNameUpdate: DisplayNameUpdate(displayName: displayName),
      ),
    );
    return body.displayName;
  }

  /// Deletes the caller's account and all of its data.
  ///
  /// Irreversible. The server forfeits or cancels their live games, deletes the
  /// identity provider account, then purges the database, in that order, so a
  /// failure leaves the account intact and the call retriable.
  Future<void> deleteAccount() => engineCall(() => _api.deleteAccount());
}
