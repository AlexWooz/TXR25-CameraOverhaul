# Builds the release zip: TXRChaseCam (Lua mod + config.lua) and TXRChaseCamInput (C++ helper),
# each with an enabled.txt so players don't edit mods.txt, plus release\README.txt.
# The C++ helper must be built first:
#   cmake --build native\build --config Game__Shipping__Win64 --target TXRChaseCamInput
param(
    [string]$Version = "1.0",
    [string]$Out = (Join-Path $PSScriptRoot "..\release")
)

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$dll = Join-Path $root "native\build\TXRChaseCamInput\Game__Shipping__Win64\TXRChaseCamInput.dll"
if (-not (Test-Path $dll)) { throw "TXRChaseCamInput.dll not built: $dll" }

$stage = Join-Path ([IO.Path]::GetTempPath()) ("TXRChaseCam-" + [guid]::NewGuid())
try {
    $lua = Join-Path $stage "TXRChaseCam\Scripts"
    $native = Join-Path $stage "TXRChaseCamInput\dlls"
    New-Item -ItemType Directory -Force $lua, $native | Out-Null

    Copy-Item (Join-Path $root "mod\TXRChaseCam\Scripts\*.lua") $lua
    Copy-Item $dll (Join-Path $native "main.dll")
    foreach ($m in "TXRChaseCam", "TXRChaseCamInput") {
        [IO.File]::WriteAllText((Join-Path $stage "$m\enabled.txt"), "")
    }
    Copy-Item (Join-Path $root "release\README.txt") $stage
    Copy-Item (Join-Path $root "LICENSE") (Join-Path $stage "LICENSE.txt")

    New-Item -ItemType Directory -Force $Out | Out-Null
    $zip = Join-Path (Resolve-Path $Out) "TXRChaseCam-$Version.zip"
    if (Test-Path $zip) { Remove-Item $zip }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip
    Write-Host "Packed $zip"
    Get-ChildItem $stage -Recurse -File | ForEach-Object { "  " + $_.FullName.Substring($stage.Length + 1) }
} finally {
    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}
