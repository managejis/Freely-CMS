import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freely_cms/screens/auth_screens.dart';
import 'package:freely_cms/ui.dart';

Future<void> _loadFonts() async {
  for (final f in {
    'DMSerif': ['assets/fonts/DMSerifDisplay-Regular.ttf'],
    'Poppins': ['assets/fonts/Poppins-Regular.ttf', 'assets/fonts/Poppins-Medium.ttf', 'assets/fonts/Poppins-SemiBold.ttf'],
  }.entries) {
    final l = FontLoader(f.key);
    for (final p in f.value) {
      l.addFont(Future.value(ByteData.view(File(p).readAsBytesSync().buffer)));
    }
    await l.load();
  }
}

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      builder: (c, child) => SkyBackground(child: child!),
      home: home,
    );

/// A static copy of the new look (cards, pills, bottom bar) so that the design can be reviewed as a picture.
class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      floatingActionButtonLocation: brandFabLocation,
      floatingActionButton: BrandFab(icon: Icons.add, onPressed: () {}),
      bottomNavigationBar: BrandBottomBar(items: [
        NavItem(Icons.home_rounded, 'Home', () {}, selected: true),
        NavItem(Icons.calendar_month_outlined, 'Events', () {}),
        NavItem(Icons.notifications_none_rounded, 'Announcements', () {}),
        NavItem(Icons.person_outline_rounded, 'Profile', () {}),
      ]),
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Row(children: [RoundIconButton(icon: Icons.menu_rounded, onTap: () {}), const Spacer(), Text('Grace Assembly', style: serif(18, color: Colors.white)), const Spacer(), const CircleAvatar(radius: 20, child: Icon(Icons.church))]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 110), children: [
        const Text('Hi, Aby', style: TextStyle(color: Colors.grey)),
        Text('Good Morning', style: serif(36)),
        const SizedBox(height: 14),
        TextField(decoration: searchDecoration('Search members, events, announcements')),
        const SizedBox(height: 14),
        SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, children: [
          PillChip(icon: Icons.people_alt_outlined, label: 'Members', onTap: () {}, filled: true),
          PillChip(icon: Icons.event_outlined, label: 'Events', onTap: () {}),
          PillChip(icon: Icons.fact_check_outlined, label: 'Attendance', onTap: () {}),
        ])),
        const SizedBox(height: 20),
        Text('Upcoming Events', style: serif(24)),
        const SizedBox(height: 10),
        Container(
          height: 168,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A8CF5), Color(0xFF2F6AE0)])),
          child: Stack(children: [
            const Positioned(right: 6, bottom: 6, child: ChurchIllustration(size: 130, onBlue: true)),
            Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Next Service', style: serif(22, color: Colors.white)),
              const Text('10:00 AM', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
              const Text('Sunday Worship · 22 Nov 2026', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),
        RowCard(child: ListTile(leading: const CircleAvatar(child: Text('J')), title: const Text('John Mathew', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('9876543210 · Mathew family'), trailing: const Text('Active', style: TextStyle(color: Colors.green)))),
      ]),
    );
  }
}

void main() {
  testWidgets('welcome and home look', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: _app(const WelcomeScreen())));
    await tester.pump();
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/welcome.png'));

    final key2 = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key2, child: _app(const _Preview())));
    await tester.pump();
    await expectLater(find.byKey(key2), matchesGoldenFile('goldens/home_preview.png'));
  });
}
