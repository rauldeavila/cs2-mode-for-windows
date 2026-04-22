#requires -version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Toggle', 'CS2', 'Normal', 'Status', 'SetVibrance', 'SetGamma', 'Overlay', 'VerifyCurrent')]
    [string]$Mode = 'Toggle',

    [ValidateRange(0, 100)]
    [int]$Cs2Vibrance = 80,

    [ValidateRange(0, 100)]
    [int]$NormalVibrance = 65,

    [ValidateRange(0.50, 3.00)]
    [double]$Cs2Gamma = 1.08,

    [ValidateRange(0.50, 3.00)]
    [double]$NormalGamma = 0.97,

    [ValidateRange(0, 100)]
    [int]$Vibrance = 65,

    [ValidateRange(0.50, 3.00)]
    [double]$Gamma = 1.00,

    [int[]]$DisplayIndexes = @(),

    [switch]$PrimaryOnly,

    [switch]$AllDisplays,

    [switch]$NoMonitorSwitch,

    [int]$DisplaySwitchDelayMs = 3000,

    [switch]$NoOverlay,

    [ValidateRange(0.5, 30.0)]
    [double]$OverlaySeconds = 5.0,

    [string]$OverlayModeName = 'Teste',

    [ValidateRange(0, 100)]
    [int]$OverlayVibrance = 80,

    [ValidateRange(0.50, 3.00)]
    [double]$OverlayGamma = 1.08,

    [string]$OverlayMonitorMode = 'Preview'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = $env:LOCALAPPDATA
}
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = $PSScriptRoot
}

$stateDir = Join-Path $localAppData 'CS2ModeToggle'
$stateFile = Join-Path $stateDir 'state.json'
$overlayExe = Join-Path $stateDir 'CS2ModeOverlay.exe'

$windowsDisplayConfigSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class WindowsDisplayTopology
{
    private const uint SDC_TOPOLOGY_INTERNAL = 0x00000001;
    private const uint SDC_TOPOLOGY_EXTEND = 0x00000004;
    private const uint SDC_APPLY = 0x00000080;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int SetDisplayConfig(
        uint numPathArrayElements,
        IntPtr pathArray,
        uint numModeInfoArrayElements,
        IntPtr modeInfoArray,
        uint flags
    );

    public static void SetInternal()
    {
        Apply(SDC_TOPOLOGY_INTERNAL, "PC screen only");
    }

    public static void SetExtend()
    {
        Apply(SDC_TOPOLOGY_EXTEND, "Extend");
    }

    private static void Apply(uint topology, string label)
    {
        int status = SetDisplayConfig(0, IntPtr.Zero, 0, IntPtr.Zero, topology | SDC_APPLY);
        if (status != 0)
        {
            throw new Win32Exception(status, "SetDisplayConfig failed while switching to " + label);
        }
    }
}
'@

$windowsGammaRampSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class WindowsGammaRamp
{
    private const int RampEntries = 256;
    private const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x00000001;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DisplayDevice
    {
        public int cb;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceString;

        public int StateFlags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceID;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GammaRamp
    {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = RampEntries)]
        public ushort[] Red;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = RampEntries)]
        public ushort[] Green;

        [MarshalAs(UnmanagedType.ByValArray, SizeConst = RampEntries)]
        public ushort[] Blue;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DisplayDevice lpDisplayDevice, uint dwFlags);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateDC(string driver, string device, string output, IntPtr initData);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool SetDeviceGammaRamp(IntPtr hDC, ref GammaRamp ramp);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool GetDeviceGammaRamp(IntPtr hDC, ref GammaRamp ramp);

    public static int SetGamma(double gamma)
    {
        if (gamma < 0.50 || gamma > 3.00)
        {
            throw new ArgumentOutOfRangeException("gamma", "Gamma must be between 0.50 and 3.00.");
        }

        GammaRamp ramp = BuildRamp(gamma);
        int updatedDisplays = 0;
        int lastError = 0;

        for (uint index = 0; index < 16; index++)
        {
            DisplayDevice display = new DisplayDevice();
            display.cb = Marshal.SizeOf(typeof(DisplayDevice));

            if (!EnumDisplayDevices(null, index, ref display, 0))
            {
                break;
            }

            if ((display.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0)
            {
                continue;
            }

            IntPtr dc = CreateDC(null, display.DeviceName, null, IntPtr.Zero);
            if (dc == IntPtr.Zero)
            {
                lastError = Marshal.GetLastWin32Error();
                continue;
            }

            try
            {
                if (SetDeviceGammaRamp(dc, ref ramp))
                {
                    updatedDisplays++;
                }
                else
                {
                    lastError = Marshal.GetLastWin32Error();
                }
            }
            finally
            {
                DeleteDC(dc);
            }
        }

        if (updatedDisplays == 0)
        {
            throw new Win32Exception(lastError, "SetDeviceGammaRamp failed for all attached displays.");
        }

        return updatedDisplays;
    }

    public static string[] GetGammaReport()
    {
        List<string> report = new List<string>();

        for (uint index = 0; index < 16; index++)
        {
            DisplayDevice display = new DisplayDevice();
            display.cb = Marshal.SizeOf(typeof(DisplayDevice));

            if (!EnumDisplayDevices(null, index, ref display, 0))
            {
                break;
            }

            if ((display.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0)
            {
                continue;
            }

            IntPtr dc = CreateDC(null, display.DeviceName, null, IntPtr.Zero);
            if (dc == IntPtr.Zero)
            {
                report.Add(String.Format("{0}: gamma read failed (CreateDC error {1})", display.DeviceName, Marshal.GetLastWin32Error()));
                continue;
            }

            try
            {
                GammaRamp ramp = new GammaRamp
                {
                    Red = new ushort[RampEntries],
                    Green = new ushort[RampEntries],
                    Blue = new ushort[RampEntries]
                };

                if (!GetDeviceGammaRamp(dc, ref ramp))
                {
                    report.Add(String.Format("{0}: gamma read failed (GetDeviceGammaRamp error {1})", display.DeviceName, Marshal.GetLastWin32Error()));
                    continue;
                }

                double redGamma = EstimateGamma(ramp.Red);
                double greenGamma = EstimateGamma(ramp.Green);
                double blueGamma = EstimateGamma(ramp.Blue);
                double averageGamma = (redGamma + greenGamma + blueGamma) / 3.0;

                report.Add(String.Format(
                    "{0}: estimated gamma {1:0.00} (R {2:0.00}, G {3:0.00}, B {4:0.00})",
                    display.DeviceName,
                    averageGamma,
                    redGamma,
                    greenGamma,
                    blueGamma
                ));
            }
            finally
            {
                DeleteDC(dc);
            }
        }

        if (report.Count == 0)
        {
            report.Add("No attached display gamma ramp could be read.");
        }

        return report.ToArray();
    }

    private static GammaRamp BuildRamp(double gamma)
    {
        ushort[] values = new ushort[RampEntries];
        for (int i = 0; i < RampEntries; i++)
        {
            double normalized = i / 255.0;
            int value = (int)Math.Round(65535.0 * Math.Pow(normalized, 1.0 / gamma));
            if (value < 0)
            {
                value = 0;
            }
            else if (value > 65535)
            {
                value = 65535;
            }

            values[i] = (ushort)value;
        }

        return new GammaRamp
        {
            Red = (ushort[])values.Clone(),
            Green = (ushort[])values.Clone(),
            Blue = (ushort[])values.Clone()
        };
    }

    private static double EstimateGamma(ushort[] values)
    {
        int[] sampleIndexes = new int[] { 64, 96, 128, 160, 192 };
        double total = 0.0;
        int count = 0;

        foreach (int sampleIndex in sampleIndexes)
        {
            double input = sampleIndex / 255.0;
            double output = values[sampleIndex] / 65535.0;

            if (input <= 0.0 || input >= 1.0 || output <= 0.0 || output >= 1.0)
            {
                continue;
            }

            total += Math.Log(input) / Math.Log(output);
            count++;
        }

        return count == 0 ? Double.NaN : total / count;
    }
}
'@

$overlayAppSource = @'
using System;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            string mode = GetArg(args, "--mode", "CS2");
            string monitorMode = GetArg(args, "--monitors", "PC screen only");
            int vibrance = ParseInt(GetArg(args, "--vibrance", "80"), 80);
            string gamma = GetArg(args, "--gamma", "1.08");
            double seconds = ParseDouble(GetArg(args, "--seconds", "3"), 3);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using (OverlayForm form = new OverlayForm(mode, vibrance, gamma, monitorMode, seconds))
            {
                Application.Run(form);
            }
        }
        catch (Exception ex)
        {
            try
            {
                string dir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "CS2ModeToggle"
                );
                Directory.CreateDirectory(dir);
                File.AppendAllText(
                    Path.Combine(dir, "overlay.log"),
                    DateTime.Now.ToString("o", CultureInfo.InvariantCulture) + " " + ex.ToString() + Environment.NewLine
                );
            }
            catch
            {
            }
        }
    }

    private static string GetArg(string[] args, string name, string fallback)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (String.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }

        return fallback;
    }

    private static int ParseInt(string value, int fallback)
    {
        int parsed;
        return Int32.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed)
            ? parsed
            : fallback;
    }

    private static double ParseDouble(string value, double fallback)
    {
        double parsed;
        return Double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out parsed)
            ? parsed
            : fallback;
    }
}

internal sealed class OverlayForm : Form
{
    private readonly Timer closeTimer;

    public OverlayForm(string mode, int vibrance, string gamma, string monitorMode, double seconds)
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        Width = 360;
        Height = 142;
        BackColor = Color.FromArgb(22, 24, 28);
        Opacity = 0.96;

        Rectangle area = Screen.PrimaryScreen.WorkingArea;
        int margin = 24;
        Left = area.Right - Width - margin;
        Top = area.Top + margin;

        Color accent = String.Equals(mode, "CS2", StringComparison.OrdinalIgnoreCase)
            ? Color.FromArgb(244, 167, 43)
            : Color.FromArgb(85, 176, 255);

        Panel bar = new Panel
        {
            Dock = DockStyle.Left,
            Width = 6,
            BackColor = accent
        };
        Controls.Add(bar);

        Label title = new Label
        {
            AutoSize = false,
            Left = 22,
            Top = 16,
            Width = 316,
            Height = 30,
            Font = new Font("Segoe UI", 15, FontStyle.Bold),
            ForeColor = Color.White,
            Text = "Modo " + mode
        };
        Controls.Add(title);

        Label details = new Label
        {
            AutoSize = false,
            Left = 23,
            Top = 52,
            Width = 316,
            Height = 74,
            Font = new Font("Segoe UI", 10),
            ForeColor = Color.FromArgb(226, 232, 240),
            Text = String.Format(
                CultureInfo.InvariantCulture,
                "Gamma: {0}\r\nDigital Vibrance: {1}%\r\nMonitores: {2}",
                gamma,
                vibrance,
                monitorMode
            )
        };
        Controls.Add(details);

        closeTimer = new Timer();
        closeTimer.Interval = Math.Max(500, (int)Math.Round(seconds * 1000.0));
        closeTimer.Tick += delegate
        {
            closeTimer.Stop();
            Close();
        };

        Shown += delegate
        {
            ForceShow();
            BringToFront();
            Activate();
            closeTimer.Start();
        };
    }

    protected override bool ShowWithoutActivation
    {
        get { return false; }
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            return cp;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            closeTimer.Dispose();
        }

        base.Dispose(disposing);
    }

    private void ForceShow()
    {
        ShowWindow(Handle, 5);
        SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
        SetForegroundWindow(Handle);
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@

$nvApiSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class NvidiaDigitalVibrance
{
    private const uint NvAPI_InitializeId = 0x0150E828;
    private const uint NvAPI_UnloadId = 0xD22BDD7E;
    private const uint NvAPI_GetErrorMessageId = 0x6C2D048C;
    private const uint NvAPI_EnumNvidiaDisplayHandleId = 0x9ABDD40D;
    private const uint NvAPI_GetDVCInfoExId = 0x0E45002D;
    private const uint NvAPI_SetDVCLevelExId = 0x4A82C2B1;
    private const int NvAPI_OK = 0;
    private const int NvAPI_END_ENUMERATION = -7;
    private const uint DvcInfoExVersion = (1u << 16) | 20u;

    [StructLayout(LayoutKind.Sequential)]
    private struct DvcInfoEx
    {
        public uint version;
        public int currentLevel;
        public int minLevel;
        public int maxLevel;
        public int defaultLevel;
    }

    public sealed class DisplayInfo
    {
        public int Index;
        public int CurrentLevel;
        public int MinLevel;
        public int MaxLevel;
        public int DefaultLevel;

        public override string ToString()
        {
            return String.Format(
                "Display {0}: Digital Vibrance {1}% (min {2}, max {3}, default {4})",
                Index,
                CurrentLevel,
                MinLevel,
                MaxLevel,
                DefaultLevel
            );
        }
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr QueryInterfaceDelegate(uint functionId);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int InitializeDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int UnloadDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetErrorMessageDelegate(int status, StringBuilder message);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int EnumNvidiaDisplayHandleDelegate(int index, out IntPtr displayHandle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetDvcInfoExDelegate(IntPtr displayHandle, uint outputId, ref DvcInfoEx info);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SetDvcLevelExDelegate(IntPtr displayHandle, uint outputId, ref DvcInfoEx info);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibrary(string fileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string procName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);

    private sealed class NvApiSession : IDisposable
    {
        private readonly IntPtr module;
        private readonly QueryInterfaceDelegate queryInterface;
        private readonly GetErrorMessageDelegate getErrorMessage;
        private readonly UnloadDelegate unload;
        public readonly EnumNvidiaDisplayHandleDelegate EnumDisplay;
        public readonly GetDvcInfoExDelegate GetDvcInfo;
        public readonly SetDvcLevelExDelegate SetDvcLevel;

        public NvApiSession()
        {
            string dllName = IntPtr.Size == 8 ? "nvapi64.dll" : "nvapi.dll";
            module = LoadLibrary(dllName);
            if (module == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not load " + dllName);
            }

            IntPtr queryPtr = GetProcAddress(module, "nvapi_QueryInterface");
            if (queryPtr == IntPtr.Zero)
            {
                throw new InvalidOperationException("Could not locate nvapi_QueryInterface.");
            }

            queryInterface = Marshal.GetDelegateForFunctionPointer<QueryInterfaceDelegate>(queryPtr);
            InitializeDelegate initialize = GetDelegate<InitializeDelegate>(NvAPI_InitializeId, "NvAPI_Initialize");
            unload = GetDelegate<UnloadDelegate>(NvAPI_UnloadId, "NvAPI_Unload");
            getErrorMessage = GetDelegate<GetErrorMessageDelegate>(NvAPI_GetErrorMessageId, "NvAPI_GetErrorMessage");
            EnumDisplay = GetDelegate<EnumNvidiaDisplayHandleDelegate>(NvAPI_EnumNvidiaDisplayHandleId, "NvAPI_EnumNvidiaDisplayHandle");
            GetDvcInfo = GetDelegate<GetDvcInfoExDelegate>(NvAPI_GetDVCInfoExId, "NvAPI_GetDVCInfoEx");
            SetDvcLevel = GetDelegate<SetDvcLevelExDelegate>(NvAPI_SetDVCLevelExId, "NvAPI_SetDVCLevelEx");

            int status = initialize();
            EnsureOk(status, "NvAPI_Initialize");
        }

        private T GetDelegate<T>(uint functionId, string name)
        {
            IntPtr ptr = queryInterface(functionId);
            if (ptr == IntPtr.Zero)
            {
                throw new NotSupportedException(name + " is not available in this NVIDIA driver.");
            }

            return Marshal.GetDelegateForFunctionPointer<T>(ptr);
        }

        public void EnsureOk(int status, string operation)
        {
            if (status == NvAPI_OK)
            {
                return;
            }

            StringBuilder message = new StringBuilder(64);
            try
            {
                getErrorMessage(status, message);
            }
            catch
            {
                message.Append("Unknown NVAPI error");
            }

            throw new InvalidOperationException(String.Format(
                "{0} failed: {1} ({2})",
                operation,
                message.ToString(),
                status
            ));
        }

        public void Dispose()
        {
            try
            {
                if (unload != null)
                {
                    unload();
                }
            }
            catch
            {
            }

            if (module != IntPtr.Zero)
            {
                FreeLibrary(module);
            }
        }
    }

    public static DisplayInfo[] GetDisplays()
    {
        using (NvApiSession session = new NvApiSession())
        {
            List<DisplayInfo> displays = new List<DisplayInfo>();

            for (int index = 0; index < 16; index++)
            {
                IntPtr handle;
                int enumStatus = session.EnumDisplay(index, out handle);
                if (enumStatus == NvAPI_END_ENUMERATION)
                {
                    break;
                }

                if (enumStatus != NvAPI_OK)
                {
                    continue;
                }

                DvcInfoEx info = new DvcInfoEx();
                info.version = DvcInfoExVersion;
                int infoStatus = session.GetDvcInfo(handle, 0, ref info);
                session.EnsureOk(infoStatus, "NvAPI_GetDVCInfoEx display " + index);

                displays.Add(new DisplayInfo
                {
                    Index = index,
                    CurrentLevel = info.currentLevel,
                    MinLevel = info.minLevel,
                    MaxLevel = info.maxLevel,
                    DefaultLevel = info.defaultLevel
                });
            }

            return displays.ToArray();
        }
    }

    public static string[] SetLevel(int level, int[] displayIndexes, bool primaryOnly)
    {
        if (level < 0 || level > 100)
        {
            throw new ArgumentOutOfRangeException("level", "Digital Vibrance must be between 0 and 100.");
        }

        using (NvApiSession session = new NvApiSession())
        {
            List<string> changed = new List<string>();
            HashSet<int> requested = null;
            if (displayIndexes != null && displayIndexes.Length > 0)
            {
                requested = new HashSet<int>(displayIndexes);
            }

            for (int index = 0; index < 16; index++)
            {
                if (primaryOnly && index > 0)
                {
                    break;
                }

                IntPtr handle;
                int enumStatus = session.EnumDisplay(index, out handle);
                if (enumStatus == NvAPI_END_ENUMERATION)
                {
                    break;
                }

                if (enumStatus != NvAPI_OK)
                {
                    continue;
                }

                if (requested != null && !requested.Contains(index))
                {
                    continue;
                }

                DvcInfoEx info = new DvcInfoEx();
                info.version = DvcInfoExVersion;
                int infoStatus = session.GetDvcInfo(handle, 0, ref info);
                session.EnsureOk(infoStatus, "NvAPI_GetDVCInfoEx display " + index);

                int clamped = Math.Max(info.minLevel, Math.Min(info.maxLevel, level));
                info.currentLevel = clamped;

                int setStatus = session.SetDvcLevel(handle, 0, ref info);
                session.EnsureOk(setStatus, "NvAPI_SetDVCLevelEx display " + index);

                changed.Add(String.Format("Display {0}: Digital Vibrance set to {1}%", index, clamped));
            }

            if (changed.Count == 0)
            {
                throw new InvalidOperationException("No active NVIDIA display was found to update.");
            }

            return changed.ToArray();
        }
    }
}
'@

function Add-NvidiaDigitalVibranceType {
    if (-not ('NvidiaDigitalVibrance' -as [type])) {
        Add-Type -TypeDefinition $nvApiSource -Language CSharp
    }
}

function Add-WindowsDisplayTopologyType {
    if (-not ('WindowsDisplayTopology' -as [type])) {
        Add-Type -TypeDefinition $windowsDisplayConfigSource -Language CSharp
    }
}

function Add-WindowsGammaRampType {
    if (-not ('WindowsGammaRamp' -as [type])) {
        Add-Type -TypeDefinition $windowsGammaRampSource -Language CSharp
    }
}

function Get-ActiveMonitorCount {
    Add-Type -AssemblyName System.Windows.Forms
    return [System.Windows.Forms.Screen]::AllScreens.Count
}

function Read-State {
    if (-not (Test-Path -LiteralPath $stateFile)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-State {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CS2', 'Normal')]
        [string]$CurrentMode
    )

    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }

    [pscustomobject]@{
        mode = $CurrentMode
        updatedAt = (Get-Date).ToString('o')
        cs2Vibrance = $Cs2Vibrance
        normalVibrance = $NormalVibrance
        cs2Gamma = $Cs2Gamma
        normalGamma = $NormalGamma
    } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
}

function Set-MonitorTopology {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('internal', 'extend')]
        [string]$Target
    )

    if ($NoMonitorSwitch) {
        Write-Output "Monitor switch skipped (-NoMonitorSwitch)."
        return
    }

    Add-WindowsDisplayTopologyType
    switch ($Target) {
        'internal' {
            [WindowsDisplayTopology]::SetInternal()
            Write-Output "Monitor topology set to PC screen only."
            break
        }
        'extend' {
            [WindowsDisplayTopology]::SetExtend()
            Write-Output "Monitor topology set to Extend."
            break
        }
    }

    if ($DisplaySwitchDelayMs -gt 0) {
        Start-Sleep -Milliseconds $DisplaySwitchDelayMs
    }
}

function Set-DigitalVibrance {
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$Level
    )

    Add-NvidiaDigitalVibranceType
    $usePrimaryOnly = -not [bool]$AllDisplays
    if ($DisplayIndexes.Count -gt 0) {
        $usePrimaryOnly = $false
    }
    if ($PrimaryOnly) {
        $usePrimaryOnly = $true
    }

    return [NvidiaDigitalVibrance]::SetLevel($Level, $DisplayIndexes, $usePrimaryOnly)
}

function Set-DesktopGamma {
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0.50, 3.00)]
        [double]$Level
    )

    Add-WindowsGammaRampType
    try {
        $updatedDisplays = [WindowsGammaRamp]::SetGamma($Level)
        Write-Host ("Desktop gamma set to {0:N2} on {1} display(s)." -f $Level, $updatedDisplays)
        return $true
    }
    catch {
        Write-Warning ("Could not apply desktop gamma {0:N2}: {1}" -f $Level, $_.Exception.Message)
        return $false
    }
}

function ConvertTo-OverlayArgument {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + ($Value -replace '"', '\"') + '"'
}

function Ensure-OverlayExecutable {
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }

    $scriptTimestamp = (Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc
    $shouldBuild = -not (Test-Path -LiteralPath $overlayExe)
    if (-not $shouldBuild) {
        $shouldBuild = (Get-Item -LiteralPath $overlayExe).LastWriteTimeUtc -lt $scriptTimestamp
    }

    if (-not $shouldBuild) {
        return
    }

    $tempOverlayExe = Join-Path $stateDir ("CS2ModeOverlay.{0}.exe" -f ([guid]::NewGuid().ToString('N')))
    Add-Type `
        -TypeDefinition $overlayAppSource `
        -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.Drawing.dll') `
        -OutputAssembly $tempOverlayExe `
        -OutputType WindowsApplication

    Move-Item -LiteralPath $tempOverlayExe -Destination $overlayExe -Force
}

function Show-ModeOverlay {
    param(
        [Parameter(Mandatory)]
        [string]$ModeName,

        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$VibranceLevel,

        [Parameter(Mandatory)]
        [string]$GammaText,

        [Parameter(Mandatory)]
        [string]$MonitorMode
    )

    if ($NoOverlay) {
        return
    }

    try {
        Ensure-OverlayExecutable

        $invariant = [System.Globalization.CultureInfo]::InvariantCulture
        $arguments = @(
            '--mode', (ConvertTo-OverlayArgument -Value $ModeName),
            '--vibrance', $VibranceLevel.ToString($invariant),
            '--gamma', (ConvertTo-OverlayArgument -Value $GammaText),
            '--monitors', (ConvertTo-OverlayArgument -Value $MonitorMode),
            '--seconds', $OverlaySeconds.ToString('0.###', $invariant)
        ) -join ' '

        Start-Process -FilePath $overlayExe -ArgumentList $arguments -WindowStyle Normal | Out-Null
    }
    catch {
        Write-Warning ("Could not show overlay: {0}" -f $_.Exception.Message)
    }
}

function Show-Status {
    Add-NvidiaDigitalVibranceType
    $state = Read-State
    $activeMonitorCount = Get-ActiveMonitorCount

    if ($null -eq $state) {
        Write-Output "Saved mode: unknown"
    }
    else {
        Write-Output ("Saved mode: {0} ({1})" -f $state.mode, $state.updatedAt)
    }

    Write-Output ("Active Windows monitors: {0}" -f $activeMonitorCount)

    [NvidiaDigitalVibrance]::GetDisplays() | ForEach-Object {
        Write-Output $_.ToString()
    }
}

function Show-CurrentVerification {
    Add-NvidiaDigitalVibranceType
    Add-WindowsGammaRampType

    $state = Read-State
    $activeMonitorCount = Get-ActiveMonitorCount

    Write-Output ("Verification timestamp: {0}" -f (Get-Date).ToString('o'))
    if ($null -eq $state) {
        Write-Output "Saved mode: unknown"
    }
    else {
        Write-Output ("Saved mode: {0} ({1})" -f $state.mode, $state.updatedAt)
    }

    Write-Output ("Active Windows monitors: {0}" -f $activeMonitorCount)
    Write-Output ""
    Write-Output "Digital Vibrance:"
    [NvidiaDigitalVibrance]::GetDisplays() | ForEach-Object {
        Write-Output ("  {0}" -f $_.ToString())
    }

    Write-Output ""
    Write-Output "Gamma ramp:"
    [WindowsGammaRamp]::GetGammaReport() | ForEach-Object {
        Write-Output ("  {0}" -f $_)
    }

    Write-Output ""
    Write-Output "Note: gamma is estimated from the current Windows gamma ramp, so tiny rounding differences are normal."
}

function Enter-CS2Mode {
    Set-MonitorTopology -Target internal
    Set-DigitalVibrance -Level $Cs2Vibrance
    $gammaApplied = Set-DesktopGamma -Level $Cs2Gamma
    Write-State -CurrentMode CS2
    $gammaText = if ($gammaApplied) { $Cs2Gamma.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) } else { "{0} (not applied)" -f $Cs2Gamma.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) }
    Show-ModeOverlay -ModeName 'CS2' -VibranceLevel $Cs2Vibrance -GammaText $gammaText -MonitorMode 'BENQ XL2411P'
    Write-Output "CS2 mode enabled."
}

function Enter-NormalMode {
    Set-MonitorTopology -Target extend
    Set-DigitalVibrance -Level $NormalVibrance
    $gammaApplied = Set-DesktopGamma -Level $NormalGamma
    Write-State -CurrentMode Normal
    $gammaText = if ($gammaApplied) { $NormalGamma.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) } else { "{0} (not applied)" -f $NormalGamma.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) }
    Show-ModeOverlay -ModeName 'Normal' -VibranceLevel $NormalVibrance -GammaText $gammaText -MonitorMode 'Extend'
    Write-Output "Normal mode enabled."
}

switch ($Mode) {
    'Status' {
        Show-Status
        break
    }
    'VerifyCurrent' {
        Show-CurrentVerification
        break
    }
    'SetVibrance' {
        Set-DigitalVibrance -Level $Vibrance
        break
    }
    'SetGamma' {
        $null = Set-DesktopGamma -Level $Gamma
        break
    }
    'Overlay' {
        Show-ModeOverlay -ModeName $OverlayModeName -VibranceLevel $OverlayVibrance -GammaText $OverlayGamma.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture) -MonitorMode $OverlayMonitorMode
        break
    }
    'CS2' {
        Enter-CS2Mode
        break
    }
    'Normal' {
        Enter-NormalMode
        break
    }
    'Toggle' {
        $activeMonitorCount = Get-ActiveMonitorCount

        if ($activeMonitorCount -le 1) {
            Enter-NormalMode
        }
        else {
            Enter-CS2Mode
        }
        break
    }
}
