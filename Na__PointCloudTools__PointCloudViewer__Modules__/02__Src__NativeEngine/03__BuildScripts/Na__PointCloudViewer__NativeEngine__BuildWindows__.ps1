# =============================================================================
# NA POINT CLOUD VIEWER - NATIVE ENGINE - WINDOWS BUILD SCRIPT
# =============================================================================
#
# FILE       : Na__PointCloudViewer__NativeEngine__BuildWindows__.ps1
# PURPOSE    : Configure + build the native engine DLL with MSVC (VS 2022 Build
#              Tools), CMake and Ninja - the decimator's toolchain.
#
# USAGE      : powershell -ExecutionPolicy Bypass -File <this file>
#
# NOTES:
# - The modules folder is mapped to a FREE drive letter for the build (subst)
#   to stay clear of MSVC's path-length limits, then unmapped again. It never
#   reuses a letter another build already mapped.
# - The build tree lives in %TEMP%; only the DLL lands in the repo.
# - Rebuilding while SketchUp runs is safe: the plugin loads a shadow COPY of
#   the DLL, so this file is never locked. Settings > Reload Plugin picks up
#   the new build without restarting SketchUp.
#
# =============================================================================

$ErrorActionPreference = "Stop"

$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeRoot  = (Resolve-Path (Join-Path $ScriptRoot "..")).Path
$ModuleRoot  = (Resolve-Path (Join-Path $NativeRoot "..")).Path
$BuildRoot   = Join-Path ([System.IO.Path]::GetTempPath()) "Na__PointCloudViewer__NativeBuild"
$OutputDll   = Join-Path $NativeRoot "04__Bin__WindowsSketchUp2026\Na__PointCloudViewer__NativeEngine.dll"

# -----------------------------------------------------------------------------
# REGION | Toolchain
# -----------------------------------------------------------------------------

function Na__Build__FindCommand([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Na__Build__FindVisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -eq 0 -and $path) { return $path.Trim() }
    }
    foreach ($candidate in @("C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
                             "C:\Program Files\Microsoft Visual Studio\2022\Community",
                             "C:\Program Files\Microsoft Visual Studio\2022\Professional")) {
        if (Test-Path (Join-Path $candidate "Common7\Tools\VsDevCmd.bat")) { return $candidate }
    }
    return $null
}

function Na__Build__FreeDriveLetter {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($letter in @('P','Q','R','S','T','U','V','W','Y','Z')) {
        if ($used -notcontains $letter) { return "$($letter):" }
    }
    throw "No free drive letter for the short build path."
}

# endregion -------------------------------------------------------------------

$cmake = Na__Build__FindCommand "cmake.exe"
$ninja = Na__Build__FindCommand "ninja.exe"
if (-not $cmake) { throw "cmake.exe was not found on PATH (python -m pip install cmake)." }
if (-not $ninja) { throw "ninja.exe was not found on PATH (python -m pip install ninja)." }
$vs = Na__Build__FindVisualStudio
if (-not $vs) { throw "Visual Studio 2022 Build Tools (C++ workload) were not found." }
$vsDevCmd = Join-Path $vs "Common7\Tools\VsDevCmd.bat"

# VsDevCmd calls vswhere from PATH; without this it prints a harmless warning.
$installerDir = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer"
if (Test-Path $installerDir) { $env:PATH = "$installerDir;$env:PATH" }

$drive = Na__Build__FreeDriveLetter
cmd.exe /c "subst $drive `"$ModuleRoot`"" | Out-Null
# Native tools write progress to stderr; Windows PowerShell 5.1 would turn that
# into a terminating error under "Stop". Success is judged by the exit code.
$ErrorActionPreference = "Continue"
try {
    $cmakeLists = "$drive\02__Src__NativeEngine\02__BuildSystem"
    New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
    $command = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 -no_logo && " +
               "cmake -S `"$cmakeLists`" -B `"$BuildRoot`" -G Ninja -DCMAKE_BUILD_TYPE=Release && " +
               "cmake --build `"$BuildRoot`" --config Release"
    cmd.exe /c "$command 2>&1"
    $buildExit = $LASTEXITCODE
}
finally {
    cmd.exe /c "subst $drive /D" | Out-Null
    $ErrorActionPreference = "Stop"
}
if ($buildExit -ne 0) { throw "Native build failed (exit $buildExit) - see the compiler output above." }

$dll = Get-Item $OutputDll
Write-Host ("[+] Built {0} ({1:N0} KB, {2})" -f $dll.Name, ($dll.Length / 1KB), $dll.LastWriteTime)
