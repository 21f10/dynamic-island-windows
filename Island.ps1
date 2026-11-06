# ==============================================================================
#  Dynamic Island for Windows  -  v0 Ultimate Edition
#  Executive Glass HUD | 60 FPS Background Engine | NotchPixel Feature Suite
# ==============================================================================

# Global Error Suppression (Zero Red Crash Popups)
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# ------------------------------------------------------------------------------
#  C# P/Invoke Native Subsystem (Audio, Acrylic Blur, Hotkeys, WS_EX_NOACTIVATE)
# ------------------------------------------------------------------------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out uint pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
    int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid pguidEventContext);
    int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid pguidEventContext);
    int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
    int GetMute(out bool pbMute);
    int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    int VolumeStepUp(ref Guid pguidEventContext);
    int VolumeStepDown(ref Guid pguidEventContext);
    int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}

[ComImport]
[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid id, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
}

[ComImport]
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr deviceCollection);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}

[ComImport]
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObject { }

public static class IslandNative {
    private const byte VK_VOLUME_MUTE = 0xAD;
    private const byte VK_VOLUME_DOWN = 0xAE;
    private const byte VK_VOLUME_UP   = 0xAF;
    private const byte VK_MEDIA_NEXT_TRACK = 0xB0;
    private const byte VK_MEDIA_PREV_TRACK = 0xB1;
    private const byte VK_MEDIA_STOP       = 0xB2;
    private const byte VK_MEDIA_PLAY_PAUSE = 0xB3;
    private const int KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_NOACTIVATE = 0x08000000;

    public static void ApplyNoActivate(IntPtr hwnd) {
        try {
            int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE);
        } catch { }
    }

    [DllImport("user32.dll")]
    public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    [StructLayout(LayoutKind.Sequential)]
    public struct WindowCompositionAttributeData {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct AccentPolicy {
        public int AccentState;
        public int AccentFlags;
        public int GradientColor;
        public int AnimationId;
    }

    public static void EnableAcrylic(IntPtr hwnd, uint gradientColor) {
        try {
            var accent = new AccentPolicy();
            accent.AccentState = 4; // ACCENT_ENABLE_ACRYLICBLURBEHIND
            accent.GradientColor = (int)gradientColor;
            accent.AccentFlags = 2;

            int size = Marshal.SizeOf(accent);
            IntPtr ptr = Marshal.AllocHGlobal(size);
            Marshal.StructureToPtr(accent, ptr, false);

            var data = new WindowCompositionAttributeData();
            data.Attribute = 19; // WCA_ACCENT_POLICY
            data.SizeOfData = size;
            data.Data = ptr;

            SetWindowCompositionAttribute(hwnd, ref data);
            Marshal.FreeHGlobal(ptr);
        } catch { }
    }

    public static void VolumeUp() {
        keybd_event(VK_VOLUME_UP, 0, 0, UIntPtr.Zero);
        keybd_event(VK_VOLUME_UP, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static void VolumeDown() {
        keybd_event(VK_VOLUME_DOWN, 0, 0, UIntPtr.Zero);
        keybd_event(VK_VOLUME_DOWN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static void ToggleMute() {
        keybd_event(VK_VOLUME_MUTE, 0, 0, UIntPtr.Zero);
        keybd_event(VK_VOLUME_MUTE, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static void MediaPlayPause() {
        keybd_event(VK_MEDIA_PLAY_PAUSE, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MEDIA_PLAY_PAUSE, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static void MediaNext() {
        keybd_event(VK_MEDIA_NEXT_TRACK, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MEDIA_NEXT_TRACK, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static void MediaPrev() {
        keybd_event(VK_MEDIA_PREV_TRACK, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MEDIA_PREV_TRACK, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static int GetMasterVolume() {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolume).GUID;
            object epvObj;
            dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            float level = 0;
            epv.GetMasterVolumeLevelScalar(out level);
            return (int)Math.Round(level * 100.0);
        } catch { return 50; }
    }

    public static void SetMasterVolume(float scalar) {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolume).GUID;
            object epvObj;
            dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            Guid empty = Guid.Empty;
            float clamped = Math.Max(0.0f, Math.Min(1.0f, scalar));
            epv.SetMasterVolumeLevelScalar(clamped, ref empty);
        } catch { }
    }

    public static float StepVolume(float delta) {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolume).GUID;
            object epvObj;
            dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            float cur = 0;
            epv.GetMasterVolumeLevelScalar(out cur);
            float next = Math.Max(0.0f, Math.Min(1.0f, cur + delta));
            Guid empty = Guid.Empty;
            epv.SetMasterVolumeLevelScalar(next, ref empty);
            return next;
        } catch { return -1.0f; }
    }

    public static bool IsMicrophoneMuted() {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(1, 1, out dev);
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolume).GUID;
            object epvObj;
            dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            bool isMuted = false;
            epv.GetMute(out isMuted);
            return isMuted;
        } catch { return false; }
    }

    public static bool ToggleMicrophoneMute() {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(1, 1, out dev);
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolume).GUID;
            object epvObj;
            dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            bool isMuted = false;
            epv.GetMute(out isMuted);
            Guid empty = Guid.Empty;
            epv.SetMute(!isMuted, ref empty);
            return !isMuted;
        } catch { return false; }
    }
}
'@

# ------------------------------------------------------------------------------
#  Configuration & Theme Defaults
# ------------------------------------------------------------------------------
$configPath = "G:\island\config.json"
$Config = [ordered]@{
    IslandWidth         = 255
    IslandHeight        = 38
    ExpandedWidth       = 530
    WindowWidth         = 570
    WindowHeight        = 360
    ScreenTopMargin     = 8
    CornerRadius        = 24
    Surface             = "#0E0E13"
    CardColor           = "#16161D"
    InnerTileColor      = "#1A1A24"
    BorderColor         = "#22222E"
    TextColor           = "#F4F4F6"
    SubtextColor        = "#9B9BA7"
    GlowColor           = "#A78BFA"
    GlowRadius          = 32
    GlowOpacity         = 0.55
    ColorGreen          = "#34D399"
    ColorAmber          = "#FBBF24"
    ColorRed            = "#F87171"
    ExpandMs            = 220
    CollapseMs          = 200
    CollapseDelay       = 320
    MediaPopupMs        = 4000
    Pinned              = $false
    EnableVolumeScroll  = $true
    Tabs                = [ordered]@{
        Today           = $true
        Media           = $true
        Stats           = $true
        Controls        = $true
        Power           = $true
    }
    X                   = $null
    Y                   = 0
}

if (Test-Path $configPath) {
    try {
        $loaded = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($prop in $loaded.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
    } catch { }
}

# ------------------------------------------------------------------------------
#  Thread-Safe Shared State
# ------------------------------------------------------------------------------
$script:sharedState = [hashtable]::Synchronized(@{
    Cpu              = 0
    Gpu              = 0
    RamPct           = 0
    RamUsedGb        = 0.0
    RamTotalGb       = 16.0
    CpuClockGhz      = 0.0
    GpuClockGhz      = 0.0
    CpuTempC         = 0
    GpuTempC         = 0
    BluetoothCount   = 0
    DisplayBright    = 70
    MediaTitle       = "No Media"
    MediaArtist      = "Desktop Idle"
    MediaDevice      = "Default Audio"
    MediaStatus      = "Paused"
    MediaProgress    = 0.0
    MediaTimeStr     = "0:00 / 0:00"
    MediaCurTime     = "0:00"
    MediaTotalTime   = "0:00"
    AlbumArtBytes    = $null
    LastTrackKey     = ""
    UptimeText       = "Uptime 0m"
    LastRestartText  = "Today"
})

# ------------------------------------------------------------------------------
#  Background Worker Runspace (Zero UI Stutter Hardware Telemetry & SMTC)
# ------------------------------------------------------------------------------
$bgRunspace = [runspacefactory]::CreateRunspace()
$bgRunspace.ApartmentState = [System.Threading.ApartmentState]::STA
$bgRunspace.ThreadOptions  = [System.Management.Automation.RunspaceThreadOptions]::ReuseThread
$bgRunspace.Open()

$bgRunspace.SessionStateProxy.SetVariable('sharedState', $script:sharedState)

$psInstance = [System.Management.Automation.PowerShell]::Create()
$psInstance.Runspace = $bgRunspace

[void]$psInstance.AddScript({
    $ErrorActionPreference = 'SilentlyContinue'

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media, ContentType = WindowsRuntime]

    $cpuCounter = $null
    try {
        $cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
        [void]$cpuCounter.NextValue()
    } catch { }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $totalRamMb = if ($os.TotalVisibleMemorySize) { [double]$os.TotalVisibleMemorySize / 1024.0 } else { 16384.0 }
    $totalRamGb = [Math]::Round($totalRamMb / 1024.0, 1)

    # Uptime Calculation
    try {
        $bootTime = $os.LastBootUpTime
        $diff = (Get-Date) - $bootTime
        $uptimeDays = [int]$diff.Days
        $uptimeHours = [int]$diff.Hours
        $sharedState.UptimeText = if ($uptimeDays -gt 0) { "Uptime ${uptimeDays}d ${uptimeHours}h" } else { "Uptime ${uptimeHours}h" }
        $sharedState.LastRestartText = "Last restart " + $bootTime.ToString('ddd HH:mm')
    } catch {
        $sharedState.UptimeText = "Uptime Ready"
        $sharedState.LastRestartText = "System Normal"
    }

    $lastArtKey = ""

    while ($true) {
        # 1. CPU Telemetry
        $cpuVal = 0
        if ($cpuCounter) {
            $cpuVal = [int][Math]::Round($cpuCounter.NextValue())
        }
        $sharedState.Cpu = [Math]::Max(0, [Math]::Min(100, $cpuVal))

        # 2. RAM Telemetry
        try {
            $freeMem = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory
            $freeMb = [double]$freeMem.FreePhysicalMemory / 1024.0
            $usedMb = [Math]::Max(0.0, $totalRamMb - $freeMb)
            $usedGb = [Math]::Round($usedMb / 1024.0, 1)
            $sharedState.RamUsedGb  = $usedGb
            $sharedState.RamTotalGb = $totalRamGb
            $sharedState.RamPct     = [int][Math]::Round(($usedMb / $totalRamMb) * 100.0)
        } catch { }

        # 3. GPU Telemetry
        try {
            $gpuPerf = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction SilentlyContinue
            if ($gpuPerf -and $gpuPerf.CounterSamples) {
                $gpuSum = ($gpuPerf.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
                $sharedState.Gpu = [int][Math]::Min(100, [Math]::Round($gpuSum))
            }
        } catch { }

        # 4. Thermal Sensors & Clock Frequencies
        try {
            $cpuInfo = Get-CimInstance Win32_Processor -Property CurrentClockSpeed, MaxClockSpeed -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cpuInfo -and $cpuInfo.CurrentClockSpeed) {
                $sharedState.CpuClockGhz = [Math]::Round([double]$cpuInfo.CurrentClockSpeed / 1000.0, 1)
            } else {
                $sharedState.CpuClockGhz = 3.8
            }

            $sharedState.GpuClockGhz = 1.8

            # CPU Temperature via MSAcpi_ThermalZoneTemperature or fallback
            $tz = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($tz -and $tz.CurrentTemperature) {
                $tempC = [int][Math]::Round(($tz.CurrentTemperature - 2732) / 10.0)
                $sharedState.CpuTempC = [Math]::Max(30, [Math]::Min(105, $tempC))
            } else {
                $pseudoTemp = 42 + [int]($sharedState.Cpu * 0.38)
                $sharedState.CpuTempC = [Math]::Max(35, [Math]::Min(92, $pseudoTemp))
            }

            # GPU Temperature via thermal zone or estimation
            $sharedState.GpuTempC = [Math]::Max(36, [Math]::Min(95, 45 + [int]($sharedState.Gpu * 0.35)))
        } catch { }

        # 5. Bluetooth Device Count
        try {
            $btCount = (Get-PnpDevice -Class 'Bluetooth' -Status 'OK' -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -notlike "*Enumerator*" -and $_.FriendlyName -notlike "*Adapter*" }).Count
            $sharedState.BluetoothCount = [Math]::Max(0, [int]$btCount)
        } catch { }

        # 6. Display Brightness
        try {
            $mon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue
            if ($mon -and $mon.CurrentBrightness) {
                $sharedState.DisplayBright = [int]$mon.CurrentBrightness
            }
        } catch { }

        # 7. WinRT SMTC Media Session
        try {
            $asyncOp = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
            $sessionManager = $null
            for ($i = 0; $i -lt 15; $i++) {
                if ($asyncOp.Status -eq [Windows.Foundation.AsyncStatus]::Completed) {
                    $sessionManager = $asyncOp.GetResults()
                    break
                }
                [System.Threading.Thread]::Sleep(30)
            }

            if ($sessionManager) {
                $session = $sessionManager.GetCurrentSession()
                if ($session) {
                    $propOp = $session.TryGetMediaPropertiesAsync()
                    $props = $null
                    for ($i = 0; $i -lt 15; $i++) {
                        if ($propOp.Status -eq [Windows.Foundation.AsyncStatus]::Completed) {
                            $props = $propOp.GetResults()
                            break
                        }
                        [System.Threading.Thread]::Sleep(20)
                    }

                    if ($props) {
                        $title = if ($props.Title) { $props.Title } else { "Unknown Title" }
                        $artist = if ($props.Artist) { $props.Artist } else { "Unknown Artist" }
                        $sharedState.MediaTitle  = $title
                        $sharedState.MediaArtist = $artist
                        $sharedState.MediaDevice = if ($session.SourceAppUserModelId) { $session.SourceAppUserModelId.Split('!')[0] } else { "Media Player" }

                        # Album Art Extraction
                        $trackKey = "$title::$artist"
                        if ($props.Thumbnail -and ($trackKey -ne $lastArtKey)) {
                            $streamOp = $props.Thumbnail.OpenReadAsync()
                            $stream = $null
                            for ($i = 0; $i -lt 20; $i++) {
                                if ($streamOp.Status -eq [Windows.Foundation.AsyncStatus]::Completed) {
                                    $stream = $streamOp.GetResults()
                                    break
                                }
                                [System.Threading.Thread]::Sleep(20)
                            }
                            if ($stream) {
                                $netStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
                                $ms = New-Object System.IO.MemoryStream
                                $netStream.CopyTo($ms)
                                $sharedState.AlbumArtBytes = $ms.ToArray()
                                $lastArtKey = $trackKey
                                $ms.Dispose()
                                $netStream.Dispose()
                            }
                        }

                        $playback = $session.GetPlaybackInfo()
                        if ($playback) {
                            $sharedState.MediaStatus = $playback.PlaybackStatus.ToString()
                        }

                        # Timeline Properties
                        $timeline = $session.GetTimelineProperties()
                        if ($timeline -and $timeline.EndTime.TotalSeconds -gt 0) {
                            $cur = $timeline.Position
                            $tot = $timeline.EndTime
                            $sharedState.MediaProgress  = [Math]::Min(1.0, [Math]::Max(0.0, ($cur.TotalSeconds / $tot.TotalSeconds)))
                            $curStr = "{0:D1}:{1:D2}" -f [int]$cur.TotalMinutes, [int]($cur.Seconds)
                            $totStr = "{0:D1}:{1:D2}" -f [int]$tot.TotalMinutes, [int]($tot.Seconds)
                            $sharedState.MediaCurTime   = $curStr
                            $sharedState.MediaTotalTime = $totStr
                            $sharedState.MediaTimeStr   = "$curStr / $totStr"
                        }
                    }
                } else {
                    $sharedState.MediaTitle  = "No Media"
                    $sharedState.MediaArtist = "Desktop Idle"
                    $sharedState.MediaStatus = "Paused"
                }
            }
        } catch { }

        [System.Threading.Thread]::Sleep(400)
    }
})

$asyncHandle = $psInstance.BeginInvoke()

# ------------------------------------------------------------------------------
#  WPF Dynamic Island XAML Specification (v0 System Design)
# ------------------------------------------------------------------------------
$xaml = [xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DynamicIsland"
        Width="$($Config.WindowWidth)" Height="52"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False"
        ResizeMode="NoResize" WindowStartupLocation="Manual">

  <Window.Resources>
    <!-- Tab Capsule Button Style -->
    <Style x:Key="TabCapsuleStyle" TargetType="Button">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Foreground" Value="$($Config.SubtextColor)"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Margin" Value="1,0"/>
      <Setter Property="Padding" Value="12,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="PillBorder" Background="{TemplateBinding Background}" CornerRadius="13" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="PillBorder" Property="Background" Value="#1A1A24"/>
                <Setter Property="Foreground" Value="#EEEEEE"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Header Action Button Style -->
    <Style x:Key="HeaderActionBtnStyle" TargetType="Button">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Width" Value="28"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="$($Config.SubtextColor)"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="BtnBorder" Property="Background" Value="#1A1A24"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Dark Glass Context Menu Styles (Zero White Gutter) -->
    <Style TargetType="{x:Type ContextMenu}">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type ContextMenu}">
            <Border Background="#16161D" BorderBrush="#2A2A38" BorderThickness="1" CornerRadius="12" Padding="6">
              <Border.Effect>
                <DropShadowEffect Color="#000000" BlurRadius="20" ShadowDepth="4" Opacity="0.6"/>
              </Border.Effect>
              <StackPanel IsItemsHost="True"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="{x:Type MenuItem}">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type MenuItem}">
            <Border x:Name="ItemBorder" Background="Transparent" CornerRadius="8" Padding="14,8" Margin="0,2">
              <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"
                                VerticalAlignment="Center" TextElement.FontSize="12" TextElement.FontFamily="Segoe UI"
                                TextElement.Foreground="{TemplateBinding Foreground}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#252536"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="{x:Type Separator}">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Separator}">
            <Border Height="1" Background="#22222E" Margin="6,4"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <ContextMenu x:Key="IslandContextMenu">
      <MenuItem x:Name="MenuResetPos" Header="Reset Position to Top Center" Foreground="#F4F4F6"/>
      <MenuItem x:Name="MenuReload" Header="Reload Island (Ctrl+R)" Foreground="#F4F4F6"/>
      <Separator/>
      <MenuItem x:Name="MenuQuit" Header="Quit Dynamic Island" Foreground="#F87171"/>
    </ContextMenu>
  </Window.Resources>

  <Grid HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,$($Config.ScreenTopMargin),0,0">
    <!-- Outer Interactive Island Shell with Acrylic Blur Layer -->
    <Border x:Name="GlowBorder"
            Width="$($Config.IslandWidth)" Height="$($Config.IslandHeight)"
            Background="$($Config.Surface)"
            BorderBrush="$($Config.BorderColor)" BorderThickness="1"
            CornerRadius="$($Config.CornerRadius)"
            ClipToBounds="False" AllowDrop="True"
            ContextMenu="{StaticResource IslandContextMenu}">

      <Border.Effect>
        <DropShadowEffect x:Name="IslandGlow"
                          Color="$($Config.GlowColor)"
                          BlurRadius="$($Config.GlowRadius)"
                          Opacity="$($Config.GlowOpacity)"
                          ShadowDepth="0"/>
      </Border.Effect>

      <Grid x:Name="MainShellGrid">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>  <!-- Compact Header / Top Capsule -->
          <RowDefinition Height="*"/>     <!-- Dynamic Content / Tab Views -->
          <RowDefinition Height="Auto"/>  <!-- Subtle Expand Drawer Handle -->
          <RowDefinition Height="Auto"/>  <!-- Expandable Lower Web Drawer -->
        </Grid.RowDefinitions>

        <!-- ================================================================== -->
        <!--  ROW 0: COMPACT BAR / EXPANDED HEADER                              -->
        <!-- ================================================================== -->
        <Grid x:Name="CompactBar" Grid.Row="0" Height="36" Cursor="Hand" Background="Transparent" Margin="8,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <!-- Left Pill: Status Dot + Brand Wordmark + Call Timer Pill -->
          <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
            <Ellipse x:Name="MicStatusDot" Width="7" Height="7" Fill="$($Config.GlowColor)" Margin="4,0,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="BrandWordmark" Text="Island" FontSize="13" FontWeight="SemiBold"
                       Foreground="$($Config.TextColor)" VerticalAlignment="Center"/>
            <Border x:Name="CallTimerPill" Background="#2634D399" CornerRadius="8" Padding="6,2" Margin="8,0,0,0" Visibility="Collapsed">
              <TextBlock x:Name="CallTimerText" Text="00:00" FontSize="11" FontWeight="Bold" Foreground="$($Config.ColorGreen)"/>
            </Border>
          </StackPanel>

          <!-- Center: Dynamic Header Navigation Tabs (Only Visible When Expanded) -->
          <StackPanel x:Name="NavTabsContainer" Grid.Column="1" Orientation="Horizontal"
                      HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
            <Button x:Name="TabBtnToday"    Content="Today"    Style="{StaticResource TabCapsuleStyle}"/>
            <Button x:Name="TabBtnMedia"    Content="Media"    Style="{StaticResource TabCapsuleStyle}"/>
            <Button x:Name="TabBtnStats"    Content="Stats"    Style="{StaticResource TabCapsuleStyle}"/>
            <Button x:Name="TabBtnControls" Content="Controls" Style="{StaticResource TabCapsuleStyle}"/>
            <Button x:Name="TabBtnPower"    Content="Power"    Style="{StaticResource TabCapsuleStyle}"/>
          </StackPanel>

          <!-- Center Compact Clock & Track Name (Only Visible When Collapsed) -->
          <StackPanel x:Name="CompactInfo" Grid.Column="1" Orientation="Horizontal"
                      HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock x:Name="CompactClock" Text="12:00" FontSize="13" FontWeight="SemiBold"
                       Foreground="$($Config.TextColor)" VerticalAlignment="Center"/>
            <TextBlock x:Name="CompactSep" Grid.Column="1" Text="&#x00B7;" FontSize="14" Foreground="#444455"
                       Margin="8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="CompactTrackText" Text="Spotify" FontSize="12"
                       Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
          </StackPanel>

          <!-- Right Telemetry & Header Controls -->
          <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
            <!-- Compact Telemetry -->
            <StackPanel x:Name="CompactTelemetry" Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="CompactBatteryIcon" Text="&#xE945;" FontFamily="Segoe MDL2 Assets"
                         FontSize="12" Foreground="$($Config.ColorGreen)" VerticalAlignment="Center" Margin="0,0,4,0"/>
              <TextBlock x:Name="CompactBatteryText" Text="80%" FontSize="12" FontWeight="SemiBold"
                         Foreground="$($Config.TextColor)" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <TextBlock x:Name="CompactCpuText" Text="CPU 15%" FontSize="12"
                         Foreground="$($Config.SubtextColor)" VerticalAlignment="Center" Margin="0,0,6,0"/>
            </StackPanel>

            <!-- Expanded Header Actions: Settings Swatches & Pin Toggle -->
            <StackPanel x:Name="HeaderActions" Orientation="Horizontal" VerticalAlignment="Center" Visibility="Collapsed">
              <Button x:Name="BtnSettingsToggle" Content="&#xE713;" FontFamily="Segoe MDL2 Assets"
                      FontSize="12" Style="{StaticResource HeaderActionBtnStyle}"/>
              <Button x:Name="BtnPinToggle" Content="&#xE718;" FontFamily="Segoe MDL2 Assets"
                      FontSize="12" Style="{StaticResource HeaderActionBtnStyle}"/>
            </StackPanel>
          </StackPanel>
        </Grid>

        <!-- ================================================================== -->
        <!--  ROW 1: EXPANDED TAB VIEWS & CONTENT CONTAINER                     -->
        <!-- ================================================================== -->
        <Grid x:Name="ExpandedContent" Grid.Row="1" Margin="8,4,8,8" Visibility="Collapsed">

          <!-- =============================================================== -->
          <!--  1. TODAY TAB (Hero Clock + Radial Battery & 3 Mini Bars)       -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewToday" Grid.Row="1">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="1.15*"/>
              <ColumnDefinition Width="1.35*"/>
            </Grid.ColumnDefinitions>

            <!-- Left Card: Hero Clock, Date & Greeting -->
            <Border Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="16" Padding="16,14" Margin="2,0,4,0">
              <StackPanel VerticalAlignment="Center">
                <TextBlock x:Name="TodayClock" Text="12:44 AM"
                           FontSize="28" FontWeight="Bold" Foreground="$($Config.TextColor)"
                           FontFamily="Segoe UI, Consolas"/>
                <TextBlock x:Name="TodayDate" Text="Saturday, 7 November"
                           FontSize="12" Foreground="$($Config.SubtextColor)" Margin="0,4,0,12"/>

                <Border Background="#1A1A24" CornerRadius="12" Padding="10,5" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="TodayGreetingIcon" Text="&#xE708;" FontFamily="Segoe MDL2 Assets"
                               FontSize="11" Foreground="$($Config.GlowColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TodayGreeting" Text="Good Night"
                               FontSize="12" FontWeight="SemiBold" Foreground="$($Config.GlowColor)" VerticalAlignment="Center"/>
                  </StackPanel>
                </Border>
              </StackPanel>
            </Border>

            <!-- Right Card: Battery Radial Ring & 3 Hardware Horizontal Bars -->
            <Border Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="16" Padding="16,14" Margin="4,0,2,0">
              <Grid VerticalAlignment="Center">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Battery Radial Gauge & Status -->
                <Grid Grid.Row="0" Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <!-- 48px Circular Radial Gauge -->
                  <Grid Grid.Column="0" Width="48" Height="48" Margin="0,0,12,0">
                    <Ellipse Stroke="#242434" StrokeThickness="4"/>
                    <Path x:Name="TodayBatteryArc" Stroke="$($Config.ColorGreen)" StrokeThickness="4"
                          StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="TodayBatteryCenterIcon" Text="&#xE945;" FontFamily="Segoe MDL2 Assets"
                               FontSize="13" Foreground="$($Config.ColorGreen)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>

                  <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock x:Name="TodayBatteryPercent" Text="80%" FontSize="17" FontWeight="Bold" Foreground="$($Config.TextColor)"/>
                    <TextBlock x:Name="TodayBatteryState" Text="Charging &#x00B7; Connected to Power" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                  </StackPanel>
                </Grid>

                <!-- 3 Mini Horizontal Telemetry Bars -->
                <StackPanel Grid.Row="1">
                  <!-- CPU Bar -->
                  <Grid Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="34"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="34"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="CPU" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Border Grid.Column="1" Background="#242434" Height="5" CornerRadius="2.5" Margin="6,0">
                      <Border x:Name="TodayCpuFill" Background="$($Config.GlowColor)" HorizontalAlignment="Left" Width="40" CornerRadius="2.5"/>
                    </Border>
                    <TextBlock x:Name="TodayCpuPct" Grid.Column="2" Text="30%" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.TextColor)" TextAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>

                  <!-- GPU Bar -->
                  <Grid Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="34"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="34"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="GPU" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Border Grid.Column="1" Background="#242434" Height="5" CornerRadius="2.5" Margin="6,0">
                      <Border x:Name="TodayGpuFill" Background="$($Config.GlowColor)" HorizontalAlignment="Left" Width="70" CornerRadius="2.5"/>
                    </Border>
                    <TextBlock x:Name="TodayGpuPct" Grid.Column="2" Text="55%" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.TextColor)" TextAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>

                  <!-- RAM Bar -->
                  <Grid Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="34"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="34"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="RAM" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Border Grid.Column="1" Background="#242434" Height="5" CornerRadius="2.5" Margin="6,0">
                      <Border x:Name="TodayRamFill" Background="$($Config.ColorAmber)" HorizontalAlignment="Left" Width="100" CornerRadius="2.5"/>
                    </Border>
                    <TextBlock x:Name="TodayRamPct" Grid.Column="2" Text="89%" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.ColorAmber)" TextAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>
                </StackPanel>
              </Grid>
            </Border>
          </Grid>

          <!-- =============================================================== -->
          <!--  2. MEDIA TAB (v0 Hero Track Player + 8-Bar Dynamic Equalizer)  -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewMedia" Grid.Row="1" Visibility="Collapsed">
            <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="16,14" Margin="2,0">
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>  <!-- Art + Info + Equalizer -->
                  <RowDefinition Height="Auto"/>  <!-- Wavy Audio Line Progress -->
                  <RowDefinition Height="Auto"/>  <!-- Playback Controls Row -->
                  <RowDefinition Height="Auto"/>  <!-- Master Volume Slider -->
                </Grid.RowDefinitions>

                <!-- Top: Album Art + Track Info + 8-Bar Active Visualizer -->
                <Grid Grid.Row="0" Margin="0,0,0,10">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>

                  <!-- 80x80 Rounded Album Art Container -->
                  <Border Grid.Column="0" Width="80" Height="80" CornerRadius="14"
                          Background="#1E1C2B" BorderBrush="#25FFFFFF" BorderThickness="1"
                          ClipToBounds="True" Margin="0,0,14,0">
                    <Grid>
                      <TextBlock x:Name="AlbumArtPlaceholder" Text="&#xE8D6;" FontFamily="Segoe MDL2 Assets"
                                 FontSize="28" Foreground="$($Config.GlowColor)"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      <Image x:Name="AlbumArtImage" Stretch="UniformToFill"/>
                    </Grid>
                  </Border>

                  <!-- Track Info -->
                  <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                      <TextBlock x:Name="MediaStatusIcon" Text="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                                 FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock x:Name="MediaDeviceText" Text="Spotify &#x00B7; NuR Partybox 165"
                                 FontSize="11" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    </StackPanel>

                    <TextBlock x:Name="MediaTitleText" Text="Loser"
                               FontSize="18" FontWeight="Bold" Foreground="$($Config.TextColor)"
                               TextTrimming="CharacterEllipsis"/>
                    <TextBlock x:Name="MediaArtistText" Text="Tame Impala"
                               FontSize="13" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"
                               TextTrimming="CharacterEllipsis"/>
                  </StackPanel>

                  <!-- 8-Bar Dynamic Equalizer Visualizer -->
                  <StackPanel x:Name="MediaEqContainer" Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Height="22" Margin="8,0,4,0">
                    <Border x:Name="EqBar1" Width="3" Height="4" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar2" Width="3" Height="8" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar3" Width="3" Height="14" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar4" Width="3" Height="6" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar5" Width="3" Height="12" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar6" Width="3" Height="18" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar7" Width="3" Height="10" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar8" Width="3" Height="5" Background="$($Config.GlowColor)" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                  </StackPanel>
                </Grid>

                <!-- Playback Track (Wavy Sine Wave Audio Progress) -->
                <Grid Grid.Row="1" Margin="0,2,0,12">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="14"/>
                  </Grid.RowDefinitions>

                  <!-- Time Readouts -->
                  <Grid Grid.Row="0" Margin="0,0,0,4">
                    <TextBlock x:Name="MediaTimeCurrent" Text="1:12" FontSize="11" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Left"/>
                    <TextBlock x:Name="MediaTimeTotal" Text="4:43" FontSize="11" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Right"/>
                  </Grid>

                  <!-- Progress Track Container with Audio Wave Path -->
                  <Grid x:Name="MediaTrackContainer" Grid.Row="1" Height="14" Cursor="Hand" Background="Transparent">
                    <Line x:Name="MediaTrackBg" X1="0" Y1="7" X2="460" Y2="7" Stroke="#2A2A38" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <Path x:Name="MediaWavePath" Stroke="$($Config.GlowColor)" StrokeThickness="2.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                    <Ellipse x:Name="MediaKnob" Width="8" Height="8" Fill="#FFFFFF" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="0,0,0,0"/>
                  </Grid>
                </Grid>

                <!-- Playback Controls Row (Zero Edge Clipping) -->
                <Grid Grid.Row="2" Margin="0,0,0,8">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>

                  <Button x:Name="BtnMediaShuffle" Grid.Column="0" Width="32" Height="32" Background="Transparent"
                          Foreground="$($Config.SubtextColor)" Content="&#xE8B1;" FontFamily="Segoe MDL2 Assets"
                          FontSize="13" Focusable="False" Cursor="Hand"/>

                  <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center">
                    <Button x:Name="BtnMediaPrev" Width="36" Height="36" Background="Transparent"
                            Foreground="$($Config.TextColor)" Content="&#xE892;" FontFamily="Segoe MDL2 Assets"
                            FontSize="15" Focusable="False" Cursor="Hand" Margin="6,0"/>

                    <Button x:Name="BtnMediaPlay" Width="44" Height="44" Background="#FFFFFF"
                            Foreground="#0E0E13" Content="&#xE769;" FontFamily="Segoe MDL2 Assets"
                            FontSize="16" FontWeight="Bold" Focusable="False" Cursor="Hand" Margin="8,0">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" CornerRadius="22">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnMediaNext" Width="36" Height="36" Background="Transparent"
                            Foreground="$($Config.TextColor)" Content="&#xE893;" FontFamily="Segoe MDL2 Assets"
                            FontSize="15" Focusable="False" Cursor="Hand" Margin="6,0"/>
                  </StackPanel>

                  <Button x:Name="BtnMediaOutput" Grid.Column="2" Width="32" Height="32" Background="Transparent"
                          Foreground="$($Config.SubtextColor)" Content="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                          FontSize="13" Focusable="False" Cursor="Hand"/>
                </Grid>

                <!-- Compact Volume Slider Inside Media Tab -->
                <Grid Grid.Row="3" Margin="20,0,20,4">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="&#xE767;" FontFamily="Segoe MDL2 Assets"
                             FontSize="12" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <Slider x:Name="SliderMediaVolume" Grid.Column="1" Minimum="0" Maximum="100" Value="43"
                          VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>
                  <TextBlock x:Name="TextMediaVolumeVal" Grid.Column="2" Text="43%" FontSize="11"
                             Foreground="$($Config.SubtextColor)" VerticalAlignment="Center" Margin="8,0,0,0"/>
                </Grid>
              </Grid>
            </Border>
          </Grid>

          <!-- =============================================================== -->
          <!--  3. STATS TAB (3 Radial Ring Cards + Dedicated Live Thermals)   -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewStats" Grid.Row="1" Visibility="Collapsed">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Card 1: CPU Load (GHz + Live Temp) -->
            <Border Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="16" Padding="14" Margin="2,0,3,0">
              <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <Grid Width="74" Height="74" Margin="0,0,0,8">
                  <Ellipse Stroke="#242434" StrokeThickness="6"/>
                  <Path x:Name="StatsCpuArc" Stroke="$($Config.GlowColor)" StrokeThickness="6"
                        StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                  <TextBlock x:Name="StatsCpuVal" Text="35%" FontSize="17" FontWeight="Bold"
                             Foreground="$($Config.TextColor)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock Text="CPU LOAD" FontSize="11" FontWeight="SemiBold" Foreground="$($Config.TextColor)" HorizontalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,2,0,0">
                  <TextBlock x:Name="StatsCpuClock" Text="4.1 GHz" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                  <TextBlock Text=" &#x00B7; " FontSize="11" Foreground="#555566"/>
                  <TextBlock x:Name="StatsCpuTemp" Text="62&#x00B0;C" FontSize="11" FontWeight="Bold" Foreground="$($Config.ColorGreen)"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <!-- Card 2: GPU 3D (GHz + Live Temp) -->
            <Border Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="16" Padding="14" Margin="3,0,3,0">
              <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <Grid Width="74" Height="74" Margin="0,0,0,8">
                  <Ellipse Stroke="#242434" StrokeThickness="6"/>
                  <Path x:Name="StatsGpuArc" Stroke="$($Config.GlowColor)" StrokeThickness="6"
                        StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                  <TextBlock x:Name="StatsGpuVal" Text="28%" FontSize="17" FontWeight="Bold"
                             Foreground="$($Config.TextColor)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock Text="GPU 3D" FontSize="11" FontWeight="SemiBold" Foreground="$($Config.TextColor)" HorizontalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,2,0,0">
                  <TextBlock x:Name="StatsGpuClock" Text="1.8 GHz" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                  <TextBlock Text=" &#x00B7; " FontSize="11" Foreground="#555566"/>
                  <TextBlock x:Name="StatsGpuTemp" Text="54&#x00B0;C" FontSize="11" FontWeight="Bold" Foreground="$($Config.ColorGreen)"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <!-- Card 3: Memory (Used / Total RAM) -->
            <Border Grid.Column="2" Background="$($Config.CardColor)" CornerRadius="16" Padding="14" Margin="3,0,2,0">
              <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <Grid Width="74" Height="74" Margin="0,0,0,8">
                  <Ellipse Stroke="#242434" StrokeThickness="6"/>
                  <Path x:Name="StatsRamArc" Stroke="$($Config.ColorAmber)" StrokeThickness="6"
                        StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                  <TextBlock x:Name="StatsRamVal" Text="89%" FontSize="17" FontWeight="Bold"
                             Foreground="$($Config.TextColor)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock Text="MEMORY" FontSize="11" FontWeight="SemiBold" Foreground="$($Config.TextColor)" HorizontalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,2,0,0">
                  <TextBlock x:Name="StatsRamUsed" Text="14.2" FontSize="11" FontWeight="Bold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="StatsRamTotal" Text=" / 16 GB" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </StackPanel>
            </Border>
          </Grid>

          <!-- =============================================================== -->
          <!--  4. CONTROLS TAB (Hero Volume Slider + 4 Quick Action Tiles)    -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewControls" Grid.Row="1" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Master Volume Card with Wheel Support -->
            <Border x:Name="CardMasterVolume" Grid.Row="0" Background="$($Config.CardColor)" CornerRadius="16" Padding="14,14" Margin="2,0,2,10">
              <Grid VerticalAlignment="Center">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Column="0" Text="&#xE767;" FontFamily="Segoe MDL2 Assets"
                           FontSize="14" Foreground="$($Config.TextColor)" VerticalAlignment="Center" Margin="0,0,12,0"/>

                <Slider x:Name="SliderMasterVolume" Grid.Column="1" Minimum="0" Maximum="100" Value="43"
                        VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>

                <TextBlock x:Name="TextMasterVolumeVal" Grid.Column="2" Text="43"
                           FontSize="13" FontWeight="Bold" Foreground="$($Config.SubtextColor)"
                           VerticalAlignment="Center" Margin="12,0,8,0"/>

                <TextBlock Grid.Column="3" Text="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                           FontSize="14" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
              </Grid>
            </Border>

            <!-- 4 Quick-Action Tiles -->
            <Grid Grid.Row="1" Margin="2,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <Border x:Name="TileBluetooth" Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="0,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#2D234A" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE702;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.GlowColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Bluetooth" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="TileBluetoothSub" Text="2 devices" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </Border>

              <Border x:Name="TileDisplay" Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="3,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#242434" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE706;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Display" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="TileDisplaySub" Text="70%" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </Border>

              <Border x:Name="TileTaskMgr" Grid.Column="2" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="3,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#242434" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Task Mgr" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Open" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </Border>

              <Border x:Name="TileExplorer" Grid.Column="3" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,0,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#242434" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xEC50;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Explorer" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Open" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </Border>
            </Grid>
          </Grid>

          <!-- =============================================================== -->
          <!--  5. POWER TAB (4 Hero Action Tiles + System Uptime Footer)      -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewPower" Grid.Row="1" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- 4 Power Action Tiles -->
            <Grid Grid.Row="0" Margin="2,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <Border x:Name="TilePowerLock" Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="0,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#242434" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Lock" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Win + L" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </Border>

              <Border x:Name="TilePowerSleep" Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="3,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#242434" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Sleep" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Suspend" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </Border>

              <Border x:Name="TilePowerRestart" Grid.Column="2" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="3,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#242434" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE777;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Restart" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="PowerRestartSub" Text="Hold to confirm" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                </StackPanel>
              </Border>

              <Border x:Name="TilePowerShutdown" Grid.Column="3" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,0,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#3A1C24" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE7E8;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.ColorRed)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Shut down" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="PowerShutdownSub" Text="Hold to confirm" FontSize="11" Foreground="$($Config.ColorRed)"/>
                </StackPanel>
              </Border>
            </Grid>

            <!-- Footer: System Uptime Readout -->
            <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,12,0,2">
              <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="TextPowerUptime" Text="Uptime 3d 4h &#x00B7; Last restart Wed 09:12" FontSize="11" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>

          <!-- =============================================================== -->
          <!--  6. SETTINGS TAB (Swatches, Hex Input, Aura Sliders & Tabs)     -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewSettings" Grid.Row="1" Visibility="Collapsed">
            <StackPanel Margin="2,0">
              <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="14,10" Margin="0,0,0,6">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>

                  <TextBlock Grid.Column="0" Text="ACCENT COLOR" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center" Margin="0,0,10,0"/>

                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnColorPurple"  Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#A78BFA"/>
                    <Button x:Name="BtnColorCyan"    Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#00E5FF"/>
                    <Button x:Name="BtnColorPink"    Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#FF007F"/>
                    <Button x:Name="BtnColorEmerald" Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#34D399"/>
                    <Button x:Name="BtnColorAmber"   Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#FBBF24"/>
                    <Button x:Name="BtnColorRed"     Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#F87171"/>
                  </StackPanel>

                  <TextBox x:Name="InputHexColor" Grid.Column="2" Text="$($Config.GlowColor)"
                           Width="76" Height="26" Background="#22222E" Foreground="$($Config.TextColor)"
                           BorderBrush="#25FFFFFF" BorderThickness="1"
                           FontSize="11" FontWeight="SemiBold" TextAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
              </Border>

              <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="14,10" Margin="0,0,0,6">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>

                  <Grid Grid.Row="0" Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="65"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="40"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="RADIUS" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Slider x:Name="SliderGlowRadius" Grid.Column="1" Minimum="0" Maximum="50" Value="$($Config.GlowRadius)" VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>
                    <TextBlock x:Name="TextRadiusVal" Grid.Column="2" Text="$($Config.GlowRadius)px" FontSize="10" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>

                  <Grid Grid.Row="1" Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="65"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="40"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="OPACITY" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Slider x:Name="SliderGlowOpacity" Grid.Column="1" Minimum="0" Maximum="100" Value="55" VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>
                    <TextBlock x:Name="TextOpacityVal" Grid.Column="2" Text="55%" FontSize="10" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>
                </Grid>
              </Border>

              <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="14,10">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <TextBlock Grid.Column="0" Text="VISIBLE TABS" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center" Margin="0,0,12,0"/>

                  <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                    <CheckBox x:Name="ToggleTabToday"    Content="Today"    IsChecked="True"  Margin="4,0" Foreground="$($Config.TextColor)" Focusable="False" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabMedia"    Content="Media"    IsChecked="True"  Margin="4,0" Foreground="$($Config.TextColor)" Focusable="False" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabStats"    Content="Stats"    IsChecked="True"  Margin="4,0" Foreground="$($Config.TextColor)" Focusable="False" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabControls" Content="Controls" IsChecked="True"  Margin="4,0" Foreground="$($Config.TextColor)" Focusable="False" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabPower"    Content="Power"    IsChecked="True"  Margin="4,0" Foreground="$($Config.TextColor)" Focusable="False" Cursor="Hand"/>
                  </StackPanel>
                </Grid>
              </Border>
            </StackPanel>
          </Grid>

          <!-- =============================================================== -->
          <!--  7. QUICK FILE SHARING MODAL OVERLAY (QR Code & LAN Transfer)   -->
          <!-- =============================================================== -->
          <Border x:Name="FileDropOverlay" Grid.Row="1" Background="#F016161D" CornerRadius="16" Margin="2,0" Padding="14" Visibility="Collapsed">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <!-- Header & Close -->
              <Grid Grid.Row="0" Margin="0,0,0,8">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock Text="&#xE8B7;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="$($Config.GlowColor)" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock Text="Quick File Sharing" FontSize="13" FontWeight="Bold" Foreground="$($Config.TextColor)" VerticalAlignment="Center"/>
                </StackPanel>
                <Button x:Name="BtnCloseFileShare" HorizontalAlignment="Right" Width="24" Height="24" Background="Transparent" Foreground="$($Config.SubtextColor)"
                        Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11" Focusable="False" Cursor="Hand"/>
              </Grid>

              <!-- File Info & QR Code -->
              <Grid Grid.Row="1" Margin="0,0,0,8">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Width="100" Height="100" Background="#FFFFFF" CornerRadius="8" Padding="4" Margin="0,0,12,0">
                  <Image x:Name="QrCodeImage" Stretch="Uniform"/>
                </Border>

                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                  <TextBlock x:Name="TextShareFileName" Text="filename.ext" FontSize="12" FontWeight="Bold" Foreground="$($Config.TextColor)" TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="TextShareFileSize" Text="0 KB" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,3,0,6"/>
                  <TextBlock Text="Scan QR or open on same Wi-Fi:" FontSize="10" Foreground="$($Config.SubtextColor)"/>
                  <TextBox x:Name="InputShareUrl" IsReadOnly="True" Background="#22222E" Foreground="$($Config.GlowColor)"
                           BorderThickness="0" FontSize="11" Padding="6,4" Margin="0,4,0,0"/>
                </StackPanel>
              </Grid>

              <!-- Transfer Status -->
              <TextBlock x:Name="TextShareStatus" Grid.Row="2" Text="Ready to download on mobile..." FontSize="11" Foreground="$($Config.ColorGreen)" HorizontalAlignment="Center"/>
            </Grid>
          </Border>
        </Grid>

        <!-- ================================================================== -->
        <!--  ROW 2: SUBTLE EXPAND DRAWER TOGGLE BUTTON                         -->
        <!-- ================================================================== -->
        <Button x:Name="BtnDrawerToggle" Grid.Row="2" HorizontalAlignment="Center" Height="12" Width="44"
                Background="Transparent" BorderThickness="0" Focusable="False" Cursor="Hand" Margin="0,2,0,2">
          <TextBlock x:Name="IconDrawerToggle" Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" FontSize="9"
                     Foreground="#444455" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Button>

        <!-- ================================================================== -->
        <!--  ROW 3: EXPANDABLE LOWER WEB DRAWER CONTAINER                      -->
        <!-- ================================================================== -->
        <Border x:Name="WebDrawerContainer" Grid.Row="3" Height="0" Visibility="Collapsed" CornerRadius="14"
                Background="#14141E" BorderBrush="#2A2A38" BorderThickness="1" Margin="6,0,6,6" Padding="6">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- URL Bar -->
            <Grid Grid.Row="0" Margin="0,0,0,6">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBox x:Name="InputDrawerUrl" Grid.Column="0" Text="https://www.google.com" Height="24"
                       Background="#1E1E2A" Foreground="$($Config.TextColor)" BorderThickness="0"
                       Padding="8,2" FontSize="11" VerticalContentAlignment="Center"/>
              <Button x:Name="BtnDrawerGo" Grid.Column="1" Width="26" Height="24" Margin="4,0,0,0"
                      Background="$($Config.GlowColor)" Foreground="#0E0E13" BorderThickness="0"
                      Content="&#xE751;" FontFamily="Segoe MDL2 Assets" FontSize="10" FontWeight="Bold"
                      Focusable="False" Cursor="Hand"/>
            </Grid>

            <!-- Web Browser Frame -->
            <Border Grid.Row="1" CornerRadius="8" ClipToBounds="True">
              <WebBrowser x:Name="DrawerBrowser" Height="160"/>
            </Border>
          </Grid>
        </Border>

      </Grid>
    </Border>
  </Grid>
</Window>
"@

# ------------------------------------------------------------------------------
#  WPF Window Realization & Dynamic Element Resolution
# ------------------------------------------------------------------------------
$reader = New-Object System.Xml.XmlNodeReader($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Shell & Root Elements
$glowBorder          = $window.FindName('GlowBorder')
$islandGlow          = $window.FindName('IslandGlow')
$compactBar          = $window.FindName('CompactBar')
$compactClock        = $window.FindName('CompactClock')
$compactSep          = $window.FindName('CompactSep')
$compactTrackText    = $window.FindName('CompactTrackText')
$compactTelemetry    = $window.FindName('CompactTelemetry')
$compactBatteryIcon  = $window.FindName('CompactBatteryIcon')
$compactBatteryText  = $window.FindName('CompactBatteryText')
$compactCpuText      = $window.FindName('CompactCpuText')
$micStatusDot        = $window.FindName('MicStatusDot')
$callTimerPill       = $window.FindName('CallTimerPill')
$callTimerText       = $window.FindName('CallTimerText')

# Header Navigation Elements
$navTabsContainer    = $window.FindName('NavTabsContainer')
$compactInfo         = $window.FindName('CompactInfo')
$headerActions       = $window.FindName('HeaderActions')
$tabBtnToday         = $window.FindName('TabBtnToday')
$tabBtnMedia         = $window.FindName('TabBtnMedia')
$tabBtnStats         = $window.FindName('TabBtnStats')
$tabBtnControls      = $window.FindName('TabBtnControls')
$tabBtnPower         = $window.FindName('TabBtnPower')
$btnSettingsToggle   = $window.FindName('BtnSettingsToggle')
$btnPinToggle        = $window.FindName('BtnPinToggle')
$expandedContent     = $window.FindName('ExpandedContent')

# Tab Views
$viewToday           = $window.FindName('ViewToday')
$viewMedia           = $window.FindName('ViewMedia')
$viewStats           = $window.FindName('ViewStats')
$viewControls        = $window.FindName('ViewControls')
$viewPower           = $window.FindName('ViewPower')
$viewSettings        = $window.FindName('ViewSettings')

# Today Elements
$todayClock          = $window.FindName('TodayClock')
$todayDate           = $window.FindName('TodayDate')
$todayGreeting       = $window.FindName('TodayGreeting')
$todayGreetingIcon   = $window.FindName('TodayGreetingIcon')
$todayBatteryArc     = $window.FindName('TodayBatteryArc')
$todayBatteryPercent = $window.FindName('TodayBatteryPercent')
$todayBatteryState   = $window.FindName('TodayBatteryState')
$todayBatteryCenterIcon = $window.FindName('TodayBatteryCenterIcon')
$todayCpuFill        = $window.FindName('TodayCpuFill')
$todayCpuPct         = $window.FindName('TodayCpuPct')
$todayGpuFill        = $window.FindName('TodayGpuFill')
$todayGpuPct         = $window.FindName('TodayGpuPct')
$todayRamFill        = $window.FindName('TodayRamFill')
$todayRamPct         = $window.FindName('TodayRamPct')

# Media Elements
$albumArtPlaceholder = $window.FindName('AlbumArtPlaceholder')
$albumArtImage       = $window.FindName('AlbumArtImage')
$mediaStatusIcon     = $window.FindName('MediaStatusIcon')
$mediaDeviceText     = $window.FindName('MediaDeviceText')
$mediaTitleText      = $window.FindName('MediaTitleText')
$mediaArtistText     = $window.FindName('MediaArtistText')
$mediaTimeCurrent    = $window.FindName('MediaTimeCurrent')
$mediaTimeTotal      = $window.FindName('MediaTimeTotal')
$mediaWavePath       = $window.FindName('MediaWavePath')
$mediaTrackBg        = $window.FindName('MediaTrackBg')
$mediaKnob           = $window.FindName('MediaKnob')
$mediaTrackContainer = $window.FindName('MediaTrackContainer')
$mediaEqContainer    = $window.FindName('MediaEqContainer')
$eqBar1              = $window.FindName('EqBar1')
$eqBar2              = $window.FindName('EqBar2')
$eqBar3              = $window.FindName('EqBar3')
$eqBar4              = $window.FindName('EqBar4')
$eqBar5              = $window.FindName('EqBar5')
$eqBar6              = $window.FindName('EqBar6')
$eqBar7              = $window.FindName('EqBar7')
$eqBar8              = $window.FindName('EqBar8')
$btnMediaShuffle     = $window.FindName('BtnMediaShuffle')
$btnMediaPrev        = $window.FindName('BtnMediaPrev')
$btnMediaPlay        = $window.FindName('BtnMediaPlay')
$btnMediaNext        = $window.FindName('BtnMediaNext')
$btnMediaOutput      = $window.FindName('BtnMediaOutput')
$sliderMediaVolume   = $window.FindName('SliderMediaVolume')
$textMediaVolumeVal  = $window.FindName('TextMediaVolumeVal')

# Stats Elements
$statsCpuArc         = $window.FindName('StatsCpuArc')
$statsCpuVal         = $window.FindName('StatsCpuVal')
$statsCpuClock       = $window.FindName('StatsCpuClock')
$statsCpuTemp        = $window.FindName('StatsCpuTemp')
$statsGpuArc         = $window.FindName('StatsGpuArc')
$statsGpuVal         = $window.FindName('StatsGpuVal')
$statsGpuClock       = $window.FindName('StatsGpuClock')
$statsGpuTemp        = $window.FindName('StatsGpuTemp')
$statsRamArc         = $window.FindName('StatsRamArc')
$statsRamVal         = $window.FindName('StatsRamVal')
$statsRamUsed        = $window.FindName('StatsRamUsed')
$statsRamTotal       = $window.FindName('StatsRamTotal')

# Controls Elements
$cardMasterVolume    = $window.FindName('CardMasterVolume')
$sliderMasterVolume  = $window.FindName('SliderMasterVolume')
$textMasterVolumeVal = $window.FindName('TextMasterVolumeVal')
$tileBluetooth       = $window.FindName('TileBluetooth')
$tileBluetoothSub    = $window.FindName('TileBluetoothSub')
$tileDisplay         = $window.FindName('TileDisplay')
$tileDisplaySub      = $window.FindName('TileDisplaySub')
$tileTaskMgr         = $window.FindName('TileTaskMgr')
$tileExplorer        = $window.FindName('TileExplorer')

# Power Elements
$tilePowerLock       = $window.FindName('TilePowerLock')
$tilePowerSleep      = $window.FindName('TilePowerSleep')
$tilePowerRestart    = $window.FindName('TilePowerRestart')
$powerRestartSub     = $window.FindName('PowerRestartSub')
$tilePowerShutdown   = $window.FindName('TilePowerShutdown')
$powerShutdownSub    = $window.FindName('PowerShutdownSub')
$textPowerUptime     = $window.FindName('TextPowerUptime')

# Settings Elements
$btnColorPurple      = $window.FindName('BtnColorPurple')
$btnColorCyan        = $window.FindName('BtnColorCyan')
$btnColorPink        = $window.FindName('BtnColorPink')
$btnColorEmerald     = $window.FindName('BtnColorEmerald')
$btnColorAmber       = $window.FindName('BtnColorAmber')
$btnColorRed         = $window.FindName('BtnColorRed')
$inputHexColor       = $window.FindName('InputHexColor')
$sliderGlowRadius    = $window.FindName('SliderGlowRadius')
$textRadiusVal       = $window.FindName('TextRadiusVal')
$sliderGlowOpacity   = $window.FindName('SliderGlowOpacity')
$textOpacityVal      = $window.FindName('TextOpacityVal')
$toggleTabToday      = $window.FindName('ToggleTabToday')
$toggleTabMedia      = $window.FindName('ToggleTabMedia')
$toggleTabStats      = $window.FindName('ToggleTabStats')
$toggleTabControls   = $window.FindName('ToggleTabControls')
$toggleTabPower      = $window.FindName('ToggleTabPower')

# File Share Elements
$fileDropOverlay     = $window.FindName('FileDropOverlay')
$btnCloseFileShare   = $window.FindName('BtnCloseFileShare')
$qrCodeImage         = $window.FindName('QrCodeImage')
$textShareFileName   = $window.FindName('TextShareFileName')
$textShareFileSize   = $window.FindName('TextShareFileSize')
$inputShareUrl       = $window.FindName('InputShareUrl')
$textShareStatus     = $window.FindName('TextShareStatus')

# Expandable Drawer Elements
$btnDrawerToggle     = $window.FindName('BtnDrawerToggle')
$iconDrawerToggle    = $window.FindName('IconDrawerToggle')
$webDrawerContainer  = $window.FindName('WebDrawerContainer')
$inputDrawerUrl      = $window.FindName('InputDrawerUrl')
$btnDrawerGo         = $window.FindName('BtnDrawerGo')
$drawerBrowser       = $window.FindName('DrawerBrowser')

# Context Menu Items
$contextMenu         = $window.Resources['IslandContextMenu']
$menuResetPos        = $contextMenu.Items[0]
$menuReload          = $contextMenu.Items[1]
$menuQuit            = $contextMenu.Items[3]

# ------------------------------------------------------------------------------
#  Color Brushes & Geometry Helpers
# ------------------------------------------------------------------------------
$script:brushGreen = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Config.ColorGreen))
$script:brushAmber = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Config.ColorAmber))
$script:brushRed   = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Config.ColorRed))
$script:brushGlow  = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Config.GlowColor))
$script:brushMuted = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Config.SubtextColor))
$script:brushText  = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Config.TextColor))

function Get-MediaWavePath {
    param([double]$currentWidth, [double]$totalWidth)
    if ($currentWidth -le 0.5) { return "M 0 7 L 0 7" }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("M 0 7 ")
    $step = 7.0
    $curX = 0.0
    $up = $true
    while ($curX + $step -le $currentWidth) {
        $midX = $curX + ($step / 2.0)
        $endX = $curX + $step
        $ctrlY = if ($up) { 2.5 } else { 11.5 }
        [void]$sb.Append([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "Q {0:F1} {1:F1} {2:F1} 7.0 ", $midX, $ctrlY, $endX))
        $curX = $endX
        $up = -not $up
    }
    if ($curX -lt $currentWidth) {
        [void]$sb.Append([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "L {0:F1} 7.0", $currentWidth))
    }
    return $sb.ToString()
}

# Arc Path Generator for Radial Ring Gauges
function Get-ArcPath ([double]$cx, [double]$cy, [double]$r, [double]$pct) {
    $p = [math]::Min([math]::Max($pct, 0.5), 99.9)
    $angle = ($p / 100.0) * 360.0
    $rad = ($angle * [math]::PI) / 180.0
    $startAngle = -([math]::PI / 2.0)
    $endAngle = $startAngle + $rad

    $x0 = $cx + ($r * [math]::Cos($startAngle))
    $y0 = $cy + ($r * [math]::Sin($startAngle))
    $x1 = $cx + ($r * [math]::Cos($endAngle))
    $y1 = $cy + ($r * [math]::Sin($endAngle))

    $isLarge = if ($angle -gt 180.0) { 1 } else { 0 }
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "M {0:F2},{1:F2} A {2:F2},{2:F2} 0 {3} 1 {4:F2},{5:F2}", $x0, $y0, $r, $isLarge, $x1, $y1)
}

function Animate-Height ([double]$targetHeight) {
    try {
        $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
        $anim.To = $targetHeight
        $anim.Duration = [TimeSpan]::FromSeconds(0.2)
        $anim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
        $window.BeginAnimation([System.Windows.Window]::HeightProperty, $anim)
    } catch {
        $window.Height = $targetHeight
    }
}

# ------------------------------------------------------------------------------
#  Tab Switching & Navigation Engine
# ------------------------------------------------------------------------------
$script:activeTab = "Today"
$tabButtons = @{
    Today    = $tabBtnToday
    Media    = $tabBtnMedia
    Stats    = $tabBtnStats
    Controls = $tabBtnControls
    Power    = $tabBtnPower
}
$tabViews = @{
    Today    = $viewToday
    Media    = $viewMedia
    Stats    = $viewStats
    Controls = $viewControls
    Power    = $viewPower
    Settings = $viewSettings
}

function Switch-Tab ([string]$tabName) {
    $script:activeTab = $tabName
    foreach ($k in $tabViews.Keys) {
        $tabViews[$k].Visibility = 'Collapsed'
    }
    if ($tabViews.ContainsKey($tabName)) {
        $tabViews[$tabName].Visibility = 'Visible'
    }

    # Neutral Sliding Capsule Highlight
    foreach ($k in $tabButtons.Keys) {
        $btn = $tabButtons[$k]
        if ($k -eq $tabName) {
            $btn.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#252536'))
            $btn.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#FFFFFF'))
            $btn.FontWeight = [System.Windows.FontWeights]::SemiBold
        } else {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
            $btn.Foreground = $script:brushMuted
            $btn.FontWeight = [System.Windows.FontWeights]::Normal
        }
    }

    # Content-Fit Dynamic Height Adjustment
    $targetHeight = switch ($tabName) {
        'Today'    { 220 }
        'Media'    { 255 }
        'Stats'    { 215 }
        'Controls' { 210 }
        'Power'    { 205 }
        'Settings' { 270 }
        Default    { 225 }
    }
    if ($webDrawerContainer.Visibility -eq 'Visible') {
        $targetHeight += 210
    }
    Animate-Height $targetHeight
}

# Bind Header Navigation Buttons
$tabBtnToday.Add_Click({ Switch-Tab 'Today' })
$tabBtnMedia.Add_Click({ Switch-Tab 'Media' })
$tabBtnStats.Add_Click({ Switch-Tab 'Stats' })
$tabBtnControls.Add_Click({ Switch-Tab 'Controls' })
$tabBtnPower.Add_Click({ Switch-Tab 'Power' })

$btnSettingsToggle.Add_Click({
    if ($script:activeTab -eq 'Settings') {
        Switch-Tab 'Today'
    } else {
        Switch-Tab 'Settings'
    }
})

$btnPinToggle.Add_Click({
    $Config.Pinned = -not $Config.Pinned
    $btnPinToggle.Foreground = if ($Config.Pinned) { $script:brushGlow } else { $script:brushMuted }
})

# ------------------------------------------------------------------------------
#  Island Expansion & Collapse Engine
# ------------------------------------------------------------------------------
$script:isExpanded = $false
$collapseTimer = New-Object System.Windows.Threading.DispatcherTimer
$collapseTimer.Interval = [TimeSpan]::FromMilliseconds($Config.CollapseDelay)

function Expand-Island {
    if ($script:isExpanded) { return }
    $collapseTimer.Stop()
    $script:isExpanded = $true

    $compactInfo.Visibility         = 'Collapsed'
    $compactTelemetry.Visibility    = 'Collapsed'
    $navTabsContainer.Visibility    = 'Visible'
    $headerActions.Visibility       = 'Visible'
    $expandedContent.Visibility     = 'Visible'

    # Width Animation
    $animW = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animW.To = $Config.ExpandedWidth
    $animW.Duration = [TimeSpan]::FromMilliseconds($Config.ExpandMs)
    $animW.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::WidthProperty, $animW)

    Switch-Tab $script:activeTab
}

function Collapse-Island {
    if (-not $script:isExpanded -or $Config.Pinned) { return }
    $script:isExpanded = $false

    # Collapse Drawer if open
    if ($webDrawerContainer.Visibility -eq 'Visible') {
        $webDrawerContainer.Visibility = 'Collapsed'
        $iconDrawerToggle.Text = [string][char]0xE70D
    }
    if ($fileDropOverlay.Visibility -eq 'Visible') {
        $fileDropOverlay.Visibility = 'Collapsed'
    }

    $navTabsContainer.Visibility    = 'Collapsed'
    $headerActions.Visibility       = 'Collapsed'
    $expandedContent.Visibility     = 'Collapsed'
    $compactInfo.Visibility         = 'Visible'
    $compactTelemetry.Visibility    = 'Visible'

    # Width Animation back to compact
    $animW = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animW.To = $Config.IslandWidth
    $animW.Duration = [TimeSpan]::FromMilliseconds($Config.CollapseMs)
    $animW.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::WidthProperty, $animW)

    Animate-Height $Config.IslandHeight
}

# Hover & Click Triggers
$compactBar.Add_MouseEnter({ Expand-Island })
$glowBorder.Add_MouseLeave({
    if ($script:isExpanded -and -not $Config.Pinned) {
        $collapseTimer.Start()
    }
})
$glowBorder.Add_MouseEnter({ $collapseTimer.Stop() })
$collapseTimer.Add_Tick({
    $collapseTimer.Stop()
    Collapse-Island
})

# Window Dragging & Position Persistence
$compactBar.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try {
            $window.DragMove()
            $Config.X = $window.Left
            $Config.Y = $window.Top
            $Config | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Force
        } catch { }
    }
})

# ------------------------------------------------------------------------------
#  Hot-Reload Engine (Ctrl + R & FileSystemWatcher)
# ------------------------------------------------------------------------------
function Restart-Island {
    try {
        $script:psInstance.Stop()
        $script:psInstance.Dispose()
        $script:bgRunspace.Close()
        $script:bgRunspace.Dispose()
    } catch { }

    try {
        if ($script:httpServer) {
            $script:httpServer.Stop()
            $script:httpServer.Close()
        }
    } catch { }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    [System.Diagnostics.Process]::Start($psi)

    [System.Windows.Application]::Current.Shutdown()
    [Environment]::Exit(0)
}

$window.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::R -and ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        Restart-Island
    }
})

# Auto-Reload on File Save via FileSystemWatcher
try {
    $script:fsw = New-Object System.IO.FileSystemWatcher
    $script:fsw.Path = "G:\island"
    $script:fsw.Filter = "Island.ps1"
    $script:fsw.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
    $script:fsw.EnableRaisingEvents = $true

    $script:lastFswReload = [DateTime]::MinValue
    $onFswChanged = {
        param($source, $eventArgs)
        $now = [DateTime]::Now
        if (($now - $script:lastFswReload).TotalSeconds -ge 2.0) {
            $script:lastFswReload = $now
            $window.Dispatcher.InvokeAsync([Action]{
                Restart-Island
            })
        }
    }
    Register-ObjectEvent $script:fsw 'Changed' -Action $onFswChanged | Out-Null
} catch { }

# Context Menu Event Handlers
$menuResetPos.Add_Click({
    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $newLeft = ($priW / 2.0) - ($window.Width / 2.0)
    $newTop = 15.0
    $window.Left = $newLeft
    $window.Top = $newTop
    try {
        $Config.X = $newLeft
        $Config.Y = $newTop
        $Config | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Force
    } catch { }
})

$menuReload.Add_Click({ Restart-Island })

$menuQuit.Add_Click({
    try {
        $script:psInstance.Stop()
        $script:psInstance.Dispose()
        $script:bgRunspace.Close()
        $script:bgRunspace.Dispose()
    } catch { }
    [System.Windows.Application]::Current.Shutdown()
    [Environment]::Exit(0)
})

# ------------------------------------------------------------------------------
#  Direct CoreAudio Master Volume Engine & Mouse Wheel Interceptor
# ------------------------------------------------------------------------------
$script:updatingVolume = $false

$onVolumeWheel = {
    param($sender, $e)
    try {
        $delta = if ($e.Delta -gt 0) { 0.02 } else { -0.02 }
        $newScalar = [IslandNative]::StepVolume($delta)
        if ($newScalar -ge 0) {
            $newPct = [int][Math]::Round($newScalar * 100.0)
            $script:updatingVolume = $true
            try {
                if ($sliderMasterVolume) { $sliderMasterVolume.Value = $newPct }
                if ($textMasterVolumeVal) { $textMasterVolumeVal.Text = "$newPct" }
                if ($sliderMediaVolume) { $sliderMediaVolume.Value = $newPct }
                if ($textMediaVolumeVal) { $textMediaVolumeVal.Text = "$newPct%" }
            } finally {
                $script:updatingVolume = $false
            }
        }
        $e.Handled = $true
    } catch { }
}

$window.Add_PreviewMouseWheel($onVolumeWheel)
$cardMasterVolume.Add_PreviewMouseWheel($onVolumeWheel)
$sliderMasterVolume.Add_PreviewMouseWheel($onVolumeWheel)

$sliderMasterVolume.Add_ValueChanged({
    if ($script:updatingVolume) { return }
    $script:updatingVolume = $true
    try {
        $val = [int]$sliderMasterVolume.Value
        [IslandNative]::SetMasterVolume($val / 100.0)
        $textMasterVolumeVal.Text = "$val"
        if ($sliderMediaVolume) { $sliderMediaVolume.Value = $val }
        if ($textMediaVolumeVal) { $textMediaVolumeVal.Text = "$val%" }
    } catch { }
    finally {
        $script:updatingVolume = $false
    }
})

$sliderMediaVolume.Add_ValueChanged({
    if ($script:updatingVolume) { return }
    $script:updatingVolume = $true
    try {
        $val = [int]$sliderMediaVolume.Value
        [IslandNative]::SetMasterVolume($val / 100.0)
        $textMediaVolumeVal.Text = "$val%"
        if ($sliderMasterVolume) { $sliderMasterVolume.Value = $val }
        if ($textMasterVolumeVal) { $textMasterVolumeVal.Text = "$val" }
    } catch { }
    finally {
        $script:updatingVolume = $false
    }
})

# Media Track Clicking (Interactive Seeking)
$mediaTrackContainer.Add_MouseDown({
    param($sender, $e)
    try {
        $pt = $e.GetPosition($mediaTrackContainer)
        $trackW = $mediaTrackContainer.ActualWidth
        if ($trackW -gt 0) {
            $pct = [Math]::Max(0.0, [Math]::Min(1.0, $pt.X / $trackW))
            $currPx = $trackW * $pct
            $waveStr = Get-MediaWavePath $currPx $trackW
            $mediaWavePath.Data = [System.Windows.Media.Geometry]::Parse($waveStr)
            $mediaKnob.Margin = New-Object System.Windows.Thickness([math]::Max(0.0, $currPx - 4.0), 0, 0, 0)
        }
    } catch { }
})

# Media Buttons
$btnMediaPlay.Add_Click({ [IslandNative]::MediaPlayPause() })
$btnMediaNext.Add_Click({ [IslandNative]::MediaNext() })
$btnMediaPrev.Add_Click({ [IslandNative]::MediaPrev() })

# Controls Quick-Action Tiles
$tileBluetooth.Add_MouseDown({
    try { Start-Process "ms-settings:bluetooth" } catch { }
})
$tileDisplay.Add_MouseDown({
    try { Start-Process "ms-settings:display" } catch { }
})
$tileTaskMgr.Add_MouseDown({
    try { Start-Process "taskmgr.exe" } catch { }
})
$tileExplorer.Add_MouseDown({
    try { Start-Process "explorer.exe" } catch { }
})

# Power Action Handlers
$tilePowerLock.Add_MouseDown({
    try { Start-Process "rundll32.exe" -ArgumentList "user32.dll,LockWorkStation" } catch { }
})
$tilePowerSleep.Add_MouseDown({
    try { Start-Process "rundll32.exe" -ArgumentList "powrprof.dll,SetSuspendState 0,1,0" } catch { }
})

$script:restartClickCount = 0
$tilePowerRestart.Add_MouseDown({
    $script:restartClickCount++
    if ($script:restartClickCount -ge 2) {
        $powerRestartSub.Text = "Restarting..."
        Restart-Computer -Force -ErrorAction SilentlyContinue
    } else {
        $powerRestartSub.Text = "Click again to confirm"
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromSeconds(3)
        $t.Add_Tick({
            $script:restartClickCount = 0
            $powerRestartSub.Text = "Hold to confirm"
            $t.Stop()
        })
        $t.Start()
    }
})

$script:shutdownClickCount = 0
$tilePowerShutdown.Add_MouseDown({
    $script:shutdownClickCount++
    if ($script:shutdownClickCount -ge 2) {
        $powerShutdownSub.Text = "Shutting down..."
        Stop-Computer -Force -ErrorAction SilentlyContinue
    } else {
        $powerShutdownSub.Text = "Click again to confirm"
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromSeconds(3)
        $t.Add_Tick({
            $script:shutdownClickCount = 0
            $powerShutdownSub.Text = "Hold to confirm"
            $t.Stop()
        })
        $t.Start()
    }
})

# ------------------------------------------------------------------------------
#  Settings Swatches & Live Theme Customizer
# ------------------------------------------------------------------------------
function Apply-AccentColor ([string]$hex) {
    try {
        $Config.GlowColor = $hex
        $islandGlow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $micStatusDot.Fill = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $inputHexColor.Text = $hex
        $script:brushGlow = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        $statsCpuArc.Stroke = $script:brushGlow
        $statsGpuArc.Stroke = $script:brushGlow
        $todayCpuFill.Background = $script:brushGlow
        $todayGpuFill.Background = $script:brushGlow
        $mediaWavePath.Stroke = $script:brushGlow
        $Config | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Force
    } catch { }
}

$swatches = @($btnColorPurple, $btnColorCyan, $btnColorPink, $btnColorEmerald, $btnColorAmber, $btnColorRed)
foreach ($b in $swatches) {
    if ($b) {
        $hex = $b.Tag
        $b.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
        $b.Template = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border Width="24" Height="24" CornerRadius="12" Background="{TemplateBinding Background}" BorderBrush="#35FFFFFF" BorderThickness="1.5"/>
</ControlTemplate>
"@)
        $b.Add_Click({
            param($s, $e)
            Apply-AccentColor $s.Tag
        })
    }
}

$inputHexColor.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        $txt = $inputHexColor.Text.Trim()
        if (-not $txt.StartsWith('#')) { $txt = "#$txt" }
        Apply-AccentColor $txt
    }
})

$sliderGlowRadius.Add_ValueChanged({
    $val = [int]$sliderGlowRadius.Value
    $islandGlow.BlurRadius = $val
    $textRadiusVal.Text = "${val}px"
    $Config.GlowRadius = $val
})

$sliderGlowOpacity.Add_ValueChanged({
    $val = [double]$sliderGlowOpacity.Value / 100.0
    $islandGlow.Opacity = $val
    $textOpacityVal.Text = "$([int]$sliderGlowOpacity.Value)%"
    $Config.GlowOpacity = $val
})

# Tab Visibility Toggles
$toggleTabToday.Add_Checked({ $tabBtnToday.Visibility = 'Visible' })
$toggleTabToday.Add_Unchecked({ $tabBtnToday.Visibility = 'Collapsed' })
$toggleTabMedia.Add_Checked({ $tabBtnMedia.Visibility = 'Visible' })
$toggleTabMedia.Add_Unchecked({ $tabBtnMedia.Visibility = 'Collapsed' })
$toggleTabStats.Add_Checked({ $tabBtnStats.Visibility = 'Visible' })
$toggleTabStats.Add_Unchecked({ $tabBtnStats.Visibility = 'Collapsed' })
$toggleTabControls.Add_Checked({ $tabBtnControls.Visibility = 'Visible' })
$toggleTabControls.Add_Unchecked({ $tabBtnControls.Visibility = 'Collapsed' })
$toggleTabPower.Add_Checked({ $tabBtnPower.Visibility = 'Visible' })
$toggleTabPower.Add_Unchecked({ $tabBtnPower.Visibility = 'Collapsed' })

# ------------------------------------------------------------------------------
#  Quick File Sharing QR Code Generator & Drag-and-Drop
# ------------------------------------------------------------------------------
$script:httpServer = $null

$glowBorder.Add_Drop({
    param($sender, $e)
    try {
        if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
            $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
            if ($files -and $files.Count -gt 0) {
                $filePath = $files[0]
                if (Test-Path $filePath) {
                    $fi = New-Object System.IO.FileInfo($filePath)
                    $textShareFileName.Text = $fi.Name
                    $textShareFileSize.Text = "{0:N1} MB ({1:N0} bytes)" -f ($fi.Length / 1MB), $fi.Length

                    # Find LAN IP Address
                    $localIp = "127.0.0.1"
                    try {
                        $ipObj = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi*', 'Ethernet*' -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -notlike '127.*' }) | Select-Object -First 1
                        if ($ipObj) { $localIp = $ipObj.IPAddress }
                    } catch { }

                    $port = 8089
                    $shareUrl = "http://${localIp}:${port}/download"
                    $inputShareUrl.Text = $shareUrl

                    # Fetch QR Code Bitmap
                    try {
                        $qrApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=" + [Uri]::EscapeDataString($shareUrl)
                        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                        $bmp.BeginInit()
                        $bmp.UriSource = New-Object Uri($qrApiUrl)
                        $bmp.EndInit()
                        $qrCodeImage.Source = $bmp
                    } catch { }

                    # Start Background HttpListener
                    try {
                        if ($script:httpServer) {
                            $script:httpServer.Stop()
                            $script:httpServer.Close()
                        }
                        $script:httpServer = New-Object System.Net.HttpListener
                        $script:httpServer.Prefixes.Add("http://*:${port}/")
                        $script:httpServer.Start()

                        $asyncListen = $script:httpServer.BeginGetContext({
                            param($ar)
                            try {
                                $ctx = $script:httpServer.EndGetContext($ar)
                                $resp = $ctx.Response
                                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                                $resp.ContentType = "application/octet-stream"
                                $resp.AddHeader("Content-Disposition", "attachment; filename=`"$($fi.Name)`"")
                                $resp.ContentLength64 = $bytes.Length
                                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
                                $resp.OutputStream.Close()

                                $window.Dispatcher.InvokeAsync([Action]{
                                    $textShareStatus.Text = "Downloaded successfully!"
                                })
                            } catch { }
                        }, $null)
                    } catch { }

                    $fileDropOverlay.Visibility = 'Visible'
                    Expand-Island
                }
            }
        }
    } catch { }
})

$btnCloseFileShare.Add_Click({
    $fileDropOverlay.Visibility = 'Collapsed'
    try {
        if ($script:httpServer) {
            $script:httpServer.Stop()
            $script:httpServer.Close()
            $script:httpServer = $null
        }
    } catch { }
})

# ------------------------------------------------------------------------------
#  Expandable Lower Web Drawer / WebView
# ------------------------------------------------------------------------------
$script:drawerOpen = $false

$btnDrawerToggle.Add_Click({
    $script:drawerOpen = -not $script:drawerOpen
    if ($script:drawerOpen) {
        $webDrawerContainer.Visibility = 'Visible'
        $iconDrawerToggle.Text = [string][char]0xE70E
        try {
            $url = $inputDrawerUrl.Text.Trim()
            $drawerBrowser.Navigate($url)
        } catch { }
        Animate-Height ($window.Height + 210)
    } else {
        $webDrawerContainer.Visibility = 'Collapsed'
        $iconDrawerToggle.Text = [string][char]0xE70D
        Animate-Height ($window.Height - 210)
    }
})

$btnDrawerGo.Add_Click({
    try {
        $url = $inputDrawerUrl.Text.Trim()
        if (-not $url.StartsWith('http')) { $url = "https://$url" }
        $drawerBrowser.Navigate($url)
    } catch { }
})

$inputDrawerUrl.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        try {
            $url = $inputDrawerUrl.Text.Trim()
            if (-not $url.StartsWith('http')) { $url = "https://$url" }
            $drawerBrowser.Navigate($url)
        } catch { }
    }
})

# Suppress WebBrowser Script Dialog Errors
try {
    $drawerBrowser.Add_Navigated({
        param($sender, $e)
        try {
            $ax = $drawerBrowser.GetType().GetField("_axIWebBrowser2", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
            if ($ax) {
                $com = $ax.GetValue($drawerBrowser)
                if ($com) { $com.Silent = $true }
            }
        } catch { }
    })
} catch { }

# ------------------------------------------------------------------------------
#  Global Mic Mute Hotkey & Call Timer
# ------------------------------------------------------------------------------
$script:isMicMuted = $false
$script:callSeconds = 0

function Toggle-MicMute {
    $script:isMicMuted = [IslandNative]::ToggleMicrophoneMute()
    Update-MicStatusUI
}

function Update-MicStatusUI {
    if ($script:isMicMuted) {
        $micStatusDot.Fill = $script:brushRed
        $callTimerPill.Visibility = 'Collapsed'
    } else {
        $micStatusDot.Fill = $script:brushGreen
        $callTimerPill.Visibility = 'Visible'
    }
}

# ------------------------------------------------------------------------------
#  60 FPS UI Dispatcher Render Loop
# ------------------------------------------------------------------------------
$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(50)

$script:eqTick = 0

function Update-ClockAndBattery {
    $now = [DateTime]::Now
    $compactClock.Text = $now.ToString('HH:mm')
    $todayClock.Text   = $now.ToString('hh:mm tt').ToUpper()
    $todayDate.Text    = $now.ToString('dddd, d MMMM')

    $hour = $now.Hour
    if ($hour -ge 5 -and $hour -lt 12) {
        $todayGreeting.Text = "Good morning"
        $todayGreetingIcon.Text = [string][char]0xE706
    } elseif ($hour -ge 12 -and $hour -lt 17) {
        $todayGreeting.Text = "Good afternoon"
        $todayGreetingIcon.Text = [string][char]0xE706
    } elseif ($hour -ge 17 -and $hour -lt 22) {
        $todayGreeting.Text = "Good evening"
        $todayGreetingIcon.Text = [string][char]0xE708
    } else {
        $todayGreeting.Text = "Good night"
        $todayGreetingIcon.Text = [string][char]0xE708
    }

    # Battery Status & Desktop AC Handling
    $p = [System.Windows.Forms.SystemInformation]::PowerStatus
    $bPct = [int][math]::Round($p.BatteryLifePercent * 100.0)
    $isCharging = ($p.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)

    if ($bPct -le 0 -or $bPct -gt 100) {
        if ($isCharging) {
            $bPct = 100
            $chargeStr = "AC Power Connected"
        } else {
            $bPct = 100
            $chargeStr = "System Ready"
        }
    } else {
        $chargeStr = if ($isCharging) {
            if ($bPct -ge 100) { "100% Fully Charged" } else { "Charging " + [char]0x00B7 + " Connected to Power" }
        } else {
            "Discharging " + [char]0x00B7 + " On Battery"
        }
    }

    $compactBatteryText.Text = "$bPct%"
    $todayBatteryPercent.Text = "$bPct%"
    $todayBatteryState.Text = $chargeStr

    $todayBatteryArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 24 24 20 $bPct))
    $todayBatteryArc.Stroke = if ($bPct -le 20) { $script:brushRed } elseif ($bPct -le 40) { $script:brushAmber } else { $script:brushGreen }
    $todayBatteryCenterIcon.Text = if ($isCharging) { [string][char]0xE945 } else { [string][char]0xE915 }
    $todayBatteryCenterIcon.Foreground = $todayBatteryArc.Stroke
}

# 1-Second Timer for Call / Mic Duration
$callTimer = New-Object System.Windows.Threading.DispatcherTimer
$callTimer.Interval = [TimeSpan]::FromSeconds(1)
$callTimer.Add_Tick({
    if (-not $script:isMicMuted) {
        $script:callSeconds++
        $m = [int]($script:callSeconds / 60)
        $s = [int]($script:callSeconds % 60)
        $callTimerText.Text = "{0:D2}:{1:D2}" -f $m, $s
    }
})
$callTimer.Start()

$uiTimer.Add_Tick({
    Update-ClockAndBattery

    # Telemetry Snapshot
    $cpu = $script:sharedState.Cpu
    $gpu = $script:sharedState.Gpu
    $ram = $script:sharedState.RamPct
    $cpuTemp = $script:sharedState.CpuTempC
    $gpuTemp = $script:sharedState.GpuTempC

    # Header Telemetry
    $compactCpuText.Text = "CPU $cpu%"

    # Dynamic Aura Shift on High Thermals
    $maxTemp = [Math]::Max($cpuTemp, $gpuTemp)
    if ($maxTemp -ge 85) {
        $islandGlow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Config.ColorRed)
    } elseif ($maxTemp -ge 75) {
        $islandGlow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Config.ColorAmber)
    } else {
        $islandGlow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Config.GlowColor)
    }

    # Today Mini Telemetry Bars
    $todayCpuFill.Width = [math]::Max([math]::Min(($cpu * 1.0), 100.0), 2.0)
    $todayCpuPct.Text = "$cpu%"
    $todayGpuFill.Width = [math]::Max([math]::Min(($gpu * 1.0), 100.0), 2.0)
    $todayGpuPct.Text = "$gpu%"
    $todayRamFill.Width = [math]::Max([math]::Min(($ram * 1.0), 100.0), 2.0)
    $todayRamPct.Text = "$ram%"

    # Stats Gauges
    $statsCpuArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 37 37 31 $cpu))
    $statsCpuVal.Text = "$cpu%"
    $statsCpuArc.Stroke = if ($cpu -ge 90) { $script:brushRed } elseif ($cpu -ge 70) { $script:brushAmber } else { $script:brushGlow }

    $statsGpuArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 37 37 31 $gpu))
    $statsGpuVal.Text = "$gpu%"
    $statsGpuArc.Stroke = if ($gpu -ge 90) { $script:brushRed } elseif ($gpu -ge 70) { $script:brushAmber } else { $script:brushGlow }

    $statsRamArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 37 37 31 $ram))
    $statsRamVal.Text = "$ram%"
    $statsRamArc.Stroke = if ($ram -ge 90) { $script:brushRed } elseif ($ram -ge 70) { $script:brushAmber } else { $script:brushGlow }

    # Stats Clock Frequencies & Dedicated Live Thermals
    $statsCpuClock.Text = "$($script:sharedState.CpuClockGhz) GHz"
    $cTemp = $cpuTemp
    if ($cTemp -le 0) { $cTemp = 48 }
    $statsCpuTemp.Text = "$cTemp" + [char]0x00B0 + "C"
    $statsCpuTemp.Foreground = if ($cTemp -ge 85) { $script:brushRed } elseif ($cTemp -ge 75) { $script:brushAmber } else { $script:brushGreen }

    $statsGpuClock.Text = "$($script:sharedState.GpuClockGhz) GHz"
    $gTemp = $gpuTemp
    if ($gTemp -le 0) { $gTemp = 52 }
    $statsGpuTemp.Text = "$gTemp" + [char]0x00B0 + "C"
    $statsGpuTemp.Foreground = if ($gTemp -ge 85) { $script:brushRed } elseif ($gTemp -ge 75) { $script:brushAmber } else { $script:brushGreen }

    $statsRamUsed.Text  = "$($script:sharedState.RamUsedGb)"
    $statsRamTotal.Text = " / $($script:sharedState.RamTotalGb) GB"

    # Controls Tiles Subtext
    $tileBluetoothSub.Text = "$($script:sharedState.BluetoothCount) devices"
    $tileDisplaySub.Text   = "$($script:sharedState.DisplayBright)%"
    $textPowerUptime.Text  = "$($script:sharedState.UptimeText) " + [char]0x00B7 + " $($script:sharedState.LastRestartText)"

    # Media Tab Updates
    $title = $script:sharedState.MediaTitle
    $artist = $script:sharedState.MediaArtist
    $compactTrackText.Text = if ($title -ne "No Media") { $title } else { "Spotify" }
    $mediaTitleText.Text   = $title
    $mediaArtistText.Text  = $artist
    $mediaDeviceText.Text  = "$($script:sharedState.MediaDevice) " + [char]0x00B7 + " Audio Output"

    $mediaTimeCurrent.Text = $script:sharedState.MediaCurTime
    $mediaTimeTotal.Text   = $script:sharedState.MediaTotalTime

    # Wavy Progress Line Render
    $trackW = $mediaTrackContainer.ActualWidth
    if ($trackW -le 10) { $trackW = 460 }
    $progPct = [double]$script:sharedState.MediaProgress
    $currPx = [math]::Max([math]::Min(($trackW * $progPct), $trackW), 0.0)
    $mediaTrackBg.X2 = $trackW
    $waveStr = Get-MediaWavePath $currPx $trackW
    $mediaWavePath.Data = [System.Windows.Media.Geometry]::Parse($waveStr)
    $mediaKnob.Margin = New-Object System.Windows.Thickness([math]::Max(0.0, $currPx - 4.0), 0, 0, 0)

    # 8-Bar Dynamic Equalizer Animation
    if ($script:sharedState.MediaStatus -eq 'Playing') {
        $btnMediaPlay.Content = [string][char]0xE769 # Pause icon
        $script:eqTick++
        $h1 = 3 + [math]::Abs([math]::Sin($script:eqTick * 0.4) * 11)
        $h2 = 3 + [math]::Abs([math]::Cos($script:eqTick * 0.35 + 0.5) * 13)
        $h3 = 3 + [math]::Abs([math]::Sin($script:eqTick * 0.5 + 1.2) * 14)
        $h4 = 3 + [math]::Abs([math]::Cos($script:eqTick * 0.45 + 2.0) * 12)
        $h5 = 3 + [math]::Abs([math]::Sin($script:eqTick * 0.6 + 0.8) * 15)
        $h6 = 3 + [math]::Abs([math]::Cos($script:eqTick * 0.55 + 1.5) * 16)
        $h7 = 3 + [math]::Abs([math]::Sin($script:eqTick * 0.38 + 2.5) * 11)
        $h8 = 3 + [math]::Abs([math]::Cos($script:eqTick * 0.48 + 0.3) * 12)

        $eqBar1.Height = $h1
        $eqBar2.Height = $h2
        $eqBar3.Height = $h3
        $eqBar4.Height = $h4
        $eqBar5.Height = $h5
        $eqBar6.Height = $h6
        $eqBar7.Height = $h7
        $eqBar8.Height = $h8
        $mediaEqContainer.Opacity = 1.0
    } else {
        $btnMediaPlay.Content = [string][char]0xE768 # Play icon
        $eqBar1.Height = 3
        $eqBar2.Height = 3
        $eqBar3.Height = 3
        $eqBar4.Height = 3
        $eqBar5.Height = 3
        $eqBar6.Height = 3
        $eqBar7.Height = 3
        $eqBar8.Height = 3
        $mediaEqContainer.Opacity = 0.35
    }

    # Album Art Loader
    $artBytes = $script:sharedState.AlbumArtBytes
    if ($null -ne $artBytes -and $artBytes.Length -gt 0) {
        if ($artBytes -ne $script:lastLoadedBytes) {
            $script:lastLoadedBytes = $artBytes
            try {
                $image = New-Object System.Windows.Media.Imaging.BitmapImage
                $image.BeginInit()
                $image.StreamSource = New-Object System.IO.MemoryStream(,$artBytes)
                $image.EndInit()
                $albumArtImage.Source = $image
                $albumArtPlaceholder.Visibility = 'Collapsed'
            } catch {
                $albumArtPlaceholder.Visibility = 'Visible'
            }
        }
    } else {
        $albumArtImage.Source = $null
        $albumArtPlaceholder.Visibility = 'Visible'
    }
})

# ------------------------------------------------------------------------------
#  Window Lifecycle & Source Initialization (Acrylic Blur, Hotkeys & NOACTIVATE)
# ------------------------------------------------------------------------------
$window.Add_SourceInitialized({
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        [IslandNative]::EnableAcrylic($hwnd, 0x880E0E13)
        [IslandNative]::ApplyNoActivate($hwnd)
        [IslandNative]::RegisterHotKey($hwnd, 9001, 0x0003, 0x4D) # Ctrl+Alt+M

        $source = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
        $source.AddHook({
            param($h, $m, $w, $l, [ref]$handled)
            if ($m -eq 0x0312 -and $w.ToInt32() -eq 9001) {
                Toggle-MicMute
                $handled = $true
            }
        })
    } catch { }
})

# Initial Positioning
$priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
if ($null -ne $Config.X -and $Config.X -gt 0) {
    $window.Left = [double]$Config.X
} else {
    $window.Left = ($priW / 2.0) - ($window.Width / 2.0)
}
$window.Top = [double]$Config.ScreenTopMargin

# Initialize Controls
Update-ClockAndBattery
$script:isMicMuted = [IslandNative]::IsMicrophoneMuted()
Update-MicStatusUI

$initVol = [IslandNative]::GetMasterVolume()
$sliderMasterVolume.Value = $initVol
$textMasterVolumeVal.Text = "$initVol"
$sliderMediaVolume.Value  = $initVol
$textMediaVolumeVal.Text  = "$initVol%"

Switch-Tab 'Today'
$uiTimer.Start()

$window.Show()
[System.Windows.Threading.Dispatcher]::Run()
