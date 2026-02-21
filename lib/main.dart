import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'providers/theme_provider.dart';
import 'providers/linux_environment_provider.dart';
import 'providers/project_provider.dart';
import 'providers/editor_provider.dart';
import 'providers/terminal_provider.dart';
import 'screens/splash_screen.dart';
import 'services/linux_environment_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize services
  final linuxService = LinuxEnvironmentService();
  await linuxService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LinuxEnvironmentProvider(linuxService)),
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider(create: (_) => EditorProvider()),
        ChangeNotifierProxyProvider<LinuxEnvironmentProvider, TerminalProvider>(
          create: (context) => TerminalProvider(context.read<LinuxEnvironmentProvider>(), linuxService),
          update: (context, linuxProvider, terminalProvider) =>
              terminalProvider ?? TerminalProvider(linuxProvider, linuxService),
        ),
      ],
      child: const PyomApp(),
    ),
  );
}

class PyomApp extends StatelessWidget {
  const PyomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return MaterialApp(
              title: 'Pyom',
              debugShowCheckedModeBanner: false,
              theme: _buildLightTheme(lightDynamic),
              darkTheme: _buildDarkTheme(darkDynamic),
              themeMode: themeProvider.themeMode,
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }

  ThemeData _buildLightTheme(ColorScheme? dynamic) {
    return FlexThemeData.light(
      scheme: FlexScheme.blueM3,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 7,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        appBarBackgroundSchemeColor: SchemeColor.primaryContainer,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      swapLegacyOnMaterial3: true,
    );
  }

  ThemeData _buildDarkTheme(ColorScheme? dynamic) {
    return FlexThemeData.dark(
      scheme: FlexScheme.blueM3,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 13,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 20,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        appBarBackgroundSchemeColor: SchemeColor.primaryContainer,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
      swapLegacyOnMaterial3: true,
    );
  }
}
