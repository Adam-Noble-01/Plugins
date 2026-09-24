$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeRoot = Resolve-Path (Join-Path $ScriptRoot "..")
$CMakeListsFolder = Join-Path $NativeRoot "02__BuildSystem"
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) "Na__TexturedPlaneToImage__NativeBuild"

function Na__BuildScript__FindCommand {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$visualStudioPath = $null
if (Test-Path $vswhere) {
    $visualStudioPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
    if ($visualStudioPath) { $visualStudioPath = $visualStudioPath.Trim() }
}

if (-not $visualStudioPath) {
    throw "MSVC Build Tools were not found."
}

$cmake = Na__BuildScript__FindCommand "cmake.exe"
if (-not $cmake) { throw "cmake.exe was not found on PATH." }

$vsDevCmd = Join-Path $visualStudioPath "Common7\Tools\VsDevCmd.bat"
$pluginsRoot = "C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins"
$shortDrive = "W:"
$existingSubst = cmd.exe /c subst
if ($existingSubst -notmatch [regex]::Escape("$shortDrive\")) {
    cmd.exe /c "subst $shortDrive `"$pluginsRoot`""
}

$nativeOnShortDrive = "$shortDrive\Na__Noble3dModellingTools__Modules__\10__PluginModules\35__SourceCode__TexturedPlaneToImage\02__NativeEngine"
$buildCommand = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 && cmake -S `"$nativeOnShortDrive\02__BuildSystem`" -B `"$shortDrive\na_plane_image_build`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DNA_OUTPUT_DIR=`"$nativeOnShortDrive/04__Bin__WindowsSketchUp2026`" && cmake --build `"$shortDrive\na_plane_image_build`" --config Release"
cmd.exe /c $buildCommand
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[+] Textured Plane to Image native sampler built."
