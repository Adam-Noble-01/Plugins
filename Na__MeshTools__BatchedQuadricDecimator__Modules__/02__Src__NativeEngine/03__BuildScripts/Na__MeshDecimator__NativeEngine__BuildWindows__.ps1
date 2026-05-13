param(
    [switch]$InstallMissingBuildTools
)

$ErrorActionPreference = "Stop"

$ScriptRoot       = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeRoot       = Resolve-Path (Join-Path $ScriptRoot "..")
$ModuleRoot       = Resolve-Path (Join-Path $NativeRoot "..")
$BuildRoot        = Join-Path ([System.IO.Path]::GetTempPath()) "Na__MeshDecimator__NativeBuild__WindowsSketchUp2026"
$CMakeListsFolder = Join-Path $NativeRoot "02__BuildSystem"
$DependencyRoot   = Join-Path $ModuleRoot "01__ExternalDependencies__VersionLocked"
$BuildToolsFolder = Join-Path $DependencyRoot "90__BuildTools__Manifest"
$ManifestPath     = Join-Path $BuildToolsFolder "Na__MeshDecimator__NativeEngine__DependencyManifest.json"
$VsBootstrapper   = Join-Path $BuildToolsFolder "vs_BuildTools_2022.exe"
$ShortDrive       = "X:"
$ShortModuleRoot  = "$ShortDrive\"
$ShortCMakeFolder = Join-Path $ShortModuleRoot "02__Src__NativeEngine\02__BuildSystem"

function Na__BuildScript__FindCommand {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Na__BuildScript__FindVsWhere {
    $path = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $path) { return $path }
    return $null
}

function Na__BuildScript__FindVisualStudioInstall {
    $vswhere = Na__BuildScript__FindVsWhere
    $fallbackPaths = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools",
        "C:\Program Files\Microsoft Visual Studio\2022\Community",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
    )

    if ($vswhere) {
        $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -eq 0 -and $installPath) { return $installPath.Trim() }

        $installPath = & $vswhere -latest -products * -property installationPath
        if ($LASTEXITCODE -eq 0 -and $installPath) {
            $candidate = $installPath.Trim()
            if (Test-Path (Join-Path $candidate "Common7\Tools\VsDevCmd.bat")) { return $candidate }
        }
    }

    foreach ($path in $fallbackPaths) {
        if (Test-Path (Join-Path $path "Common7\Tools\VsDevCmd.bat")) { return $path }
    }

    return $null
}

function Na__BuildScript__DownloadVsBootstrapper {
    if (Test-Path $VsBootstrapper) { return }

    $uri = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
    Invoke-WebRequest -Uri $uri -OutFile $VsBootstrapper
}

function Na__BuildScript__InstallBuildTools {
    $winget = Na__BuildScript__FindCommand "winget.exe"
    if (-not $winget) {
        Na__BuildScript__DownloadVsBootstrapper
        throw "MSVC Build Tools are missing. Bootstrapper downloaded to $VsBootstrapper, but winget.exe was not found for unattended install."
    }

    & $winget install --id Microsoft.VisualStudio.2022.BuildTools --source winget --accept-package-agreements --accept-source-agreements --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
}

function Na__BuildScript__WriteManifest {
    param(
        [string]$Status,
        [string]$VisualStudioPath,
        [string]$Message
    )

    $dependencyRepo = Join-Path $DependencyRoot "01__SketchUpRubyCExtensionExamples__Pinned"
    $dependencyCommit = ""
    if (Test-Path (Join-Path $dependencyRepo ".git")) {
        $dependencyCommit = (& git -C $dependencyRepo rev-parse HEAD).Trim()
    }

    $manifest = [ordered]@{
        name = "Na__MeshDecimator__NativeEngine"
        target = "Windows SketchUp 2026 Ruby 3.2"
        status = $Status
        message = $Message
        generatedAt = (Get-Date).ToString("s")
        dependencyRoot = $DependencyRoot
        sketchUpRubyCExtensionExamples = [ordered]@{
            path = $dependencyRepo
            commit = $dependencyCommit
        }
        tools = [ordered]@{
            cmake = (Na__BuildScript__FindCommand "cmake.exe")
            ninja = (Na__BuildScript__FindCommand "ninja.exe")
            git = (Na__BuildScript__FindCommand "git.exe")
            visualStudio = $VisualStudioPath
        }
    }

    $manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestPath -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $BuildToolsFolder | Out-Null
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

$existingSubst = cmd.exe /c subst
if ($existingSubst -notmatch [regex]::Escape("$ShortDrive\")) {
    cmd.exe /c "subst $ShortDrive `"$ModuleRoot`""
}

$cmake = Na__BuildScript__FindCommand "cmake.exe"
if (-not $cmake) {
    Na__BuildScript__WriteManifest -Status "blocked" -VisualStudioPath "" -Message "cmake.exe was not found on PATH."
    throw "cmake.exe was not found on PATH."
}

$visualStudioPath = Na__BuildScript__FindVisualStudioInstall
if (-not $visualStudioPath) {
    if ($InstallMissingBuildTools) {
        Na__BuildScript__InstallBuildTools
        $visualStudioPath = Na__BuildScript__FindVisualStudioInstall
    }
}

if (-not $visualStudioPath) {
    Na__BuildScript__DownloadVsBootstrapper
    Na__BuildScript__WriteManifest -Status "blocked" -VisualStudioPath "" -Message "MSVC Build Tools are missing. Bootstrapper is stored in the version-locked dependency manifest folder."
    throw "MSVC Build Tools are missing. Bootstrapper downloaded to $VsBootstrapper."
}

$vsDevCmd = Join-Path $visualStudioPath "Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $vsDevCmd)) {
    Na__BuildScript__WriteManifest -Status "blocked" -VisualStudioPath $visualStudioPath -Message "VsDevCmd.bat was not found under the Visual Studio installation."
    throw "VsDevCmd.bat was not found under $visualStudioPath."
}

$buildCommand = "`"$vsDevCmd`" -arch=x64 -host_arch=x64 && cmake -S `"$ShortCMakeFolder`" -B `"$BuildRoot`" -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build `"$BuildRoot`" --config Release"
cmd.exe /c $buildCommand

if ($LASTEXITCODE -ne 0) {
    Na__BuildScript__WriteManifest -Status "failed" -VisualStudioPath $visualStudioPath -Message "Native build failed. Review terminal output for compiler diagnostics."
    exit $LASTEXITCODE
}

Na__BuildScript__WriteManifest -Status "built" -VisualStudioPath $visualStudioPath -Message "Native extension built successfully."
Write-Host "[+] Na__MeshDecimator native extension built successfully."
