import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'home.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Lora', 'DMSans', 'Roboto', 'NotoEmoji']) {
      final license = await rootBundle.loadString('assets/fonts/$font-OFL.txt');
      yield LicenseEntryWithLineBreaks(['$font font'], license);
    }
  });
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  final store = AppStore();
  Object? error;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      await store.initialize();
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ready) return PocklinoApp(store: store);
    return MaterialApp(
      title: 'Pocklino',
      debugShowCheckedModeBanner: false,
      theme: PocklinoTheme.light,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PocketMark(size: 88),
                const SizedBox(height: 24),
                if (error == null) const CircularProgressIndicator(),
                if (error != null) ...[
                  const Text(
                    'Your pocket could not be opened.',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your saved data has not been reset. Try opening it again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: load, child: const Text('Try again')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PocklinoApp extends StatelessWidget {
  const PocklinoApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder:
          (context, _) => MaterialApp(
            title: 'Pocklino',
            debugShowCheckedModeBanner: false,
            theme: PocklinoTheme.light,
            darkTheme: PocklinoTheme.dark,
            themeMode: switch (store.themePreference) {
              'dark' => ThemeMode.dark,
              'system' => ThemeMode.system,
              _ => ThemeMode.light,
            },
            builder: (context, child) {
              final dark = Theme.of(context).brightness == Brightness.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: (dark
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor:
                          Theme.of(context).scaffoldBackgroundColor,
                      systemNavigationBarIconBrightness:
                          dark ? Brightness.light : Brightness.dark,
                    ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: PocketHome(store: store),
          ),
    );
  }
}
