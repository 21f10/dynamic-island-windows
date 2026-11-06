# ==============================================================================
#  Dynamic Island for Windows  -  v3.5 (Performance & Customization Edition)
#  Background Runspace Telemetry | 60 FPS Audio Wave | Pill Tab Styles | Inline Aura Settings
# ==============================================================================

# Global Error Suppression (Zero Red Crash Windows)
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$VerbosePreference     = 'SilentlyContinue'
$DebugPreference       = 'SilentlyContinue'

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
    ExpandedWidth   = 460
    ExpandedHeight  = 240
    CornerRadius    = 22
    ScreenTopMargin = 8
    WindowWidth     = 520
    WindowHeight    = 300

    # --- Visual Customization & Aura ---
    GlowColor       = '#00E5FF'          # Active Glow / Aura color
    GlowRadius      = 26                 # Outer glow blur radius
    GlowOpacity     = 0.55               # Outer glow opacity
    BackgroundColor = '#F50F0F14'        # Frosted obsidian background
    CardColor       = '#14141E'          # Modular card fill
    CardBorderColor = '#25FFFFFF'        # Glass border
    TextColor       = '#FFFFFFFF'        # Primary text
    SubtextColor    = '#FFA0A0B2'        # Subdued gray text
    AccentPurple    = '#FFA855F7'        # GPU accent
    AccentGreen     = '#FF10B981'        # RAM & Battery accent
    WarnColor       = '#FFFF9100'        # Load > 78% glow
    CritColor       = '#FFFF1744'        # Load > 92% glow

    # --- Animation Timing ---
    ExpandMs        = 240
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
        $Config | ConvertTo-Json -Depth 4 | Set-Content $ConfigPath -Encoding UTF8 -Force
    } catch { }
}

# ------------------------------------------------------------------------------
#  S2  NATIVE INTEROP (Thread-Safe AudioMaster & Memory APIs)
# ------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class IslandNative {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr h, int i, int v);
    [DllImport("user32.dll")]
    public static extern bool LockWorkStation();
    [DllImport("PowrProf.dll", CharSet = CharSet.Auto, ExactSpelling = true)]
    public static extern bool SetSuspendState(bool hiberate, bool forceCritical, bool disableWakeEvent);
}

public class SysMem {
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
    [return: MarshalAs(UnmanagedType.Bool)]
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

    public static uint GetMemoryLoad() {
        try {
            MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
            if (GlobalMemoryStatusEx(mem)) return mem.dwMemoryLoad;
        } catch { }
        return 0;
    }
    public static ulong GetTotalPhysicalGB() {
        try {
            MEMORYSTATUSEX mem = new MEMORYSTATUSEX();
            if (GlobalMemoryStatusEx(mem)) return (mem.ullTotalPhys / (1024 * 1024 * 1024));
        } catch { }
        return 16;
    }
}

// Crash-proof COM Audio Interfaces with [PreserveSig]
[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolumeSafe {
    [PreserveSig] int RegisterControlChangeNotify(IntPtr pNotify);
    [PreserveSig] int UnregisterControlChangeNotify(IntPtr pNotify);
    [PreserveSig] int GetChannelCount(out uint pnChannelCount);
    [PreserveSig] int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
    [PreserveSig] int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
    [PreserveSig] int GetMasterVolumeLevel(out float pfLevelDB);
    [PreserveSig] int GetMasterVolumeLevelScalar(out float pfLevel);
    [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
    [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceSafe {
    [PreserveSig] int Activate(ref Guid id, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumeratorSafe {
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr device);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDeviceSafe endpoint);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObjectSafe { }

public class AudioMasterSafe {
    public static float GetVolume() {
        try {
            var enumerator = (IMMDeviceEnumeratorSafe)(new MMDeviceEnumeratorComObjectSafe());
            if (enumerator == null) return 50f;
            IMMDeviceSafe dev = null;
            int hr = enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            if (hr != 0 || dev == null) return 50f;
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolumeSafe).GUID;
            object epv = null;
            hr = dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epv);
            if (hr != 0 || epv == null) return 50f;
            var vol = (IAudioEndpointVolumeSafe)epv;
            float currentVol = 0.5f;
            vol.GetMasterVolumeLevelScalar(out currentVol);
            return currentVol * 100f;
        } catch { return 50f; }
    }
    public static void SetVolume(float levelPercent) {
        try {
            levelPercent = Math.Max(0f, Math.Min(100f, levelPercent));
            var enumerator = (IMMDeviceEnumeratorSafe)(new MMDeviceEnumeratorComObjectSafe());
            if (enumerator == null) return;
            IMMDeviceSafe dev = null;
            int hr = enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            if (hr != 0 || dev == null) return;
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolumeSafe).GUID;
            object epv = null;
            hr = dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epv);
            if (hr != 0 || epv == null) return;
            var vol = (IAudioEndpointVolumeSafe)epv;
            Guid g = Guid.Empty;
            vol.SetMasterVolumeLevelScalar(levelPercent / 100f, ref g);
        } catch { }
    }
}
"@
[IslandNative]::SetProcessDPIAware() | Out-Null

# ------------------------------------------------------------------------------
#  S3  BACKGROUND TELEMETRY RUNSPACE (Offloads heavy WMI & Counters)
# ------------------------------------------------------------------------------
$script:sharedState = [hashtable]::Synchronized(@{
    Cpu         = 0
    Gpu         = 0
    Ram         = 0
    MediaTitle  = ''
    MediaArtist = ''
    MediaStatus = 'None'
    Volume      = 50
    IsRunning   = $true
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

        $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]

        $mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
        $asTaskMgr = $asTaskGeneric.MakeGenericMethod($mgrType)
        $asyncOp = $mgrType::RequestAsync()
        $task = $asTaskMgr.Invoke($null, @($asyncOp))
        $task.Wait(3000) | Out-Null
        $sessionMgr = $task.Result
        $smtcReady = ($null -ne $sessionMgr)
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
            $state.Ram = [int][SysMem]::GetMemoryLoad()
        } catch { }

        # 4. SMTC Media Session
        if ($smtcReady -and $null -ne $sessionMgr) {
            try {
                $session = $sessionMgr.GetCurrentSession()
                if ($null -ne $session) {
                    $pbInfo = $session.GetPlaybackInfo()
                    $st = $pbInfo.PlaybackStatus.ToString()
                    $state.MediaStatus = if ($st -in 'Playing','Paused','Stopped') { $st } else { 'None' }

                    $propsType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
                    $asTaskP = $asTaskGeneric.MakeGenericMethod($propsType)
                    $asyncP = $session.TryGetMediaPropertiesAsync()
                    $taskP = $asTaskP.Invoke($null, @($asyncP))
                    $taskP.Wait(1500) | Out-Null
                    $props = $taskP.Result
                    if ($null -ne $props) {
                        $state.MediaTitle = if ($props.Title) { $props.Title } else { '' }
                        $state.MediaArtist = if ($props.Artist) { $props.Artist } else { '' }
                    }
                } else {
                    $state.MediaStatus = 'None'
                    $state.MediaTitle = ''
                    $state.MediaArtist = ''
                }
            } catch {
                $state.MediaStatus = 'None'
            }
        }

        # Background Interval (1.2s sleep in small slices)
        for ($i = 0; $i -lt 12; $i++) {
            if (-not $state.IsRunning) { break }
            [System.Threading.Thread]::Sleep(100)
        }
    }
}).AddArgument($script:sharedState)

$script:bgHandle = $script:bgRunspace.BeginInvoke()

# Helper: SMTC Media Commands executed asynchronously
function Send-MediaCommand ([string]$Cmd) {
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
            $mgrTask.Wait(2000) | Out-Null
            $sess = $mgrTask.Result.GetCurrentSession()
            if ($null -ne $sess) {
                switch ($Cmd) {
                    'PlayPause' {
                        $pb = $sess.GetPlaybackInfo()
                        if ($pb.PlaybackStatus.ToString() -eq 'Playing') { $sess.TryPauseAsync() | Out-Null }
                        else { $sess.TryPlayAsync() | Out-Null }
                    }
                    'Next'     { $sess.TrySkipNextAsync() | Out-Null }
                    'Previous' { $sess.TrySkipPreviousAsync() | Out-Null }
                }
            }
        } catch { }
    }) | Out-Null
}

# SVG Arc Path calculation for Circular Rings
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
#  S4  WPF XAML INTERFACE (Cylindrical Pill Tabs & Inline Customization)
# ------------------------------------------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="{x:Null}"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False"
        ResizeMode="NoResize"
        RenderOptions.BitmapScalingMode="HighQuality"
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
                    CornerRadius="14"
                    Padding="10,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="TabBorder" Property="Background" Value="#22FFFFFF"/>
                <Setter Property="Foreground" Value="#FFFFFFFF"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="TabBorder" Property="Background" Value="#33FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Color Swatch Button Style -->
    <Style x:Key="SwatchButtonStyle" TargetType="Button">
      <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="12">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Module Toggle Pill Style -->
    <Style x:Key="ToggleModuleButtonStyle" TargetType="Button">
      <Setter Property="Background" Value="#1C1C28"/>
      <Setter Property="Foreground" Value="#FFFFFFFF"/>
      <Setter Property="BorderBrush" Value="#33FFFFFF"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
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
          <!-- 2. EXPANDED DASHBOARD VIEW (Hitodama UI)                      -->
          <!-- ============================================================= -->
          <Grid x:Name="ExpandedCard" Opacity="0" Visibility="Collapsed" Margin="14,10,14,12">
            <Grid.RowDefinitions>
              <!-- Row 0: Tab Navigation Header -->
              <RowDefinition Height="Auto"/>
              <!-- Row 1: Active Tab Content Area -->
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- TAB NAVIGATION BAR -->
            <Grid Grid.Row="0" Margin="0,0,0,10">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <!-- Left Status Dot -->
              <Ellipse x:Name="StatusDot" Grid.Column="0" Width="8" Height="8" Fill="$($Config.GlowColor)"
                       VerticalAlignment="Center" Margin="4,0,8,0">
                <Ellipse.Effect>
                  <DropShadowEffect Color="$($Config.GlowColor)" BlurRadius="8" ShadowDepth="0" Opacity="0.8"/>
                </Ellipse.Effect>
              </Ellipse>

              <!-- Center Segmented Pill Tab Bar -->
              <Border Grid.Column="1" Background="#161620" CornerRadius="16" Padding="3" HorizontalAlignment="Center">
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="TabBtnToday" Content="Today" Width="68" Style="{StaticResource TabPillButtonStyle}"/>
                  <Button x:Name="TabBtnMedia" Content="Media" Width="68" Style="{StaticResource TabPillButtonStyle}"/>
                  <Button x:Name="TabBtnStats" Content="Stats" Width="68" Style="{StaticResource TabPillButtonStyle}"/>
                  <Button x:Name="TabBtnControls" Content="Controls" Width="68" Style="{StaticResource TabPillButtonStyle}"/>
                  <Button x:Name="TabBtnPower" Content="Power" Width="64" Style="{StaticResource TabPillButtonStyle}"/>
                </StackPanel>
              </Border>

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
            <!-- TAB 1: TODAY VIEW                                           -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewToday" Grid.Row="1" Visibility="Visible">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="1.2*"/>
                <ColumnDefinition Width="1.4*"/>
              </Grid.ColumnDefinitions>

              <!-- Left: Big Clock & Date Card -->
              <Border Grid.Column="0" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Margin="0,0,6,0" Padding="12,14">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock x:Name="TodayClockText" Text="12:00 PM"
                             Foreground="$($Config.TextColor)"
                             FontFamily="Segoe UI Variable Display, Segoe UI"
                             FontSize="26" FontWeight="Bold"
                             HorizontalAlignment="Center"/>
                  <TextBlock x:Name="TodayDateText" Text="Friday, 6 November"
                             Foreground="$($Config.SubtextColor)"
                             FontFamily="Segoe UI Variable Text, Segoe UI"
                             FontSize="12" HorizontalAlignment="Center" Margin="0,4,0,0"/>
                  <!-- Greeting Pill -->
                  <Border Background="#1AFFFFFF" CornerRadius="10" HorizontalAlignment="Center" Margin="0,10,0,0" Padding="10,3">
                    <TextBlock x:Name="TodayGreeting" Text="Good Evening" Foreground="$($Config.GlowColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold"/>
                  </Border>
                </StackPanel>
              </Border>

              <!-- Right: Battery & Quick Metrics Card -->
              <Border Grid.Column="1" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Margin="6,0,0,0" Padding="14,12">
                <StackPanel VerticalAlignment="Center">
                  <!-- Battery Header -->
                  <Grid Margin="0,0,0,8">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                      <TextBlock x:Name="TodayBattIcon" Text="&#xEA93;" FontFamily="Segoe MDL2 Assets"
                                 FontSize="14" Foreground="$($Config.AccentGreen)" Margin="0,0,6,0"/>
                      <TextBlock Text="Battery Status" Foreground="$($Config.SubtextColor)"
                                 FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12" FontWeight="SemiBold"/>
                    </StackPanel>
                    <TextBlock x:Name="TodayBattPct" Text="85%" Foreground="$($Config.TextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" FontWeight="Bold"
                               HorizontalAlignment="Right"/>
                  </Grid>

                  <!-- Battery Progress Bar -->
                  <Border Background="#252535" Height="7" CornerRadius="3.5" Margin="0,0,0,8">
                    <Border x:Name="TodayBattBar" Background="$($Config.AccentGreen)" Height="7" CornerRadius="3.5"
                            HorizontalAlignment="Left" Width="140"/>
                  </Border>

                  <TextBlock x:Name="TodayBattStatus" Text="AC Connected  |  Charging"
                             Foreground="$($Config.AccentGreen)" FontFamily="Segoe UI Variable Text, Segoe UI"
                             FontSize="11" Margin="0,0,0,12"/>

                  <!-- Mini System Stats Badges -->
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0" Background="#1C1C28" CornerRadius="8" Padding="4,5" Margin="0,0,3,0">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="CPU" Foreground="#888899" FontSize="10" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TodayMiniCpu" Text="0%" Foreground="$($Config.GlowColor)" FontWeight="Bold" FontSize="11" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>

                    <Border Grid.Column="1" Background="#1C1C28" CornerRadius="8" Padding="4,5" Margin="2,0,2,0">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="GPU" Foreground="#888899" FontSize="10" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TodayMiniGpu" Text="0%" Foreground="$($Config.AccentPurple)" FontWeight="Bold" FontSize="11" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>

                    <Border Grid.Column="2" Background="#1C1C28" CornerRadius="8" Padding="4,5" Margin="3,0,0,0">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="RAM" Foreground="#888899" FontSize="10" HorizontalAlignment="Center"/>
                        <TextBlock x:Name="TodayMiniRam" Text="0%" Foreground="$($Config.AccentGreen)" FontWeight="Bold" FontSize="11" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>
                  </Grid>

                </StackPanel>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 2: MEDIA VIEW (60 FPS Animated Equalizer)               -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewMedia" Grid.Row="1" Visibility="Collapsed">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>

              <!-- Left: Album Artwork Container -->
              <Border Grid.Column="0" Width="110" Height="140" CornerRadius="16" Margin="0,0,14,0"
                      Background="#141420" BorderBrush="#25FFFFFF" BorderThickness="1">
                <Grid>
                  <Border CornerRadius="16">
                    <Border.Background>
                      <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                        <GradientStop Color="#2A1640" Offset="0"/>
                        <GradientStop Color="#0F172A" Offset="1"/>
                      </LinearGradientBrush>
                    </Border.Background>
                  </Border>
                  <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                    <TextBlock Text="&#xE8D6;" FontFamily="Segoe MDL2 Assets" FontSize="36"
                               Foreground="$($Config.GlowColor)" HorizontalAlignment="Center"/>
                    <TextBlock Text="SMTC Audio" Foreground="#66FFFFFF" FontSize="10" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                  </StackPanel>
                </Grid>
              </Border>

              <!-- Right: Song Info, Wave Equalizer & Pill Controls -->
              <Border Grid.Column="1" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,10">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                  </Grid.RowDefinitions>

                  <!-- Song Title -->
                  <TextBlock x:Name="MediaTitleText" Grid.Row="0" Text="No Media Playing"
                             Foreground="$($Config.TextColor)"
                             FontFamily="Segoe UI Variable Display, Segoe UI"
                             FontSize="14" FontWeight="Bold"
                             TextTrimming="CharacterEllipsis"/>

                  <!-- Artist -->
                  <TextBlock x:Name="MediaArtistText" Grid.Row="1" Text="Windows SMTC Audio Session"
                             Foreground="$($Config.SubtextColor)"
                             FontFamily="Segoe UI Variable Text, Segoe UI"
                             FontSize="12" Margin="0,2,0,6"
                             TextTrimming="CharacterEllipsis"/>

                  <!-- ANIMATED AUDIO WAVEFORM EQUALIZER -->
                  <Grid Grid.Row="2" Height="26" Margin="0,0,0,8">
                    <Path x:Name="MediaWaveLine" Stroke="#5500E5FF" StrokeThickness="2" VerticalAlignment="Center"/>

                    <!-- 7 Dynamic Equalizer Bars -->
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Height="24">
                      <Border x:Name="EqBar1" Width="4" Height="6" Background="$($Config.GlowColor)" CornerRadius="2" Margin="2,0" VerticalAlignment="Bottom"/>
                      <Border x:Name="EqBar2" Width="4" Height="14" Background="$($Config.GlowColor)" CornerRadius="2" Margin="2,0" VerticalAlignment="Bottom"/>
                      <Border x:Name="EqBar3" Width="4" Height="20" Background="$($Config.GlowColor)" CornerRadius="2" Margin="2,0" VerticalAlignment="Bottom"/>
                      <Border x:Name="EqBar4" Width="4" Height="16" Background="$($Config.GlowColor)" CornerRadius="2" Margin="2,0" VerticalAlignment="Bottom"/>
                      <Border x:Name="EqBar5" Width="4" Height="22" Background="$($Config.GlowColor)" CornerRadius="2" Margin="2,0" VerticalAlignment="Bottom"/>
                      <Border x:Name="EqBar6" Width="4" Height="12" Background="$($Config.GlowColor)" CornerRadius="2" Margin="2,0" VerticalAlignment="Bottom"/>
                      <Border x:Name="EqBar7" Width="4" Height="8" Background="$($Config.GlowColor)" CornerRadius="2" Margin="2,0" VerticalAlignment="Bottom"/>
                    </StackPanel>
                  </Grid>

                  <!-- Media Pill Controls + Volume Mini -->
                  <Grid Grid.Row="3" VerticalAlignment="Bottom">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal">
                      <Button x:Name="BtnMediaPrev" Content="&#xE892;" FontFamily="Segoe MDL2 Assets"
                              FontSize="13" Foreground="$($Config.TextColor)"
                              Background="#1C1C28" BorderBrush="#33FFFFFF" BorderThickness="1"
                              Width="38" Height="32" Cursor="Hand" Focusable="False">
                        <Button.Template>
                          <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="16">
                              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                          </ControlTemplate>
                        </Button.Template>
                      </Button>

                      <Button x:Name="BtnMediaPlay" Content="&#xE768;" FontFamily="Segoe MDL2 Assets"
                              FontSize="16" Foreground="#000000"
                              Background="$($Config.GlowColor)" BorderThickness="0"
                              Width="44" Height="32" Margin="8,0" Cursor="Hand" Focusable="False">
                        <Button.Template>
                          <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="16">
                              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                          </ControlTemplate>
                        </Button.Template>
                      </Button>

                      <Button x:Name="BtnMediaNext" Content="&#xE893;" FontFamily="Segoe MDL2 Assets"
                              FontSize="13" Foreground="$($Config.TextColor)"
                              Background="#1C1C28" BorderBrush="#33FFFFFF" BorderThickness="1"
                              Width="38" Height="32" Cursor="Hand" Focusable="False">
                        <Button.Template>
                          <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="16">
                              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                          </ControlTemplate>
                        </Button.Template>
                      </Button>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <TextBlock Text="&#xE767;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="$($Config.SubtextColor)" Margin="0,0,6,0"/>
                      <TextBlock x:Name="MediaVolPct" Text="50%" Foreground="$($Config.SubtextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" Width="30"/>
                    </StackPanel>
                  </Grid>

                </Grid>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 3: STATS VIEW (Ring Gauges)                             -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewStats" Grid.Row="1" Visibility="Collapsed">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <Border Grid.Row="0" Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,12">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <!-- 1. CPU RING GAUGE -->
                  <StackPanel x:Name="RingPanelCpu" Grid.Column="0" HorizontalAlignment="Center">
                    <Grid Width="72" Height="72">
                      <Ellipse Width="60" Height="60" Stroke="#232330" StrokeThickness="5.5"/>
                      <Path x:Name="CpuArcPath" Stroke="$($Config.GlowColor)" StrokeThickness="5.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                        <TextBlock x:Name="CpuPctText" Text="0%" Foreground="$($Config.TextColor)"
                                   FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="14" FontWeight="Bold"
                                   HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Grid>
                    <TextBlock Text="CPU LOAD" Foreground="$($Config.SubtextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold"
                               HorizontalAlignment="Center" Margin="0,6,0,0"/>
                  </StackPanel>

                  <!-- 2. GPU RING GAUGE -->
                  <StackPanel x:Name="RingPanelGpu" Grid.Column="1" HorizontalAlignment="Center">
                    <Grid Width="72" Height="72">
                      <Ellipse Width="60" Height="60" Stroke="#232330" StrokeThickness="5.5"/>
                      <Path x:Name="GpuArcPath" Stroke="$($Config.AccentPurple)" StrokeThickness="5.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                        <TextBlock x:Name="GpuPctText" Text="0%" Foreground="$($Config.TextColor)"
                                   FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="14" FontWeight="Bold"
                                   HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Grid>
                    <TextBlock Text="GPU LOAD" Foreground="$($Config.SubtextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold"
                               HorizontalAlignment="Center" Margin="0,6,0,0"/>
                  </StackPanel>

                  <!-- 3. RAM RING GAUGE -->
                  <StackPanel x:Name="RingPanelRam" Grid.Column="2" HorizontalAlignment="Center">
                    <Grid Width="72" Height="72">
                      <Ellipse Width="60" Height="60" Stroke="#232330" StrokeThickness="5.5"/>
                      <Path x:Name="RamArcPath" Stroke="$($Config.AccentGreen)" StrokeThickness="5.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                        <TextBlock x:Name="RamPctText" Text="0%" Foreground="$($Config.TextColor)"
                                   FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="14" FontWeight="Bold"
                                   HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Grid>
                    <TextBlock Text="MEMORY" Foreground="$($Config.SubtextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold"
                               HorizontalAlignment="Center" Margin="0,6,0,0"/>
                  </StackPanel>

                </Grid>
              </Border>

              <Border Grid.Row="1" Background="#161622" CornerRadius="12" Margin="0,10,0,0" Padding="14,8">
                <Grid>
                  <TextBlock x:Name="StatsSummaryText" Text="Hardware Telemetry Active"
                             Foreground="$($Config.SubtextColor)" FontFamily="Segoe UI Variable Text, Segoe UI"
                             FontSize="11" HorizontalAlignment="Center"/>
                </Grid>
              </Border>

            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 4: CONTROLS VIEW (Quick Settings & Volume)              -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewControls" Grid.Row="1" Visibility="Collapsed">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <Grid Grid.Row="0" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Wi-Fi Tile -->
                <Button x:Name="BtnCtrlWifi" Grid.Column="0" Background="#14141E" BorderBrush="#1FFFFFFF" BorderThickness="1"
                        Height="64" Margin="0,0,4,0" Cursor="Hand" Focusable="False">
                  <Button.Template>
                    <ControlTemplate TargetType="Button">
                      <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                          <TextBlock Text="&#xE701;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="$($Config.GlowColor)" HorizontalAlignment="Center"/>
                          <TextBlock Text="Wi-Fi" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                        </StackPanel>
                      </Border>
                    </ControlTemplate>
                  </Button.Template>
                </Button>

                <!-- Bluetooth Tile -->
                <Button x:Name="BtnCtrlBt" Grid.Column="1" Background="#14141E" BorderBrush="#1FFFFFFF" BorderThickness="1"
                        Height="64" Margin="2,0,2,0" Cursor="Hand" Focusable="False">
                  <Button.Template>
                    <ControlTemplate TargetType="Button">
                      <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                          <TextBlock Text="&#xE702;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="$($Config.AccentPurple)" HorizontalAlignment="Center"/>
                          <TextBlock Text="Bluetooth" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                        </StackPanel>
                      </Border>
                    </ControlTemplate>
                  </Button.Template>
                </Button>

                <!-- Dark Mode Toggle Tile -->
                <Button x:Name="BtnCtrlTheme" Grid.Column="2" Background="#14141E" BorderBrush="#1FFFFFFF" BorderThickness="1"
                        Height="64" Margin="2,0,2,0" Cursor="Hand" Focusable="False">
                  <Button.Template>
                    <ControlTemplate TargetType="Button">
                      <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                          <TextBlock x:Name="ThemeTileIcon" Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="$($Config.GlowColor)" HorizontalAlignment="Center"/>
                          <TextBlock x:Name="ThemeTileText" Text="Dark Mode" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                        </StackPanel>
                      </Border>
                    </ControlTemplate>
                  </Button.Template>
                </Button>

                <!-- Task Manager Tile -->
                <Button x:Name="BtnCtrlTaskMgr" Grid.Column="3" Background="#14141E" BorderBrush="#1FFFFFFF" BorderThickness="1"
                        Height="64" Margin="4,0,0,0" Cursor="Hand" Focusable="False">
                  <Button.Template>
                    <ControlTemplate TargetType="Button">
                      <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                          <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="$($Config.AccentGreen)" HorizontalAlignment="Center"/>
                          <TextBlock Text="Task Mgr" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                        </StackPanel>
                      </Border>
                    </ControlTemplate>
                  </Button.Template>
                </Button>
              </Grid>

              <!-- Master Volume Slider Card -->
              <Border Grid.Row="1" Background="#14141E" CornerRadius="14" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,10">
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>

                  <TextBlock Grid.Column="0" Text="&#xE995;" FontFamily="Segoe MDL2 Assets" FontSize="16"
                             Foreground="$($Config.GlowColor)" VerticalAlignment="Center" Margin="0,0,12,0"/>

                  <Slider x:Name="CtrlVolSlider" Grid.Column="1" Minimum="0" Maximum="100" Value="50"
                          VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>

                  <TextBlock x:Name="CtrlVolLabel" Grid.Column="2" Text="50%" Foreground="$($Config.TextColor)"
                             FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="12" FontWeight="Bold"
                             VerticalAlignment="Center" Margin="12,0,0,0" Width="36" TextAlignment="Right"/>
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
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>

                  <Grid Grid.Row="0">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Button x:Name="BtnPowerLock" Grid.Column="0" Background="#1C1C28" BorderBrush="#25FFFFFF" BorderThickness="1"
                            Height="68" Margin="0,0,4,0" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="$($Config.GlowColor)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Lock" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnPowerSleep" Grid.Column="1" Background="#1C1C28" BorderBrush="#25FFFFFF" BorderThickness="1"
                            Height="68" Margin="2,0,2,0" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="$($Config.AccentPurple)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Sleep" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnPowerRestart" Grid.Column="2" Background="#1C1C28" BorderBrush="#25FFFFFF" BorderThickness="1"
                            Height="68" Margin="2,0,2,0" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE777;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="$($Config.WarnColor)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Restart" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>

                    <Button x:Name="BtnPowerShutdown" Grid.Column="3" Background="#1C1C28" BorderBrush="#25FFFFFF" BorderThickness="1"
                            Height="68" Margin="4,0,0,0" Cursor="Hand" Focusable="False">
                      <Button.Template>
                        <ControlTemplate TargetType="Button">
                          <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14">
                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                              <TextBlock Text="&#xE7E8;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="$($Config.CritColor)" HorizontalAlignment="Center"/>
                              <TextBlock Text="Power Off" Foreground="$($Config.TextColor)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" Margin="0,4,0,0" HorizontalAlignment="Center"/>
                            </StackPanel>
                          </Border>
                        </ControlTemplate>
                      </Button.Template>
                    </Button>
                  </Grid>

                  <Button x:Name="BtnExitIsland" Grid.Row="1" Background="#26FF1744" BorderBrush="#44FF1744" BorderThickness="1"
                          Height="32" Margin="0,10,0,0" Cursor="Hand" Focusable="False">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
                          <TextBlock Text="Quit Dynamic Island" Foreground="#FFFF5252" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="11" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                </Grid>
              </Border>
            </Grid>

            <!-- =========================================================== -->
            <!-- TAB 6: SETTINGS & INLINE CUSTOMIZATION VIEW                 -->
            <!-- =========================================================== -->
            <Grid x:Name="ViewSettings" Grid.Row="1" Visibility="Collapsed">
              <Border Background="#14141E" CornerRadius="16" BorderBrush="#1FFFFFFF" BorderThickness="1" Padding="14,10">
                <Grid>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>

                  <!-- Row 0: Aura & Accent Swatches -->
                  <Grid Grid.Row="0" Margin="0,0,0,10">
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="AURA &amp; ACCENT GLOW PRESETS" Foreground="$($Config.SubtextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="10" FontWeight="Bold" Margin="0,0,0,6"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center">
                      <Button x:Name="SwatchCyan" Content="Cyan" Width="64" Height="24" Background="#FF00E5FF" Foreground="#000000" Margin="3,0" Cursor="Hand" Focusable="False" Style="{StaticResource SwatchButtonStyle}"/>
                      <Button x:Name="SwatchMagenta" Content="Magenta" Width="64" Height="24" Background="#FFFF007F" Foreground="#FFFFFF" Margin="3,0" Cursor="Hand" Focusable="False" Style="{StaticResource SwatchButtonStyle}"/>
                      <Button x:Name="SwatchPurple" Content="Purple" Width="64" Height="24" Background="#FFA855F7" Foreground="#FFFFFF" Margin="3,0" Cursor="Hand" Focusable="False" Style="{StaticResource SwatchButtonStyle}"/>
                      <Button x:Name="SwatchEmerald" Content="Emerald" Width="64" Height="24" Background="#FF10B981" Foreground="#000000" Margin="3,0" Cursor="Hand" Focusable="False" Style="{StaticResource SwatchButtonStyle}"/>
                      <Button x:Name="SwatchAmber" Content="Amber" Width="64" Height="24" Background="#FFFF9100" Foreground="#000000" Margin="3,0" Cursor="Hand" Focusable="False" Style="{StaticResource SwatchButtonStyle}"/>
                      <Button x:Name="SwatchRed" Content="Red" Width="64" Height="24" Background="#FFFF1744" Foreground="#FFFFFF" Margin="3,0" Cursor="Hand" Focusable="False" Style="{StaticResource SwatchButtonStyle}"/>
                    </StackPanel>
                  </Grid>

                  <!-- Row 1: Glow Sliders -->
                  <Grid Grid.Row="1" Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0" Background="#1C1C28" CornerRadius="10" Padding="10,6" Margin="0,0,4,0">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="Auto"/>
                          <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0">
                          <TextBlock Text="Glow Radius" Foreground="#888899" FontSize="10" FontWeight="SemiBold"/>
                          <TextBlock x:Name="GlowRadiusLabel" Text="26px" Foreground="#FFFFFF" FontSize="10" FontWeight="Bold" HorizontalAlignment="Right"/>
                        </Grid>
                        <Slider x:Name="GlowRadiusSlider" Grid.Row="1" Minimum="10" Maximum="45" Value="26" Margin="0,4,0,0" Focusable="False" Cursor="Hand"/>
                      </Grid>
                    </Border>

                    <Border Grid.Column="1" Background="#1C1C28" CornerRadius="10" Padding="10,6" Margin="4,0,0,0">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="Auto"/>
                          <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid Grid.Row="0">
                          <TextBlock Text="Glow Opacity" Foreground="#888899" FontSize="10" FontWeight="SemiBold"/>
                          <TextBlock x:Name="GlowOpacityLabel" Text="55%" Foreground="#FFFFFF" FontSize="10" FontWeight="Bold" HorizontalAlignment="Right"/>
                        </Grid>
                        <Slider x:Name="GlowOpacitySlider" Grid.Row="1" Minimum="20" Maximum="90" Value="55" Margin="0,4,0,0" Focusable="False" Cursor="Hand"/>
                      </Grid>
                    </Border>
                  </Grid>

                  <!-- Row 2: Tab Modules Visibility Toggles -->
                  <Grid Grid.Row="2" Margin="0,0,0,10">
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="NAVIGATION TAB MODULES" Foreground="$($Config.SubtextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="10" FontWeight="Bold" Margin="0,0,0,6"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center">
                      <Button x:Name="ToggleTabToday" Content="[ON] Today" Width="76" Height="24" Margin="3,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                      <Button x:Name="ToggleTabMedia" Content="[ON] Media" Width="76" Height="24" Margin="3,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                      <Button x:Name="ToggleTabStats" Content="[ON] Stats" Width="76" Height="24" Margin="3,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                      <Button x:Name="ToggleTabControls" Content="[ON] Controls" Width="84" Height="24" Margin="3,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                      <Button x:Name="ToggleTabPower" Content="[ON] Power" Width="76" Height="24" Margin="3,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                    </StackPanel>
                  </Grid>

                  <!-- Row 3: Telemetry Ring Modules Toggles -->
                  <Grid Grid.Row="3">
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="TELEMETRY RINGS" Foreground="$($Config.SubtextColor)"
                               FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="10" FontWeight="Bold" Margin="0,0,0,6"/>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center">
                      <Button x:Name="ToggleRingCpu" Content="[ON] CPU" Width="76" Height="24" Margin="4,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                      <Button x:Name="ToggleRingGpu" Content="[ON] GPU" Width="76" Height="24" Margin="4,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                      <Button x:Name="ToggleRingRam" Content="[ON] RAM" Width="76" Height="24" Margin="4,0" Style="{StaticResource ToggleModuleButtonStyle}"/>
                    </StackPanel>
                  </Grid>

                </Grid>
              </Border>
            </Grid>

          </Grid>
          <!-- END EXPANDED DASHBOARD VIEW -->

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
$todayClockText  = $window.FindName('TodayClockText')
$todayDateText   = $window.FindName('TodayDateText')
$todayGreeting   = $window.FindName('TodayGreeting')
$todayBattIcon   = $window.FindName('TodayBattIcon')
$todayBattPct    = $window.FindName('TodayBattPct')
$todayBattBar    = $window.FindName('TodayBattBar')
$todayBattStatus = $window.FindName('TodayBattStatus')
$todayMiniCpu    = $window.FindName('TodayMiniCpu')
$todayMiniGpu    = $window.FindName('TodayMiniGpu')
$todayMiniRam    = $window.FindName('TodayMiniRam')

# Tab 2: Media Elements
$mediaTitleText  = $window.FindName('MediaTitleText')
$mediaArtistText = $window.FindName('MediaArtistText')
$mediaWaveLine   = $window.FindName('MediaWaveLine')
$eqBars          = @(
    $window.FindName('EqBar1'), $window.FindName('EqBar2'), $window.FindName('EqBar3'),
    $window.FindName('EqBar4'), $window.FindName('EqBar5'), $window.FindName('EqBar6'), $window.FindName('EqBar7')
)
$btnMediaPrev    = $window.FindName('BtnMediaPrev')
$btnMediaPlay    = $window.FindName('BtnMediaPlay')
$btnMediaNext    = $window.FindName('BtnMediaNext')
$mediaVolPct     = $window.FindName('MediaVolPct')

# Tab 3: Stats Elements
$ringPanelCpu    = $window.FindName('RingPanelCpu')
$ringPanelGpu    = $window.FindName('RingPanelGpu')
$ringPanelRam    = $window.FindName('RingPanelRam')
$cpuArcPath      = $window.FindName('CpuArcPath')
$gpuArcPath      = $window.FindName('GpuArcPath')
$ramArcPath      = $window.FindName('RamArcPath')
$cpuPctText      = $window.FindName('CpuPctText')
$gpuPctText      = $window.FindName('GpuPctText')
$ramPctText      = $window.FindName('RamPctText')
$statsSummaryText= $window.FindName('StatsSummaryText')

# Tab 4: Controls Elements
$btnCtrlWifi     = $window.FindName('BtnCtrlWifi')
$btnCtrlBt       = $window.FindName('BtnCtrlBt')
$btnCtrlTheme    = $window.FindName('BtnCtrlTheme')
$btnCtrlTaskMgr  = $window.FindName('BtnCtrlTaskMgr')
$themeTileIcon   = $window.FindName('ThemeTileIcon')
$themeTileText   = $window.FindName('ThemeTileText')
$ctrlVolSlider   = $window.FindName('CtrlVolSlider')
$ctrlVolLabel    = $window.FindName('CtrlVolLabel')

# Tab 5: Power Elements
$btnPowerLock    = $window.FindName('BtnPowerLock')
$btnPowerSleep   = $window.FindName('BtnPowerSleep')
$btnPowerRestart = $window.FindName('BtnPowerRestart')
$btnPowerShutdown= $window.FindName('BtnPowerShutdown')
$btnExitIsland   = $window.FindName('BtnExitIsland')

# Tab 6: Settings Elements
$swatchCyan      = $window.FindName('SwatchCyan')
$swatchMagenta   = $window.FindName('SwatchMagenta')
$swatchPurple    = $window.FindName('SwatchPurple')
$swatchEmerald   = $window.FindName('SwatchEmerald')
$swatchAmber     = $window.FindName('SwatchAmber')
$swatchRed       = $window.FindName('SwatchRed')
$glowRadiusSlider= $window.FindName('GlowRadiusSlider')
$glowRadiusLabel = $window.FindName('GlowRadiusLabel')
$glowOpacitySlider=$window.FindName('GlowOpacitySlider')
$glowOpacityLabel =$window.FindName('GlowOpacityLabel')
$toggleTabToday  = $window.FindName('ToggleTabToday')
$toggleTabMedia  = $window.FindName('ToggleTabMedia')
$toggleTabStats  = $window.FindName('ToggleTabStats')
$toggleTabControls=$window.FindName('ToggleTabControls')
$toggleTabPower  = $window.FindName('ToggleTabPower')
$toggleRingCpu   = $window.FindName('ToggleRingCpu')
$toggleRingGpu   = $window.FindName('ToggleRingGpu')
$toggleRingRam   = $window.FindName('ToggleRingRam')

# Runtime States
$script:expanded       = $false
$script:pinned         = $false
$script:isDragging     = $false
$script:activeTab      = 'Today'
$script:pct            = 0
$script:charging       = $false
$script:tick           = 0
$script:mediaAutoShown = $false
$script:wavePhase      = 0.0
$script:totalRamGB     = [SysMem]::GetTotalPhysicalGB()

# Pre-compiled Brushes
$bc = [System.Windows.Media.BrushConverter]::new()
$script:brushWhite       = [System.Windows.Media.Brushes]::White
$script:brushSub         = $bc.ConvertFromString($Config.SubtextColor); $script:brushSub.Freeze()
$script:brushGreen       = $bc.ConvertFromString($Config.AccentGreen);  $script:brushGreen.Freeze()
$script:brushRed         = $bc.ConvertFromString($Config.CritColor);    $script:brushRed.Freeze()
$script:brushInactiveTab = [System.Windows.Media.Brushes]::Transparent

$script:colorWarn        = [System.Windows.Media.ColorConverter]::ConvertFromString($Config.WarnColor)
$script:colorCrit        = [System.Windows.Media.ColorConverter]::ConvertFromString($Config.CritColor)

# Dynamic Aura Theme Applicator
function Apply-AuraTheme ([string]$hexColor) {
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
    foreach ($b in $eqBars) { $b.Background = $script:brushAccentSolid }

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

# Hidden from Alt-Tab
$window.Add_SourceInitialized({
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
    $s = [IslandNative]::GetWindowLong($h, -20)
    [IslandNative]::SetWindowLong($h, -20, ($s -bor 0x80)) | Out-Null
})

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
}

function Switch-Tab ([string]$tabName) {
    if (-not $script:allTabs.ContainsKey($tabName)) { return }
    $script:activeTab = $tabName
    $viewSettings.Visibility = 'Collapsed'
    $btnSettings.Foreground  = $script:brushSub

    foreach ($key in $script:allTabs.Keys) {
        $item = $script:allTabs[$key]
        if ($key -eq $tabName) {
            # Active Cylindrical Pill Highlight
            $item.Btn.Background      = $script:brushActiveTab
            $item.Btn.BorderBrush     = $script:brushAccentBorder
            $item.Btn.BorderThickness = New-Object System.Windows.Thickness(1)
            $item.Btn.Foreground      = $script:brushWhite
            $item.View.Visibility     = 'Visible'

            $a = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, [TimeSpan]::FromMilliseconds(160))
            $item.View.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
        } else {
            # Inactive Pill
            $item.Btn.Background      = $script:brushInactiveTab
            $item.Btn.BorderThickness = New-Object System.Windows.Thickness(0)
            $item.Btn.Foreground      = $script:brushSub
            $item.View.Visibility     = 'Collapsed'
        }
    }
}

$tabBtnToday.Add_Click({ Switch-Tab 'Today' })
$tabBtnMedia.Add_Click({ Switch-Tab 'Media' })
$tabBtnStats.Add_Click({ Switch-Tab 'Stats' })
$tabBtnControls.Add_Click({ Switch-Tab 'Controls' })
$tabBtnPower.Add_Click({ Switch-Tab 'Power' })

# Settings / Customization View Toggle
$btnSettings.Add_Click({
    if ($viewSettings.Visibility -eq 'Visible') {
        Switch-Tab $script:activeTab
    } else {
        foreach ($k in $script:allTabs.Keys) {
            $script:allTabs[$k].View.Visibility = 'Collapsed'
            $script:allTabs[$k].Btn.Background  = $script:brushInactiveTab
            $script:allTabs[$k].Btn.Foreground  = $script:brushSub
            $script:allTabs[$k].Btn.BorderThickness = New-Object System.Windows.Thickness(0)
        }
        $viewSettings.Visibility = 'Visible'
        $btnSettings.Foreground  = $script:brushAccentSolid
        $a = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, [TimeSpan]::FromMilliseconds(160))
        $viewSettings.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
    }
})

# Pin Button Toggle
$btnPin.Add_Click({
    $script:pinned = -not $script:pinned
    if ($script:pinned) {
        $btnPin.Foreground = $script:brushAccentSolid
        $btnPin.Content    = [char]0xE840
    } else {
        $btnPin.Foreground = $script:brushSub
        $btnPin.Content    = [char]0xE718
    }
})

# ------------------------------------------------------------------------------
#  S8  CUSTOMIZATION EVENT HANDLERS (Aura Presets & Module Toggles)
# ------------------------------------------------------------------------------
# 1. Swatches
$swatchCyan.Add_Click({    Apply-AuraTheme '#00E5FF' })
$swatchMagenta.Add_Click({ Apply-AuraTheme '#FF007F' })
$swatchPurple.Add_Click({  Apply-AuraTheme '#A855F7' })
$swatchEmerald.Add_Click({ Apply-AuraTheme '#10B981' })
$swatchAmber.Add_Click({   Apply-AuraTheme '#FF9100' })
$swatchRed.Add_Click({     Apply-AuraTheme '#FF1744' })

# 2. Glow Sliders
$glowRadiusSlider.Value = $Config.GlowRadius
$glowRadiusLabel.Text   = "$($Config.GlowRadius)px"
$glowRadiusSlider.Add_ValueChanged({
    $val = [int]$glowRadiusSlider.Value
    $Config.GlowRadius    = $val
    $glowFx.BlurRadius    = $val
    $glowRadiusLabel.Text = "${val}px"
    Save-Config
})

$glowOpacitySlider.Value = [int]($Config.GlowOpacity * 100)
$glowOpacityLabel.Text   = "$([int]($Config.GlowOpacity * 100))%"
$glowOpacitySlider.Add_ValueChanged({
    $val = [int]$glowOpacitySlider.Value
    $dec = $val / 100.0
    $Config.GlowOpacity    = $dec
    $glowFx.Opacity        = $dec
    $glowOpacityLabel.Text = "${val}%"
    Save-Config
})

# 3. Tab Visibility Toggles
function Sync-TabToggles {
    $tabBtnToday.Visibility    = if ($Config.Tabs.Today)    { 'Visible' } else { 'Collapsed' }
    $tabBtnMedia.Visibility    = if ($Config.Tabs.Media)    { 'Visible' } else { 'Collapsed' }
    $tabBtnStats.Visibility    = if ($Config.Tabs.Stats)    { 'Visible' } else { 'Collapsed' }
    $tabBtnControls.Visibility = if ($Config.Tabs.Controls) { 'Visible' } else { 'Collapsed' }
    $tabBtnPower.Visibility    = if ($Config.Tabs.Power)    { 'Visible' } else { 'Collapsed' }

    $toggleTabToday.Content    = if ($Config.Tabs.Today)    { '[ON] Today' } else { '[OFF] Today' }
    $toggleTabMedia.Content    = if ($Config.Tabs.Media)    { '[ON] Media' } else { '[OFF] Media' }
    $toggleTabStats.Content    = if ($Config.Tabs.Stats)    { '[ON] Stats' } else { '[OFF] Stats' }
    $toggleTabControls.Content = if ($Config.Tabs.Controls) { '[ON] Controls' } else { '[OFF] Controls' }
    $toggleTabPower.Content    = if ($Config.Tabs.Power)    { '[ON] Power' } else { '[OFF] Power' }
}
Sync-TabToggles

$toggleTabToday.Add_Click({
    $Config.Tabs.Today = -not $Config.Tabs.Today
    Sync-TabToggles; Save-Config
})
$toggleTabMedia.Add_Click({
    $Config.Tabs.Media = -not $Config.Tabs.Media
    Sync-TabToggles; Save-Config
})
$toggleTabStats.Add_Click({
    $Config.Tabs.Stats = -not $Config.Tabs.Stats
    Sync-TabToggles; Save-Config
})
$toggleTabControls.Add_Click({
    $Config.Tabs.Controls = -not $Config.Tabs.Controls
    Sync-TabToggles; Save-Config
})
$toggleTabPower.Add_Click({
    $Config.Tabs.Power = -not $Config.Tabs.Power
    Sync-TabToggles; Save-Config
})

# 4. Ring Modules Toggles
function Sync-RingToggles {
    $ringPanelCpu.Visibility = if ($Config.StatsModules.Cpu) { 'Visible' } else { 'Collapsed' }
    $ringPanelGpu.Visibility = if ($Config.StatsModules.Gpu) { 'Visible' } else { 'Collapsed' }
    $ringPanelRam.Visibility = if ($Config.StatsModules.Ram) { 'Visible' } else { 'Collapsed' }

    $toggleRingCpu.Content = if ($Config.StatsModules.Cpu) { '[ON] CPU' } else { '[OFF] CPU' }
    $toggleRingGpu.Content = if ($Config.StatsModules.Gpu) { '[ON] GPU' } else { '[OFF] GPU' }
    $toggleRingRam.Content = if ($Config.StatsModules.Ram) { '[ON] RAM' } else { '[OFF] RAM' }
}
Sync-RingToggles

$toggleRingCpu.Add_Click({
    $Config.StatsModules.Cpu = -not $Config.StatsModules.Cpu
    Sync-RingToggles; Save-Config
})
$toggleRingGpu.Add_Click({
    $Config.StatsModules.Gpu = -not $Config.StatsModules.Gpu
    Sync-RingToggles; Save-Config
})
$toggleRingRam.Add_Click({
    $Config.StatsModules.Ram = -not $Config.StatsModules.Ram
    Sync-RingToggles; Save-Config
})

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

    $hr = $now.Hour
    $todayGreeting.Text  = if ($hr -lt 12) { 'Good Morning' } elseif ($hr -lt 18) { 'Good Afternoon' } else { 'Good Evening' }

    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    $script:pct = [int][math]::Round($ps.BatteryLifePercent * 100)
    $script:charging = ($ps.PowerLineStatus -eq 'Online')

    $battGlyph = if ($script:charging) { [char]0xEA93 } else { [char]0xEA81 }
    $compactBattIcon.Text = [string]$battGlyph
    $compactBattText.Text = "$($script:pct)%"

    $todayBattIcon.Text   = [string]$battGlyph
    $todayBattPct.Text    = "$($script:pct)%"
    $todayBattStatus.Text = if ($script:charging) { 'AC Connected  |  Charging' } else { 'Battery  |  Discharging' }
    $todayBattBar.Width   = [math]::Max(4, [int](($script:pct / 100.0) * 150))

    if ($script:pct -le 20 -and -not $script:charging) {
        $compactBattIcon.Foreground = $script:brushRed
        $todayBattBar.Background    = $script:brushRed
    } else {
        $compactBattIcon.Foreground = $script:brushGreen
        $todayBattBar.Background    = $script:brushGreen
    }
}

function Update-UIFromBackgroundState {
    # 1. Telemetry
    $cpu = $script:sharedState.Cpu
    $gpu = $script:sharedState.Gpu
    $ram = $script:sharedState.Ram

    $cpuPctText.Text   = "${cpu}%"
    $gpuPctText.Text   = "${gpu}%"
    $ramPctText.Text   = "${ram}%"
    $todayMiniCpu.Text = "${cpu}%"
    $todayMiniGpu.Text = "${gpu}%"
    $todayMiniRam.Text = "${ram}%"

    $compactLoadText.Text = "CPU ${cpu}%"

    $cpuArcPath.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 36 36 30 $cpu))
    $gpuArcPath.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 36 36 30 $gpu))
    $ramArcPath.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 36 36 30 $ram))

    $statsSummaryText.Text = "CPU: ${cpu}%  |  GPU: ${gpu}%  |  RAM: ${ram}% of $($script:totalRamGB) GB"

    # Dynamic Load/Thermal Reactive Glow
    if ($Config.EnableDynamicGlow) {
        $peak = [math]::Max($cpu, $gpu)
        $targetColor = if ($peak -ge 92)     { $script:colorCrit }
                       elseif ($peak -ge 78) { $script:colorWarn }
                       else                  { [System.Windows.Media.ColorConverter]::ConvertFromString($Config.GlowColor) }

        if ($glowFx.Color -ne $targetColor) {
            $ca = New-Object System.Windows.Media.Animation.ColorAnimation($targetColor, [TimeSpan]::FromMilliseconds(500))
            $glowFx.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::ColorProperty, $ca)
        }
    }

    # 2. Media Info
    $title  = $script:sharedState.MediaTitle
    $artist = $script:sharedState.MediaArtist
    $status = $script:sharedState.MediaStatus

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
            if (-not $script:mediaAutoShown) {
                $script:mediaAutoShown = $true
                Switch-Tab 'Media'
                Expand-Island
                $script:autoCollapseTimer.Interval = [TimeSpan]::FromMilliseconds($Config.MediaPopupMs)
                $script:autoCollapseTimer.Start()
            }
        }
    }
    $script:lastMediaTitle = $title
}

# ------------------------------------------------------------------------------
#  S10  60 FPS AUDIO EQUALIZER (High-Speed Lightweight Animation)
# ------------------------------------------------------------------------------
$waveTimer = New-Object System.Windows.Threading.DispatcherTimer
$waveTimer.Interval = [TimeSpan]::FromMilliseconds(35)
$waveTimer.Add_Tick({
    if ($script:sharedState.MediaStatus -eq 'Playing') {
        $script:wavePhase += 0.28

        $eqBars[0].Height = 4 + [int](14 * [math]::Abs([math]::Sin($script:wavePhase * 1.1)))
        $eqBars[1].Height = 4 + [int](18 * [math]::Abs([math]::Cos($script:wavePhase * 0.9 + 0.4)))
        $eqBars[2].Height = 4 + [int](20 * [math]::Abs([math]::Sin($script:wavePhase * 1.4 + 1.2)))
        $eqBars[3].Height = 5 + [int](22 * [math]::Abs([math]::Cos($script:wavePhase * 1.3 + 2.0)))
        $eqBars[4].Height = 4 + [int](18 * [math]::Abs([math]::Sin($script:wavePhase * 0.8 + 0.7)))
        $eqBars[5].Height = 4 + [int](16 * [math]::Abs([math]::Cos($script:wavePhase * 1.2 + 1.5)))
        $eqBars[6].Height = 4 + [int](13 * [math]::Abs([math]::Sin($script:wavePhase * 1.5 + 2.3)))

        $p1 = 13 + [int](8 * [math]::Sin($script:wavePhase * 1.2))
        $p2 = 13 - [int](9 * [math]::Cos($script:wavePhase * 1.4))
        $p3 = 13 + [int](7 * [math]::Sin($script:wavePhase * 0.9))
        $mediaWaveLine.Data = [System.Windows.Media.Geometry]::Parse("M 0,13 Q 30,$p1 60,13 T 120,13 T 180,$p2 T 240,13 T 300,$p3")
    } else {
        foreach ($b in $eqBars) { if ($b.Height -gt 4) { $b.Height = [math]::Max(4, $b.Height - 1) } }
        $mediaWaveLine.Data = [System.Windows.Media.Geometry]::Parse("M 0,13 L 280,13")
    }
})

# ------------------------------------------------------------------------------
#  S11  QUICK CONTROLS & VOLUME
# ------------------------------------------------------------------------------
function Sync-VolumeUI {
    $vol = [int][math]::Round([AudioMasterSafe]::GetVolume())
    $ctrlVolSlider.Value = $vol
    $ctrlVolLabel.Text   = "${vol}%"
    $mediaVolPct.Text    = "${vol}%"
}

$ctrlVolSlider.Add_ValueChanged({
    $v = [float]$ctrlVolSlider.Value
    [AudioMasterSafe]::SetVolume($v)
    $intV = [int][math]::Round($v)
    $ctrlVolLabel.Text = "${intV}%"
    $mediaVolPct.Text  = "${intV}%"
})

function Update-ThemeButtonText {
    $reg = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
    $isLight = ($null -ne $reg -and $reg.AppsUseLightTheme -eq 1)
    if ($isLight) {
        $themeTileIcon.Text = [string][char]0xE706
        $themeTileText.Text = 'Light Mode'
    } else {
        $themeTileIcon.Text = [string][char]0xE708
        $themeTileText.Text = 'Dark Mode'
    }
}
Update-ThemeButtonText

$btnCtrlTheme.Add_Click({
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $reg = Get-ItemProperty -Path $regPath -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
    $cur = if ($null -ne $reg) { $reg.AppsUseLightTheme } else { 0 }
    $newVal = if ($cur -eq 1) { 0 } else { 1 }
    Set-ItemProperty -Path $regPath -Name "AppsUseLightTheme" -Value $newVal -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $regPath -Name "SystemUsesLightTheme" -Value $newVal -ErrorAction SilentlyContinue
    Update-ThemeButtonText
})

$btnCtrlWifi.Add_Click({ Start-Process "ms-settings:network-wifi" })
$btnCtrlBt.Add_Click({   Start-Process "ms-settings:bluetooth" })
$btnCtrlTaskMgr.Add_Click({ Start-Process "taskmgr.exe" })

$btnPowerLock.Add_Click({     [IslandNative]::LockWorkStation() | Out-Null })
$btnPowerSleep.Add_Click({    [IslandNative]::SetSuspendState($false, $false, $false) | Out-Null })
$btnPowerRestart.Add_Click({  Start-Process "shutdown.exe" -ArgumentList "/r /t 0" })
$btnPowerShutdown.Add_Click({ Start-Process "shutdown.exe" -ArgumentList "/s /t 0" })
$btnExitIsland.Add_Click({    $window.Close() })

$btnMediaPrev.Add_Click({ Send-MediaCommand 'Previous' })
$btnMediaPlay.Add_Click({ Send-MediaCommand 'PlayPause' })
$btnMediaNext.Add_Click({ Send-MediaCommand 'Next' })

# ------------------------------------------------------------------------------
#  S12  EVENT TRIGGERS: HOVER, FREE DRAG & VOLUME SCROLL
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
        $e.OriginalSource -isnot [System.Windows.Controls.Primitives.Thumb]) {
        $script:isDragging = $true
        $window.DragMove()
        $script:isDragging = $false
        $Config.X = $window.Left
        $Config.Y = $window.Top
        Save-Config
    }
})

# Mouse Wheel Quick Volume Scroll
if ($Config.EnableVolumeScroll) {
    $glowBorder.Add_MouseWheel({
        param($sender, $e)
        $cur = [AudioMasterSafe]::GetVolume()
        $delta = if ($e.Delta -gt 0) { 3.0 } else { -3.0 }
        $newVol = [math]::Min([math]::Max(($cur + $delta), 0.0), 100.0)
        [AudioMasterSafe]::SetVolume($newVol)
        Sync-VolumeUI
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
#  S13  UI TIMERS & LAUNCH
# ------------------------------------------------------------------------------
$clockTimer = New-Object System.Windows.Threading.DispatcherTimer
$clockTimer.Interval = [TimeSpan]::FromSeconds(1)
$clockTimer.Add_Tick({
    $script:tick++
    if ($script:tick % 30 -eq 0) { Update-ClockAndBattery }
    else {
        $compactTime.Text    = (Get-Date).ToString('h:mm tt')
        $todayClockText.Text = (Get-Date).ToString('h:mm tt')
    }
})

$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$uiTimer.Add_Tick({ Update-UIFromBackgroundState })

# Initial paint
Update-ClockAndBattery
Update-UIFromBackgroundState
Sync-VolumeUI

$clockTimer.Start()
$uiTimer.Start()
$waveTimer.Start()

$window.ShowDialog() | Out-Null
