// lib/screens/onboarding_screen.dart
// First-launch onboarding. 3 pages, paginated, skip-able.
// On completion, marks session.hasSeenOnboarding and the root router
// advances to the home screen.
//
// Round 12 polish (ON1-ON4): touch-up — explicit theme colors + animated
// background tint that follows the current page's accent.

import 'package:flutter/material.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctl = PageController();
  int _idx = 0;

  static const _ownerPages = <_OnbPageData>[
    _OnbPageData(
      icon: Icons.apartment,
      title: 'Manage cleaning requests',
      body:
          'Create cleaning requests for your rental units and track every booking in one place.',
      accent: AppColors.primary,
    ),
    _OnbPageData(
      icon: Icons.person_search,
      title: 'Find an eligible provider',
      body:
          'Mandatory availability and conflict checks are applied first. Eligible providers are then ranked by distance, rating, and workload.',
      accent: AppColors.secondary,
    ),
    _OnbPageData(
      icon: Icons.verified,
      title: 'Track progress and evidence',
      body:
          'Follow the booking from Pending to Completed and review the provider’s before-and-after photos and completion remarks.',
      accent: AppColors.primaryLight,
    ),
  ];

  static const _providerPages = <_OnbPageData>[
    _OnbPageData(
      icon: Icons.inbox_outlined,
      title: 'Review incoming requests',
      body:
          'See the service details and requested interval before accepting or declining each Pending request.',
      accent: AppColors.primary,
    ),
    _OnbPageData(
      icon: Icons.event_available,
      title: 'Keep your schedule accurate',
      body:
          'Maintain declared availability and view the Accepted and In Progress bookings that occupy your schedule.',
      accent: AppColors.secondary,
    ),
    _OnbPageData(
      icon: Icons.add_a_photo_outlined,
      title: 'Record completion evidence',
      body:
          'Update job progress and submit before-and-after photos with completion remarks before marking work Completed.',
      accent: AppColors.primaryLight,
    ),
  ];

  List<_OnbPageData> _pagesFor(UserRole role) =>
      role == UserRole.provider ? _providerPages : _ownerPages;

  void _skip() => UserSessionAccess.of(context).markOnboardingSeen();

  void _next() {
    final pages = _pagesFor(UserSessionAccess.of(context).role);
    if (_idx < pages.length - 1) {
      _ctl.nextPage(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      UserSessionAccess.of(context).markOnboardingSeen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pagesFor(UserSessionAccess.of(context).role);
    final isLast = _idx == pages.length - 1;
    final sem = SemanticColors.of(context);
    final accent = pages[_idx].accent;
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        // ON1: subtle accent-tinted background that animates with the page
        color: accent.withOpacity(isLast ? 0.0 : 0.04),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: sem.textSecondary,
                  ),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _ctl,
                  onPageChanged: (i) => setState(() => _idx = i),
                  itemCount: pages.length,
                  itemBuilder: (ctx, i) => _OnbPage(data: pages[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pages.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _idx ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _idx ? pages[_idx].accent : sem.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(isLast ? 'Get started' : 'Next'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnbPageData {
  const _OnbPageData({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
}

class _OnbPage extends StatelessWidget {
  const _OnbPage({required this.data});
  final _OnbPageData data;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ON2: ring around icon for extra polish
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: data.accent.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: data.accent.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Icon(data.icon, size: 64, color: data.accent),
          ),
          const SizedBox(height: 32),
          Text(
            data.title,
            textAlign: TextAlign.center,
            // ON3: explicit theme color for title
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: sem.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: sem.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
