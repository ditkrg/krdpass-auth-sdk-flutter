import 'package:demo_krdpass_auth/theme.dart';
import 'package:demo_krdpass_auth/widgets/krdpass_logo.dart';
import 'package:flutter/material.dart';

class LandingScreen extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool citizenScope;
  final bool offlineScope;
  final bool useServerMode;
  final ValueChanged<bool> onCitizenScopeChange;
  final ValueChanged<bool> onOfflineScopeChange;
  final ValueChanged<bool> onServerModeChange;
  final VoidCallback onSignInClick;
  final VoidCallback onClearError;

  const LandingScreen({
    required this.loading,
    this.error,
    required this.citizenScope,
    required this.offlineScope,
    required this.useServerMode,
    required this.onCitizenScopeChange,
    required this.onOfflineScopeChange,
    required this.onServerModeChange,
    required this.onSignInClick,
    required this.onClearError,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                // Logo Section
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.lock, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 16), // Compacted spacing
                Text(
                  'KRDPass',
                  style: TextStyle(
                    fontSize: 28, // HeadlineMedium roughly
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Digital Identity Demo',
                  style: TextStyle(
                    fontSize: 14, // BodyMedium
                    color: Theme.of(
                      context,
                    ).extension<KrdpassThemeColors>()!.caption,
                  ),
                ),
                const SizedBox(height: 32), // Compacted spacing
                // Error Handling
                if (error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning,
                          color: Theme.of(context).colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                              maxLines: null,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onClearError,
                          icon: Icon(
                            Icons.close,
                            color: Theme.of(context).colorScheme.error,
                            size: 16,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          iconSize: 16,
                        ),
                      ],
                    ),
                  ),

                // Configuration Section (Card Style)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: Theme.of(context)
                          .extension<KrdpassThemeColors>()!
                          .line
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  color: Theme.of(context).cardTheme.color,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      children: [
                        // Citizen Data Toggle
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Citizen Data',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Include citizen_identity scope',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .extension<KrdpassThemeColors>()!
                                          .caption,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: citizenScope,
                                onChanged: onCitizenScopeChange,
                                activeThumbColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Theme.of(context)
                                .extension<KrdpassThemeColors>()!
                                .line
                                .withValues(alpha: 0.5),
                          ),
                        ),

                        // Offline Access Toggle (Refresh Token)
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Offline Access',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Include offline_access scope (Refresh Token)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .extension<KrdpassThemeColors>()!
                                          .caption,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: offlineScope,
                                onChanged: onOfflineScopeChange,
                                activeThumbColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Theme.of(context)
                                .extension<KrdpassThemeColors>()!
                                .line
                                .withValues(alpha: 0.5),
                          ),
                        ),

                        // Auth Mode Toggle
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auth Mode',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    useServerMode
                                        ? 'Backend-mediated (Secure)'
                                        : 'Direct (Client-only)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: useServerMode,
                                onChanged: onServerModeChange,
                                activeThumbColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24), // Compacted spacing
                // Action Button
                SizedBox(
                  width: double.infinity,
                  height: 52, // Matches Developer Console button height
                  child: FilledButton(
                    onPressed: loading ? null : onSignInClick,
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              KRDPASSLogo(size: 20),
                              const SizedBox(width: 12),
                              Text(
                                'Sign in with KRDPASS',
                                style: TextStyle(
                                  fontSize: 16,
                                  letterSpacing: 0.02 * 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
