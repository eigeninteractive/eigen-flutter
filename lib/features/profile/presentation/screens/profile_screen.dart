import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:eigen_api/eigen_api.dart';
import 'package:eigen_flutter/features/profile/providers/profile_providers.dart';
import 'package:eigen_flutter/features/rating/presentation/widgets/player_ratings.dart';

/// Profile screen: cinematic hero, per-pool rating cards, link to history.
///
/// Avatar tap → change photo directly.
/// ✎ icon → edit display name and username.
/// Ratings refresh automatically on each navigation (auto-dispose providers).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final profileAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            actions: [
              if (profileAsync.hasValue)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit profile',
                  onPressed: () => _showEditSheet(context, profileAsync.value!),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 72,
                end: 72,
                bottom: 14,
              ),
              centerTitle: true,
              title: profileAsync.whenOrNull(
                data: (p) => Text(
                  p.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              background: profileAsync.when(
                data: (p) => _HeroBanner(
                  avatarUrl: p.avatarUrl,
                  username: p.username,
                  onAvatarTap: _pickAndUploadAvatar,
                ),
                loading: () => const _HeroBanner(
                  avatarUrl: null,
                  username: null,
                  onAvatarTap: null,
                ),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: _RatingsSection()),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, Profile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final ImageSource? source;
      if (kIsWeb) {
        source = ImageSource.gallery;
      } else {
        source = await _showImageSourceSheet();
        if (source == null) return;
      }

      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, maxWidth: 1024);
      if (file == null || !mounted) return;

      final cropped = await _cropImage(file.path);
      if (cropped == null || !mounted) return;

      final bytes = await cropped.readAsBytes();
      await ref.read(currentUserProfileProvider.notifier).uploadAvatar(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile photo updated!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update photo: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<CroppedFile?> _cropImage(String sourcePath) {
    return ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        WebUiSettings(context: context, presentStyle: WebPresentStyle.dialog),
      ],
    );
  }

  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero banner ───────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.avatarUrl,
    required this.username,
    required this.onAvatarTap,
  });

  final String? avatarUrl;
  final String? username;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colorScheme.primaryContainer, colorScheme.surface],
              ),
            ),
          ),
        ),
        Positioned(
          top: kToolbarHeight,
          left: 0,
          right: 0,
          bottom: 40,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onAvatarTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _AvatarDisplay(avatarUrl: avatarUrl, radius: 60),
                    if (onAvatarTap != null)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: colorScheme.primary,
                          child: Icon(
                            Icons.edit,
                            size: 12,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (username != null) ...[
                const SizedBox(height: 8),
                Text(
                  '@$username',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Avatar display ────────────────────────────────────────────────────────────

class _AvatarDisplay extends StatelessWidget {
  const _AvatarDisplay({required this.avatarUrl, required this.radius});

  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl == null) return _PersonIconCircle(radius: radius);

    return CachedNetworkImage(
      imageUrl: avatarUrl!,
      imageBuilder: (_, imageProvider) =>
          CircleAvatar(radius: radius, backgroundImage: imageProvider),
      placeholder: (_, _) => _PersonIconCircle(radius: radius),
      errorWidget: (_, _, _) => _PersonIconCircle(radius: radius),
    );
  }
}

class _PersonIconCircle extends StatelessWidget {
  const _PersonIconCircle({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.person_outline,
        size: radius,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ── Ratings section ───────────────────────────────────────────────────────────

class _RatingsSection extends StatelessWidget {
  const _RatingsSection();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Text(
              'Ratings',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const PlayerRatings.me(),
        ],
      ),
    );
  }
}

// ── Edit profile sheet ────────────────────────────────────────────────────────

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _displayName;
  late String _username;
  bool _saving = false;

  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_.]{3,20}$');

  @override
  void initState() {
    super.initState();
    _displayName = widget.profile.displayName;
    _username = widget.profile.username;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
              child: Text('Edit Profile', style: textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  TextFormField(
                    key: ValueKey('username_${widget.profile.id}'),
                    initialValue: widget.profile.username,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'Enter your username',
                      helperText: '3-20 characters: letters, numbers, _ or .',
                      prefixIcon: Icon(Icons.alternate_email),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter a username';
                      }
                      if (!_usernameRegex.hasMatch(v.trim())) {
                        return 'Use 3-20 characters: letters, numbers, _ or .';
                      }
                      return null;
                    },
                    onSaved: (v) => _username = v ?? '',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: ValueKey('displayName_${widget.profile.id}'),
                    initialValue: widget.profile.displayName,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      hintText: 'Enter your display name',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter a display name';
                      }
                      if (v.trim().length < 2) {
                        return 'Display name must be at least 2 characters';
                      }
                      return null;
                    },
                    onSaved: (v) => _displayName = v ?? '',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _saving = true);
    try {
      await ref
          .read(currentUserProfileProvider.notifier)
          .updateProfileFields(
            username: _username.trim(),
            displayName: _displayName.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _errorMessage(Object error) {
    final s = error.toString();
    if (s.contains('Username already taken')) return 'Username already taken';
    if (s.contains('Username must be')) {
      return 'Username must be 3-20 characters, alphanumeric, underscores, or dots only';
    }
    return 'Failed to save: $s';
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
