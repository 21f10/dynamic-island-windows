# ==============================================================================
#  Dynamic Island for Windows  -  v4.2 (Executive Edition)
#  Hitodama Dynamic Island Audio Deck | 60 FPS Wavy Scrubber | Direct Hardware Controls
# ==============================================================================

# Global Error Suppression (Zero Red Crash Windows)
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
$ConfigPath = (Join-Path $PSScriptRoot 'config.json')

# Default Configuration Hashtable
$Config = @{
    # --- Screen Positioning ---
    X               = $null
    Y               = $null

    # --- Layout Geometry (px) ---
    IslandWidth     = 255
    IslandHeight    = 38
    ExpandedWidth   = 490
    ExpandedHeight  = 255
    CornerRadius    = 22
    ScreenTopMargin = 8
    WindowWidth     = 550
    WindowHeight    = 320

    # --- Visual Customization & Aura ---
    GlowColor       = '#00E5FF'          # Active Glow / Aura color
    GlowRadius      = 28                 # Outer glow blur radius
    GlowOpacity     = 0.65               # Outer glow opacity
    BackgroundColor = '#F50F0F14'        # Frosted obsidian background
    CardColor       = '#14141E'          # Modular card fill
    CardBorderColor = '#25FFFFFF'        # Glass border
    TextColor       = '#FFFFFFFF'        # Primary text
    SubtextColor    = '#FFA0A0B2'        # Subdued gray text
    AccentPurple    = '#FFA855F7'        # GPU accent
    AccentGreen     = '#FF00E676'        # Emerald accent
    WarnColor       = '#FFFFB300'        # Amber warning (>75%)
    CritColor       = '#FFFF1744'        # Crimson critical (>88% or batt <20%)

    # --- Animation Timing ---
    ExpandMs        = 220
    CollapseMs      = 200
    CollapseDelay   = 320
    MediaPopupMs    = 4000

    # --- Module Toggles (Tabs & Widgets) ---
    Tabs            = @{
        Today       = $true
        Media       = $true
        Stats       = $true
        Controls    = $true
        Power       = $true
    }
    StatsModules    = @{
        Cpu         = $true
        Gpu         = $true
        Ram         = $true
        Battery     = $true
    }

    # --- Feature Toggles ---
    EnableSMTC        = $true
    EnableDynamicGlow = $true
    EnableVolumeScroll= $true
}

# Load saved configuration from config.json if present
if (Test-Path $ConfigPath) {
    try {
        $saved = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($null -ne $saved) {
            if ($null -ne $saved.X) { $Config.X = [double]$saved.X }
            if ($null -ne $saved.Y) { $Config.Y = [double]$saved.Y }
            if ($null -ne $saved.GlowColor -and $saved.GlowColor -match '^#[0-9A-Fa-f]{6}$') { $Config.GlowColor = $saved.GlowColor }
            if ($null -ne $saved.GlowRadius) { $Config.GlowRadius = [int]$saved.GlowRadius }
            if ($null -ne $saved.GlowOpacity) { $Config.GlowOpacity = [double]$saved.GlowOpacity }
            if ($null -ne $saved.Tabs) {
                if ($null -ne $saved.Tabs.Today)    { $Config.Tabs.Today    = [bool]$saved.Tabs.Today }
                if ($null -ne $saved.Tabs.Media)    { $Config.Tabs.Media    = [bool]$saved.Tabs.Media }
                if ($null -ne $saved.Tabs.Stats)    { $Config.Tabs.Stats    = [bool]$saved.Tabs.Stats }
                if ($null -ne $saved.Tabs.Controls) { $Config.Tabs.Controls = [bool]$saved.Tabs.Controls }
                if ($null -ne $saved.Tabs.Power)    { $Config.Tabs.Power    = [bool]$saved.Tabs.Power }
            }
            if ($null -ne $saved.StatsModules) {
                if ($null -ne $saved.StatsModules.Cpu) { $Config.StatsModules.Cpu = [bool]$saved.StatsModules.Cpu }
                if ($null -ne $saved.StatsModules.Gpu) { $Config.StatsModules.Gpu = [bool]$saved.StatsModules.Gpu }
                if ($null -ne $saved.StatsModules.Ram) { $Config.StatsModules.Ram = [bool]$saved.StatsModules.Ram }
            }
        }
    } catch { }
}

function Save-Config {
    try {
        $Config | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding UTF8 -Force
    } catch { }
}

# ------------------------------------------------------------------------------
#  S2  NATIVE INTEROP (Hardware Volume Keys & System Telemetry)
# ------------------------------------------------------------------------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class IslandNative {
    private const byte VK_VOLUME_MUTE = 0xAD;
    private const byte VK_VOLUME_DOWN = 0xAE;
    private const byte VK_VOLUME_UP   = 0xAF;
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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private class MEMORYSTATUSEX {
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
    private static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

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
    MediaTitle     = ''
    MediaArtist    = ''
    MediaStatus    = 'None'
    MediaDevice    = 'Headphones (NuR Partybox 165)'
    MediaPosition  = '0:54'
    MediaDuration  = '3:13'
    MediaProgress  = 0.35
    AlbumArtBytes  = $null
    LastThumbTitle = ''
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
        } catch { }

        # 2. GPU Telemetry
        try {
            $c = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop
            $sum = ($c.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
            $state.Gpu = [int][math]::Min([math]::Round($sum), 100)
        } catch { $state.Gpu = 0 }

        # 3. RAM Telemetry
        try {
            $state.Ram = [int][IslandNative]::GetMemoryLoad()
        } catch { }

        # 4. WinRT SMTC Media Session & Live Timeline Extraction
        $sessionHandled = $false
        if ($smtcReady -and $null -ne $sessionMgr) {
            try {
                $session = $sessionMgr.GetCurrentSession()
                if ($null -ne $session) {
                    $pbInfo = $session.GetPlaybackInfo()
                    $st = $pbInfo.PlaybackStatus.ToString()
                    $state.MediaStatus = if ($st -in 'Playing','Paused','Stopped') { $st } else { 'None' }

                    # Timeline extraction (Position, Duration, Progress)
                    try {
                        $tl = $session.GetTimelineProperties()
                        if ($null -ne $tl) {
                            $pos = $tl.Position
                            $end = $tl.EndTime
                            if ($end.TotalSeconds -gt 0) {
                                $state.MediaPosition = "$([int]$pos.TotalMinutes):$($pos.Seconds.ToString('00'))"
                                $state.MediaDuration = "$([int]$end.TotalMinutes):$($end.Seconds.ToString('00'))"
                                $state.MediaProgress = [math]::Min([math]::Max(($pos.TotalSeconds / $end.TotalSeconds), 0.05), 0.96)
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
                            $sessionHandled = $true

                            # Device source name
                            $appId = $session.SourceAppUserModelId
                            if ($appId -match 'spotify') { $state.MediaDevice = 'Spotify • Headphones (NuR Partybox 165)' }
                            elseif ($appId -match 'edge|chrome') { $state.MediaDevice = 'Browser • Headphones (NuR Partybox 165)' }
                            else { $state.MediaDevice = 'Headphones (NuR Partybox 165)' }

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
                                                $rawBytes = New-Object byte[] ([int]$stream.Size)
                                                $dr.ReadBytes($rawBytes)
                                                $state.AlbumArtBytes = $rawBytes
                                            }
                                            $dr.Dispose()
                                            $stream.Dispose()
                                        } else {
                                            $state.AlbumArtBytes = $null
                                        }
                                    }
                                } catch {
                                    $state.AlbumArtBytes = $null
                                }
                            } elseif (-not $props.Thumbnail) {
                                $state.AlbumArtBytes = $null
                                $state.LastThumbTitle = ''
                            }
                        }
                    }
                }
            } catch { }
        }

        # Fallback Window Title Scraping (Spotify, Chrome, Edge, Firefox)
        if (-not $sessionHandled) {
            try {
                $procs = Get-Process -Name spotify, msedge, chrome, firefox, brave, opera -ErrorAction SilentlyContinue |
                         Where-Object { $_.MainWindowTitle -match ' - | · | • ' -or $_.MainWindowTitle.Length -gt 3 }
                if ($procs) {
                    $winTitle = $procs[0].MainWindowTitle
                    if ($winTitle -match '^(.+?)\s*[-·•]\s*(.+)$') {
                        $state.MediaArtist = $matches[1].Trim()
                        $state.MediaTitle  = $matches[2].Trim()
                    } else {
                        $state.MediaTitle  = $winTitle
                        $state.MediaArtist = $procs[0].ProcessName
                    }
                    $state.MediaStatus   = 'Playing'
                    $state.MediaDevice   = "Headphones (NuR Partybox 165)"
                    $state.AlbumArtBytes = $null
                } else {
                    $state.MediaStatus   = 'None'
                    $state.MediaTitle    = ''
                    $state.MediaArtist   = ''
                    $state.AlbumArtBytes = $null
                }
            } catch { }
        }

        Start-Sleep -Milliseconds 400
    }
})
$null = $script:bgRunspace.AddArgument($script:sharedState)
$script:bgHandle = $script:bgRunspace.BeginInvoke()

# Helper for asynchronous media control actions
function Send-MediaCommandAsync ([string]$Cmd) {
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        try {
            Add-Type -AssemblyName System.Runtime.WindowsRuntime
            [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
            $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
                $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
            })[0]
            $mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
            $mgrTask = $asTask.MakeGenericMethod($mgrType).Invoke($null, @($mgrType::RequestAsync()))
            if ($mgrTask.Wait(1500)) {
                $sess = $mgrTask.Result.GetCurrentSession()
                if ($null -ne $sess) {
                    switch ($Cmd) {
                        'PlayPause' { [void]$sess.TryTogglePlayPauseAsync() }
                        'Previous'  { [void]$sess.TrySkipPreviousAsync() }
                        'Next'      { [void]$sess.TrySkipNextAsync() }
                    }
                }
            }
        } catch { }
    })
}

# ------------------------------------------------------------------------------
#  S4  WPF XAML INTERFACE (Executive Glass Deck & Modern Hitodama UI)
# ------------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="{x:Null}"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False"
        ResizeMode="NoResize"
        RenderOptions.BitmapScalingMode="HighQuality"
        RenderOptions.EdgeMode="Aliased"
        TextOptions.TextRenderingMode="ClearType"
        TextOptions.TextFormattingMode="Display"
        Width="$($Config.WindowWidth)" Height="$($Config.WindowHeight)">

  <Window.Resources>
    <!-- Cylindrical Rounded Pill Tab Button Style -->
    <Style x:Key="TabPillButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="$($Config.SubtextColor)"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="TabBorder"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="16"
                    Padding="12,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="TabBorder" Property="Background" Value="#26FFFFFF"/>
                <Setter Property="Foreground" Value="$($Config.GlowColor)"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="TabBorder" Property="Background" Value="#33FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- iOS / Win11 Toggle Switch Style -->
    <Style x:Key="Win11ToggleSwitch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Foreground" Value="#EEEEF4"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Border x:Name="Track" Width="36" Height="18" CornerRadius="9" Background="#262638" BorderBrush="#33FFFFFF" BorderThickness="1">
                <Ellipse x:Name="Thumb" Width="12" Height="12" Fill="#FFFFFF" HorizontalAlignment="Left" Margin="2,0,0,0">
                  <Ellipse.Effect>
                    <DropShadowEffect BlurRadius="4" ShadowDepth="1" Opacity="0.3" Color="#000000"/>
                  </Ellipse.Effect>
                </Ellipse>
              </Border>
              <ContentPresenter Content="{TemplateBinding Content}" Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="$($Config.GlowColor)"/>
                <Setter TargetName="Track" Property="BorderBrush" Value="$($Config.GlowColor)"/>
                <Setter TargetName="Thumb" Property="Margin" Value="20,0,0,0"/>
                <Setter TargetName="Thumb" Property="Fill" Value="#0F0F14"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Modern Glow Slider Style -->
    <Style x:Key="ModernGlowSlider" TargetType="Slider">
      <Setter Property="Stylus.IsPressAndHoldEnabled" Value="False"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="$($Config.GlowColor)"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid VerticalAlignment="Center">
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="{x:Static Slider.DecreaseLarge}">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton">
                        <Border Background="{TemplateBinding Foreground}" Height="4" CornerRadius="2"/>
                      </ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border Width="12" Height="12" CornerRadius="6" Background="#FFFFFF" BorderBrush="{TemplateBinding Foreground}" BorderThickness="2">
                          <Border.Effect>
                            <DropShadowEffect BlurRadius="6" ShadowDepth="0" Color="$($Config.GlowColor)" Opacity="0.8"/>
                          </Border.Effect>
                        </Border>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="{x:Static Slider.IncreaseLarge}">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton">
                        <Border Background="#262638" Height="4" CornerRadius="2"/>
                      </ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Modern Dark Glass Context Menu Style -->
    <Style x:Key="ModernContextMenu" TargetType="ContextMenu">
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Grid.IsSharedSizeScope" Value="True"/>
      <Setter Property="HasDropShadow" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ContextMenu">
            <Border Background="#161622"
                    BorderBrush="#2C2C3E"
                    BorderThickness="1"
                    CornerRadius="14"
                    Padding="6">
              <Border.Effect>
                <DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.65" Color="#000000"/>
              </Border.Effect>
              <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Modern Dark Glass Menu Item Style -->
    <Style x:Key="ModernMenuItem" TargetType="MenuItem">
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Foreground" Value="#EEEEF4"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="Medium"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="ItemBorder"
                    Background="Transparent"
                    CornerRadius="8"
                    Padding="10,6"
                    Margin="0,1">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="24"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <ContentPresenter x:Name="IconHost" Grid.Column="0" Content="{TemplateBinding Icon}"
                                  VerticalAlignment="Center" HorizontalAlignment="Left"/>
                <ContentPresenter x:Name="HeaderHost" Grid.Column="1" Content="{TemplateBinding Header}"
                                  VerticalAlignment="Center" Margin="8,0,10,0"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="#252538"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#66FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Modern Separator Style -->
    <Style TargetType="Separator">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Separator">
            <Border Height="1" Background="#242436" Margin="4,4"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid HorizontalAlignment="Center" VerticalAlignment="Top">

    <!-- Glowing Outer Shell -->
    <Border x:Name="GlowBorder"
            CornerRadius="$($Config.CornerRadius)"
            Width="$($Config.IslandWidth)" Height="$($Config.IslandHeight)"
            Margin="0,$($Config.ScreenTopMargin),0,0"
            HorizontalAlignment="Center" VerticalAlignment="Top">
      <Border.ContextMenu>
        <ContextMenu Style="{StaticResource ModernContextMenu}">
          <MenuItem x:Name="MenuResetPos" Header="Reset Position to Top Center" Style="{StaticResource ModernMenuItem}">
            <MenuItem.Icon>
              <TextBlock x:Name="MenuResetIcon" Text="&#xE895;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.GlowColor)"/>
            </MenuItem.Icon>
          </MenuItem>
          <Separator/>
          <MenuItem x:Name="MenuQuit" Header="Quit Dynamic Island" Style="{StaticResource ModernMenuItem}">
            <MenuItem.Icon>
              <TextBlock Text="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#FF5252"/>
            </MenuItem.Icon>
          </MenuItem>
        </ContextMenu>
      </Border.ContextMenu>
      <Border.Effect>
        <DropShadowEffect x:Name="GlowFx"
                          Color="$($Config.GlowColor)"
                          BlurRadius="$($Config.GlowRadius)"
                          ShadowDepth="0"
                          Opacity="$($Config.GlowOpacity)"
                          Direction="0"/>
      </Border.Effect>

      <!-- Main Pill Container -->
      <Border x:Name="Pill"
              Background="$($Config.BackgroundColor)"
              BorderBrush="$($Config.CardBorderColor)"
              BorderThickness="1"
              CornerRadius="$($Config.CornerRadius)"
              ClipToBounds="True">

        <Grid>

          <!-- ============================================================= -->
          <!-- 1. COMPACT PILL VIEW (Default idle state)                      -->
          <!-- ============================================================= -->
          <Grid x:Name="CompactBar" Height="$($Config.IslandHeight)" VerticalAlignment="Top" Margin="10,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
              <!-- Mini Icon (Clock or Music glyph) -->
              <TextBlock x:Name="CompactIcon" Text="&#xE823;" FontFamily="Segoe MDL2 Assets"
                         FontSize="12" Foreground="$($Config.GlowColor)"
                         VerticalAlignment="Center" Margin="0,0,8,0"/>

              <!-- Time -->
              <TextBlock x:Name="CompactTime" Text="12:00 PM"
                         FontFamily="Segoe UI Variable Display, Segoe UI"
                         FontSize="13" FontWeight="SemiBold"
                         Foreground="$($Config.TextColor)"
                         VerticalAlignment="Center"/>

              <!-- Separator -->
              <TextBlock Text=" | " Foreground="#44FFFFFF" VerticalAlignment="Center" Margin="6,0"/>

              <!-- Battery Glyph + % -->
              <TextBlock x:Name="CompactBattIcon" Text="&#xEA81;" FontFamily="Segoe MDL2 Assets"
                         FontSize="12" Foreground="$($Config.AccentGreen)"
                         VerticalAlignment="Center" Margin="0,0,4,0"/>
              <TextBlock x:Name="CompactBattText" Text="100%"
                         FontFamily="Segoe UI Variable Text, Segoe UI"
                         FontSize="12" Foreground="$($Config.TextColor)"
                         VerticalAlignment="Center"/>

              <!-- Separator -->
              <TextBlock Text=" | " Foreground="#44FFFFFF" VerticalAlignment="Center" Margin="6,0"/>

              <!-- Load mini-badge -->
              <TextBlock x:Name="CompactLoadText" Text="0%"
                         FontFamily="Segoe UI Variable Text, Segoe UI"
                         FontSize="12" Foreground="$($Config.SubtextColor)"
                         VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>

          <!-- ============================================================= -->
          <!-- 2. EXPANDED DASHBOARD VIEW (Hitodama Executive UI)           -->
          <!-- ============================================================= -->
          <Grid x:Name="ExpandedCard" Opacity="0" Visibility="Collapsed" Margin="14,10,14,12">
            <Grid.RowDefinitions>
              <!-- Row 0: Tab Navigation Header -->
              <RowDefinition Height="Auto"/>
              <!-- Row 1: Active Tab Content Area -->
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Navigation Bar Header -->
            <Grid Grid.Row="0" Margin="0,0,0,10">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <!-- Left Status Dot Indicator -->
              <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                <Ellipse x:Name="StatusDot" Width="7" Height="7" Fill="$($Config.GlowColor)" Margin="2,0,8,0"/>
                <TextBlock Text="ISLAND" Foreground="#55FFFFFF"
                           FontFamily="Segoe UI Variable Display, Segoe UI"
                           FontSize="10" FontWeight="Bold" VerticalAlignment="Center"/>
              </StackPanel>

              <!-- Center Rounded Pill Tabs -->
              <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center">
                <Button x:Name="TabBtnToday" Content="Today" Style="{StaticResource TabPillButtonStyle}"/>
                <Button x:Name="TabBtnMedia" Content="Media" Style="{StaticResource TabPillButtonStyle}"/>
                <Button x:Name="TabBtnStats" Content="Stats" Style="{StaticResource TabPillButtonStyle}"/>
                <Button x:Name="TabBtnControls" Content="Controls" Style="{StaticResource TabPillButtonStyle}"/>
                <Button x:Name="TabBtnPower" Content="Power" Style="{StaticResource TabPillButtonStyle}"/>
              </StackPanel>

              <!-- Right Actions: Settings Gear & Pin Toggle -->
              <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="BtnSettings" Content="&#xE713;" FontFamily="Segoe MDL2 Assets"
                        FontSize="12" Foreground="$($Config.SubtextColor)"
                        Background="Transparent" BorderThickness="0"
                        Padding="6,4" Cursor="Hand" Focusable="False"
                        ToolTip="Customization &amp; Aura Settings" VerticalAlignment="Center" Margin="0,0,2,0"/>
                <Button x:Name="BtnPin" Content="&#xE718;" FontFamily="Segoe MDL2 Assets"
                        FontSize="12" Foreground="$($Config.SubtextColor)"
                        Background="Transparent" BorderThickness="0"
                        Padding="6,4" Cursor="Hand" Focusable="False"
                        ToolTip="Pin / Unpin Open" VerticalAlignment="Center"/>
              </StackPanel>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 1: TODAY VIEW (Smart Dashboard & Radial Battery)        -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewToday" Grid.Row="1" Visibility="Visible">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="1.1*"/>
                <ColumnDefinition Width="1.3*"/>
              </Grid.ColumnDefinitions>

              <!-- Left: Big Clock, Date & Smart Greeting Card -->
              <Border Grid.Column="0" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Margin="0,0,6,0" Padding="12,12">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock x:Name="TodayClockText" Text="12:00 PM"
                             Foreground="$($Config.TextColor)"
                             FontFamily="Segoe UI Variable Display, Segoe UI"
                             FontSize="26" FontWeight="Bold"
                             HorizontalAlignment="Center"/>
                  <TextBlock x:Name="TodayDateText" Text="Friday, 6 November"
                             Foreground="$($Config.SubtextColor)"
                             FontFamily="Segoe UI Variable Text, Segoe UI"
                             FontSize="12" HorizontalAlignment="Center" Margin="0,3,0,0"/>

                  <!-- Smart Greeting Pill with Weather / Sun / Moon Icon -->
                  <Border Background="#1AFFFFFF" CornerRadius="12" HorizontalAlignment="Center" Margin="0,8,0,0" Padding="10,4">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                      <TextBlock x:Name="TodayGreetingIcon" Text="&#xE708;" FontFamily="Segoe MDL2 Assets"
                                 FontSize="12" Foreground="$($Config.GlowColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock x:Name="TodayGreeting" Text="Good Evening" Foreground="$($Config.GlowColor)"
                                 FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
                    </StackPanel>
                  </Border>
                </StackPanel>
              </Border>

              <!-- Right: Battery Radial Ring Gauge & System Micro Cards -->
              <Border Grid.Column="1" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Margin="6,0,0,0" Padding="12,10">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                  </Grid.RowDefinitions>

                  <!-- Top: Circular Radial Ring Gauge for Battery -->
                  <Grid Grid.Row="0" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="70"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Circular Arc Battery Gauge (70x70) -->
                    <Grid Grid.Column="0" Width="70" Height="70" HorizontalAlignment="Center" VerticalAlignment="Center">
                      <Path Stroke="#252538" StrokeThickness="5" Data="M 35,6 A 29,29 0 1,1 34.99,6"/>
                      <Path x:Name="TodayBattArcPath" Stroke="$($Config.AccentGreen)" StrokeThickness="5"
                            StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                      <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                        <TextBlock x:Name="TodayBattIcon" Text="&#xEA93;" FontFamily="Segoe MDL2 Assets"
                                   FontSize="13" Foreground="$($Config.AccentGreen)" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TodayBattPct" Text="80%" Foreground="$($Config.TextColor)"
                                   FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12" FontWeight="Bold"
                                   HorizontalAlignment="Center" Margin="0,1,0,0"/>
                      </StackPanel>
                    </Grid>

                    <!-- Battery Status & AC Text -->
                    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="8,0,0,0">
                      <TextBlock Text="POWER &amp; BATTERY" Foreground="#777788"
                                 FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="9" FontWeight="Bold"/>
                      <TextBlock x:Name="TodayBattStatus" Text="AC Connected | Charging"
                                 Foreground="$($Config.AccentGreen)" FontFamily="Segoe UI Variable Text, Segoe UI"
                                 FontSize="11" FontWeight="SemiBold" Margin="0,2,0,0"/>
                      <TextBlock Text="System Ready" Foreground="#55FFFFFF" FontSize="10" Margin="0,1,0,0"/>
                    </StackPanel>
                  </Grid>

                  <!-- Bottom: 3 System Micro Glass Cards (CPU, GPU, RAM) -->
                  <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0" Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1" CornerRadius="10" Padding="4,5" Margin="0,0,3,0">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="CPU" Foreground="#888899" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TodayMiniCpu" Text="0%" Foreground="$($Config.GlowColor)" FontWeight="Bold" FontSize="12" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>

                    <Border Grid.Column="1" Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1" CornerRadius="10" Padding="4,5" Margin="2,0,2,0">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="GPU" Foreground="#888899" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TodayMiniGpu" Text="0%" Foreground="$($Config.AccentPurple)" FontWeight="Bold" FontSize="12" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>

                    <Border Grid.Column="2" Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1" CornerRadius="10" Padding="4,5" Margin="3,0,0,0">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="RAM" Foreground="#888899" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TodayMiniRam" Text="0%" Foreground="$($Config.AccentGreen)" FontWeight="Bold" FontSize="12" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>
                  </Grid>

                </Grid>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 2: MEDIA VIEW (Hitodama Reference Style with Wavy Scrubber) -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewMedia" Grid.Row="1" Visibility="Collapsed">
              <Border Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,10">
                <Grid>
                  <Grid.RowDefinitions>
                    <!-- Row 0: Device Source Tag (Headphones NuR Partybox 165) -->
                    <RowDefinition Height="Auto"/>
                    <!-- Row 1: Cover Art, Info & Large Squircle Controls -->
                    <RowDefinition Height="Auto"/>
                    <!-- Row 2: Wavy Scrubber Progress Timeline -->
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>

                  <!-- Row 0: Active Audio Output Device Pill -->
                  <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="2,0,0,8" VerticalAlignment="Center">
                    <TextBlock x:Name="MediaDeviceIcon" Text="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                               FontSize="11" Foreground="$($Config.GlowColor)" Margin="0,0,6,0" VerticalAlignment="Center"/>
                    <TextBlock x:Name="MediaDeviceText" Text="Headphones (NuR Partybox 165)"
                               Foreground="$($Config.SubtextColor)" FontFamily="Segoe UI Variable Text, Segoe UI"
                               FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
                  </StackPanel>

                  <!-- Row 1: Squircle Cover Art + Info + Big Squircle Play Button -->
                  <Grid Grid.Row="1" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                      <!-- Col 0: Squircle Album Art -->
                      <ColumnDefinition Width="64"/>
                      <!-- Col 1: Title & Artist -->
                      <ColumnDefinition Width="*"/>
                      <!-- Col 2: Previous | Big Play | Next -->
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Squircle Album Artwork (58x58, CornerRadius 14) -->
                    <Border Grid.Column="0" Width="58" Height="58" CornerRadius="14"
                            Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1"
                            HorizontalAlignment="Left" VerticalAlignment="Center">
                      <Border.Effect>
                        <DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.35" Color="#000000"/>
                      </Border.Effect>
                      <Grid>
                        <Image x:Name="AlbumArtImage" Width="58" Height="58" Stretch="UniformToFill" Visibility="Collapsed">
                          <Image.Clip>
                            <RectangleGeometry Rect="0,0,58,58" RadiusX="14" RadiusY="14"/>
                          </Image.Clip>
                        </Image>

                        <Border x:Name="AlbumArtFallback" CornerRadius="14" Visibility="Visible">
                          <Border.Background>
                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                              <GradientStop Color="#2A1624" Offset="0"/>
                              <GradientStop Color="#140E18" Offset="1"/>
                            </LinearGradientBrush>
                          </Border.Background>
                          <TextBlock Text="&#xE8D6;" FontFamily="Segoe MDL2 Assets" FontSize="24"
                                     Foreground="$($Config.GlowColor)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </Grid>
                    </Border>

                    <!-- Title & Artist -->
                    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="10,0,10,0">
                      <TextBlock x:Name="MediaTitleText" Text="No Media Playing"
                                 Foreground="$($Config.TextColor)"
                                 FontFamily="Segoe UI Variable Display, Segoe UI"
                                 FontSize="15" FontWeight="Bold"
                                 TextTrimming="CharacterEllipsis"/>
                      <TextBlock x:Name="MediaArtistText" Text="Ready for Spotify, YouTube, or Media"
                                 Foreground="$($Config.SubtextColor)"
                                 FontFamily="Segoe UI Variable Text, Segoe UI"
                                 FontSize="12" FontWeight="SemiBold" Margin="0,2,0,0"
                                 TextTrimming="CharacterEllipsis"/>
                    </StackPanel>

                    <!-- Controls: |<<  [ ▶ ]  >>| -->
                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                      <!-- Previous Button -->
                      <Button x:Name="BtnMediaPrev" Content="&#xE892;" FontFamily="Segoe MDL2 Assets"
                              FontSize="12" Foreground="$($Config.TextColor)"
                              Background="#201C28" BorderBrush="#26FFFFFF" BorderThickness="1"
                              Width="34" Height="34" Cursor="Hand" Focusable="False">
                        <Button.Template>
                          <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="17">
                              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                          </ControlTemplate>
                        </Button.Template>
                      </Button>

                      <!-- Big Squircle Accent Play/Pause Button -->
                      <Button x:Name="BtnMediaPlay" Content="&#xE768;" FontFamily="Segoe MDL2 Assets"
                              FontSize="16" Foreground="#141018"
                              Background="$($Config.GlowColor)" BorderThickness="0"
                              Width="50" Height="38" Margin="8,0" Cursor="Hand" Focusable="False">
                        <Button.Template>
                          <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="15">
                              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                          </ControlTemplate>
                        </Button.Template>
                      </Button>

                      <!-- Next Button -->
                      <Button x:Name="BtnMediaNext" Content="&#xE893;" FontFamily="Segoe MDL2 Assets"
                              FontSize="12" Foreground="$($Config.TextColor)"
                              Background="#201C28" BorderBrush="#26FFFFFF" BorderThickness="1"
                              Width="34" Height="34" Cursor="Hand" Focusable="False">
                        <Button.Template>
                          <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="17">
                              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                          </ControlTemplate>
                        </Button.Template>
                      </Button>
                    </StackPanel>
                  </Grid>

                  <!-- Row 2: Wavy Scrubber Progress Bar (0:54 ~~~~~~~•────── 3:13) -->
                  <Grid Grid.Row="2" Height="18" Margin="2,0,2,2">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Current Time -->
                    <TextBlock x:Name="MediaTimeCurrent" Grid.Column="0" Text="0:54"
                               Foreground="#888899" FontFamily="Segoe UI Variable Text, Segoe UI"
                               FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,8,0"/>

                    <!-- Wavy Progress Canvas -->
                    <Canvas x:Name="MediaWaveCanvas" Grid.Column="1" Height="16" VerticalAlignment="Center" ClipToBounds="True">
                      <!-- Left Wavy Played Path -->
                      <Path x:Name="MediaWaveProgress" Stroke="$($Config.GlowColor)" StrokeThickness="2.5"
                            StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                      <!-- Scrubber Handle Knob -->
                      <Ellipse x:Name="MediaWaveThumb" Width="8" Height="8" Fill="$($Config.GlowColor)" VerticalAlignment="Center"/>
                      <!-- Right Remaining Straight Track -->
                      <Path x:Name="MediaWaveRemaining" Stroke="#33FFFFFF" StrokeThickness="2"
                            StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    </Canvas>

                    <!-- Total Duration -->
                    <TextBlock x:Name="MediaTimeTotal" Grid.Column="2" Text="3:13"
                               Foreground="#888899" FontFamily="Segoe UI Variable Text, Segoe UI"
                               FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="8,0,0,0"/>
                  </Grid>

                </Grid>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 3: STATS VIEW (Ring Gauges)                             -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewStats" Grid.Row="1" Visibility="Collapsed">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <!-- CPU Gauge -->
              <Border Grid.Column="0" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Margin="0,0,4,0" Padding="8,10">
                <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                  <Grid Width="72" Height="72" HorizontalAlignment="Center">
                    <Path Stroke="#252538" StrokeThickness="5" Data="M 36,6 A 30,30 0 1,1 35.99,6"/>
                    <Path x:Name="CpuArcPath" Stroke="$($Config.GlowColor)" StrokeThickness="5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="StatsCpuPct" Text="0%" Foreground="$($Config.TextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" FontWeight="Bold"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                  <TextBlock Text="CPU LOAD" Foreground="#888899" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>

              <!-- GPU Gauge -->
              <Border Grid.Column="1" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Margin="2,0,2,0" Padding="8,10">
                <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                  <Grid Width="72" Height="72" HorizontalAlignment="Center">
                    <Path Stroke="#252538" StrokeThickness="5" Data="M 36,6 A 30,30 0 1,1 35.99,6"/>
                    <Path x:Name="GpuArcPath" Stroke="$($Config.AccentPurple)" StrokeThickness="5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="StatsGpuPct" Text="0%" Foreground="$($Config.TextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" FontWeight="Bold"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                  <TextBlock Text="GPU 3D" Foreground="#888899" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>

              <!-- RAM Gauge -->
              <Border Grid.Column="2" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Margin="4,0,0,0" Padding="8,10">
                <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                  <Grid Width="72" Height="72" HorizontalAlignment="Center">
                    <Path Stroke="#252538" StrokeThickness="5" Data="M 36,6 A 30,30 0 1,1 35.99,6"/>
                    <Path x:Name="RamArcPath" Stroke="$($Config.AccentGreen)" StrokeThickness="5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="StatsRamPct" Text="0%" Foreground="$($Config.TextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" FontWeight="Bold"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                  <TextBlock Text="MEMORY" Foreground="#888899" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 4: CONTROLS VIEW (Quick Settings & Hardware Volume Deck) -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewControls" Grid.Row="1" Visibility="Collapsed">
              <Border Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,12">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                  </Grid.RowDefinitions>

                  <!-- Row 0: Hardware Volume & Audio Output Deck -->
                  <Grid Grid.Row="0" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="1.3*"/>
                      <ColumnDefinition Width="1*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Volume Hardware Stepper Card -->
                    <Border Grid.Column="0" Background="#181824" CornerRadius="12" Padding="10,8" Margin="0,0,5,0">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="Auto"/>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                          <TextBlock Text="&#xE767;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.GlowColor)" Margin="0,0,6,0"/>
                          <TextBlock Text="System Volume" Foreground="#EEEEEE" FontSize="11" FontWeight="SemiBold"/>
                        </StackPanel>

                        <!-- Hardware Vol Buttons [-] and [+] that work on ALL Bluetooth/Headsets -->
                        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                          <Button x:Name="BtnVolDown" Content="-" Width="28" Height="24" Background="#262638" Foreground="#FFFFFF"
                                  FontWeight="Bold" FontSize="13" Margin="2,0" Cursor="Hand" Focusable="False" ToolTip="Volume Down">
                            <Button.Template>
                              <ControlTemplate TargetType="Button">
                                <Border Background="{TemplateBinding Background}" CornerRadius="6">
                                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                              </ControlTemplate>
                            </Button.Template>
                          </Button>
                          <Button x:Name="BtnVolUp" Content="+" Width="28" Height="24" Background="#262638" Foreground="#FFFFFF"
                                  FontWeight="Bold" FontSize="13" Margin="2,0" Cursor="Hand" Focusable="False" ToolTip="Volume Up">
                            <Button.Template>
                              <ControlTemplate TargetType="Button">
                                <Border Background="{TemplateBinding Background}" CornerRadius="6">
                                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                              </ControlTemplate>
                            </Button.Template>
                          </Button>
                          <Button x:Name="BtnMuteToggle" Content="Mute" Width="44" Height="24" Background="#262638" Foreground="#FFFFFF"
                                  FontSize="10" FontWeight="SemiBold" Margin="4,0,0,0" Cursor="Hand" Focusable="False">
                            <Button.Template>
                              <ControlTemplate TargetType="Button">
                                <Border Background="{TemplateBinding Background}" CornerRadius="6">
                                  <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                </Border>
                              </ControlTemplate>
                            </Button.Template>
                          </Button>
                        </StackPanel>
                      </Grid>
                    </Border>

                    <!-- Audio Output Switcher (Partybox vs Speakers) -->
                    <Button x:Name="BtnAudioDevices" Grid.Column="1" Height="40" Margin="5,0,0,0"
                            Background="#181824" BorderBrush="#25FFFFFF" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12">
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                              <TextBlock Text="&#xE7F6;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="$($Config.AccentPurple)" Margin="0,0,6,0"/>
                              <TextBlock Text="Sound Devices" Foreground="#FFFFFF" FontSize="11" FontWeight="SemiBold"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>
                  </Grid>

                  <!-- Row 1: Fast System Launcher Deck -->
                  <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Button x:Name="BtnActionBluetooth" Grid.Column="0" Margin="0,0,3,0" Height="38"
                            Background="#181824" BorderBrush="#25FFFFFF" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                              <TextBlock Text="&#xE702;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="$($Config.GlowColor)" Margin="0,0,5,0"/>
                              <TextBlock Text="Bluetooth" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnActionDisplay" Grid.Column="1" Margin="2,0,2,0" Height="38"
                            Background="#181824" BorderBrush="#25FFFFFF" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                              <TextBlock Text="&#xE706;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="$($Config.WarnColor)" Margin="0,0,5,0"/>
                              <TextBlock Text="Display" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnActionTaskMgr" Grid.Column="2" Margin="2,0,2,0" Height="38"
                            Background="#181824" BorderBrush="#25FFFFFF" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                              <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="$($Config.AccentGreen)" Margin="0,0,5,0"/>
                              <TextBlock Text="Task Mgr" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnActionExplorer" Grid.Column="3" Margin="3,0,0,0" Height="38"
                            Background="#181824" BorderBrush="#25FFFFFF" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                              <TextBlock Text="&#xEC50;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="$($Config.AccentPurple)" Margin="0,0,5,0"/>
                              <TextBlock Text="Explorer" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>
                  </Grid>

                </Grid>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 5: POWER VIEW                                           -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewPower" Grid.Row="1" Visibility="Collapsed">
              <Border Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,12">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                  </Grid.RowDefinitions>

                  <TextBlock Grid.Row="0" Text="SYSTEM POWER ACTIONS" Foreground="$($Config.SubtextColor)"
                             FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="10" FontWeight="Bold" Margin="0,0,0,10"/>

                  <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Button x:Name="BtnPowerLock" Grid.Column="0" Margin="0,0,3,0" Height="50"
                            Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="$($Config.GlowColor)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Lock" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,3,0,0"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnPowerSleep" Grid.Column="1" Margin="2,0,2,0" Height="50"
                            Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="$($Config.AccentPurple)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Sleep" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,3,0,0"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnPowerRestart" Grid.Column="2" Margin="2,0,2,0" Height="50"
                            Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE777;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="$($Config.WarnColor)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Restart" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,3,0,0"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnPowerShutdown" Grid.Column="3" Margin="3,0,0,0" Height="50"
                            Background="#181824" BorderBrush="#2A2A3C" BorderThickness="1" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE7E8;" FontFamily="Segoe MDL2 Assets" FontSize="15" Foreground="$($Config.CritColor)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Shut Down" Foreground="#FFFFFF" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,3,0,0"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>
                  </Grid>

                </Grid>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 6: SETTINGS & INLINE CUSTOMIZATION (Un-congested UX)    -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewSettings" Grid.Row="1" Visibility="Collapsed">
              <Border Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,12">
                <Grid>
                  <Grid.RowDefinitions>
                    <!-- Section 1: Color Presets & Hex -->
                    <RowDefinition Height="Auto"/>
                    <!-- Section 2: Glow Sliders -->
                    <RowDefinition Height="Auto"/>
                    <!-- Section 3: Navigation Tab Switches -->
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>

                  <!-- 1. AURA PRESETS & CUSTOM HEX -->
                  <Border Grid.Row="0" Background="#181824" CornerRadius="12" Padding="10,8" Margin="0,0,0,8">
                    <Grid>
                      <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                      </Grid.RowDefinitions>
                      <TextBlock Grid.Row="0" Text="THEME AURA ACCENT COLOR" Foreground="#888899"
                                 FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="9" FontWeight="Bold" Margin="0,0,0,6"/>
                      <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center">
                        <Button x:Name="SwatchCyan" Content="Cyan" Width="54" Height="24" Background="#FF00E5FF" Foreground="#000000" Margin="2,0" Cursor="Hand" Focusable="False" Style="{StaticResource TabPillButtonStyle}"/>
                        <Button x:Name="SwatchMagenta" Content="Pink" Width="54" Height="24" Background="#FFFF007F" Foreground="#FFFFFF" Margin="2,0" Cursor="Hand" Focusable="False" Style="{StaticResource TabPillButtonStyle}"/>
                        <Button x:Name="SwatchPurple" Content="Purple" Width="54" Height="24" Background="#FFA855F7" Foreground="#FFFFFF" Margin="2,0" Cursor="Hand" Focusable="False" Style="{StaticResource TabPillButtonStyle}"/>
                        <Button x:Name="SwatchEmerald" Content="Emerald" Width="58" Height="24" Background="#FF00E676" Foreground="#000000" Margin="2,0" Cursor="Hand" Focusable="False" Style="{StaticResource TabPillButtonStyle}"/>
                        <Button x:Name="SwatchAmber" Content="Amber" Width="54" Height="24" Background="#FFFFB300" Foreground="#000000" Margin="2,0" Cursor="Hand" Focusable="False" Style="{StaticResource TabPillButtonStyle}"/>
                        <Button x:Name="SwatchRed" Content="Red" Width="50" Height="24" Background="#FFFF1744" Foreground="#FFFFFF" Margin="2,0" Cursor="Hand" Focusable="False" Style="{StaticResource TabPillButtonStyle}"/>

                        <!-- Hex Input Pill -->
                        <TextBox x:Name="CustomHexInput" Text="$($Config.GlowColor)" Width="68" Height="24" Margin="8,0,3,0"
                                 Background="#14141E" Foreground="#FFFFFF" BorderBrush="#33FFFFFF" BorderThickness="1"
                                 FontFamily="Consolas, Segoe UI" FontSize="11" VerticalContentAlignment="Center" Padding="4,0"/>
                        <Button x:Name="BtnApplyHex" Content="Apply" Width="44" Height="24"
                                Background="#2A2A3E" Foreground="#FFFFFF" BorderThickness="0" Cursor="Hand" Focusable="False">
                          <Button.Template>
                            <ControlTemplate TargetType="Button">
                              <Border Background="{TemplateBinding Background}" CornerRadius="6">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                              </Border>
                            </ControlTemplate>
                          </Button.Template>
                        </Button>
                      </StackPanel>
                    </Grid>
                  </Border>

                  <!-- 2. GLOW SLIDERS (Spacious) -->
                  <Grid Grid.Row="1" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0" Background="#181824" CornerRadius="12" Padding="10,6" Margin="0,0,4,0">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="Auto"/>
                          <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0">
                          <TextBlock Text="Aura Glow Radius" Foreground="#888899" FontSize="10" FontWeight="SemiBold"/>
                          <TextBlock x:Name="GlowRadiusLabel" Text="28px" Foreground="#FFFFFF" FontSize="10" FontWeight="Bold" HorizontalAlignment="Right"/>
                        </Grid>
                        <Slider x:Name="GlowRadiusSlider" Style="{StaticResource ModernGlowSlider}" Grid.Row="1" Minimum="10" Maximum="50" Value="28" Margin="0,5,0,0"/>
                      </Grid>
                    </Border>

                    <Border Grid.Column="1" Background="#181824" CornerRadius="12" Padding="10,6" Margin="4,0,0,0">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="Auto"/>
                          <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0">
                          <TextBlock Text="Aura Glow Opacity" Foreground="#888899" FontSize="10" FontWeight="SemiBold"/>
                          <TextBlock x:Name="GlowOpacityLabel" Text="65%" Foreground="#FFFFFF" FontSize="10" FontWeight="Bold" HorizontalAlignment="Right"/>
                        </Grid>
                        <Slider x:Name="GlowOpacitySlider" Style="{StaticResource ModernGlowSlider}" Grid.Row="1" Minimum="20" Maximum="95" Value="65" Margin="0,5,0,0"/>
                      </Grid>
                    </Border>
                  </Grid>

                  <!-- 3. VISIBLE TABS (Spacious Win11 Switches) -->
                  <Border Grid.Row="2" Background="#181824" CornerRadius="12" Padding="10,6">
                    <Grid>
                      <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                      </Grid.RowDefinitions>
                      <TextBlock Grid.Row="0" Text="ACTIVE NAVIGATION TABS" Foreground="#888899"
                                 FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="9" FontWeight="Bold" Margin="0,0,0,4"/>
                      <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center">
                        <CheckBox x:Name="ToggleTabToday" Content="Today" Style="{StaticResource Win11ToggleSwitch}" IsChecked="True" Margin="6,0"/>
                        <CheckBox x:Name="ToggleTabMedia" Content="Media" Style="{StaticResource Win11ToggleSwitch}" IsChecked="True" Margin="6,0"/>
                        <CheckBox x:Name="ToggleTabStats" Content="Stats" Style="{StaticResource Win11ToggleSwitch}" IsChecked="True" Margin="6,0"/>
                        <CheckBox x:Name="ToggleTabControls" Content="Controls" Style="{StaticResource Win11ToggleSwitch}" IsChecked="True" Margin="6,0"/>
                        <CheckBox x:Name="ToggleTabPower" Content="Power" Style="{StaticResource Win11ToggleSwitch}" IsChecked="True" Margin="6,0"/>
                      </StackPanel>
                    </Grid>
                  </Border>

                </Grid>
              </Border>
            </Grid>

          </Grid>

        </Grid>
      </Border>
    </Border>

  </Grid>
</Window>
"@

# ------------------------------------------------------------------------------
#  S5  ELEMENT REFERENCES & STATE INITIALIZATION
# ------------------------------------------------------------------------------
$window          = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$glowBorder      = $window.FindName('GlowBorder')
$glowFx          = $window.FindName('GlowFx')
$pill            = $window.FindName('Pill')
$statusDot       = $window.FindName('StatusDot')
$compactBar      = $window.FindName('CompactBar')
$expandedCard    = $window.FindName('ExpandedCard')

# Modern Context Menu Elements
$menuResetPos    = $window.FindName('MenuResetPos')
$menuResetIcon   = $window.FindName('MenuResetIcon')
$menuQuit        = $window.FindName('MenuQuit')

# Compact Elements
$compactIcon     = $window.FindName('CompactIcon')
$compactTime     = $window.FindName('CompactTime')
$compactBattIcon = $window.FindName('CompactBattIcon')
$compactBattText = $window.FindName('CompactBattText')
$compactLoadText = $window.FindName('CompactLoadText')

# Header & Tabs
$tabBtnToday     = $window.FindName('TabBtnToday')
$tabBtnMedia     = $window.FindName('TabBtnMedia')
$tabBtnStats     = $window.FindName('TabBtnStats')
$tabBtnControls  = $window.FindName('TabBtnControls')
$tabBtnPower     = $window.FindName('TabBtnPower')
$btnSettings     = $window.FindName('BtnSettings')
$btnPin          = $window.FindName('BtnPin')

# Views
$viewToday       = $window.FindName('ViewToday')
$viewMedia       = $window.FindName('ViewMedia')
$viewStats       = $window.FindName('ViewStats')
$viewControls    = $window.FindName('ViewControls')
$viewPower       = $window.FindName('ViewPower')
$viewSettings    = $window.FindName('ViewSettings')

# Tab 1: Today Elements
$todayClockText     = $window.FindName('TodayClockText')
$todayDateText      = $window.FindName('TodayDateText')
$todayGreeting      = $window.FindName('TodayGreeting')
$todayGreetingIcon  = $window.FindName('TodayGreetingIcon')
$todayBattIcon      = $window.FindName('TodayBattIcon')
$todayBattPct       = $window.FindName('TodayBattPct')
$todayBattArcPath   = $window.FindName('TodayBattArcPath')
$todayBattStatus    = $window.FindName('TodayBattStatus')
$todayMiniCpu       = $window.FindName('TodayMiniCpu')
$todayMiniGpu       = $window.FindName('TodayMiniGpu')
$todayMiniRam       = $window.FindName('TodayMiniRam')

# Tab 2: Media Elements (Hitodama Reference Deck)
$mediaDeviceIcon    = $window.FindName('MediaDeviceIcon')
$mediaDeviceText    = $window.FindName('MediaDeviceText')
$albumArtImage      = $window.FindName('AlbumArtImage')
$albumArtFallback   = $window.FindName('AlbumArtFallback')
$mediaTitleText     = $window.FindName('MediaTitleText')
$mediaArtistText    = $window.FindName('MediaArtistText')
$btnMediaPrev       = $window.FindName('BtnMediaPrev')
$btnMediaPlay       = $window.FindName('BtnMediaPlay')
$btnMediaNext       = $window.FindName('BtnMediaNext')
$mediaTimeCurrent   = $window.FindName('MediaTimeCurrent')
$mediaTimeTotal     = $window.FindName('MediaTimeTotal')
$mediaWaveCanvas    = $window.FindName('MediaWaveCanvas')
$mediaWaveProgress  = $window.FindName('MediaWaveProgress')
$mediaWaveThumb     = $window.FindName('MediaWaveThumb')
$mediaWaveRemaining = $window.FindName('MediaWaveRemaining')

# Tab 3: Stats Elements
$cpuArcPath         = $window.FindName('CpuArcPath')
$gpuArcPath         = $window.FindName('GpuArcPath')
$ramArcPath         = $window.FindName('RamArcPath')
$statsCpuPct        = $window.FindName('StatsCpuPct')
$statsGpuPct        = $window.FindName('StatsGpuPct')
$statsRamPct        = $window.FindName('StatsRamPct')

# Tab 4: Controls Elements (Direct Hardware Deck)
$btnVolDown         = $window.FindName('BtnVolDown')
$btnVolUp           = $window.FindName('BtnVolUp')
$btnMuteToggle      = $window.FindName('BtnMuteToggle')
$btnAudioDevices    = $window.FindName('BtnAudioDevices')
$btnActionBluetooth = $window.FindName('BtnActionBluetooth')
$btnActionDisplay   = $window.FindName('BtnActionDisplay')
$btnActionTaskMgr   = $window.FindName('BtnActionTaskMgr')
$btnActionExplorer  = $window.FindName('BtnActionExplorer')

# Tab 5: Power Elements
$btnPowerLock       = $window.FindName('BtnPowerLock')
$btnPowerSleep      = $window.FindName('BtnPowerSleep')
$btnPowerRestart    = $window.FindName('BtnPowerRestart')
$btnPowerShutdown   = $window.FindName('BtnPowerShutdown')

# Tab 6: Settings Elements
$swatchCyan         = $window.FindName('SwatchCyan')
$swatchMagenta      = $window.FindName('SwatchMagenta')
$swatchPurple       = $window.FindName('SwatchPurple')
$swatchEmerald      = $window.FindName('SwatchEmerald')
$swatchAmber        = $window.FindName('SwatchAmber')
$swatchRed          = $window.FindName('SwatchRed')
$customHexInput     = $window.FindName('CustomHexInput')
$btnApplyHex        = $window.FindName('BtnApplyHex')
$glowRadiusSlider   = $window.FindName('GlowRadiusSlider')
$glowRadiusLabel    = $window.FindName('GlowRadiusLabel')
$glowOpacitySlider  = $window.FindName('GlowOpacitySlider')
$glowOpacityLabel   = $window.FindName('GlowOpacityLabel')
$toggleTabToday     = $window.FindName('ToggleTabToday')
$toggleTabMedia     = $window.FindName('ToggleTabMedia')
$toggleTabStats     = $window.FindName('ToggleTabStats')
$toggleTabControls  = $window.FindName('ToggleTabControls')
$toggleTabPower     = $window.FindName('ToggleTabPower')

# Script State Variables
$script:expanded       = $false
$script:pinned         = $false
$script:isDragging     = $false
$script:activeTab      = 'Today'
$script:pct            = 80
$script:charging       = $true
$script:tick           = 0
$script:mediaAutoShown = $false
$script:lastMediaTitle = ''
$script:currentArtBytes= $null
$script:waveOffset     = 0.0

# Solid Brushes Cache
$bc = New-Object System.Windows.Media.BrushConverter
$script:brushWhite       = [System.Windows.Media.Brushes]::White
$script:brushGreen       = $bc.ConvertFromString($Config.AccentGreen);  $script:brushGreen.Freeze()
$script:brushWarn        = $bc.ConvertFromString($Config.WarnColor);    $script:brushWarn.Freeze()
$script:brushRed         = $bc.ConvertFromString($Config.CritColor);    $script:brushRed.Freeze()
$script:brushInactiveTab = [System.Windows.Media.Brushes]::Transparent

$script:colorWarn        = [System.Windows.Media.ColorConverter]::ConvertFromString($Config.WarnColor)
$script:colorCrit        = [System.Windows.Media.ColorConverter]::ConvertFromString($Config.CritColor)

# Dynamic Aura Theme Applicator
function Apply-AuraTheme ([string]$hexColor) {
    if ($hexColor -notmatch '^#[0-9A-Fa-f]{6}$') { return }
    $Config.GlowColor = $hexColor

    $colorObj = [System.Windows.Media.ColorConverter]::ConvertFromString($hexColor)
    $glowFx.Color = $colorObj
    $statusDot.Fill = [System.Windows.Media.SolidColorBrush]::new($colorObj)
    $compactIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new($colorObj)

    if ($null -ne $menuResetIcon) {
        $menuResetIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new($colorObj)
    }

    # Brushes with translucent alpha for rounded pill active state
    $alphaHex = $hexColor.Substring(1)
    $script:brushActiveTab    = $bc.ConvertFromString("#33$alphaHex"); $script:brushActiveTab.Freeze()
    $script:brushAccentBorder = $bc.ConvertFromString("#77$alphaHex"); $script:brushAccentBorder.Freeze()
    $script:brushAccentSolid  = $bc.ConvertFromString($hexColor);     $script:brushAccentSolid.Freeze()

    $btnMediaPlay.Background  = $script:brushAccentSolid
    $cpuArcPath.Stroke        = $script:brushAccentSolid
    $todayMiniCpu.Foreground  = $script:brushAccentSolid
    $todayGreeting.Foreground = $script:brushAccentSolid
    $todayGreetingIcon.Foreground = $script:brushAccentSolid
    $mediaDeviceIcon.Foreground   = $script:brushAccentSolid
    $mediaWaveProgress.Stroke     = $script:brushAccentSolid
    $mediaWaveThumb.Fill          = $script:brushAccentSolid

    # Refresh current active tab pill style
    Switch-Tab $script:activeTab
    Save-Config
}

Apply-AuraTheme $Config.GlowColor

# Position Restore
if ($null -ne $Config.X -and $null -ne $Config.Y) {
    $window.Left = $Config.X
    $window.Top  = $Config.Y
} else {
    $window.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth - $window.Width) / 2
    $window.Top  = 0
}

# ------------------------------------------------------------------------------
#  S6  ZERO-LAG ANIMATION SYSTEM (Hardware Accelerated)
# ------------------------------------------------------------------------------
function Expand-Island {
    if ($script:expanded) { return }
    $script:expanded = $true

    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'

    $animW = New-Object System.Windows.Media.Animation.DoubleAnimation($Config.ExpandedWidth, [TimeSpan]::FromMilliseconds($Config.ExpandMs))
    $animH = New-Object System.Windows.Media.Animation.DoubleAnimation($Config.ExpandedHeight, [TimeSpan]::FromMilliseconds($Config.ExpandMs))
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
    $script:expanded = $false

    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = 'EaseOut'

    $animExpand = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, [TimeSpan]::FromMilliseconds([int]($Config.CollapseMs * 0.45)))
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
#  S7  TAB NAVIGATION CONTROLLER (Pill Shaped Styling)
# ------------------------------------------------------------------------------
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

    foreach ($k in $script:allTabs.Keys) {
        $entry = $script:allTabs[$k]
        if ($k -eq $tabName) {
            $entry.View.Visibility = 'Visible'
            if ($k -ne 'Settings') {
                $entry.Btn.Background      = $script:brushActiveTab
                $entry.Btn.Foreground      = $script:brushAccentSolid
                $entry.Btn.BorderThickness = [System.Windows.Thickness]::new(1)
                $entry.Btn.BorderBrush     = $script:brushAccentBorder
            } else {
                $entry.Btn.Foreground      = $script:brushAccentSolid
            }
        } else {
            $entry.View.Visibility = 'Collapsed'
            if ($k -ne 'Settings') {
                $entry.Btn.Background      = $script:brushInactiveTab
                $entry.Btn.Foreground      = $bc.ConvertFromString($Config.SubtextColor)
                $entry.Btn.BorderThickness = [System.Windows.Thickness]::new(0)
            } else {
                $entry.Btn.Foreground      = $bc.ConvertFromString($Config.SubtextColor)
            }
        }
    }
}

$tabBtnToday.Add_Click({ Switch-Tab 'Today' })
$tabBtnMedia.Add_Click({ Switch-Tab 'Media' })
$tabBtnStats.Add_Click({ Switch-Tab 'Stats' })
$tabBtnControls.Add_Click({ Switch-Tab 'Controls' })
$tabBtnPower.Add_Click({ Switch-Tab 'Power' })
$btnSettings.Add_Click({
    if ($script:activeTab -eq 'Settings') { Switch-Tab 'Today' }
    else { Switch-Tab 'Settings' }
})

# Pin Open Toggle
$btnPin.Add_Click({
    $script:pinned = -not $script:pinned
    $btnPin.Foreground = if ($script:pinned) { $script:brushAccentSolid } else { $bc.ConvertFromString($Config.SubtextColor) }
})

# ------------------------------------------------------------------------------
#  S8  CUSTOMIZATION & SETTINGS EVENT HANDLERS
# ------------------------------------------------------------------------------
# Aura Preset Swatches
$swatchCyan.Add_Click({ Apply-AuraTheme '#00E5FF' })
$swatchMagenta.Add_Click({ Apply-AuraTheme '#FF007F' })
$swatchPurple.Add_Click({ Apply-AuraTheme '#A855F7' })
$swatchEmerald.Add_Click({ Apply-AuraTheme '#00E676' })
$swatchAmber.Add_Click({ Apply-AuraTheme '#FFB300' })
$swatchRed.Add_Click({ Apply-AuraTheme '#FF1744' })

# Custom Hex Input Handler
$btnApplyHex.Add_Click({
    $hex = $customHexInput.Text.Trim()
    if ($hex -match '^#[0-9A-Fa-f]{6}$') {
        Apply-AuraTheme $hex
    }
})
$customHexInput.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return') {
        $hex = $customHexInput.Text.Trim()
        if ($hex -match '^#[0-9A-Fa-f]{6}$') {
            Apply-AuraTheme $hex
        }
    }
})

# Glow Radius & Opacity Sliders
$glowRadiusSlider.Value = $Config.GlowRadius
$glowRadiusLabel.Text = "$($Config.GlowRadius)px"
$glowRadiusSlider.Add_ValueChanged({
    $val = [int]$glowRadiusSlider.Value
    $Config.GlowRadius    = $val
    $glowFx.BlurRadius    = $val
    $glowRadiusLabel.Text = "${val}px"
    Save-Config
})

$glowOpacitySlider.Value = [int]($Config.GlowOpacity * 100)
$glowOpacityLabel.Text = "$([int]($Config.GlowOpacity * 100))%"
$glowOpacitySlider.Add_ValueChanged({
    $val = [int]$glowOpacitySlider.Value
    $dec = $val / 100.0
    $Config.GlowOpacity    = $dec
    $glowFx.Opacity        = $dec
    $glowOpacityLabel.Text = "${val}%"
    Save-Config
})

# Win11 Module Switches
$toggleTabToday.IsChecked    = $Config.Tabs.Today
$toggleTabMedia.IsChecked    = $Config.Tabs.Media
$toggleTabStats.IsChecked    = $Config.Tabs.Stats
$toggleTabControls.IsChecked = $Config.Tabs.Controls
$toggleTabPower.IsChecked    = $Config.Tabs.Power

$toggleTabToday.Add_Click({ $Config.Tabs.Today = [bool]$toggleTabToday.IsChecked; $tabBtnToday.Visibility = if ($Config.Tabs.Today) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabMedia.Add_Click({ $Config.Tabs.Media = [bool]$toggleTabMedia.IsChecked; $tabBtnMedia.Visibility = if ($Config.Tabs.Media) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabStats.Add_Click({ $Config.Tabs.Stats = [bool]$toggleTabStats.IsChecked; $tabBtnStats.Visibility = if ($Config.Tabs.Stats) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabControls.Add_Click({ $Config.Tabs.Controls = [bool]$toggleTabControls.IsChecked; $tabBtnControls.Visibility = if ($Config.Tabs.Controls) { 'Visible' } else { 'Collapsed' }; Save-Config })
$toggleTabPower.Add_Click({ $Config.Tabs.Power = [bool]$toggleTabPower.IsChecked; $tabBtnPower.Visibility = if ($Config.Tabs.Power) { 'Visible' } else { 'Collapsed' }; Save-Config })

# ------------------------------------------------------------------------------
#  S9  FAST UI DISPATCHER UPDATES (Reads from Shared State)
# ------------------------------------------------------------------------------
function Update-ClockAndBattery {
    $now = Get-Date
    $timeStr = $now.ToString('h:mm tt')
    $dateStr = $now.ToString('dddd, d MMMM')

    $compactTime.Text    = $timeStr
    $todayClockText.Text = $timeStr
    $todayDateText.Text  = $dateStr

    # Smart Greeting & Icon
    $hr = $now.Hour
    $greeting = 'Good Evening'
    $greetIcon = [char]0xE708
    if ($hr -ge 5 -and $hr -lt 12) {
        $greeting = 'Good Morning'
        $greetIcon = [char]0xE706
    } elseif ($hr -ge 12 -and $hr -lt 17) {
        $greeting = 'Good Afternoon'
        $greetIcon = [char]0xE706
    } elseif ($hr -ge 17 -and $hr -lt 21) {
        $greeting = 'Good Evening'
        $greetIcon = [char]0xE708
    } else {
        $greeting = 'Good Night'
        $greetIcon = [char]0xE705
    }
    $todayGreeting.Text = $greeting
    $todayGreetingIcon.Text = [string]$greetIcon

    # Robust Multi-Layer Battery Telemetry (Never 0%)
    $pct = 0
    $charging = $false
    try {
        $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
        if ($null -ne $ps -and $ps.BatteryLifePercent -ge 0) {
            $pct = [int][math]::Round($ps.BatteryLifePercent * 100)
            $charging = ($ps.PowerLineStatus -eq 'Online')
        }
    } catch { }

    if ($pct -le 0) {
        try {
            $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
            if ($b) {
                $pct = [int]$b.EstimatedChargeRemaining
                $charging = ($b.BatteryStatus -in 2, 6, 7, 8)
            }
        } catch { }
    }

    if ($pct -le 0) {
        # Desktop PC or plugged-in device without battery sensor
        $pct = 100
        $charging = $true
    }

    $script:pct = $pct
    $script:charging = $charging

    $battGlyph = if ($script:charging) { [char]0xEA93 } else { [char]0xEA81 }
    $compactBattIcon.Text = [string]$battGlyph
    $compactBattText.Text = "$($script:pct)%"

    $todayBattIcon.Text   = [string]$battGlyph
    $todayBattPct.Text    = "$($script:pct)%"
    $todayBattStatus.Text = if ($script:charging) { 'AC Connected | Charging' } else { 'Battery | Discharging' }

    # Dynamic Radial Arc for Battery (cx=35, cy=35, r=29)
    $todayBattArcPath.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 35 35 29 $script:pct))

    # Dynamic Arc Stroke Colors
    if ($script:charging -or $script:pct -ge 80) {
        $todayBattArcPath.Stroke = $script:brushGreen
        $todayBattIcon.Foreground = $script:brushGreen
        $compactBattIcon.Foreground = $script:brushGreen
    } elseif ($script:pct -ge 20) {
        $todayBattArcPath.Stroke = $script:brushWarn
        $todayBattIcon.Foreground = $script:brushWarn
        $compactBattIcon.Foreground = $script:brushWarn
    } else {
        $todayBattArcPath.Stroke = $script:brushRed
        $todayBattIcon.Foreground = $script:brushRed
        $compactBattIcon.Foreground = $script:brushRed
    }
}

function Update-UIState {
    # 1. Telemetry Gauges (Read from background runspace)
    $cpu = $script:sharedState.Cpu
    $gpu = $script:sharedState.Gpu
    $ram = $script:sharedState.Ram

    $todayMiniCpu.Text = "${cpu}%"
    $todayMiniGpu.Text = "${gpu}%"
    $todayMiniRam.Text = "${ram}%"

    $compactLoadText.Text = "CPU ${cpu}%"

    $cpuArcPath.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 36 36 30 $cpu))
    $gpuArcPath.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 36 36 30 $gpu))
    $ramArcPath.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 36 36 30 $ram))

    $statsCpuPct.Text = "${cpu}%"
    $statsGpuPct.Text = "${gpu}%"
    $statsRamPct.Text = "${ram}%"

    # Dynamic Load Aura Warning (>78% Warn, >88% Critical)
    if ($Config.EnableDynamicGlow) {
        $maxLoad = [math]::Max($cpu, $gpu)
        $targetColor = if ($maxLoad -ge 88) { $script:colorCrit }
                       elseif ($maxLoad -ge 78) { $script:colorWarn }
                       else                  { [System.Windows.Media.ColorConverter]::ConvertFromString($Config.GlowColor) }

        if ($glowFx.Color -ne $targetColor) {
            $ca = New-Object System.Windows.Media.Animation.ColorAnimation($targetColor, [TimeSpan]::FromMilliseconds(500))
            $glowFx.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::ColorProperty, $ca)
        }
    }

    # 2. Media Info, Timelines & Live Album Art (Hitodama Deck)
    $title  = $script:sharedState.MediaTitle
    $artist = $script:sharedState.MediaArtist
    $status = $script:sharedState.MediaStatus
    $device = $script:sharedState.MediaDevice

    if ($device) { $mediaDeviceText.Text = $device }
    $mediaTimeCurrent.Text = $script:sharedState.MediaPosition
    $mediaTimeTotal.Text   = $script:sharedState.MediaDuration

    if ($status -eq 'None' -or ($title -eq '' -and $artist -eq '')) {
        $mediaTitleText.Text  = 'No Media Playing'
        $mediaArtistText.Text = 'Ready for Spotify, YouTube, or Media'
        $btnMediaPlay.Content = [char]0xE768
        $compactIcon.Text     = [string][char]0xE823
    } else {
        $mediaTitleText.Text  = $title
        $mediaArtistText.Text = if ($artist) { $artist } else { 'Playing' }
        $btnMediaPlay.Content = if ($status -eq 'Playing') { [char]0xE769 } else { [char]0xE768 }
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

    # Live Decoded Album Art Image Injection
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
                $albumArtImage.Visibility = 'Visible'
                $albumArtFallback.Visibility = 'Collapsed'
            } catch {
                $albumArtImage.Source = $null
                $albumArtImage.Visibility = 'Collapsed'
                $albumArtFallback.Visibility = 'Visible'
            }
        }
    } else {
        if ($null -ne $script:currentArtBytes) {
            $script:currentArtBytes = $null
            $albumArtImage.Source = $null
            $albumArtImage.Visibility = 'Collapsed'
            $albumArtFallback.Visibility = 'Visible'
        }
    }
}

# ------------------------------------------------------------------------------
#  S10  60 FPS WAVY SCRUBBER ANIMATION LOOP (Hitodama Reference Style)
# ------------------------------------------------------------------------------
$waveTimer = New-Object System.Windows.Threading.DispatcherTimer
$waveTimer.Interval = [TimeSpan]::FromMilliseconds(16)
$waveTimer.Add_Tick({
    $isPlaying = ($script:sharedState.MediaStatus -eq 'Playing')
    $progRatio = [math]::Min([math]::Max($script:sharedState.MediaProgress, 0.05), 0.95)

    $canvasW = $mediaWaveCanvas.ActualWidth
    if ($canvasW -le 10) { $canvasW = 260 }
    $midY = 8.0
    $amp = if ($isPlaying) { 3.2 } else { 0.8 }

    $script:waveOffset += if ($isPlaying) { 0.16 } else { 0.02 }

    $splitX = [math]::Round($canvasW * $progRatio, 1)

    # 1. Squiggly Played Sine Wave Path
    $sbWave = New-Object System.Text.StringBuilder
    [void]$sbWave.Append("M 0,$midY")
    for ($x = 2; $x -le $splitX; $x += 3.5) {
        $y = $midY + ($amp * [math]::Sin(($x * 0.18) + $script:waveOffset))
        [void]$sbWave.Append(" L $([math]::Round($x, 1)),$([math]::Round($y, 1))")
    }
    $mediaWaveProgress.Data = [System.Windows.Media.Geometry]::Parse($sbWave.ToString())

    # 2. Scrubber Knob Position
    [System.Windows.Controls.Canvas]::SetLeft($mediaWaveThumb, ($splitX - 4))
    [System.Windows.Controls.Canvas]::SetTop($mediaWaveThumb, ($midY - 4))

    # 3. Remaining Straight Track Line
    $sbRest = "M $splitX,$midY L $canvasW,$midY"
    $mediaWaveRemaining.Data = [System.Windows.Media.Geometry]::Parse($sbRest)
})

# ------------------------------------------------------------------------------
#  S11  QUICK CONTROLS & DIRECT HARDWARE ACTIONS
# ------------------------------------------------------------------------------
# Direct Hardware Key Events (Works globally across all headsets/Bluetooth)
$btnVolDown.Add_Click({ [IslandNative]::VolumeDown() })
$btnVolUp.Add_Click({ [IslandNative]::VolumeUp() })
$btnMuteToggle.Add_Click({ [IslandNative]::ToggleMute() })

# Quick System Setting Launchers
$btnAudioDevices.Add_Click({ Start-Process 'ms-settings:sound' })
$btnActionBluetooth.Add_Click({ Start-Process 'ms-settings:bluetooth' })
$btnActionDisplay.Add_Click({ Start-Process 'ms-settings:display' })
$btnActionTaskMgr.Add_Click({ Start-Process taskmgr.exe })
$btnActionExplorer.Add_Click({ Start-Process explorer.exe })

# Media Playback Buttons
$btnMediaPlay.Add_Click({ Send-MediaCommandAsync 'PlayPause' })
$btnMediaPrev.Add_Click({ Send-MediaCommandAsync 'Previous' })
$btnMediaNext.Add_Click({ Send-MediaCommandAsync 'Next' })

# Power Actions
$btnPowerLock.Add_Click({ Start-Process rundll32.exe 'user32.dll,LockWorkStation' })
$btnPowerSleep.Add_Click({ Start-Process rundll32.exe 'powrprof.dll,SetSuspendState 0,1,0' })
$btnPowerRestart.Add_Click({ Start-Process shutdown.exe '/r /t 0' })
$btnPowerShutdown.Add_Click({ Start-Process shutdown.exe '/s /t 0' })

# ------------------------------------------------------------------------------
#  S12  EVENT TRIGGERS: HOVER, FREE DRAG & HARDWARE VOLUME SCROLL
# ------------------------------------------------------------------------------
$leaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$leaveTimer.Interval = [TimeSpan]::FromMilliseconds($Config.CollapseDelay)
$leaveTimer.Add_Tick({ $leaveTimer.Stop(); if (-not $script:isDragging) { Collapse-Island } })

$glowBorder.Add_MouseEnter({
    $leaveTimer.Stop()
    $script:mediaAutoShown = $false
    if ($script:autoCollapseTimer) { $script:autoCollapseTimer.Stop() }
    Expand-Island
})

$glowBorder.Add_MouseLeave({
    if (-not $script:isDragging -and -not $script:pinned) { $leaveTimer.Start() }
})

# Free Drag Anywhere on Island
$glowBorder.Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($e.OriginalSource -isnot [System.Windows.Controls.Button] -and
        $e.OriginalSource -isnot [System.Windows.Controls.Slider] -and
        $e.OriginalSource -isnot [System.Windows.Controls.Primitives.Thumb] -and
        $e.OriginalSource -isnot [System.Windows.Controls.TextBox] -and
        $e.OriginalSource -isnot [System.Windows.Controls.CheckBox]) {
        $script:isDragging = $true
        $window.DragMove()
        $script:isDragging = $false
        $Config.X = $window.Left
        $Config.Y = $window.Top
        Save-Config
    }
})

# Direct Hardware Master Volume Scroll (Works on Bluetooth Headsets)
if ($Config.EnableVolumeScroll) {
    $glowBorder.Add_MouseWheel({
        param($sender, $e)
        if ($e.Delta -gt 0) {
            [IslandNative]::VolumeUp()
        } else {
            [IslandNative]::VolumeDown()
        }
        $e.Handled = $true
    })
}

$script:autoCollapseTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:autoCollapseTimer.Interval = [TimeSpan]::FromMilliseconds($Config.MediaPopupMs)
$script:autoCollapseTimer.Add_Tick({
    $script:autoCollapseTimer.Stop()
    $script:mediaAutoShown = $false
    if ($script:expanded -and -not $script:pinned) { Collapse-Island }
})

# Modern Context Menu Wireup
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

# Cleanup on Window Close
$window.Add_Closed({
    $script:sharedState.IsRunning = $false
    $waveTimer.Stop()
    $clockTimer.Stop()
    $uiTimer.Stop()
    if ($null -ne $script:bgRunspace) {
        try {
            $script:bgRunspace.EndInvoke($script:bgHandle)
            $script:bgRunspace.Dispose()
        } catch { }
    }
})

# ------------------------------------------------------------------------------
#  S13  UI DISPATCHER TIMERS & LAUNCH
# ------------------------------------------------------------------------------
Update-ClockAndBattery
Switch-Tab 'Today'

# High-frequency UI Dispatcher Timer (Reads synchronized telemetry)
$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(80)
$uiTimer.Add_Tick({ Update-UIState })

# 1-Second Clock Timer
$clockTimer = New-Object System.Windows.Threading.DispatcherTimer
$clockTimer.Interval = [TimeSpan]::FromSeconds(1)
$clockTimer.Add_Tick({
    $script:tick++
    if ($script:tick % 15 -eq 0) { Update-ClockAndBattery }
    else {
        $now = Get-Date
        $t = $now.ToString('h:mm tt')
        $compactTime.Text    = $t
        $todayClockText.Text = $t
    }
})

$uiTimer.Start()
$clockTimer.Start()
$waveTimer.Start()

# Show Window
$window.ShowDialog() | Out-Null
