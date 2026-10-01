[CmdletBinding()]
param(
  [string]$Flutter = 'flutter',
  [string]$VisualStudioPath = ''
)

# Flutter 3.29 selects VS 2019 when it sees the newer VS 2026 installation.
# Keep that compatibility workaround inside this project; never patch the SDK.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectDirectory
try {
  $outputLines = New-Object 'System.Collections.Generic.List[string]'
  $savedErrorPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Flutter build windows --release 2>&1 | ForEach-Object {
      $line = $_.ToString()
      $outputLines.Add($line)
      Write-Host $line
    }
    $flutterExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $savedErrorPreference
  }

  if ($flutterExitCode -eq 0) {
    Write-Output 'Windows release: build/windows/x64/runner/Release/pocklino.exe'
    return
  }

  $outputText = $outputLines -join "`n"
  if ($outputText -notmatch 'Visual Studio 16 2019' -or
      $outputText -notmatch 'could not find any instance of Visual Studio') {
    throw 'The standard Flutter build failed for a reason other than the known Visual Studio 2026 detection issue. See the output above.'
  }

  if ([string]::IsNullOrWhiteSpace($VisualStudioPath)) {
    $vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (!(Test-Path -LiteralPath $vswherePath)) {
      throw 'Visual Studio discovery is unavailable. Pass -VisualStudioPath with the Visual Studio 2026 installation directory.'
    }
    $VisualStudioPath = (& $vswherePath -latest -products '*' -version '[18.0,19.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
  }
  if ([string]::IsNullOrWhiteSpace($VisualStudioPath)) {
    throw 'Visual Studio 2026 with the desktop C++ workload was not found.'
  }
  $cmakePath = Join-Path $VisualStudioPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
  if (!(Test-Path -LiteralPath $cmakePath)) {
    throw 'The Visual Studio CMake component is missing. Install it through the Visual Studio Installer.'
  }
  if (!(Test-Path -LiteralPath 'windows/flutter/ephemeral/generated_config.cmake')) {
    throw 'Flutter did not generate its Windows configuration; the fallback cannot proceed.'
  }

  Write-Host 'Using the installed Visual Studio 2026 generator with the Flutter-generated project.'
  & $cmakePath -S windows -B build/windows-vs2026/x64 -G 'Visual Studio 18 2026' -A x64 '-DFLUTTER_TARGET_PLATFORM=windows-x64' '-DCMAKE_POLICY_VERSION_MINIMUM=3.5'
  if ($LASTEXITCODE -ne 0) { throw 'Visual Studio 2026 CMake generation failed.' }
  & $cmakePath --build build/windows-vs2026/x64 --config Release --target INSTALL
  if ($LASTEXITCODE -ne 0) { throw 'The Windows release build failed.' }
  Write-Output 'Windows release: build/windows-vs2026/x64/runner/Release/pocklino.exe'
  Write-Output 'Keep the complete Release directory together: DLLs and the data directory are required.'
} finally {
  Pop-Location
}
