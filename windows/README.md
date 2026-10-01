# Windows build

Pocklino supports native Windows notes, lists, local storage, file/paste receiving and QR display. Camera scanning is not available in the Windows app.

Normally, use `flutter build windows --release`. Flutter 3.29.3 recognizes Visual Studio 2022 but incorrectly selects the Visual Studio 2019 generator for Visual Studio 2026. The project includes a local workaround:

```powershell
powershell -ExecutionPolicy Bypass -File windows/build_release.ps1
```

If Flutter is not on PATH, pass its executable explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File windows/build_release.ps1 -Flutter 'C:\path\to\flutter\bin\flutter.bat'
```

The script attempts the normal Flutter build first. Only when the known generator mismatch occurs does it use the installed Visual Studio 2026 CMake generator with Flutter's generated configuration. It does not patch Flutter, change the global environment or delete another build directory. It requires the desktop C++ workload, Windows SDK and Visual Studio's CMake component.

The fallback output is `build/windows-vs2026/x64/runner/Release/pocklino.exe`. Keep the whole `Release` directory together when running or packaging: the Flutter/plugin DLLs and `data` directory are required. This is an unsigned desktop build, not an installer or Microsoft Store package. Install the current Microsoft Visual C++ runtime if it is missing on a target machine.

Build generation, compilation and asset installation were verified locally with Visual Studio Community 2026 18.1.1 and Flutter 3.29.3. Native window behavior, file dialogs, accessibility and distribution on a clean Windows device still require manual testing.
