# Copies the chase cam mod and the discovery probe into the game's UE4SS Mods folder and enables them.
# UE4SS hot reload is on (Ctrl+R in game), so re-run this after editing and reload.
param(
    [string]$Game = "C:\Program Files (x86)\Steam\steamapps\common\TokyoXtremeRacer",
    [string[]]$Mods = @("TXRChaseCam", "TXRCamProbe")
)

$dest = Join-Path $Game "TokyoXtremeRacer\Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path $dest)) { throw "UE4SS not found at $dest" }

$sources = @{
    TXRChaseCam = Join-Path $PSScriptRoot "..\mod\TXRChaseCam"
    TXRCamProbe = Join-Path $PSScriptRoot "..\discovery\TXRCamProbe"
}

$list = Join-Path $dest "mods.txt"
foreach ($name in $Mods) {
    Copy-Item $sources[$name] $dest -Recurse -Force
    $lines = [IO.File]::ReadAllLines($list)
    if (-not ($lines -match "^$name\s*:")) {
        # Keybinds must stay last, so insert before it.
        $i = [array]::FindIndex([string[]]$lines, [Predicate[string]]{ param($l) $l -match '^; Built-in keybinds' })
        if ($i -lt 0) { $i = $lines.Count }
        $lines = @($lines[0..($i - 1)]) + "$name : 1" + @($lines[$i..($lines.Count - 1)])
        # WriteAllLines writes UTF-8 without a BOM; Set-Content -Encoding utf8 would add one on PS 5.1.
        [IO.File]::WriteAllLines($list, [string[]]$lines)
    }
    Write-Host "Installed $name to $dest"
}
