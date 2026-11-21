import 'package:flutter/material.dart';

/// Look of the app, after the "church app" reference: a soft sky-blue gradient (with hills and a cross in the distance), big white
/// rounded sheets, a serif display font for headings, blue pill chips, and a white bottom bar with a floating round + button.
const brandBlue = Color(0xFF3F7FEA);
const brandNavy = Color(0xFF2B5FC7);
const skyTop = Color(0xFF6C9CEA);
const skyBottom = Color(0xFFBBD8F3);
const lavender = Color(0xFFE6EFFB); // soft blue tint
const panelWhite = Color(0xFFF6F9FE);
const accentOrange = Color(0xFFFDB846);
const accentGreen = Color(0xFF5BC17A);
const accentSky = Color(0xFF42B8F5);
const accentPink = Color(0xFFF0668F);
const accentViolet = Color(0xFF8B6CF0);

const serifFont = 'DMSerif';
const bodyFont = 'Poppins';

/// Heading style. Kept under the old name: it is now Poppins SemiBold (clean and easy to read), slightly smaller than the
/// size given because Poppins is wider than a serif face.
TextStyle serif(double size, {Color? color, FontWeight? weight}) =>
    TextStyle(fontFamily: bodyFont, fontSize: size >= 30 ? size * 0.82 : size * 0.88, color: color, fontWeight: weight ?? FontWeight.w600, height: 1.2, letterSpacing: -0.2);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ColorScheme.fromSeed(seedColor: brandBlue, brightness: b);
  final cs = dark
      ? base.copyWith(primary: const Color(0xFF8FB5FF), surface: const Color(0xFF111A2B))
      : base.copyWith(primary: brandBlue, onPrimary: Colors.white, primaryContainer: const Color(0xFFDCE8FD), onPrimaryContainer: brandNavy, surface: panelWhite);
  final text = (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(fontFamily: bodyFont);
  return ThemeData(
    useMaterial3: true,
    fontFamily: bodyFont,
    colorScheme: cs,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: text.copyWith(
      headlineLarge: serif(34), headlineMedium: serif(30), headlineSmall: serif(26),
      titleLarge: serif(22), titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: serif(24, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: dark ? cs.surfaceContainerHigh : Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: brandBlue.withValues(alpha: 0.25),
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: dark ? cs.surfaceContainerHigh : const Color(0xFFE4EDFC),
      selectedColor: brandBlue,
      secondarySelectedColor: brandBlue,
      labelStyle: TextStyle(fontFamily: bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: dark ? cs.onSurface : brandNavy),
      secondaryLabelStyle: const TextStyle(fontFamily: bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(const StadiumBorder()),
        side: WidgetStateProperty.all(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brandBlue : (dark ? cs.surfaceContainerHigh : const Color(0xFFE4EDFC))),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : (dark ? cs.onSurface : brandNavy)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: const StadiumBorder(), textStyle: const TextStyle(fontFamily: bodyFont, fontWeight: FontWeight.w600, fontSize: 15))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder(), side: const BorderSide(color: brandBlue))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: const StadiumBorder())),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? cs.surfaceContainerHigh : const Color(0xFFEEF3FB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: brandBlue, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Colors.red)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: brandBlue, foregroundColor: Colors.white, elevation: 6),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), titleTextStyle: serif(22, color: dark ? Colors.white : Colors.black87)),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: dark ? cs.surfaceContainer : Colors.white, surfaceTintColor: Colors.transparent, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30)))),
    dividerTheme: DividerThemeData(color: dark ? Colors.white12 : const Color(0xFFE3EAF6)),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: brandNavy, contentTextStyle: const TextStyle(fontFamily: bodyFont, color: Colors.white)),
    listTileTheme: const ListTileThemeData(iconColor: brandBlue),
  );
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color panelColor(BuildContext c) => isDark(c) ? const Color(0xFF111A2B) : panelWhite;
Color cardColor(BuildContext c) => isDark(c) ? Theme.of(c).colorScheme.surfaceContainerHigh : Colors.white;

/// The soft blue shadow under cards and tiles.
List<BoxShadow> softShadow(BuildContext c) => [BoxShadow(color: brandBlue.withValues(alpha: isDark(c) ? 0.0 : 0.10), blurRadius: 20, offset: const Offset(0, 6))];

// ====================================================================== background
/// Sky gradient with distant hills and a cross, behind every screen.
class SkyBackground extends StatelessWidget {
  final Widget child;
  const SkyBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dark ? const [Color(0xFF1D3263), Color(0xFF0B1220)] : const [skyTop, skyBottom])),
      child: CustomPaint(painter: _HillsPainter(dark), child: child),
    );
  }
}

class _HillsPainter extends CustomPainter {
  final bool dark;
  _HillsPainter(this.dark);
  @override
  void paint(Canvas canvas, Size s) {
    final a = Colors.white.withValues(alpha: dark ? 0.05 : 0.16);
    // cross on the hill (right)
    final cross = Paint()..color = a;
    final cx = s.width * 0.82, top = s.height * 0.58;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 6, top, 12, s.height * 0.3), const Radius.circular(3)), cross);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 52, top + s.height * 0.07, 104, 12), const Radius.circular(3)), cross);
    final hills = Path()
      ..moveTo(0, s.height * 0.86)
      ..quadraticBezierTo(s.width * 0.15, s.height * 0.78, s.width * 0.32, s.height * 0.84)
      ..quadraticBezierTo(s.width * 0.55, s.height * 0.74, s.width * 0.75, s.height * 0.83)
      ..quadraticBezierTo(s.width * 0.9, s.height * 0.78, s.width, s.height * 0.85)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(hills, Paint()..color = a);
  }

  @override
  bool shouldRepaint(covariant _HillsPainter old) => old.dark != dark;
}

// ====================================================================== scaffold
/// A screen = the sky background, a header (app bar) on it, and the content on a big white sheet with rounded top corners.
class SkyScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? header, body, floatingActionButton, bottomNavigationBar, drawer;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  const SkyScaffold({super.key, this.appBar, this.header, this.body, this.floatingActionButton, this.floatingActionButtonLocation, this.bottomNavigationBar, this.drawer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      body: Column(children: [
        if (header != null) header!,
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: panelColor(context),
              borderRadius: BorderRadius.vertical(top: const Radius.circular(34), bottom: Radius.circular(bottomNavigationBar == null ? 0 : 0)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(34)), child: body ?? const SizedBox.shrink()),
          ),
        ),
      ]),
    );
  }
}

/// Round white icon button used on the gradient (menu, back, ...).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const RoundIconButton({super.key, required this.icon, required this.onTap, this.tooltip = ''});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: brandBlue.withValues(alpha: 0.3),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: brandNavy, size: 22))),
        ),
      );
}

// ====================================================================== bottom bar
class NavItem {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool selected;
  const NavItem(this.icon, this.tip, this.onTap, {this.selected = false});
}

/// White bottom bar with a notch for the floating + button: two icons left, two right.
class BrandBottomBar extends StatelessWidget {
  final List<NavItem> items; // exactly four
  const BrandBottomBar({super.key, required this.items});

  Widget _b(NavItem i) => IconButton(
        tooltip: i.tip,
        onPressed: i.onTap,
        icon: Icon(i.icon, size: 26, color: i.selected ? brandBlue : const Color(0xFF9AA9C4)),
      );

  @override
  Widget build(BuildContext context) => BottomAppBar(
        color: panelColor(context),
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: brandBlue.withValues(alpha: 0.35),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _b(items[0]), _b(items[1]), const SizedBox(width: 56), _b(items[2]), _b(items[3]),
        ]),
      );
}

const brandFabLocation = FloatingActionButtonLocation.centerDocked;

class BrandFab extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const BrandFab({super.key, required this.icon, required this.onPressed, this.tooltip = ''});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64, height: 64,
        child: FloatingActionButton(heroTag: null, shape: const CircleBorder(), tooltip: tooltip, onPressed: onPressed, child: Icon(icon, size: 32)),
      );
}

// ====================================================================== small pieces
/// White rounded card used for list rows.
class RowCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const RowCard({super.key, required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24), boxShadow: softShadow(context)),
        child: Material(color: Colors.transparent, borderRadius: BorderRadius.circular(24), child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: child)),
      );
}

/// Rounded search field (used on the home screen and in lists).
InputDecoration searchDecoration(String hint) => InputDecoration(
      prefixIcon: const Icon(Icons.search, color: Color(0xFF9AA9C4)),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA9C4), fontSize: 14),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: brandBlue)),
    );

/// A pill with an icon (the "Church / Connect / Events" chips of the reference).
class PillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const PillChip({super.key, required this.icon, required this.label, required this.onTap, this.filled = false});
  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : brandNavy;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: filled ? brandBlue : (isDark(context) ? Theme.of(context).colorScheme.surfaceContainerHigh : const Color(0xFFE4EDFC)),
        shape: const StadiumBorder(),
        elevation: filled ? 4 : 0,
        shadowColor: brandBlue.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: isDark(context) && !filled ? null : fg),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: isDark(context) && !filled ? null : fg, fontWeight: FontWeight.w600, fontSize: 13)),
          ])),
        ),
      ),
    );
  }
}

/// Small church illustration (steeple, cross, door, clouds) for the welcome screen and the "next event" card.
class ChurchIllustration extends StatelessWidget {
  final double size;
  final bool onBlue; // lighter palette on the blue card
  const ChurchIllustration({super.key, this.size = 120, this.onBlue = false});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _ChurchPainter(onBlue)));
}

class _ChurchPainter extends CustomPainter {
  final bool onBlue;
  _ChurchPainter(this.onBlue);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final wall = Paint()..color = Colors.white;
    final roof = Paint()..color = onBlue ? const Color(0xFF2B5FC7) : brandBlue;
    final dark = Paint()..color = onBlue ? const Color(0xFF1F4BA3) : brandNavy;
    final gold = Paint()..color = accentOrange;
    // cloud
    final cloud = Paint()..color = Colors.white.withValues(alpha: onBlue ? 0.35 : 0.9);
    canvas.drawCircle(Offset(w * 0.14, h * 0.28), w * 0.07, cloud);
    canvas.drawCircle(Offset(w * 0.22, h * 0.25), w * 0.09, cloud);
    canvas.drawCircle(Offset(w * 0.31, h * 0.29), w * 0.07, cloud);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, h * 0.28, w * 0.28, h * 0.07), Radius.circular(w * 0.03)), cloud);
    // nave
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.1, h * 0.62, w * 0.8, h * 0.3), Radius.circular(w * 0.03)), wall);
    // tower
    canvas.drawRect(Rect.fromLTWH(w * 0.36, h * 0.34, w * 0.28, h * 0.58), wall);
    // steeple
    final spire = Path()..moveTo(w * 0.34, h * 0.36)..lineTo(w * 0.5, h * 0.1)..lineTo(w * 0.66, h * 0.36)..close();
    canvas.drawPath(spire, roof);
    // cross
    canvas.drawRect(Rect.fromLTWH(w * 0.488, h * 0.0, w * 0.024, h * 0.13), gold);
    canvas.drawRect(Rect.fromLTWH(w * 0.45, h * 0.035, w * 0.1, h * 0.024), gold);
    // roofs of the nave
    final left = Path()..moveTo(w * 0.06, h * 0.64)..lineTo(w * 0.36, h * 0.54)..lineTo(w * 0.36, h * 0.64)..close();
    final right = Path()..moveTo(w * 0.94, h * 0.64)..lineTo(w * 0.64, h * 0.54)..lineTo(w * 0.64, h * 0.64)..close();
    canvas.drawPath(left, roof);
    canvas.drawPath(right, roof);
    // windows and door
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.455, h * 0.43, w * 0.09, h * 0.12), Radius.circular(w * 0.045)), dark);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.44, h * 0.72, w * 0.12, h * 0.2), Radius.circular(w * 0.06)), roof);
    for (final x in [0.17, 0.27, 0.68, 0.78]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * x, h * 0.7, w * 0.06, h * 0.12), Radius.circular(w * 0.03)), dark);
    }
  }

  @override
  bool shouldRepaint(covariant _ChurchPainter old) => old.onBlue != onBlue;
}


/// App name in the logo colours (Freely = orange, CMS = blue), bold, on a white pill so it reads on the coloured header.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 3))]),
        child: const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Freely ', style: TextStyle(color: Color(0xFFFF6A00))),
            TextSpan(text: 'CMS', style: TextStyle(color: Color(0xFF0047CC))),
          ]),
          style: TextStyle(fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w800, fontStyle: FontStyle.normal),
        ),
      );
}
