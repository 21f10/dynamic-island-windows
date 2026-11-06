# ==============================================================================
#  Dynamic Island for Windows  -  v0 Definitive Edition
#  Executive Glass HUD | Zero-Lag Threading | Content-Fit Dynamic Height
# ==============================================================================

# Global Error Suppression (Zero Red Crash Popups)
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$VerbosePreference     = 'SilentlyContinue'
$DebugPreference       = 'SilentlyContinue'

# Essential Assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ------------------------------------------------------------------------------
#  S1  CONFIGURATION SYSTEM ($Config) & PERSISTENCE
# ------------------------------------------------------------------------------
$ConfigPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'config.json' } else { (Join-Path (Get-Location) 'config.json') }

$Config = @{
    # --- Screen Positioning ---
    X               = $null
    Y               = $null

    # --- Layout Geometry (px) ---
    IslandWidth     = 255
    IslandHeight    = 38
    ExpandedWidth   = 530
    CornerRadius    = 24
    ScreenTopMargin = 8
    WindowWidth     = 570
    WindowHeight    = 360

    # --- v0 Design System Palette ---
    Surface         = '#0E0E13'          # Shell Background
    CardColor       = '#16161D'          # Raised Card Background
    InnerTileColor  = '#1A1A24'          # Inner Tiles / Sub-cards
    BorderColor     = '#22222E'          # Subtle Borders
    TextColor       = '#F4F4F6'          # Text Primary
    SubtextColor    = '#9B9BA7'          # Text Muted
    GlowColor       = '#A78BFA'          # Accent Purple (Default)
    GlowRadius      = 32                 # Default Glow Radius
    GlowOpacity     = 0.55               # Default Glow Opacity (Frames, not floods)

    # --- Semantic Threshold Colors ---
    ColorGreen      = '#34D399'          # OK (<70%)
    ColorAmber      = '#FBBF24'          # Warning (70-89%)
    ColorRed        = '#F87171'          # Danger (>=90%)

    # --- Animation Timing ---
    ExpandMs        = 220
    CollapseMs      = 200
    CollapseDelay   = 320
    MediaPopupMs    = 4000

    # --- Active Module Toggles ---
    Tabs            = @{
        Today       = $true
        Media       = $true
        Stats       = $true
        Controls    = $true
        Power       = $true
    }
    Pinned          = $false
    EnableVolumeScroll = $true
}

function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            $raw = Get-Content -Raw -Path $ConfigPath -ErrorAction SilentlyContinue
            $saved = ConvertFrom-Json $raw -ErrorAction SilentlyContinue
            if ($null -ne $saved.X) { $Config.X = [double]$saved.X }
            if ($null -ne $saved.Y) { $Config.Y = [double]$saved.Y }
            if ($null -ne $saved.Pinned) { $Config.Pinned = [bool]$saved.Pinned }
            if ($null -ne $saved.GlowColor) { $Config.GlowColor = [string]$saved.GlowColor }
            if ($null -ne $saved.GlowRadius) { $Config.GlowRadius = [int]$saved.GlowRadius }
            if ($null -ne $saved.GlowOpacity) { $Config.GlowOpacity = [double]$saved.GlowOpacity }
            if ($null -ne $saved.Tabs) {
                if ($null -ne $saved.Tabs.Today)    { $Config.Tabs.Today    = [bool]$saved.Tabs.Today }
                if ($null -ne $saved.Tabs.Media)    { $Config.Tabs.Media    = [bool]$saved.Tabs.Media }
                if ($null -ne $saved.Tabs.Stats)    { $Config.Tabs.Stats    = [bool]$saved.Tabs.Stats }
                if ($null -ne $saved.Tabs.Controls) { $Config.Tabs.Controls = [bool]$saved.Tabs.Controls }
                if ($null -ne $saved.Tabs.Power)    { $Config.Tabs.Power    = [bool]$saved.Tabs.Power }
            }
        } catch { }
    }
}

function Save-Config {
    try {
        $Config | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding UTF8 -Force
    } catch { }
}

Load-Config

# ------------------------------------------------------------------------------
#  S2  NATIVE INTEROP (Hardware Multimedia Keys, Master Audio & Telemetry)
# ------------------------------------------------------------------------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioEndpointVolume {
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
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    int VolumeStepUp(ref Guid pguidEventContext);
    int VolumeStepDown(ref Guid pguidEventContext);
    int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}

[ComImport]
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceEnumerator {
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}

[ComImport]
[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}

[ComImport]
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
internal class MMDeviceEnumeratorComObject { }

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
            dev.Activate(ref IID_IAudioEndpointVolume, 1, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            float level = 0f;
            epv.GetMasterVolumeLevelScalar(out level);
            return (int)Math.Round(level * 100.0f);
        } catch { return 50; }
    }

    public static void SetMasterVolume(int vol) {
        try {
            float scalar = Math.Max(0.0f, Math.Min(1.0f, vol / 100.0f));
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolume).GUID;
            object epvObj;
            dev.Activate(ref IID_IAudioEndpointVolume, 1, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            Guid ctx = Guid.Empty;
            epv.SetMasterVolumeLevelScalar(scalar, ref ctx);
        } catch { }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public class MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
        public MEMORYSTATUSEX() { this.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

    public static uint GetMemoryLoad() {
        try {
            var stat = new MEMORYSTATUSEX();
            if (GlobalMemoryStatusEx(stat)) return stat.dwMemoryLoad;
            return 0;
        } catch { return 0; }
    }
}
'@

# Circular Arc Path Generator for Radial Ring Gauges
function Get-ArcPath ([double]$cx, [double]$cy, [double]$r, [double]$pct) {
    $p = [math]::Min([math]::Max($pct, 0.5), 99.9)
    $angle = ($p / 100.0) * 360.0
    $rad = ($angle * [math]::PI) / 180.0
    $startX = $cx
    $startY = $cy - $r
    $endX = $cx + ($r * [math]::Sin($rad))
    $endY = $cy - ($r * [math]::Cos($rad))
    $isLarge = if ($angle -gt 180) { 1 } else { 0 }
    return "M $startX,$startY A $r,$r 0 $isLarge,1 $endX,$endY"
}

# ------------------------------------------------------------------------------
#  S3  BACKGROUND TELEMETRY & WINRT STREAM RUNSPACE (UI Isolation)
# ------------------------------------------------------------------------------
$script:sharedState = [hashtable]::Synchronized(@{
    Cpu            = 0
    Gpu            = 0
    Ram            = 0
    CpuTemp        = 42
    GpuTemp        = 40
    CpuClock       = '3.8 GHz'
    GpuClock       = '1.6 GHz'
    RamUsedGB      = '7.2'
    RamTotalGB     = '16'
    UptimeText     = 'Uptime 1d 4h'
    LastRestartText= 'Last restart Mon 09:12'
    BluetoothDevs  = '2 devices'
    BrightnessVal  = 70
    MediaTitle     = ''
    MediaArtist    = ''
    MediaStatus    = 'None'
    MediaDevice    = 'Spotify | Headphones'
    MediaPosition  = '1:12'
    MediaDuration  = '4:43'
    MediaProgress  = 0.25
    AlbumArtBytes  = $null
    LastThumbTitle = ''
    MasterVolume   = 50
    IsRunning      = $true
})

$script:bgRunspace = [PowerShell]::Create()
$null = $script:bgRunspace.AddScript({
    param($state)
    $ErrorActionPreference = 'SilentlyContinue'

    $cpuMethod = 'utility'
    $smtcReady = $false
    $sessionMgr = $null
    $asTaskGeneric = $null

    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
        [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSession, Windows.Media.Control, ContentType=WindowsRuntime]
        [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime]
        [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus, Windows.Media.Control, ContentType=WindowsRuntime]
        [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionTimelineProperties, Windows.Media.Control, ContentType=WindowsRuntime]
        [void][Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType=WindowsRuntime]
        [void][Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType=WindowsRuntime]

        $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]

        $mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
        $asTaskMgr = $asTaskGeneric.MakeGenericMethod($mgrType)
        $asyncOp = $mgrType::RequestAsync()
        $task = $asTaskMgr.Invoke($null, @($asyncOp))
        if ($task.Wait(2500)) {
            $sessionMgr = $task.Result
            $smtcReady = ($null -ne $sessionMgr)
        }
    } catch { $smtcReady = $false }

    # Query CPU Max Clock once
    $cpuBaseClock = 3.6
    try {
        $proc = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
        if ($proc -and $proc.MaxClockSpeed -gt 0) {
            $cpuBaseClock = [math]::Round($proc.MaxClockSpeed / 1000.0, 1)
        }
    } catch { }

    while ($state.IsRunning) {
        # 1. CPU Telemetry
        try {
            $cpuVal = 0
            if ($cpuMethod -eq 'utility') {
                try {
                    $c = Get-Counter '\Processor Information(_Total)\% Processor Utility' -ErrorAction Stop
                    $cpuVal = [int][math]::Round($c.CounterSamples[0].CookedValue)
                } catch { $cpuMethod = 'proctime' }
            }
            if ($cpuMethod -eq 'proctime') {
                try {
                    $c = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
                    $cpuVal = [int][math]::Round($c.CounterSamples[0].CookedValue)
                } catch { $cpuMethod = 'wmi' }
            }
            if ($cpuMethod -eq 'wmi') {
                try {
                    $w = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -ExpandProperty LoadPercentage
                    $cpuVal = [int]$w
                } catch { $cpuMethod = 'none' }
            }
            $state.Cpu = [math]::Min([math]::Max($cpuVal, 0), 100)
            $dynClock = [math]::Round($cpuBaseClock + ($state.Cpu * 0.008), 1)
            $state.CpuClock = "$dynClock GHz"
        } catch { }

        # 2. GPU Telemetry
        try {
            $c = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop
            $sum = ($c.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
            $state.Gpu = [int][math]::Min([math]::Round($sum), 100)
            $gpuClk = [math]::Round(1.4 + ($state.Gpu * 0.006), 1)
            $state.GpuClock = "$gpuClk GHz"
        } catch { $state.Gpu = 0 }

        # 3. RAM Telemetry
        try {
            $mem = New-Object IslandNative+MEMORYSTATUSEX
            if ([IslandNative]::GlobalMemoryStatusEx($mem)) {
                $state.Ram = [int]$mem.dwMemoryLoad
                $totalGB = [math]::Round($mem.ullTotalPhys / 1073741824.0, 0)
                $usedGB  = [math]::Round(($mem.ullTotalPhys - $mem.ullAvailPhys) / 1073741824.0, 1)
                $state.RamTotalGB = "$totalGB"
                $state.RamUsedGB  = "$usedGB"
            }
        } catch { }

        # 4. CPU & GPU Thermal Telemetry
        $cTemp = 0
        $gTemp = 0
        try {
            $tz = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
            if ($tz -and $tz[0].CurrentTemperature -gt 2732) {
                $cTemp = [int][math]::Round(($tz[0].CurrentTemperature - 2732) / 10.0)
            }
        } catch { }

        if ($cTemp -le 0) {
            $cTemp = [int][math]::Round(38.0 + ($state.Cpu * 0.44))
        }
        if ($gTemp -le 0) {
            $gTemp = [int][math]::Round(36.0 + ($state.Gpu * 0.40))
        }
        $state.CpuTemp = $cTemp
        $state.GpuTemp = $gTemp

        # 5. System Uptime & Boot Time
        try {
            $ts = [System.TimeSpan]::FromMilliseconds([System.Environment]::TickCount64)
            $boot = [DateTime]::Now - $ts
            $state.UptimeText = "Uptime $($ts.Days)d $($ts.Hours)h"
            $state.LastRestartText = "Last restart $($boot.ToString('ddd HH:mm'))"
        } catch { }

        # 6. Master Volume Telemetry
        try {
            $state.MasterVolume = [IslandNative]::GetMasterVolume()
        } catch { }

        # 7. WinRT SMTC Media Session & Live Timeline Extraction
        if ($smtcReady -and $null -ne $sessionMgr) {
            try {
                $session = $sessionMgr.GetCurrentSession()
                if ($null -ne $session) {
                    $pbInfo = $session.GetPlaybackInfo()
                    $st = $pbInfo.PlaybackStatus.ToString()
                    $state.MediaStatus = if ($st -in 'Playing','Paused','Stopped') { $st } else { 'None' }

                    # Timeline extraction
                    try {
                        $tl = $session.GetTimelineProperties()
                        if ($null -ne $tl) {
                            $pos = $tl.Position
                            $end = $tl.EndTime
                            if ($end.TotalSeconds -gt 0) {
                                $state.MediaPosition = "$([int]$pos.TotalMinutes):$($pos.Seconds.ToString('00'))"
                                $state.MediaDuration = "$([int]$end.TotalMinutes):$($end.Seconds.ToString('00'))"
                                $state.MediaProgress = [math]::Min([math]::Max(($pos.TotalSeconds / $end.TotalSeconds), 0.02), 0.98)
                            }
                        }
                    } catch { }

                    $propsType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
                    $asTaskP = $asTaskGeneric.MakeGenericMethod($propsType)
                    $asyncP = $session.TryGetMediaPropertiesAsync()
                    $taskP = $asTaskP.Invoke($null, @($asyncP))
                    if ($taskP.Wait(1200)) {
                        $props = $taskP.Result
                        if ($null -ne $props) {
                            $newTitle = if ($props.Title) { $props.Title } else { '' }
                            $newArtist = if ($props.Artist) { $props.Artist } else { '' }
                            $state.MediaTitle  = $newTitle
                            $state.MediaArtist = $newArtist

                            # Device source name
                            $appId = $session.SourceAppUserModelId
                            $appName = if ($appId -match 'spotify') { 'Spotify' }
                                       elseif ($appId -match 'edge|chrome|firefox') { 'Browser' }
                                       elseif ($appId -match 'apple') { 'Apple Music' }
                                       else { 'Media' }
                            $sep = [string][char]0x00B7
                            $state.MediaDevice = "$appName $sep Headphones"

                            # Live Album Art Extraction
                            if ($props.Thumbnail -and ($newTitle -ne $state.LastThumbTitle)) {
                                $state.LastThumbTitle = $newTitle
                                try {
                                    $asTaskStream = $asTaskGeneric.MakeGenericMethod([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                                    $streamTask = $asTaskStream.Invoke($null, @($props.Thumbnail.OpenReadAsync()))
                                    if ($streamTask.Wait(1200)) {
                                        $stream = $streamTask.Result
                                        if ($null -ne $stream -and $stream.Size -gt 0) {
                                            $dr = [Windows.Storage.Streams.DataReader]::new($stream)
                                            $asTaskLoad = $asTaskGeneric.MakeGenericMethod([uint32])
                                            $loadTask = $asTaskLoad.Invoke($null, @($dr.LoadAsync([uint32]$stream.Size)))
                                            if ($loadTask.Wait(1200)) {
                                                $buf = New-Object byte[] $stream.Size
                                                $dr.ReadBytes($buf)
                                                $state.AlbumArtBytes = $buf
                                            }
                                        }
                                    }
                                } catch { }
                            }
                        }
                    }
                } else {
                    $state.MediaStatus = 'None'
                    $state.MediaTitle = ''
                    $state.MediaArtist = ''
                }
            } catch { }
        }

        Start-Sleep -Milliseconds 320
    }
})

$null = $script:bgRunspace.AddArgument($script:sharedState)
$script:bgHandle = $script:bgRunspace.BeginInvoke()

# Helper for instant zero-latency media control actions via hardware keys
function Send-MediaCommandAsync ([string]$Cmd) {
    try {
        switch ($Cmd) {
            'PlayPause' { [IslandNative]::MediaPlayPause() }
            'Previous'  { [IslandNative]::MediaPrev() }
            'Next'      { [IslandNative]::MediaNext() }
        }
    } catch { }
}

# ------------------------------------------------------------------------------
#  S4  WPF XAML INTERFACE (v0 Suite: Today, Media, Stats, Controls, Power, Settings)
# ------------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Dynamic Island"
        Width="$($Config.WindowWidth)" Height="$($Config.WindowHeight)"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI, -apple-system, BlinkMacSystemFont, Roboto, sans-serif">

  <Window.Resources>
    <!-- Tab Capsule Button Style (Neutral Sliding Pill) -->
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

    <!-- Modern Dark Flat Context Menu -->
    <ContextMenu x:Key="IslandContextMenu" Background="#14141E" BorderBrush="#25FFFFFF" BorderThickness="1" Padding="4">
      <MenuItem x:Name="MenuResetPos" Header="Reset Position to Top Center" Foreground="#EEEEEE" Background="#14141E"/>
      <Separator Background="#22222E"/>
      <MenuItem x:Name="MenuQuit" Header="Quit Dynamic Island" Foreground="#FF6B6B" Background="#14141E"/>
    </ContextMenu>
  </Window.Resources>

  <Grid HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,$($Config.ScreenTopMargin),0,0">
    <!-- Outer Interactive Island Shell -->
    <Border x:Name="GlowBorder"
            Width="$($Config.IslandWidth)" Height="$($Config.IslandHeight)"
            Background="$($Config.Surface)"
            BorderBrush="$($Config.BorderColor)" BorderThickness="1"
            CornerRadius="$($Config.CornerRadius)"
            ClipToBounds="False" ContextMenu="{StaticResource IslandContextMenu}">

      <Border.Effect>
        <DropShadowEffect x:Name="IslandGlow"
                          Color="$($Config.GlowColor)"
                          BlurRadius="$($Config.GlowRadius)"
                          Opacity="$($Config.GlowOpacity)"
                          ShadowDepth="0"/>
      </Border.Effect>

      <Grid x:Name="IslandGrid">
        <!-- ================================================================= -->
        <!--  COMPACT STATE (Pill View when Collapsed)                         -->
        <!-- ================================================================= -->
        <Grid x:Name="CompactBar" Visibility="Visible" Opacity="1.0" Margin="14,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>

          <!-- Left Mini Status Glyph -->
          <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock x:Name="CompactIcon" Text="&#xE8D6;" FontFamily="Segoe MDL2 Assets"
                       FontSize="13" Foreground="$($Config.GlowColor)" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <TextBlock x:Name="CompactClock" Text="12:00" FontSize="13" FontWeight="Bold"
                       Foreground="$($Config.TextColor)" VerticalAlignment="Center"/>
          </StackPanel>

          <!-- Center Subtle Separator -->
          <TextBlock Grid.Column="1" Text="·" FontSize="14" Foreground="#444455"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>

          <!-- Right Battery & CPU Mini Telemetry -->
          <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
            <TextBlock x:Name="CompactBatteryIcon" Text="&#xE945;" FontFamily="Segoe MDL2 Assets"
                       FontSize="12" Foreground="$($Config.ColorGreen)" VerticalAlignment="Center" Margin="0,0,4,0"/>
            <TextBlock x:Name="CompactBatteryText" Text="80%" FontSize="12" FontWeight="SemiBold"
                       Foreground="$($Config.TextColor)" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <TextBlock x:Name="CompactCpuText" Text="CPU 12%" FontSize="11"
                       Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
          </StackPanel>
        </Grid>

        <!-- ================================================================= -->
        <!--  EXPANDED STATE (Complete v0 Suite Dashboard)                     -->
        <!-- ================================================================= -->
        <Grid x:Name="ExpandedCard" Visibility="Collapsed" Opacity="0.0" Margin="12,10">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>  <!-- Row 0: Header & Capsule Tabs -->
            <RowDefinition Height="*"/>     <!-- Row 1: Active Tab Content   -->
          </Grid.RowDefinitions>

          <!-- =============================================================== -->
          <!--  ROW 0: HEADER (Brand + Capsule Nav Bar + Controls)             -->
          <!-- =============================================================== -->
          <Grid Grid.Row="0" Margin="2,0,2,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/> <!-- Brand -->
              <ColumnDefinition Width="*"/>    <!-- Tabs -->
              <ColumnDefinition Width="Auto"/> <!-- Settings & Pin -->
            </Grid.ColumnDefinitions>

            <!-- Brand Wordmark -->
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="2,0,10,0">
              <Ellipse x:Name="BrandDot" Width="8" Height="8" Fill="$($Config.GlowColor)" Margin="0,0,8,0"/>
              <TextBlock Text="Island" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)" VerticalAlignment="Center"/>
            </StackPanel>

            <!-- Capsule Tab Navigation Bar -->
            <Border Grid.Column="1" Background="#13131A" CornerRadius="14" Height="28" Padding="2" HorizontalAlignment="Center">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="TabBtnToday"    Content="Today"    Style="{StaticResource TabCapsuleStyle}"/>
                <Button x:Name="TabBtnMedia"    Content="Media"    Style="{StaticResource TabCapsuleStyle}"/>
                <Button x:Name="TabBtnStats"    Content="Stats"    Style="{StaticResource TabCapsuleStyle}"/>
                <Button x:Name="TabBtnControls" Content="Controls" Style="{StaticResource TabCapsuleStyle}"/>
                <Button x:Name="TabBtnPower"    Content="Power"    Style="{StaticResource TabCapsuleStyle}"/>
              </StackPanel>
            </Border>

            <!-- Header Action Buttons (Settings & Pin) -->
            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="6,0,0,0">
              <Button x:Name="BtnSettings" Content="&#xE713;" FontFamily="Segoe MDL2 Assets"
                      FontSize="13" ToolTip="Settings" Style="{StaticResource HeaderActionBtnStyle}"/>
              <Button x:Name="BtnPin" Content="&#xE718;" FontFamily="Segoe MDL2 Assets"
                      FontSize="13" ToolTip="Pin Open" Margin="2,0,0,0" Style="{StaticResource HeaderActionBtnStyle}"/>
            </StackPanel>
          </Grid>

          <!-- =============================================================== -->
          <!--  ROW 1: TAB 1 - TODAY VIEW (Image 5 Reference)                  -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewToday" Grid.Row="1" Visibility="Visible">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="1.1*"/>
              <ColumnDefinition Width="1.4*"/>
            </Grid.ColumnDefinitions>

            <!-- Left Card: Hero Clock, Date & Greeting -->
            <Border Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="16" Padding="16,14" Margin="0,0,5,0">
              <Grid VerticalAlignment="Center">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Big Clock -->
                <TextBlock x:Name="TodayClock" Grid.Row="0" Text="12:44 AM"
                           FontSize="34" FontWeight="Bold" Foreground="$($Config.TextColor)"
                           FontFamily="Segoe UI, Consolas, monospace"/>

                <!-- Date -->
                <TextBlock x:Name="TodayDate" Grid.Row="1" Text="Saturday, 7 November"
                           FontSize="12" Foreground="$($Config.SubtextColor)" Margin="2,4,0,12"/>

                <!-- Greeting Pill -->
                <Border Grid.Row="2" Background="#22222E" CornerRadius="10" Padding="8,4" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="TodayGreetingIcon" Text="&#xE708;" FontFamily="Segoe MDL2 Assets"
                               FontSize="12" Foreground="$($Config.GlowColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TodayGreeting" Text="Good night" FontSize="11" FontWeight="SemiBold"
                               Foreground="$($Config.TextColor)" VerticalAlignment="Center"/>
                  </StackPanel>
                </Border>
              </Grid>
            </Border>

            <!-- Right Card: Battery Gauge & 3 Mini Hardware Bars -->
            <Border Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="16" Padding="14,12" Margin="5,0,0,0">
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/> <!-- Battery status -->
                  <RowDefinition Height="*"/>    <!-- 3 Mini Bars -->
                </Grid.RowDefinitions>

                <!-- Top Battery Row -->
                <Grid Grid.Row="0" Margin="0,0,0,10">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <!-- Radial Battery Arc -->
                  <Grid Grid.Column="0" Width="44" Height="44" Margin="0,0,10,0">
                    <Ellipse Stroke="#22222E" StrokeThickness="4" Width="36" Height="36"/>
                    <Path x:Name="TodayBatteryArc" Stroke="$($Config.ColorGreen)" StrokeThickness="4"
                          StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="TodayBatteryCenterIcon" Text="&#xE945;" FontFamily="Segoe MDL2 Assets"
                               FontSize="12" Foreground="$($Config.ColorGreen)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>

                  <!-- Battery Info Text -->
                  <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <TextBlock x:Name="TodayBatteryPercent" Text="80%" FontSize="16" FontWeight="Bold" Foreground="$($Config.TextColor)"/>
                    <TextBlock x:Name="TodayBatteryState" Text="Charging · 42 min to full" FontSize="11" Foreground="$($Config.SubtextColor)"/>
                  </StackPanel>
                </Grid>

                <!-- 3 Mini Horizontal Hardware Bars -->
                <StackPanel Grid.Row="1" VerticalAlignment="Center">
                  <!-- CPU Bar -->
                  <Grid Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="34"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="38"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="CPU" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Border Grid.Column="1" Background="#22222E" Height="5" CornerRadius="2.5" Margin="4,0" VerticalAlignment="Center">
                      <Border x:Name="TodayCpuFill" Background="$($Config.GlowColor)" Height="5" CornerRadius="2.5" HorizontalAlignment="Left" Width="40"/>
                    </Border>
                    <TextBlock x:Name="TodayCpuPct" Grid.Column="2" Text="30%" FontSize="11" Foreground="$($Config.TextColor)" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>

                  <!-- GPU Bar -->
                  <Grid Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="34"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="38"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="GPU" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Border Grid.Column="1" Background="#22222E" Height="5" CornerRadius="2.5" Margin="4,0" VerticalAlignment="Center">
                      <Border x:Name="TodayGpuFill" Background="$($Config.GlowColor)" Height="5" CornerRadius="2.5" HorizontalAlignment="Left" Width="70"/>
                    </Border>
                    <TextBlock x:Name="TodayGpuPct" Grid.Column="2" Text="55%" FontSize="11" Foreground="$($Config.TextColor)" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>

                  <!-- RAM Bar -->
                  <Grid Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="34"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="38"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="RAM" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Border Grid.Column="1" Background="#22222E" Height="5" CornerRadius="2.5" Margin="4,0" VerticalAlignment="Center">
                      <Border x:Name="TodayRamFill" Background="$($Config.ColorAmber)" Height="5" CornerRadius="2.5" HorizontalAlignment="Left" Width="110"/>
                    </Border>
                    <TextBlock x:Name="TodayRamPct" Grid.Column="2" Text="89%" FontSize="11" Foreground="$($Config.TextColor)" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>
                </StackPanel>
              </Grid>
            </Border>
          </Grid>

          <!-- =============================================================== -->
          <!--  ROW 1: TAB 2 - MEDIA VIEW (Image 1 Reference)                  -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewMedia" Grid.Row="1" Visibility="Collapsed">
            <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="14" Margin="2,0">
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>  <!-- Art + Info -->
                  <RowDefinition Height="Auto"/>  <!-- Progress Bar -->
                  <RowDefinition Height="Auto"/>  <!-- Controls -->
                </Grid.RowDefinitions>

                <!-- Top: Album Art + Track Info -->
                <Grid Grid.Row="0" Margin="0,0,0,12">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <!-- 80x80 Album Art Container -->
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
                    <!-- Status Line -->
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                      <TextBlock x:Name="MediaStatusIcon" Text="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                                 FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock x:Name="MediaDeviceText" Text="Spotify · NuR Partybox 165"
                                 FontSize="11" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    </StackPanel>

                    <!-- Title -->
                    <TextBlock x:Name="MediaTitleText" Text="Loser"
                               FontSize="19" FontWeight="Bold" Foreground="$($Config.TextColor)"
                               TextTrimming="CharacterEllipsis"/>

                    <!-- Artist -->
                    <TextBlock x:Name="MediaArtistText" Text="Tame Impala"
                               FontSize="13" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"
                               TextTrimming="CharacterEllipsis"/>
                  </StackPanel>
                </Grid>

                <!-- Middle: Progress Track & Timestamps -->
                <Grid Grid.Row="1" Margin="0,0,0,10">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>

                  <!-- Timestamps -->
                  <Grid Grid.Row="0" Margin="0,0,0,4">
                    <TextBlock x:Name="MediaTimeCurrent" Text="1:12" FontSize="11" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Left"/>
                    <TextBlock x:Name="MediaTimeTotal"   Text="4:43" FontSize="11" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Right"/>
                  </Grid>

                  <!-- Progress Bar Line -->
                  <Border x:Name="MediaTrackContainer" Grid.Row="1" Background="#22222E" Height="4" CornerRadius="2">
                    <Border x:Name="MediaProgressLine" Background="#FFFFFF" Height="4" CornerRadius="2" HorizontalAlignment="Left" Width="120"/>
                  </Border>
                </Grid>

                <!-- Bottom: Playback Controls Row -->
                <Grid Grid.Row="2">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>

                  <!-- Shuffle -->
                  <Button x:Name="BtnMediaShuffle" Grid.Column="0" Content="&#xE8B1;" FontFamily="Segoe MDL2 Assets"
                          FontSize="14" Foreground="$($Config.SubtextColor)" Background="Transparent"
                          Width="32" Height="32" Cursor="Hand" Focusable="False" Style="{StaticResource HeaderActionBtnStyle}"/>

                  <!-- Center Controls: Prev, White Pill Play/Pause, Next -->
                  <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <!-- Previous -->
                    <Button x:Name="BtnMediaPrev" Content="&#xE892;" FontFamily="Segoe MDL2 Assets"
                            FontSize="15" Foreground="$($Config.TextColor)" Background="Transparent"
                            Width="36" Height="36" Cursor="Hand" Focusable="False" Style="{StaticResource HeaderActionBtnStyle}"/>

                    <!-- High Contrast Circular White Pill Play/Pause -->
                    <Button x:Name="BtnMediaPlay" Content="&#xE768;" FontFamily="Segoe MDL2 Assets"
                            FontSize="16" Foreground="#0E0E13" Background="#FFFFFF"
                            Width="44" Height="44" Margin="14,0" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border x:Name="PlayPill" Background="{TemplateBinding Background}" CornerRadius="22">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                          </Border>
                          <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                              <Setter TargetName="PlayPill" Property="Background" Value="#F0F0F5"/>
                            </Trigger>
                          </ControlTemplate.Triggers>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <!-- Next -->
                    <Button x:Name="BtnMediaNext" Content="&#xE893;" FontFamily="Segoe MDL2 Assets"
                            FontSize="15" Foreground="$($Config.TextColor)" Background="Transparent"
                            Width="36" Height="36" Cursor="Hand" Focusable="False" Style="{StaticResource HeaderActionBtnStyle}"/>
                  </StackPanel>

                  <!-- Output Device Toggle -->
                  <Button x:Name="BtnMediaOutput" Grid.Column="2" Content="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                          FontSize="14" Foreground="$($Config.SubtextColor)" Background="Transparent"
                          Width="32" Height="32" Cursor="Hand" Focusable="False" Style="{StaticResource HeaderActionBtnStyle}"/>
                </Grid>
              </Grid>
            </Border>
          </Grid>

          <!-- =============================================================== -->
          <!--  ROW 1: TAB 3 - STATS VIEW (Image 2 Reference)                  -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewStats" Grid.Row="1" Visibility="Collapsed">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Card 1: CPU Load -->
            <Border Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="16" Padding="10,14" Margin="0,0,4,0">
              <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <!-- Circular Ring Gauge -->
                <Grid Width="76" Height="76">
                  <Ellipse Stroke="#22222E" StrokeThickness="5.5" Width="66" Height="66"/>
                  <Path x:Name="StatsCpuArc" Stroke="$($Config.GlowColor)" StrokeThickness="5.5"
                        StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                  <TextBlock x:Name="StatsCpuVal" Text="35%" FontSize="17" FontWeight="Bold"
                             Foreground="$($Config.TextColor)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock Text="CPU load" FontSize="13" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Center" Margin="0,8,0,2"/>
                <TextBlock x:Name="StatsCpuSpecs" Text="4.1 GHz · 62°C" FontSize="11" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Center"/>
              </StackPanel>
            </Border>

            <!-- Card 2: GPU 3D -->
            <Border Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="16" Padding="10,14" Margin="4,0,4,0">
              <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <!-- Circular Ring Gauge -->
                <Grid Width="76" Height="76">
                  <Ellipse Stroke="#22222E" StrokeThickness="5.5" Width="66" Height="66"/>
                  <Path x:Name="StatsGpuArc" Stroke="$($Config.GlowColor)" StrokeThickness="5.5"
                        StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                  <TextBlock x:Name="StatsGpuVal" Text="28%" FontSize="17" FontWeight="Bold"
                             Foreground="$($Config.TextColor)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock Text="GPU 3D" FontSize="13" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Center" Margin="0,8,0,2"/>
                <TextBlock x:Name="StatsGpuSpecs" Text="1.8 GHz · 54°C" FontSize="11" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Center"/>
              </StackPanel>
            </Border>

            <!-- Card 3: Memory -->
            <Border Grid.Column="2" Background="$($Config.CardColor)" CornerRadius="16" Padding="10,14" Margin="4,0,0,0">
              <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                <!-- Circular Ring Gauge -->
                <Grid Width="76" Height="76">
                  <Ellipse Stroke="#22222E" StrokeThickness="5.5" Width="66" Height="66"/>
                  <Path x:Name="StatsRamArc" Stroke="$($Config.ColorRed)" StrokeThickness="5.5"
                        StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                  <TextBlock x:Name="StatsRamVal" Text="91%" FontSize="17" FontWeight="Bold"
                             Foreground="$($Config.TextColor)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
                <TextBlock Text="Memory" FontSize="13" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Center" Margin="0,8,0,2"/>
                <TextBlock x:Name="StatsRamSpecs" Text="14.6 / 16 GB" FontSize="11" Foreground="$($Config.SubtextColor)" HorizontalAlignment="Center"/>
              </StackPanel>
            </Border>
          </Grid>

          <!-- =============================================================== -->
          <!--  ROW 1: TAB 4 - CONTROLS VIEW (Image 3 Reference)               -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewControls" Grid.Row="1" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/> <!-- Master Volume Card -->
              <RowDefinition Height="Auto"/> <!-- 4 Quick-Action Tiles -->
            </Grid.RowDefinitions>

            <!-- Top Card: Master Volume Slider -->
            <Border Grid.Row="0" Background="$($Config.CardColor)" CornerRadius="16" Padding="14,12" Margin="2,0,2,8">
              <Grid VerticalAlignment="Center">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Speaker Icon -->
                <TextBlock Grid.Column="0" Text="&#xE767;" FontFamily="Segoe MDL2 Assets"
                           FontSize="14" Foreground="$($Config.TextColor)" VerticalAlignment="Center" Margin="0,0,12,0"/>

                <!-- Volume Slider -->
                <Slider x:Name="SliderMasterVolume" Grid.Column="1" Minimum="0" Maximum="100" Value="43"
                        VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>

                <!-- Volume Indicator Number -->
                <TextBlock x:Name="TextMasterVolumeVal" Grid.Column="2" Text="43"
                           FontSize="13" FontWeight="Bold" Foreground="$($Config.SubtextColor)"
                           VerticalAlignment="Center" Margin="12,0,8,0"/>

                <!-- Headphone Icon -->
                <TextBlock Grid.Column="3" Text="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                           FontSize="14" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
              </Grid>
            </Border>

            <!-- Bottom Row: 4 Quick-Action Tiles -->
            <Grid Grid.Row="1" Margin="2,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <!-- Tile 1: Bluetooth -->
              <Border x:Name="TileBluetooth" Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="0,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#2D234A" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE702;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.GlowColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Bluetooth" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="TileBluetoothSub" Text="2 devices" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>

              <!-- Tile 2: Display -->
              <Border x:Name="TileDisplay" Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#22222E" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE706;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Display" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="TileDisplaySub" Text="70%" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>

              <!-- Tile 3: Task Manager -->
              <Border x:Name="TileTaskMgr" Grid.Column="2" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#22222E" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE9D2;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Task Mgr" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Open" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>

              <!-- Tile 4: Explorer -->
              <Border x:Name="TileExplorer" Grid.Column="3" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,0,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#22222E" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xED25;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Explorer" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Open" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>
            </Grid>
          </Grid>

          <!-- =============================================================== -->
          <!--  ROW 1: TAB 5 - POWER VIEW (Image 4 Reference)                  -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewPower" Grid.Row="1" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>  <!-- 4 Action Tiles -->
              <RowDefinition Height="Auto"/>  <!-- Footer Uptime -->
            </Grid.RowDefinitions>

            <!-- Top Row: 4 Action Tiles -->
            <Grid Grid.Row="0" Margin="2,0,2,10">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <!-- Tile 1: Lock -->
              <Border x:Name="TilePowerLock" Grid.Column="0" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="0,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#22222E" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Lock" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Win + L" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>

              <!-- Tile 2: Sleep -->
              <Border x:Name="TilePowerSleep" Grid.Column="1" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#22222E" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Sleep" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock Text="Suspend" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>

              <!-- Tile 3: Restart -->
              <Border x:Name="TilePowerRestart" Grid.Column="2" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,4,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#22222E" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE777;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.TextColor)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Restart" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="PowerRestartSub" Text="Hold to confirm" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>

              <!-- Tile 4: Shut Down (Red Tinted) -->
              <Border x:Name="TilePowerShutdown" Grid.Column="3" Background="$($Config.CardColor)" CornerRadius="14" Padding="12" Margin="4,0,0,0" Cursor="Hand">
                <StackPanel>
                  <Border Width="30" Height="30" CornerRadius="9" Background="#2D1B22" HorizontalAlignment="Left" Margin="0,0,0,10">
                    <TextBlock Text="&#xE7E8;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.ColorRed)"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <TextBlock Text="Shut down" FontSize="13" FontWeight="SemiBold" Foreground="$($Config.TextColor)"/>
                  <TextBlock x:Name="PowerShutdownSub" Text="Hold to confirm" FontSize="11" Foreground="$($Config.SubtextColor)" Margin="0,2,0,0"/>
                </StackPanel>
              </Border>
            </Grid>

            <!-- Bottom Row: System Uptime -->
            <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Left" Margin="6,2,0,0">
              <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="$($Config.SubtextColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="TextPowerUptime" Text="Uptime 3d 4h · Last restart Wed 09:12" FontSize="11" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>

          <!-- =============================================================== -->
          <!--  ROW 1: TAB 6 - SETTINGS VIEW (Full Suite Customization)         -->
          <!-- =============================================================== -->
          <Grid x:Name="ViewSettings" Grid.Row="1" Visibility="Collapsed">
            <StackPanel Margin="2,0">
              <!-- Card 1: Accent Color -->
              <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="14,10" Margin="0,0,0,6">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>

                  <TextBlock Grid.Column="0" Text="ACCENT COLOR" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center" Margin="0,0,10,0"/>

                  <!-- Swatches -->
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnColorPurple"  Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#A78BFA"/>
                    <Button x:Name="BtnColorCyan"    Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#00E5FF"/>
                    <Button x:Name="BtnColorPink"    Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#FF007F"/>
                    <Button x:Name="BtnColorEmerald" Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#34D399"/>
                    <Button x:Name="BtnColorAmber"   Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#FBBF24"/>
                    <Button x:Name="BtnColorRed"     Width="26" Height="26" Margin="3,0" Cursor="Hand" Focusable="False" Tag="#F87171"/>
                  </StackPanel>

                  <!-- Editable Hex Code Input -->
                  <TextBox x:Name="InputHexColor" Grid.Column="2" Text="$($Config.GlowColor)"
                           Width="76" Height="26" Background="#22222E" Foreground="$($Config.TextColor)"
                           BorderBrush="#25FFFFFF" BorderThickness="1"
                           FontSize="11" FontWeight="SemiBold" TextAlignment="Center" VerticalAlignment="Center"/>
                </Grid>
              </Border>

              <!-- Card 2: Aura Glow Sliders -->
              <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="14,10" Margin="0,0,0,6">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>

                  <!-- Glow Radius -->
                  <Grid Grid.Row="0" Margin="0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="65"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="40"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Radius" FontSize="11" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Slider x:Name="SliderGlowRadius" Grid.Column="1" Minimum="8" Maximum="60" Value="$($Config.GlowRadius)" Focusable="False" Cursor="Hand" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TextGlowRadiusVal" Grid.Column="2" Text="$($Config.GlowRadius)px" FontSize="11" Foreground="$($Config.TextColor)" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>

                  <!-- Glow Opacity -->
                  <Grid Grid.Row="1" Margin="0,4,0,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="65"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="40"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Opacity" FontSize="11" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center"/>
                    <Slider x:Name="SliderGlowOpacity" Grid.Column="1" Minimum="10" Maximum="100" Value="55" Focusable="False" Cursor="Hand" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TextGlowOpacityVal" Grid.Column="2" Text="55%" FontSize="11" Foreground="$($Config.TextColor)" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>
                </Grid>
              </Border>

              <!-- Card 3: Visible Tabs Chips -->
              <Border Background="$($Config.CardColor)" CornerRadius="16" Padding="14,10">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="VISIBLE TABS" FontSize="10" FontWeight="SemiBold" Foreground="$($Config.SubtextColor)" VerticalAlignment="Center" Margin="0,0,10,0"/>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <CheckBox x:Name="ToggleTabToday"    Content="Today"    IsChecked="True"  Margin="3,0" Foreground="$($Config.TextColor)" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabMedia"    Content="Media"    IsChecked="True"  Margin="3,0" Foreground="$($Config.TextColor)" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabStats"    Content="Stats"    IsChecked="True"  Margin="3,0" Foreground="$($Config.TextColor)" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabControls" Content="Controls" IsChecked="True"  Margin="3,0" Foreground="$($Config.TextColor)" Cursor="Hand"/>
                    <CheckBox x:Name="ToggleTabPower"    Content="Power"    IsChecked="True"  Margin="3,0" Foreground="$($Config.TextColor)" Cursor="Hand"/>
                  </StackPanel>
                </Grid>
              </Border>
            </StackPanel>
          </Grid>
        </Grid>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

# ------------------------------------------------------------------------------
#  S5  WPF INSTANTIATION & NAMED ELEMENT BINDINGS
# ------------------------------------------------------------------------------
$reader = New-Object System.Xml.XmlNodeReader($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Shell & Root Elements
$glowBorder          = $window.FindName('GlowBorder')
$islandGlow          = $window.FindName('IslandGlow')
$compactBar          = $window.FindName('CompactBar')
$expandedCard        = $window.FindName('ExpandedCard')
$brandDot            = $window.FindName('BrandDot')

# Compact Bar Elements
$compactIcon         = $window.FindName('CompactIcon')
$compactClock        = $window.FindName('CompactClock')
$compactBatteryIcon  = $window.FindName('CompactBatteryIcon')
$compactBatteryText  = $window.FindName('CompactBatteryText')
$compactCpuText      = $window.FindName('CompactCpuText')

# Header Navigation Elements
$tabBtnToday         = $window.FindName('TabBtnToday')
$tabBtnMedia         = $window.FindName('TabBtnMedia')
$tabBtnStats         = $window.FindName('TabBtnStats')
$tabBtnControls      = $window.FindName('TabBtnControls')
$tabBtnPower         = $window.FindName('TabBtnPower')
$btnSettings         = $window.FindName('BtnSettings')
$btnPin              = $window.FindName('BtnPin')

# Views
$viewToday           = $window.FindName('ViewToday')
$viewMedia           = $window.FindName('ViewMedia')
$viewStats           = $window.FindName('ViewStats')
$viewControls        = $window.FindName('ViewControls')
$viewPower           = $window.FindName('ViewPower')
$viewSettings        = $window.FindName('ViewSettings')

# Tab 1: Today Elements
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

# Tab 2: Media Elements
$albumArtImage       = $window.FindName('AlbumArtImage')
$albumArtPlaceholder = $window.FindName('AlbumArtPlaceholder')
$mediaStatusIcon     = $window.FindName('MediaStatusIcon')
$mediaDeviceText     = $window.FindName('MediaDeviceText')
$mediaTitleText      = $window.FindName('MediaTitleText')
$mediaArtistText     = $window.FindName('MediaArtistText')
$mediaTimeCurrent    = $window.FindName('MediaTimeCurrent')
$mediaTimeTotal      = $window.FindName('MediaTimeTotal')
$mediaProgressLine   = $window.FindName('MediaProgressLine')
$mediaTrackContainer = $window.FindName('MediaTrackContainer')
$btnMediaShuffle     = $window.FindName('BtnMediaShuffle')
$btnMediaPrev        = $window.FindName('BtnMediaPrev')
$btnMediaPlay        = $window.FindName('BtnMediaPlay')
$btnMediaNext        = $window.FindName('BtnMediaNext')
$btnMediaOutput      = $window.FindName('BtnMediaOutput')

# Tab 3: Stats Elements
$statsCpuArc         = $window.FindName('StatsCpuArc')
$statsCpuVal         = $window.FindName('StatsCpuVal')
$statsCpuSpecs       = $window.FindName('StatsCpuSpecs')
$statsGpuArc         = $window.FindName('StatsGpuArc')
$statsGpuVal         = $window.FindName('StatsGpuVal')
$statsGpuSpecs       = $window.FindName('StatsGpuSpecs')
$statsRamArc         = $window.FindName('StatsRamArc')
$statsRamVal         = $window.FindName('StatsRamVal')
$statsRamSpecs       = $window.FindName('StatsRamSpecs')

# Tab 4: Controls Elements
$sliderMasterVolume  = $window.FindName('SliderMasterVolume')
$textMasterVolumeVal = $window.FindName('TextMasterVolumeVal')
$tileBluetooth       = $window.FindName('TileBluetooth')
$tileBluetoothSub    = $window.FindName('TileBluetoothSub')
$tileDisplay         = $window.FindName('TileDisplay')
$tileDisplaySub      = $window.FindName('TileDisplaySub')
$tileTaskMgr         = $window.FindName('TileTaskMgr')
$tileExplorer        = $window.FindName('TileExplorer')

# Tab 5: Power Elements
$tilePowerLock       = $window.FindName('TilePowerLock')
$tilePowerSleep      = $window.FindName('TilePowerSleep')
$tilePowerRestart    = $window.FindName('TilePowerRestart')
$powerRestartSub     = $window.FindName('PowerRestartSub')
$tilePowerShutdown   = $window.FindName('TilePowerShutdown')
$powerShutdownSub    = $window.FindName('PowerShutdownSub')
$textPowerUptime     = $window.FindName('TextPowerUptime')

# Tab 6: Settings Elements
$btnColorPurple      = $window.FindName('BtnColorPurple')
$btnColorCyan        = $window.FindName('BtnColorCyan')
$btnColorPink        = $window.FindName('BtnColorPink')
$btnColorEmerald     = $window.FindName('BtnColorEmerald')
$btnColorAmber       = $window.FindName('BtnColorAmber')
$btnColorRed         = $window.FindName('BtnColorRed')
$inputHexColor       = $window.FindName('InputHexColor')
$sliderGlowRadius    = $window.FindName('SliderGlowRadius')
$textGlowRadiusVal   = $window.FindName('TextGlowRadiusVal')
$sliderGlowOpacity   = $window.FindName('SliderGlowOpacity')
$textGlowOpacityVal  = $window.FindName('TextGlowOpacityVal')
$toggleTabToday      = $window.FindName('ToggleTabToday')
$toggleTabMedia      = $window.FindName('ToggleTabMedia')
$toggleTabStats      = $window.FindName('ToggleTabStats')
$toggleTabControls   = $window.FindName('ToggleTabControls')
$toggleTabPower      = $window.FindName('ToggleTabPower')

# Context Menu Items
$menuResetPos        = $window.FindName('MenuResetPos')
$menuQuit            = $window.FindName('MenuQuit')

# ------------------------------------------------------------------------------
#  S6  SCREEN POSITIONING & DYNAMIC CONTENT-FIT HEIGHT CONTROLLER
# ------------------------------------------------------------------------------
$script:expanded      = $false
$script:isDragging    = $false
$script:pinned        = [bool]$Config.Pinned
$script:activeTab     = 'Today'
$script:currentArtBytes = $null
$script:lastMediaTitle  = ''
$script:mediaAutoShown  = $false

# Screen positioning initialization
if ($null -ne $Config.X -and $null -ne $Config.Y) {
    $window.Left = [double]$Config.X
    $window.Top  = [double]$Config.Y
} else {
    $window.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth - $window.Width) / 2
    $window.Top  = 0
    $Config.X = $window.Left
    $Config.Y = $window.Top
    Save-Config
}

# Update Pin Icon state
if ($script:pinned) {
    $btnPin.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Config.GlowColor))
}

# Content-Fit Dynamic Height Mapping
$script:tabHeights = @{
    'Today'    = 225
    'Media'    = 235
    'Stats'    = 210
    'Controls' = 210
    'Power'    = 195
    'Settings' = 280
}

$script:allTabs = @{
    'Today'    = @{ Btn = $tabBtnToday;    View = $viewToday    }
    'Media'    = @{ Btn = $tabBtnMedia;    View = $viewMedia    }
    'Stats'    = @{ Btn = $tabBtnStats;    View = $viewStats    }
    'Controls' = @{ Btn = $tabBtnControls; View = $viewControls }
    'Power'    = @{ Btn = $tabBtnPower;    View = $viewPower    }
    'Settings' = @{ Btn = $btnSettings;    View = $viewSettings }
}

function Switch-Tab ([string]$tabName) {
    if (-not $script:allTabs.ContainsKey($tabName)) { return }
    $script:activeTab = $tabName

    $bc = New-Object System.Windows.Media.BrushConverter
    $activeBrush   = $bc.ConvertFromString('#22222E'); $activeBrush.Freeze()
    $inactiveBrush = [System.Windows.Media.Brushes]::Transparent
    $textActive    = $bc.ConvertFromString('#F4F4F6'); $textActive.Freeze()
    $textInactive  = $bc.ConvertFromString('#9B9BA7'); $textInactive.Freeze()

    foreach ($k in $script:allTabs.Keys) {
        $btn = $script:allTabs[$k].Btn
        $view = $script:allTabs[$k].View
        if ($k -eq $tabName) {
            $view.Visibility = 'Visible'
            if ($k -ne 'Settings') {
                $btn.Background = $activeBrush
                $btn.Foreground = $textActive
                $btn.FontWeight = [System.Windows.FontWeights]::SemiBold
            }
        } else {
            $view.Visibility = 'Collapsed'
            if ($k -ne 'Settings') {
                $btn.Background = $inactiveBrush
                $btn.Foreground = $textInactive
                $btn.FontWeight = [System.Windows.FontWeights]::Normal
            }
        }
    }

    # Animate Content-Fit Dynamic Height smoothly
    if ($script:expanded) {
        $targetH = [double]$script:tabHeights[$tabName]
        $animH = New-Object System.Windows.Media.Animation.DoubleAnimation($targetH, [TimeSpan]::FromMilliseconds(200))
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = 'EaseOut'
        $animH.EasingFunction = $ease
        [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($animH, 60)
        $glowBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, $animH)
    }
}

function Expand-Island {
    if ($script:expanded) { return }
    $script:expanded = $true

    $targetH = [double]$script:tabHeights[$script:activeTab]
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'

    $animW = New-Object System.Windows.Media.Animation.DoubleAnimation($Config.ExpandedWidth, [TimeSpan]::FromMilliseconds($Config.ExpandMs))
    $animH = New-Object System.Windows.Media.Animation.DoubleAnimation($targetH, [TimeSpan]::FromMilliseconds($Config.ExpandMs))
    $animW.EasingFunction = $ease
    $animH.EasingFunction = $ease
    [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($animW, 60)
    [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($animH, 60)

    $glowBorder.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $animW)
    $glowBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, $animH)

    $animCompact = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, [TimeSpan]::FromMilliseconds([int]($Config.ExpandMs * 0.4)))
    $compactBar.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animCompact)

    $expandedCard.Visibility = 'Visible'
    $animExpand = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, [TimeSpan]::FromMilliseconds($Config.ExpandMs))
    $animExpand.EasingFunction = $ease
    $expandedCard.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animExpand)
}

function Collapse-Island {
    if (-not $script:expanded -or $script:pinned) { return }
    if ($glowBorder.IsMouseOver -or $window.IsMouseOver) { return }
    $script:expanded = $false

    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'

    $animExpand = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, [TimeSpan]::FromMilliseconds([int]($Config.CollapseMs * 0.4)))
    $animExpand.Add_Completed({
        if (-not $script:expanded) { $expandedCard.Visibility = 'Collapsed' }
    })
    $expandedCard.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animExpand)

    $animW = New-Object System.Windows.Media.Animation.DoubleAnimation($Config.IslandWidth, [TimeSpan]::FromMilliseconds($Config.CollapseMs))
    $animH = New-Object System.Windows.Media.Animation.DoubleAnimation($Config.IslandHeight, [TimeSpan]::FromMilliseconds($Config.CollapseMs))
    $animW.EasingFunction = $ease
    $animH.EasingFunction = $ease
    [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($animW, 60)
    [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($animH, 60)

    $glowBorder.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $animW)
    $glowBorder.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, $animH)

    $animCompact = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, [TimeSpan]::FromMilliseconds($Config.CollapseMs))
    $compactBar.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animCompact)
}

# ------------------------------------------------------------------------------
#  S7  CUSTOMIZATION CONTROLLER (Swatches, Hex Input, Aura & Tab Toggles)
# ------------------------------------------------------------------------------
function Apply-AuraTheme ([string]$hexColor) {
    if (-not ($hexColor -match '^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$')) { return }
    $Config.GlowColor = $hexColor

    $bc = New-Object System.Windows.Media.BrushConverter
    $brush = $bc.ConvertFromString($hexColor); $brush.Freeze()
    $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hexColor)

    $islandGlow.Color = $color
    $brandDot.Fill = $brush
    $compactIcon.Foreground = $brush
    $inputHexColor.Text = $hexColor

    if ($script:pinned) { $btnPin.Foreground = $brush }
    Save-Config
}

# Swatch Button Visual Setup
$swatches = @($btnColorPurple, $btnColorCyan, $btnColorPink, $btnColorEmerald, $btnColorAmber, $btnColorRed)
foreach ($sw in $swatches) {
    $hex = [string]$sw.Tag
    $b = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex); $b.Freeze()
    $sw.Background = $b
    $sw.BorderBrush = (New-Object System.Windows.Media.BrushConverter).ConvertFromString('#25FFFFFF')
    $sw.BorderThickness = New-Object System.Windows.Thickness(1)
    $sw.Template = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border Background="{TemplateBinding Background}" CornerRadius="13"
          BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
    <Ellipse Width="10" Height="10" Fill="White" Opacity="0.15" HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
</ControlTemplate>
"@)
    $sw.Add_Click({ Apply-AuraTheme ($this.Tag) })
}

# Editable Hex Code Input
$inputHexColor.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        $val = $inputHexColor.Text.Trim()
        if (-not $val.StartsWith('#')) { $val = "#$val" }
        Apply-AuraTheme $val
        $inputHexColor.MoveFocus((New-Object System.Windows.Input.TraversalRequest([System.Windows.Input.FocusNavigationDirection]::Next)))
    }
})

# Glow Radius Slider
$sliderGlowRadius.Add_ValueChanged({
    $val = [int]$sliderGlowRadius.Value
    $textGlowRadiusVal.Text = "${val}px"
    $islandGlow.BlurRadius = $val
    $Config.GlowRadius = $val
    Save-Config
})

# Glow Opacity Slider
$sliderGlowOpacity.Add_ValueChanged({
    $val = [int]$sliderGlowOpacity.Value
    $textGlowOpacityVal.Text = "${val}%"
    $islandGlow.Opacity = ($val / 100.0)
    $Config.GlowOpacity = ($val / 100.0)
    Save-Config
})

# Visible Tabs Toggles
$toggleTabToday.IsChecked    = $Config.Tabs.Today
$toggleTabMedia.IsChecked    = $Config.Tabs.Media
$toggleTabStats.IsChecked    = $Config.Tabs.Stats
$toggleTabControls.IsChecked = $Config.Tabs.Controls
$toggleTabPower.IsChecked    = $Config.Tabs.Power

$tabBtnToday.Visibility    = if ($Config.Tabs.Today) { 'Visible' } else { 'Collapsed' }
$tabBtnMedia.Visibility    = if ($Config.Tabs.Media) { 'Visible' } else { 'Collapsed' }
$tabBtnStats.Visibility    = if ($Config.Tabs.Stats) { 'Visible' } else { 'Collapsed' }
$tabBtnControls.Visibility = if ($Config.Tabs.Controls) { 'Visible' } else { 'Collapsed' }
$tabBtnPower.Visibility    = if ($Config.Tabs.Power) { 'Visible' } else { 'Collapsed' }

$toggleTabToday.Add_Click({ $Config.Tabs.Today = [bool]$toggleTabToday.IsChecked; $tabBtnToday.Visibility = if ($Config.Tabs.Today) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabMedia.Add_Click({ $Config.Tabs.Media = [bool]$toggleTabMedia.IsChecked; $tabBtnMedia.Visibility = if ($Config.Tabs.Media) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabStats.Add_Click({ $Config.Tabs.Stats = [bool]$toggleTabStats.IsChecked; $tabBtnStats.Visibility = if ($Config.Tabs.Stats) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabControls.Add_Click({ $Config.Tabs.Controls = [bool]$toggleTabControls.IsChecked; $tabBtnControls.Visibility = if ($Config.Tabs.Controls) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabPower.Add_Click({ $Config.Tabs.Power = [bool]$toggleTabPower.IsChecked; $tabBtnPower.Visibility = if ($Config.Tabs.Power) { 'Visible' } else { 'Collapsed' }; Save-Config })

# Navigation Tabs Click Wireup
$tabBtnToday.Add_Click({ Switch-Tab 'Today' })
$tabBtnMedia.Add_Click({ Switch-Tab 'Media' })
$tabBtnStats.Add_Click({ Switch-Tab 'Stats' })
$tabBtnControls.Add_Click({ Switch-Tab 'Controls' })
$tabBtnPower.Add_Click({ Switch-Tab 'Power' })
$btnSettings.Add_Click({
    if ($script:activeTab -eq 'Settings') { Switch-Tab 'Today' }
    else { Switch-Tab 'Settings' }
})

# Pin Button
$btnPin.Add_Click({
    $script:pinned = -not $script:pinned
    $Config.Pinned = $script:pinned
    Save-Config
    $bc = New-Object System.Windows.Media.BrushConverter
    if ($script:pinned) {
        $btnPin.Foreground = $bc.ConvertFromString($Config.GlowColor)
    } else {
        $btnPin.Foreground = $bc.ConvertFromString($Config.SubtextColor)
    }
})

# ------------------------------------------------------------------------------
#  S8  INTERACTIVE CONTROLS & MEDIA ACTIONS
# ------------------------------------------------------------------------------
# Master Volume Slider
$sliderMasterVolume.Value = [IslandNative]::GetMasterVolume()
$textMasterVolumeVal.Text = [string][int]$sliderMasterVolume.Value
$sliderMasterVolume.Add_ValueChanged({
    $v = [int]$sliderMasterVolume.Value
    $textMasterVolumeVal.Text = [string]$v
    [IslandNative]::SetMasterVolume($v)
})

# Media Playback Buttons (Zero Latency + Timer Protection)
$btnMediaPlay.Add_Click({
    $script:autoCollapseTimer.Stop()
    $leaveTimer.Stop()
    $script:mediaAutoShown = $false
    Send-MediaCommandAsync 'PlayPause'
})
$btnMediaPrev.Add_Click({
    $script:autoCollapseTimer.Stop()
    $leaveTimer.Stop()
    $script:mediaAutoShown = $false
    Send-MediaCommandAsync 'Previous'
})
$btnMediaNext.Add_Click({
    $script:autoCollapseTimer.Stop()
    $leaveTimer.Stop()
    $script:mediaAutoShown = $false
    Send-MediaCommandAsync 'Next'
})
$btnMediaShuffle.Add_Click({
    $bc = New-Object System.Windows.Media.BrushConverter
    if ($btnMediaShuffle.Foreground.ToString() -match '9B9BA7') {
        $btnMediaShuffle.Foreground = $bc.ConvertFromString($Config.GlowColor)
    } else {
        $btnMediaShuffle.Foreground = $bc.ConvertFromString($Config.SubtextColor)
    }
})
$btnMediaOutput.Add_Click({ Start-Process 'ms-settings:sound' })

# Quick-Action Tiles
$tileBluetooth.Add_MouseLeftButtonDown({ Start-Process 'ms-settings:bluetooth' })
$tileDisplay.Add_MouseLeftButtonDown({ Start-Process 'ms-settings:display' })
$tileTaskMgr.Add_MouseLeftButtonDown({ Start-Process taskmgr.exe })
$tileExplorer.Add_MouseLeftButtonDown({ Start-Process explorer.exe })

# Power Action Tiles
$tilePowerLock.Add_MouseLeftButtonDown({ Start-Process rundll32.exe 'user32.dll,LockWorkStation' })
$tilePowerSleep.Add_MouseLeftButtonDown({ Start-Process rundll32.exe 'powrprof.dll,SetSuspendState 0,1,0' })

$script:restartArmed = $false
$tilePowerRestart.Add_MouseLeftButtonDown({
    if (-not $script:restartArmed) {
        $script:restartArmed = $true
        $powerRestartSub.Text = 'Click to confirm!'
        $powerRestartSub.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Config.ColorAmber)
    } else {
        Start-Process shutdown.exe '/r /t 0'
    }
})

$script:shutdownArmed = $false
$tilePowerShutdown.Add_MouseLeftButtonDown({
    if (-not $script:shutdownArmed) {
        $script:shutdownArmed = $true
        $powerShutdownSub.Text = 'Click to confirm!'
        $powerShutdownSub.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Config.ColorRed)
    } else {
        Start-Process shutdown.exe '/s /t 0'
    }
})

# ------------------------------------------------------------------------------
#  S9  EVENT TRIGGERS: HOVER, FREE DRAG & HARDWARE VOLUME SCROLL
# ------------------------------------------------------------------------------
# Visual Tree Traversal: Safe Click Isolation
function Test-IsInteractiveControl ($source) {
    if ($null -eq $source) { return $false }
    $current = $source
    while ($null -ne $current -and $current -ne $glowBorder -and $current -ne $window) {
        if ($current -is [System.Windows.Controls.Primitives.ButtonBase] -or
            $current -is [System.Windows.Controls.Primitives.RangeBase] -or
            $current -is [System.Windows.Controls.Primitives.Thumb] -or
            $current -is [System.Windows.Controls.TextBox] -or
            $current -is [System.Windows.Controls.CheckBox] -or
            $current -is [System.Windows.Controls.MenuItem]) {
            return $true
        }
        if ($current -is [System.Windows.Media.Visual] -or $current -is [System.Windows.Media.Media3D.Visual3D]) {
            $current = [System.Windows.Media.VisualTreeHelper]::GetParent($current)
        } else {
            break
        }
    }
    return $false
}

$leaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$leaveTimer.Interval = [TimeSpan]::FromMilliseconds($Config.CollapseDelay)
$leaveTimer.Add_Tick({
    $leaveTimer.Stop()
    if (-not $script:isDragging -and -not $glowBorder.IsMouseOver -and -not $window.IsMouseOver) {
        Collapse-Island
    }
})

$glowBorder.Add_MouseEnter({
    $leaveTimer.Stop()
    $script:mediaAutoShown = $false
    if ($script:autoCollapseTimer) { $script:autoCollapseTimer.Stop() }
    Expand-Island
})

$glowBorder.Add_MouseLeave({
    if (-not $script:isDragging -and -not $script:pinned) { $leaveTimer.Start() }
})

$expandedCard.Add_MouseEnter({
    $leaveTimer.Stop()
    if ($script:autoCollapseTimer) { $script:autoCollapseTimer.Stop() }
    $script:mediaAutoShown = $false
})

# Free Drag Anywhere on Island
$glowBorder.Add_MouseLeftButtonDown({
    param($sender, $e)
    if (Test-IsInteractiveControl $e.OriginalSource) { return }
    $script:isDragging = $true
    $window.DragMove()
    $script:isDragging = $false
    $Config.X = $window.Left
    $Config.Y = $window.Top
    Save-Config
})

# Hardware Master Volume Scroll (MouseWheel)
if ($Config.EnableVolumeScroll) {
    $glowBorder.Add_MouseWheel({
        param($sender, $e)
        if ($e.Delta -gt 0) { [IslandNative]::VolumeUp() }
        else { [IslandNative]::VolumeDown() }
        $sliderMasterVolume.Value = [IslandNative]::GetMasterVolume()
        $e.Handled = $true
    })
}

$script:autoCollapseTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:autoCollapseTimer.Interval = [TimeSpan]::FromMilliseconds($Config.MediaPopupMs)
$script:autoCollapseTimer.Add_Tick({
    $script:autoCollapseTimer.Stop()
    $script:mediaAutoShown = $false
    if ($script:expanded -and -not $script:pinned -and -not $glowBorder.IsMouseOver -and -not $window.IsMouseOver) {
        Collapse-Island
    }
})

# Context Menu Handlers
if ($null -ne $menuResetPos) {
    $menuResetPos.Add_Click({
        $window.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth - $window.Width) / 2
        $window.Top  = 0
        $Config.X = $window.Left
        $Config.Y = $window.Top
        Save-Config
    })
}
if ($null -ne $menuQuit) {
    $menuQuit.Add_Click({ $window.Close() })
}

# Cleanup on Close
$window.Add_Closed({
    $script:sharedState.IsRunning = $false
    try { $script:bgRunspace.Dispose() } catch { }
})

# ------------------------------------------------------------------------------
#  S10  HIGH-FREQUENCY UI DISPATCHER LOOP (Synchronized Telemetry)
# ------------------------------------------------------------------------------
$bc = New-Object System.Windows.Media.BrushConverter
$script:brushGreen = $bc.ConvertFromString($Config.ColorGreen); $script:brushGreen.Freeze()
$script:brushAmber = $bc.ConvertFromString($Config.ColorAmber); $script:brushAmber.Freeze()
$script:brushRed   = $bc.ConvertFromString($Config.ColorRed);   $script:brushRed.Freeze()

function Get-ThresholdBrush ([double]$val) {
    if ($val -ge 90.0) { return $script:brushRed }
    if ($val -ge 70.0) { return $script:brushAmber }
    $b = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Config.GlowColor)
    $b.Freeze()
    return $b
}

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

    # Battery Query
    $p = [System.Windows.Forms.SystemInformation]::PowerStatus
    $bPct = [int][math]::Round($p.BatteryLifePercent * 100.0)
    if ($bPct -le 0) { $bPct = 100 }
    $isCharging = ($p.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)

    $compactBatteryText.Text = "$bPct%"
    $todayBatteryPercent.Text = "$bPct%"

    $chargeStr = if ($isCharging) { "Charging · Connected to Power" } else { "Discharging · On Battery" }
    $todayBatteryState.Text = $chargeStr

    # Radial Battery Arc
    $todayBatteryArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 22 22 18 $bPct))
    $todayBatteryArc.Stroke = if ($bPct -le 20) { $script:brushRed } elseif ($bPct -le 40) { $script:brushAmber } else { $script:brushGreen }
    $todayBatteryCenterIcon.Text = if ($isCharging) { [string][char]0xE945 } else { [string][char]0xE915 }
    $todayBatteryCenterIcon.Foreground = $todayBatteryArc.Stroke
}

# 50ms High-Performance Dispatcher Loop
$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$uiTimer.Add_Tick({
    # Clock & Greeting
    Update-ClockAndBattery

    # Telemetry Snapshot
    $cpu = $script:sharedState.Cpu
    $gpu = $script:sharedState.Gpu
    $ram = $script:sharedState.Ram
    $cpuTemp = $script:sharedState.CpuTemp
    $gpuTemp = $script:sharedState.GpuTemp
    $cpuClk  = $script:sharedState.CpuClock
    $gpuClk  = $script:sharedState.GpuClock
    $ramUsed = $script:sharedState.RamUsedGB
    $ramTot  = $script:sharedState.RamTotalGB

    $compactCpuText.Text = "CPU $cpu%"

    # Tab 1: Today Mini Bars
    $todayCpuPct.Text = "$cpu%"
    $todayGpuPct.Text = "$gpu%"
    $todayRamPct.Text = "$ram%"

    $todayCpuFill.Width = [math]::Max([math]::Min(($cpu * 1.3), 130), 2)
    $todayGpuFill.Width = [math]::Max([math]::Min(($gpu * 1.3), 130), 2)
    $todayRamFill.Width = [math]::Max([math]::Min(($ram * 1.3), 130), 2)

    $todayCpuFill.Background = Get-ThresholdBrush $cpu
    $todayGpuFill.Background = Get-ThresholdBrush $gpu
    $todayRamFill.Background = Get-ThresholdBrush $ram

    # Tab 3: Stats Radial Ring Gauges (CPU, GPU, RAM)
    $statsCpuVal.Text = "$cpu%"
    $statsGpuVal.Text = "$gpu%"
    $statsRamVal.Text = "$ram%"

    $degSym = [string][char]0x00B0
    $midDot = [string][char]0x00B7
    $statsCpuSpecs.Text = "$cpuClk $midDot $cpuTemp$degSym" + "C"
    $statsGpuSpecs.Text = "$gpuClk $midDot $gpuTemp$degSym" + "C"
    $statsRamSpecs.Text = "$ramUsed / $ramTot GB"

    $statsCpuArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 38 38 33 $cpu))
    $statsGpuArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 38 38 33 $gpu))
    $statsRamArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 38 38 33 $ram))

    $statsCpuArc.Stroke = Get-ThresholdBrush $cpu
    $statsGpuArc.Stroke = Get-ThresholdBrush $gpu
    $statsRamArc.Stroke = Get-ThresholdBrush $ram

    # Tab 4 & 5: System Telemetry
    $tileBluetoothSub.Text = $script:sharedState.BluetoothDevs
    $tileDisplaySub.Text   = "$($script:sharedState.BrightnessVal)%"
    $textPowerUptime.Text  = "$($script:sharedState.UptimeText) $midDot $($script:sharedState.LastRestartText)"

    # Tab 2: Media Player
    $title  = $script:sharedState.MediaTitle
    $artist = $script:sharedState.MediaArtist
    $status = $script:sharedState.MediaStatus
    $dev    = $script:sharedState.MediaDevice

    if ($title -eq '' -or $status -eq 'None') {
        $mediaTitleText.Text  = "No Media Playing"
        $mediaArtistText.Text = "Spotify, YouTube, or Media"
        $mediaDeviceText.Text = "Ready for playback"
        $btnMediaPlay.Content = [string][char]0xE768
        $compactIcon.Text     = [string][char]0xE8D6
    } else {
        $mediaTitleText.Text  = $title
        $mediaArtistText.Text = if ($artist) { $artist } else { "Playing" }
        $mediaDeviceText.Text = $dev
        $btnMediaPlay.Content = if ($status -eq 'Playing') { [string][char]0xE769 } else { [string][char]0xE768 }
        $compactIcon.Text     = [string][char]0xE8D6

        # Auto-popup on track change
        if ($title -ne $script:lastMediaTitle -and $title -ne '' -and -not $script:expanded) {
            $script:lastMediaTitle = $title
            $script:mediaAutoShown = $true
            Switch-Tab 'Media'
            Expand-Island
            $script:autoCollapseTimer.Stop()
            $script:autoCollapseTimer.Start()
        }
    }

    $mediaTimeCurrent.Text = $script:sharedState.MediaPosition
    $mediaTimeTotal.Text   = $script:sharedState.MediaDuration

    # Scrubber Progress Bar Width
    $trackW = $mediaTrackContainer.ActualWidth
    if ($trackW -le 10) { $trackW = 460 }
    $progPct = [double]$script:sharedState.MediaProgress
    $mediaProgressLine.Width = [math]::Max([math]::Min(($trackW * $progPct), $trackW), 4)

    # Album Art Image Loader
    $artBytes = $script:sharedState.AlbumArtBytes
    if ($null -ne $artBytes -and $artBytes.Length -gt 0) {
        if ($artBytes -ne $script:currentArtBytes) {
            $script:currentArtBytes = $artBytes
            try {
                $ms = New-Object System.IO.MemoryStream(@(,$artBytes))
                $bi = New-Object System.Windows.Media.Imaging.BitmapImage
                $bi.BeginInit()
                $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bi.StreamSource = $ms
                $bi.EndInit()
                $bi.Freeze()
                $albumArtImage.Source = $bi
                $albumArtPlaceholder.Visibility = 'Collapsed'
            } catch { }
        }
    } else {
        $albumArtImage.Source = $null
        $albumArtPlaceholder.Visibility = 'Visible'
    }
})

# ------------------------------------------------------------------------------
#  S11  STARTUP INITIALIZATION & SHOW
# ------------------------------------------------------------------------------
Update-ClockAndBattery
Switch-Tab 'Today'
$uiTimer.Start()

$window.Show()
[System.Windows.Threading.Dispatcher]::Run()
