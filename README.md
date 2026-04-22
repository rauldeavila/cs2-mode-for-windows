# CS2 mode toggle

This folder contains a small Windows toggle for your CS2 setup.

What it does:

- CS2 mode: switches Windows to PC screen only through the Windows display API, sets NVIDIA Digital Vibrance to 80%, and sets desktop gamma to 1.08.
- Normal mode: switches Windows to extended displays through the Windows display API, sets NVIDIA Digital Vibrance to 65%, and sets desktop gamma to 0.97.
- Toggle mode: flips between those two modes and saves the last mode in `%LOCALAPPDATA%\CS2ModeToggle\state.json`.
- After switching modes, a small overlay shows the active mode, gamma, Digital Vibrance, and monitor layout for 5 seconds. In CS2 mode the monitor line shows `BENQ XL2411P`.
- By default, Digital Vibrance is changed only on NVIDIA display index 0.

Files:

- `Toggle-CS2Mode.ps1`: main script.
- `Toggle-CS2Mode.vbs`: launcher you can double-click or bind to a shortcut.
- `Test-CS2ModePersistence.ps1`: temporary test that toggles, waits 10 seconds, then reads current gamma and Digital Vibrance.
- `%LOCALAPPDATA%\CS2ModeToggle\CS2ModeOverlay.exe`: small overlay app compiled automatically by the script when needed.

Useful commands:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode CS2
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode Normal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode Toggle
```

Optional tweaks:

```powershell
# Try only Digital Vibrance first, without changing monitor layout.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode SetVibrance -Vibrance 80 -NoMonitorSwitch

# Try only gamma first, without changing monitor layout or Digital Vibrance.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode SetGamma -Gamma 1.08

# Apply to all active NVIDIA displays.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode CS2 -AllDisplays

# Apply only to NVIDIA display index 0.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode CS2 -PrimaryOnly

# Apply to a specific NVIDIA display index.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode SetVibrance -Vibrance 65 -DisplayIndexes 1

# Use custom values.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode Toggle -Cs2Vibrance 80 -NormalVibrance 65 -Cs2Gamma 1.08 -NormalGamma 0.97

# Disable the overlay or change how long it stays visible.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode Toggle -NoOverlay
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode Toggle -OverlaySeconds 5

# Test only the overlay, without changing monitor layout, gamma, or Digital Vibrance.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-CS2Mode.ps1 -Mode Overlay -OverlayModeName CS2 -OverlayGamma 1.08 -OverlayVibrance 80 -OverlayMonitorMode "BENQ XL2411P"

# Temporary persistence check.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-CS2ModePersistence.ps1 -Mode Toggle -WaitSeconds 10
```

Notes:

- The script uses NVIDIA NVAPI. NVIDIA documents NVAPI, but the Digital Vibrance calls used by old tools are not part of the public documented color-control surface.
- Gamma is applied through the Windows desktop gamma ramp on attached display devices. HDR, Night Light, or some color calibration tools can override or reset it.
- The monitor layout no longer uses `DisplaySwitch.exe`, so it should not open the Windows+P side panel.
- If the script says the DVC function is not available, your current driver is blocking or omitting that private entry point.
- If the first run is blocked by execution policy, keep using the command above with `-ExecutionPolicy Bypass` or launch `Toggle-CS2Mode.vbs`.
