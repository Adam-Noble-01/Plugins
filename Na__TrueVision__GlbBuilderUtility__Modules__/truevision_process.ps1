param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
try {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $request.executable
    $start.WorkingDirectory = $request.cwd
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding
    $start.StandardErrorEncoding = New-Object System.Text.UTF8Encoding
    # Windows argv quoting, including quotes and trailing backslashes.
    $quoted = foreach ($arg in $request.arguments) {
        '"' + ([regex]::Replace([regex]::Replace([string]$arg, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
    }
    $start.Arguments = $quoted -join ' '
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if ($request.stdin) { $process.StandardInput.Write([string]$request.stdin) }
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(1800000)) {
        $process.Kill()
        throw 'Cloud process exceeded the 30 minute timeout.'
    }
    $result = @{exit_code=$process.ExitCode; stdout=$outTask.Result; stderr=$errTask.Result}
} catch {
    $result = @{exit_code=1; stdout=''; stderr=$_.Exception.Message}
}
# Publish the result only after it is fully written; SketchUp polls this file.
$temporaryResult = [string]$request.result + '.writing'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryResult -Encoding UTF8
Move-Item -LiteralPath $temporaryResult -Destination $request.result -Force
exit $result.exit_code
