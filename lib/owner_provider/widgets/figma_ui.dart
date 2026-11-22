// Figma page 192:605. Scoped to migrated screens; legacy screens keep their theme.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

class FigmaUi {
  static const ink = Color(0xFF17233B);
  static const muted = Color(0xFF697890);
  static const blue = Color(0xFF3159D9);
  static const background = Color(0xFFF5F7FC);
  static TextStyle text(double size, {bool bold = false, Color? color}) =>
      TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          height: 1.25,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: color ?? ink);
  static ThemeData get theme => AppTheme.light().copyWith(
        textTheme: AppTheme.light().textTheme.apply(fontFamily: 'Inter'),
        colorScheme: AppTheme.light().colorScheme.copyWith(primary: blue),
        scaffoldBackgroundColor: background,
      );
}

/// Original exported vector layers, not screenshots of entire screens.
class FigmaSurface extends StatelessWidget {
  const FigmaSurface({super.key, required this.asset, required this.child});
  final String asset;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: IgnorePointer(
                child: SvgPicture.asset('assets/figma/$asset.svg',
                    fit: BoxFit.fill, excludeFromSemantics: true))),
        child,
      ]);
}

class FigmaHeader extends StatelessWidget implements PreferredSizeWidget {
  const FigmaHeader(
      {super.key,
      required this.title,
      required this.subtitle,
      this.variant = 'dashboard',
      this.trailing});
  final String title, subtitle, variant;
  final Widget? trailing;
  @override
  Size get preferredSize => const Size.fromHeight(126);
  @override
  Widget build(BuildContext context) => FigmaSurface(
        asset: '$variant-header',
        child: SizedBox(
            height: 126,
            child: Stack(children: [
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 28,
                  child: SvgPicture.asset(
                      'assets/figma/$variant-header-band.svg',
                      fit: BoxFit.fill,
                      excludeFromSemantics: true)),
              Padding(
                  padding: const EdgeInsets.fromLTRB(22, 45, 22, 0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: FigmaUi.text(22,
                                bold: true, color: Colors.white)),
                        const SizedBox(height: 7),
                        Text(subtitle,
                            style: FigmaUi.text(11,
                                color: const Color(0xFFDDE8FF))),
                      ])),
              if (trailing != null)
                Positioned(top: 0, right: 8, child: trailing!),
            ])),
      );
}

class FigmaButton extends StatelessWidget {
  const FigmaButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.variant = 'login',
      this.outlined = false});
  final String label, variant;
  final VoidCallback? onPressed;
  final bool outlined;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: FigmaSurface(
                asset: '$variant-${outlined ? 'outline' : 'primary'}-button',
                child: TextButton(
                    onPressed: onPressed,
                    style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        foregroundColor: outlined ? FigmaUi.blue : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(label,
                        style: FigmaUi.text(12,
                            bold: true,
                            color: outlined ? FigmaUi.blue : Colors.white))))),
      );
}

class FigmaOwnerNav extends StatelessWidget {
  const FigmaOwnerNav(
      {super.key,
      this.activeId,
      required this.onChange,
      this.variant = 'dashboard'});
  final String? activeId;
  final ValueChanged<String> onChange;
  final String variant;
  @override
  Widget build(BuildContext context) => FigmaSurface(
        asset: '$variant-navigation',
        child: SafeArea(
            top: false,
            child: SizedBox(
                height: 64,
                child: Row(children: [
                  for (final item in const [
                    ('home', '⌂', 'Home'),
                    ('browse', '◇', 'Providers'),
                    ('bookings', '▣', 'Bookings'),
                    ('profile', '○', 'Profile'),
                  ])
                    Expanded(
                        child: Semantics(
                            selected: activeId == item.$1,
                            child: TextButton(
                                onPressed: () => onChange(item.$1),
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(48, 64),
                                    shape: const RoundedRectangleBorder()),
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(item.$2,
                                          style: FigmaUi.text(18,
                                              bold: true,
                                              color: activeId == item.$1
                                                  ? FigmaUi.blue
                                                  : const Color(0xFF8A97AB))),
                                      const SizedBox(height: 10),
                                      Text(item.$3,
                                          style: FigmaUi.text(9,
                                              bold: activeId == item.$1,
                                              color: activeId == item.$1
                                                  ? FigmaUi.blue
                                                  : const Color(0xFF8A97AB))),
                                    ])))),
                ]))),
      );
}
