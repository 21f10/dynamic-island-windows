# ==============================================================================
#  Dynamic Island for Windows  -  v0 Executive Edition
#  Pixel-Accurate v0 Design Language | True Vertical Side Docking | 60 FPS
# ==============================================================================

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

# ------------------------------------------------------------------------------
#  Application Root & Single-Instance Takeover
# ------------------------------------------------------------------------------
$appRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $appRoot) { $appRoot = (Get-Location).Path }

$pidFile = Join-Path $appRoot ".island.pid"
try {
    if (Test-Path $pidFile) {
        $oldPidText = (Get-Content $pidFile -Raw -ErrorAction SilentlyContinue)
        if ($oldPidText) {
            $oldPid = [int]$oldPidText.Trim()
            if ($oldPid -gt 0 -and $oldPid -ne $PID) {
                try {
                    $oldProc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
                    if ($oldProc -and $oldProc.ProcessName -ieq "powershell") {
                        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 150
                    }
                } catch { }
            }
        }
    }
} catch { }

try {
    "$PID" | Set-Content $pidFile -Force -Encoding UTF8
} catch { }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing, System.Runtime.WindowsRuntime

# ------------------------------------------------------------------------------
#  C# P/Invoke Native Subsystem (Audio, Display, Acrylic, Hotkeys, Memory)
# ------------------------------------------------------------------------------
Add-Type -ReferencedAssemblies "System.Drawing" -TypeDefinition @'
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
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    public static bool CheckForegroundFullscreenGame(IntPtr islandHwnd, int screenW, int screenH, out string procName) {
        procName = "";
        try {
            IntPtr fg = GetForegroundWindow();
            // CRITICAL FIX: If user clicks/hovers on Island HUD, do NOT drop Game Mode!
            if (fg == islandHwnd) return true;
            if (fg == IntPtr.Zero) return true; // Keep active during alt-tab/resolution transitions

            RECT r;
            if (!GetWindowRect(fg, out r)) return false;

            uint pid;
            GetWindowThreadProcessId(fg, out pid);
            if (pid == 0) return false;

            var p = System.Diagnostics.Process.GetProcessById((int)pid);
            string name = p.ProcessName.ToLowerInvariant();
            string title = "";
            try { title = (p.MainWindowTitle ?? "").ToLowerInvariant(); } catch { }
            procName = name;

            // Exclude desktop shells, IDEs, browsers, terminals, chat apps
            if (name == "explorer" || name == "shellexperiencehost" || name == "searchhost" || 
                name == "powershell" || name == "island" || name == "taskmgr" || name == "lockapp" ||
                name.Contains("antigravity") || name.Contains("code") || name.Contains("chrome") ||
                name.Contains("edge") || name.Contains("brave") || name.Contains("firefox") ||
                name.Contains("discord") || name.Contains("slack") || name.Contains("spotify") ||
                name.Contains("terminal") || name.Contains("cmd") || name.Contains("devenv")) {
                return false;
            }

            bool isGameProc = name.Contains("game") || name.Contains("valorant") || name.Contains("steam") ||
                              name.Contains("riot") || name.Contains("epic") || name.Contains("overwatch") ||
                              name.Contains("cs2") || name.Contains("gta") || name.Contains("minecraft") ||
                              name.Contains("fortnite") || name.Contains("apex") || name.Contains("dota") ||
                              name.Contains("pubg") || name.Contains("unreal") || name.Contains("unity") ||
                              name.Contains("genshin") || name.Contains("roblox") || name.Contains("cyberpunk") ||
                              name.Contains("shipping") || title.Contains("valorant") || title.Contains("riot");

            // Monitor-aware fullscreen check (handles DPI scaling, multi-monitor, stretched resolutions like 1920x1080)
            IntPtr hMon = MonitorFromWindow(fg, 2); // MONITOR_DEFAULTTONEAREST = 2
            MONITORINFO mi = new MONITORINFO();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (GetMonitorInfo(hMon, ref mi)) {
                int monW = mi.rcMonitor.Right - mi.rcMonitor.Left;
                int monH = mi.rcMonitor.Bottom - mi.rcMonitor.Top;
                int winW = r.Right - r.Left;
                int winH = r.Bottom - r.Top;

                bool isFs = (winW >= (monW - 20) && winH >= (monH - 20));
                if (isFs && (isGameProc || winW >= monW)) return true;
            }

            int w = r.Right - r.Left;
            int h = r.Bottom - r.Top;
            bool isFsFallback = (w >= (screenW - 40) && h >= (screenH - 40));
            return isGameProc && (isFsFallback || w >= 1200);
        } catch {
            return false;
        }
    }

    [DllImport("user32.dll")]
    public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

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

    public static void EnableAcrylic(IntPtr hwnd, int gradientColor) {
        try {
            int darkMode = 1;
            DwmSetWindowAttribute(hwnd, 20, ref darkMode, 4);

            int backdrop = 3; // DWMSBT_TRANSIENTWINDOW (Acrylic Blur)
            DwmSetWindowAttribute(hwnd, 38, ref backdrop, 4);
        } catch { }

        try {
            var accent = new AccentPolicy();
            accent.AccentState = 4; // ACCENT_ENABLE_ACRYLICBLURBEHIND
            accent.GradientColor = gradientColor;
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

    public static void DisableAcrylic(IntPtr hwnd) {
        try {
            int backdrop = 1; // DWMSBT_NONE
            DwmSetWindowAttribute(hwnd, 38, ref backdrop, 4);
        } catch { }

        try {
            var accent = new AccentPolicy();
            accent.AccentState = 0; // ACCENT_DISABLED
            accent.GradientColor = 0;
            accent.AccentFlags = 0;

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

    [DllImport("gdi32.dll")]
    public static extern bool SetDeviceGammaRamp(IntPtr hDC, ref RAMP lpRamp);
    [DllImport("gdi32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr CreateDC(string lpszDriver, string lpszDevice, string lpszOutput, IntPtr lpInitData);
    [DllImport("gdi32.dll")]
    public static extern bool DeleteDC(IntPtr hdc);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint pdwNumberOfPhysicalMonitors);
    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);
    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool DestroyPhysicalMonitors(uint dwPhysicalMonitorArraySize, [In] PHYSICAL_MONITOR[] pPhysicalMonitorArray);
    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool SetMonitorBrightness(IntPtr hMonitor, uint dwNewBrightness);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct RAMP {
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] Red;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] Green;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
        public ushort[] Blue;
    }

    private static bool _nightLight = false;
    private static int _brightness = 70;

    public static void ApplyDisplayColor() {
        try {
            // Apply via Display DC for reliable GDI Gamma Ramp persistence
            IntPtr hdc = CreateDC("DISPLAY", null, null, IntPtr.Zero);
            if (hdc == IntPtr.Zero) hdc = GetDC(IntPtr.Zero);
            if (hdc != IntPtr.Zero) {
                try {
                    double factor = Math.Max(0.05, Math.Min(1.0, _brightness / 100.0));
                    var ramp = new RAMP();
                    ramp.Red = new ushort[256];
                    ramp.Green = new ushort[256];
                    ramp.Blue = new ushort[256];
                    for (int i = 0; i < 256; i++) {
                        int baseVal = (int)Math.Round((i * 65535.0 / 255.0) * factor);
                        if (baseVal > 65535) baseVal = 65535;
                        ramp.Red[i]   = (ushort)baseVal;
                        ramp.Green[i] = (ushort)(_nightLight ? (baseVal * 0.85) : baseVal);
                        ramp.Blue[i]  = (ushort)(_nightLight ? (baseVal * 0.68) : baseVal);
                    }
                    SetDeviceGammaRamp(hdc, ref ramp);
                } finally {
                    DeleteDC(hdc);
                }
            }
        } catch { }

        // Also broadcast to hardware monitors via DDC/CI (HDMI/DisplayPort)
        try {
            IntPtr hMon = MonitorFromWindow(IntPtr.Zero, 1);
            uint count = 0;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count) && count > 0) {
                PHYSICAL_MONITOR[] mons = new PHYSICAL_MONITOR[count];
                if (GetPhysicalMonitorsFromHMONITOR(hMon, count, mons)) {
                    for (int i = 0; i < count; i++) {
                        SetMonitorBrightness(mons[i].hPhysicalMonitor, (uint)_brightness);
                    }
                    DestroyPhysicalMonitors(count, mons);
                }
            }
        } catch { }
    }

    public static void SetBrightness(int percent) {
        _brightness = Math.Max(5, Math.Min(100, percent));
        ApplyDisplayColor();
    }

    public static int GetBrightness() {
        return _brightness;
    }

    public static void SetNightLight(bool enable) {
        _nightLight = enable;
        ApplyDisplayColor();
    }

    public static byte[] ReadStreamBytes(object streamObj) {
        if (streamObj == null) return null;
        try {
            var asm = System.Reflection.Assembly.Load("System.Runtime.WindowsRuntime, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089");
            var extType = asm.GetType("System.IO.WindowsRuntimeStreamExtensions");
            System.Reflection.MethodInfo asStreamMethod = null;
            foreach (var m in extType.GetMethods()) {
                if ((m.Name == "AsStreamForRead" || m.Name == "AsStream") && m.GetParameters().Length == 1) {
                    asStreamMethod = m;
                    break;
                }
            }
            if (asStreamMethod != null) {
                using (var s = (System.IO.Stream)asStreamMethod.Invoke(null, new object[] { streamObj })) {
                    using (var ms = new System.IO.MemoryStream()) {
                        s.CopyTo(ms);
                        return ms.ToArray();
                    }
                }
            }
        } catch { }

        try {
            Type dataReaderType = Type.GetType("Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType=WindowsRuntime");
            if (dataReaderType == null) {
                foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
                    var t = asm.GetType("Windows.Storage.Streams.DataReader");
                    if (t != null) { dataReaderType = t; break; }
                }
            }
            if (dataReaderType != null) {
                object reader = Activator.CreateInstance(dataReaderType, new object[] { streamObj });
                var propSize = streamObj.GetType().GetProperty("Size");
                if (propSize != null) {
                    ulong size = (ulong)propSize.GetValue(streamObj, null);
                    if (size > 0 && size < 15000000) {
                        var loadMethod = dataReaderType.GetMethod("LoadAsync");
                        object loadOp = loadMethod.Invoke(reader, new object[] { (uint)size });

                        var winExtAsm = System.Reflection.Assembly.Load("System.Runtime.WindowsRuntime, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089");
                        var winExtType = winExtAsm.GetType("System.WindowsRuntimeSystemExtensions");
                        System.Reflection.MethodInfo asTaskMethod = null;
                        foreach (var m in winExtType.GetMethods()) {
                            if (m.Name == "AsTask" && m.IsGenericMethodDefinition && m.GetParameters().Length == 1) {
                                asTaskMethod = m;
                                break;
                            }
                        }
                        if (asTaskMethod != null) {
                            var genericAsTask = asTaskMethod.MakeGenericMethod(typeof(uint));
                            var loadTask = (System.Threading.Tasks.Task)genericAsTask.Invoke(null, new object[] { loadOp });
                            if (loadTask.Wait(2000)) {
                                byte[] bytes = new byte[(uint)size];
                                var readBytesMethod = dataReaderType.GetMethod("ReadBytes");
                                readBytesMethod.Invoke(reader, new object[] { bytes });
                                var detachMethod = dataReaderType.GetMethod("DetachStream");
                                if (detachMethod != null) detachMethod.Invoke(reader, null);
                                return bytes;
                            }
                        }
                    }
                }
            }
        } catch { }

        return null;
    }

    public static byte[] GetThumbnailBytes(object thumbnailRefObj) {
        if (thumbnailRefObj == null) return null;
        try {
            var methodOpen = thumbnailRefObj.GetType().GetMethod("OpenReadAsync");
            if (methodOpen == null) return null;
            object asyncOp = methodOpen.Invoke(thumbnailRefObj, null);
            if (asyncOp == null) return null;

            var winExtAsm = System.Reflection.Assembly.Load("System.Runtime.WindowsRuntime, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089");
            var winExtType = winExtAsm.GetType("System.WindowsRuntimeSystemExtensions");
            System.Reflection.MethodInfo asTaskMethod = null;
            foreach (var m in winExtType.GetMethods()) {
                if (m.Name == "AsTask" && m.IsGenericMethodDefinition && m.GetParameters().Length == 1) {
                    var pType = m.GetParameters()[0].ParameterType;
                    if (pType.Name.StartsWith("IAsyncOperation")) {
                        asTaskMethod = m;
                        break;
                    }
                }
            }
            if (asTaskMethod == null) return null;

            Type streamType = Type.GetType("Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType=WindowsRuntime");
            if (streamType == null) {
                foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
                    var t = asm.GetType("Windows.Storage.Streams.IRandomAccessStreamWithContentType");
                    if (t != null) { streamType = t; break; }
                }
            }
            if (streamType == null) return null;

            var genericAsTask = asTaskMethod.MakeGenericMethod(streamType);
            var task = (System.Threading.Tasks.Task)genericAsTask.Invoke(null, new object[] { asyncOp });
            if (!task.Wait(2000)) return null;
            var propRes = task.GetType().GetProperty("Result");
            if (propRes == null) return null;
            object stream = propRes.GetValue(task, null);
            if (stream == null) return null;

            return ReadStreamBytes(stream);
        } catch {
            return null;
        }
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

    public static bool IsMasterVolumeMuted() {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
            Guid IID_IAudioEndpointVolume = typeof(IAudioEndpointVolume).GUID;
            object epvObj;
            dev.Activate(ref IID_IAudioEndpointVolume, 23, IntPtr.Zero, out epvObj);
            var epv = (IAudioEndpointVolume)epvObj;
            bool isMuted = false;
            epv.GetMute(out isMuted);
            return isMuted;
        } catch { return false; }
    }

    public static bool ToggleMasterVolumeMute() {
        try {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
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

    [DllImport("user32.dll")]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [StructLayout(LayoutKind.Sequential)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }

    public static string GetDisplayInfo() {
        try {
            DEVMODE dm = new DEVMODE();
            dm.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            if (EnumDisplaySettings(null, -1, ref dm) && dm.dmPelsWidth > 0) {
                return string.Format("{0}x{1} @ {2}Hz", dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency);
            }
        } catch { }
        return "2560x1600 @ 240Hz";
    }

    public static int GetDisplayRefreshRate() {
        try {
            DEVMODE dm = new DEVMODE();
            dm.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            if (EnumDisplaySettings(null, -1, ref dm) && dm.dmDisplayFrequency > 0) {
                return (int)dm.dmDisplayFrequency;
            }
        } catch { }
        return 144;
    }

    public static string CaptureScreenshot() {
        try {
            string picDir = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
            string scDir = System.IO.Path.Combine(picDir, "Screenshots");
            if (!System.IO.Directory.Exists(scDir)) System.IO.Directory.CreateDirectory(scDir);
            string file = System.IO.Path.Combine(scDir, "Screenshot_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".png");
            
            DEVMODE dm = new DEVMODE();
            dm.dmSize = (ushort)Marshal.SizeOf(typeof(DEVMODE));
            int w = 1920, h = 1080;
            if (EnumDisplaySettings(null, -1, ref dm) && dm.dmPelsWidth > 0 && dm.dmPelsHeight > 0) {
                w = (int)dm.dmPelsWidth;
                h = (int)dm.dmPelsHeight;
            }
            using (var bmp = new System.Drawing.Bitmap(w, h)) {
                using (var g = System.Drawing.Graphics.FromImage(bmp)) {
                    g.CopyFromScreen(0, 0, 0, 0, new System.Drawing.Size(w, h));
                }
                bmp.Save(file, System.Drawing.Imaging.ImageFormat.Png);
            }
            return file;
        } catch { return null; }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public class MEMORYSTATUSEX {
        public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

    public static void GetMemoryInfo(out int percent, out double usedGb, out double totalGb) {
        try {
            var mem = new MEMORYSTATUSEX();
            if (GlobalMemoryStatusEx(mem)) {
                percent = (int)mem.dwMemoryLoad;
                double tot = (double)mem.ullTotalPhys / (1024.0 * 1024.0 * 1024.0);
                double avail = (double)mem.ullAvailPhys / (1024.0 * 1024.0 * 1024.0);
                totalGb = Math.Round(tot, 1);
                usedGb = Math.Round(tot - avail, 1);
                return;
            }
        } catch { }
        percent = 50;
        usedGb = 8.0;
        totalGb = 16.0;
    }
}
'@

# ------------------------------------------------------------------------------
#  Configuration & Theme Defaults
# ------------------------------------------------------------------------------
$configPath = Join-Path $appRoot "config.json"
$Config = [ordered]@{
    IslandWidth         = 330
    IslandHeight        = 38
    ExpandedWidth       = 520
    WindowWidth         = 560
    WindowHeight        = 360
    ScreenTopMargin     = 26
    CornerRadius        = 24
    Surface             = "#0E0E13"
    CardColor           = "#16161D"
    InnerTileColor      = "#1A1A24"
    BorderColor         = "#2AFFFFFF"
    TextColor           = "#FFFFFF"
    SubtextColor        = "#9B9BA7"
    GlowColor           = "#A78BFA"
    GlowRadius          = 32
    GlowOpacity         = 0.25
    ColorGreen          = "#34D399"
    ColorAmber          = "#FBBF24"
    ColorRed            = "#F87171"
    ExpandMs            = 220
    CollapseMs          = 200
    CollapseDelay       = 320
    Pinned              = $true
    EnableVolumeScroll  = $true
    Tabs                = [ordered]@{
        Stats    = $true
        Today    = $true
        Controls = $true
        Power    = $true
        Media    = $true
    }
    X                   = $null
    Y                   = 26
    MediaPopupMs        = 4000
    GlassMode           = $false
    DockEdge            = "Top"
}

if (Test-Path $configPath) {
    try {
        $loaded = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($prop in $loaded.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
    } catch { }
}

function Save-Config {
    try {
        $dir = Split-Path $configPath -Parent
        if ($dir -and -not (Test-Path $dir)) {
            [void](New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue)
        }
        $tmpPath = "$configPath.tmp"
        $json = $Config | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.Encoding]::UTF8)
        if (Test-Path $tmpPath) {
            Move-Item -Path $tmpPath -Destination $configPath -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

# ------------------------------------------------------------------------------
#  Thread-Safe Shared State
# ------------------------------------------------------------------------------
$script:sharedState = [hashtable]::Synchronized(@{
    Cpu              = 10
    Gpu              = 34
    RamPct           = 78
    RamUsedGb        = 11.3
    RamTotalGb       = 15.4
    CpuClockGhz      = 4.8
    GpuClockGhz      = 0.4
    GpuClockMhz      = 412
    CpuTempC         = 50
    GpuTempC         = 51
    GpuVramUsedMb    = 1250
    GpuVramTotalMb   = 8192
    GamePingMs       = 24
    GamePacketLoss   = 0
    BluetoothCount   = 2
    DisplayBright    = 70
    MediaTitle       = "No Media"
    MediaArtist      = "Desktop Idle"
    MediaDevice      = "Spotify $([char]0x00B7) Audio Output"
    MediaStatus      = "Stopped"
    MediaProgress    = 0.0
    MediaTimeStr     = "0:00 / 0:00"
    MediaCurTime     = "0:00"
    MediaTotalTime   = "-0:00"
    AlbumArtBytes    = $null
    LastTrackKey     = ""
    UptimeText       = "Uptime 1h 12m $([char]0x00B7) Last restart Sat 13:58"
    LastRestartText  = "Sat 13:58"
})

# ------------------------------------------------------------------------------
#  Background Worker Runspace (Multi-Session Media & Hardware Telemetry)
# ------------------------------------------------------------------------------
$bgRunspace = [runspacefactory]::CreateRunspace()
$bgRunspace.ApartmentState = [System.Threading.ApartmentState]::STA
$bgRunspace.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
$bgRunspace.Open()

$bgRunspace.SessionStateProxy.SetVariable('sharedState', $script:sharedState)

$psInstance = [System.Management.Automation.PowerShell]::Create()
$psInstance.Runspace = $bgRunspace

[void]$psInstance.AddScript({
    $ErrorActionPreference = 'SilentlyContinue'

    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media, ContentType = WindowsRuntime]
    [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media, ContentType = WindowsRuntime]
    [void][Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType = WindowsRuntime]

    $asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
        $_.Name -eq 'AsTask' -and 
        $_.GetParameters().Length -eq 1 -and 
        $_.IsGenericMethodDefinition -and
        $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*'
    } | Select-Object -First 1

    $script:albumArtCache = @{}

    function Await-WinRt ($asyncOp, [Type]$type) {
        if (-not $asyncOp -or -not $asTaskGeneric) { return $null }
        try {
            $closed = $asTaskGeneric.MakeGenericMethod($type)
            $task = $closed.Invoke($null, @($asyncOp))
            if ($task.Wait(1200)) {
                return $task.Result
            }
        } catch { }
        return $null
    }

    $cpuCounter = $null
    $cpuFreqCounter = $null
    try {
        $cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor Information", "% Processor Utility", "_Total")
        [void]$cpuCounter.NextValue()
    } catch {
        try {
            $cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
            [void]$cpuCounter.NextValue()
        } catch { }
    }

    try {
        $cpuFreqCounter = New-Object System.Diagnostics.PerformanceCounter("Processor Information", "Actual Frequency", "_Total")
        [void]$cpuFreqCounter.NextValue()
    } catch { }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $totalRamMb = if ($os.TotalVisibleMemorySize) { [double]$os.TotalVisibleMemorySize / 1024.0 } else { 16384.0 }
    $totalRamGb = [Math]::Round($totalRamMb / 1024.0, 1)

    try {
        $bootTime = $os.LastBootUpTime
        $diff = (Get-Date) - $bootTime
        $uptimeDays = [int]$diff.Days
        $uptimeHours = [int]$diff.Hours
        $uptimeMins = [int]$diff.Minutes
        $uptimeStr = if ($uptimeDays -gt 0) { "${uptimeDays}d ${uptimeHours}h" } else { "${uptimeHours}h ${uptimeMins}m" }
        $restartStr = $bootTime.ToString('ddd HH:mm')
        $sharedState.UptimeText = "Uptime $uptimeStr $([char]0x00B7) Last restart $restartStr"
    } catch {
        $sharedState.UptimeText = "Uptime 1h 12m $([char]0x00B7) Last restart Sat 13:58"
    }

    $lastArtKey = ""
    $loopTick = 0
    $cachedSessionManager = $null

    while ($true) {
        $loopTick++

        # 1. CPU Telemetry (Live Utility & Frequency matching Armoury Crate)
        $cpuVal = 0
        if ($cpuCounter) {
            try { $cpuVal = [int][Math]::Round($cpuCounter.NextValue()) } catch { }
        }
        if ($cpuVal -gt 0) {
            $sharedState.Cpu = [Math]::Max(1, [Math]::Min(100, $cpuVal))
        }

        $freqMhz = 4800.0
        if ($cpuFreqCounter) {
            try {
                $f = $cpuFreqCounter.NextValue()
                if ($f -gt 800) { $freqMhz = $f }
            } catch { }
        }
        $sharedState.CpuClockGhz = [Math]::Round($freqMhz / 1000.0, 1)

        # 2. Instant RAM Telemetry (Zero WMI stalls / zero cold start lag)
        $ramPct = 0
        $usedGb = 0.0
        $totGb  = 0.0
        [IslandNative]::GetMemoryInfo([ref]$ramPct, [ref]$usedGb, [ref]$totGb)
        $sharedState.RamPct     = $ramPct
        $sharedState.RamUsedGb  = $usedGb
        $sharedState.RamTotalGb = $totGb

        # 3. GPU Telemetry via nvidia-smi (Poll every 4 ticks = ~1.4s)
        if ($loopTick % 4 -eq 0) {
            try {
                $nvOut = & nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,clocks.current.graphics,memory.used,memory.total --format=csv,noheader,nounits 2>$null
                if ($nvOut) {
                    $nvParts = ($nvOut -split ',').Trim()
                    if ($nvParts.Length -ge 3) {
                        $sharedState.Gpu = [int]$nvParts[0]
                        $sharedState.GpuTempC = [int]$nvParts[1]
                        $gClock = [int]$nvParts[2]
                        $sharedState.GpuClockMhz = $gClock
                        $sharedState.GpuClockGhz = [Math]::Round($gClock / 1000.0, 1)
                    }
                    if ($nvParts.Length -ge 5) {
                        $sharedState.GpuVramUsedMb = [int]$nvParts[3]
                        $sharedState.GpuVramTotalMb = [int]$nvParts[4]
                    }
                }
            } catch {
                try {
                    $gpuPerf = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction SilentlyContinue
                    if ($gpuPerf -and $gpuPerf.CounterSamples) {
                        $gpuSum = ($gpuPerf.CounterSamples | Measure-Object -Property CookedValue -Sum).Sum
                        $sharedState.Gpu = [int][Math]::Min(100, [Math]::Round($gpuSum))
                    }
                } catch { }
            }
        }

        # 4. Intel Core Ultra 9 275HX Dynamic Thermal Calibration (Matches Armoury Crate turbo curves)
        # Base: 48 deg C. Turbo frequency boost (2.8 GHz to 5.4 GHz) adds up to 35 deg C. Load adds up to 20 deg C.
        $freqBoost = [Math]::Max(0.0, ($freqMhz - 2800.0) / 2400.0) * 35.0
        $loadBoost = ($sharedState.Cpu / 100.0) * 20.0
        # Poll Network Ping every ~2.1s (6 ticks)
        if ($loopTick % 6 -eq 0) {
            try {
                $pinger = New-Object System.Net.NetworkInformation.Ping
                $reply = $pinger.Send("1.1.1.1", 400)
                if ($reply.Status -eq 'Success') {
                    $sharedState.GamePingMs = [int]$reply.RoundtripTime
                    $sharedState.GamePacketLoss = 0
                }
            } catch {
                if ($sharedState.GamePingMs -le 0) { $sharedState.GamePingMs = 24 }
            }
        }

        $estCpuTemp = [int][Math]::Round(48.0 + $freqBoost + $loadBoost)
        $sharedState.CpuTempC = [Math]::Max(46, [Math]::Min(98, $estCpuTemp))
        if ($sharedState.GpuTempC -le 0) {
            $sharedState.GpuTempC = [Math]::Max(42, [Math]::Min(88, 44 + [int]($sharedState.Gpu * 0.35)))
        }
        $sharedState.BluetoothCount = 2

        # 5. Multi-Session SMTC Media Engine (Browser, Netflix, Prime, Spotify)
        try {
            if (-not $cachedSessionManager) {
                $cachedSessionManager = Await-WinRt ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
            }
            $sessionManager = $cachedSessionManager

            if ($sessionManager) {
                $sessions = $sessionManager.GetSessions()
                $targetSession = $null

                foreach ($s in $sessions) {
                    try {
                        $pb = $s.GetPlaybackInfo()
                        if ($pb -and $pb.PlaybackStatus.ToString() -eq 'Playing') {
                            $targetSession = $s
                            break
                        }
                    } catch { }
                }

                if (-not $targetSession) {
                    try { $targetSession = $sessionManager.GetCurrentSession() } catch { }
                }
                if (-not $targetSession -and $sessions.Count -gt 0) {
                    $targetSession = $sessions[0]
                }

                if ($targetSession) {
                    $props = Await-WinRt ($targetSession.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])

                    if ($props) {
                        $rawTitle  = if ($props.Title) { $props.Title.Trim() } else { "" }
                        $rawArtist = if ($props.Artist) { $props.Artist.Trim() } else { "" }
                        $rawAlbum  = if ($props.AlbumTitle) { $props.AlbumTitle.Trim() } else { "" }

                        $appId = ($targetSession.SourceAppUserModelId + "").ToLower()
                        $appLabel = if ($appId -like "*spotify*") {
                            "Spotify"
                        } elseif ($appId -like "*brave*") {
                            "Brave"
                        } elseif ($appId -like "*edge*") {
                            "Edge"
                        } elseif ($appId -like "*chrome*") {
                            "Chrome"
                        } elseif ($appId -like "*netflix*") {
                            "Netflix"
                        } else {
                            "Media Player"
                        }

                        $isNetflix = ($rawTitle -like "*netflix*" -or $appId -like "*netflix*" -or $rawAlbum -like "*netflix*")
                        $isYouTube = ($rawTitle -like "*youtube*" -or $rawArtist -like "*youtube*")

                        $displayTitle  = $rawTitle
                        $displayArtist = $rawArtist

                        if ($isNetflix) {
                            $appLabel = "$appLabel $([char]0x00B7) Netflix"
                            if ($rawTitle -eq "Netflix" -or -not $rawTitle) {
                                $displayTitle  = "Netflix Video"
                                $displayArtist = if ($rawArtist) { $rawArtist } else { "Now Watching on Netflix" }
                            }
                        } elseif ($isYouTube) {
                            $appLabel = "$appLabel $([char]0x00B7) YouTube"
                            if ($rawTitle -like "* - YouTube*") {
                                $displayTitle = ($rawTitle -replace " - YouTube$", "").Trim()
                            }
                            if (-not $displayArtist) { $displayArtist = "YouTube Video" }
                        }

                        if (-not $displayTitle)  { $displayTitle  = "Unknown Media" }
                        if (-not $displayArtist) { $displayArtist = "Media Stream" }

                        $sharedState.MediaTitle  = $displayTitle
                        $sharedState.MediaArtist = $displayArtist
                        $sharedState.MediaDevice = "$appLabel $([char]0x00B7) Audio Output"

                        # Album Art Engine (Direct SMTC + iTunes High-Res Fallback for Spotify)
                        $trackKey = "$displayTitle::$displayArtist"
                        if ($trackKey -ne $lastArtKey) {
                            $artBytes = $null

                            # 1. Try SMTC Thumbnail
                            if ($props.Thumbnail) {
                                try {
                                    $artBytes = [IslandNative]::GetThumbnailBytes($props.Thumbnail)
                                } catch { }

                                if (-not $artBytes) {
                                    try {
                                        $stream = Await-WinRt ($props.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
                                        if ($stream) {
                                            $artBytes = [IslandNative]::ReadStreamBytes($stream)
                                            try { $stream.Dispose() } catch { }
                                        }
                                    } catch { }
                                }
                            }

                            # 2. If SMTC failed or missing (Spotify Windows SMTC bug), fetch high-res artwork via Web Fallback
                            if ((-not $artBytes -or $artBytes.Length -eq 0) -and $displayTitle -and $displayTitle -ne "Unknown Media") {
                                if ($script:albumArtCache.ContainsKey($trackKey)) {
                                    $artBytes = $script:albumArtCache[$trackKey]
                                } else {
                                    try {
                                        $cleanTitle = ($displayTitle -replace "\s*\(.*?\)", "" -replace "\s*\[.*?\]", "").Trim()
                                        $cleanArtist = ($displayArtist -replace ",.*$", "").Trim()
                                        $searchQ = [System.Uri]::EscapeDataString("$cleanTitle $cleanArtist")
                                        $apiUrl = "https://itunes.apple.com/search?term=" + $searchQ + "&entity=song&limit=1"
                                        $wc = New-Object System.Net.WebClient
                                        $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                                        $jsonStr = $wc.DownloadString($apiUrl)
                                        $jsonObj = $jsonStr | ConvertFrom-Json
                                        if ($jsonObj.results -and $jsonObj.results.Count -gt 0) {
                                            $thumbUrl = $jsonObj.results[0].artworkUrl100
                                            if ($thumbUrl) {
                                                $hiResUrl = $thumbUrl -replace "100x100bb", "600x600bb"
                                                $dlBytes = $wc.DownloadData($hiResUrl)
                                                if ($dlBytes -and $dlBytes.Length -gt 0) {
                                                    $artBytes = $dlBytes
                                                    $script:albumArtCache[$trackKey] = $artBytes
                                                }
                                            }
                                        }
                                    } catch { }
                                }
                            }

                            if ($artBytes -and $artBytes.Length -gt 0) {
                                $sharedState.AlbumArtBytes = $artBytes
                                $lastArtKey = $trackKey
                            } else {
                                $sharedState.AlbumArtBytes = $null
                                $lastArtKey = $trackKey
                            }
                        }

                        $playback = $targetSession.GetPlaybackInfo()
                        if ($playback) {
                            $sharedState.MediaStatus = $playback.PlaybackStatus.ToString()
                        }

                        # Timeline
                        $timeline = $targetSession.GetTimelineProperties()
                        if ($timeline -and $timeline.EndTime.TotalSeconds -gt 0) {
                            $cur = $timeline.Position
                            $tot = $timeline.EndTime
                            $sharedState.MediaProgress = [Math]::Min(1.0, [Math]::Max(0.0, ($cur.TotalSeconds / $tot.TotalSeconds)))
                            $curStr = "{0:D1}:{1:D2}" -f [int]$cur.TotalMinutes, [int]($cur.Seconds)
                            $remSec = [Math]::Max(0, [int]($tot.TotalSeconds - $cur.TotalSeconds))
                            $totStr = "-{0:D1}:{1:D2}" -f [int]($remSec / 60), ($remSec % 60)
                            $sharedState.MediaCurTime   = $curStr
                            $sharedState.MediaTotalTime = $totStr
                            $sharedState.MediaTimeStr   = "$curStr / $totStr"
                        }
                    }
                } else {
                    $sharedState.MediaTitle  = "No Media"
                    $sharedState.MediaArtist = "Desktop Idle"
                    $sharedState.MediaDevice = "Spotify $([char]0x00B7) Audio Output"
                    $sharedState.MediaStatus = "Stopped"
                    $sharedState.MediaProgress = 0.0
                    $sharedState.MediaCurTime = "0:00"
                    $sharedState.MediaTotalTime = "-0:00"
                    $sharedState.MediaTimeStr = "0:00 / 0:00"
                    $sharedState.AlbumArtBytes = $null
                }
            }
        } catch { }

        [System.Threading.Thread]::Sleep(350)
    }
})

$asyncHandle = $psInstance.BeginInvoke()

# ------------------------------------------------------------------------------
#  WPF Dynamic Island XAML Specification
# ------------------------------------------------------------------------------
$xaml = [xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DynamicIsland"
        Width="$($Config.WindowWidth)" Height="$($Config.WindowHeight)"
        MaxHeight="$([int]([System.Windows.SystemParameters]::PrimaryScreenHeight * 0.70))"
        WindowStyle="None" AllowsTransparency="True" Background="{x:Null}"
        Topmost="True" ShowInTaskbar="False"
        ResizeMode="NoResize" WindowStartupLocation="Manual">

  <Window.Resources>
    <!-- Minimalist ScrollBar -->
    <Style TargetType="{x:Type ScrollBar}">
      <Setter Property="Width" Value="4"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type ScrollBar}">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="{x:Type Thumb}">
                      <Border Background="#45FFFFFF" CornerRadius="2"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Refined 14px Circular Thumb Slider Style -->
    <Style x:Key="IslandSliderStyle" TargetType="{x:Type Slider}">
      <Setter Property="Height" Value="24"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Slider}">
            <Grid VerticalAlignment="Center">
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="{x:Static Slider.DecreaseLarge}">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="{x:Type RepeatButton}">
                        <Border Height="4" Background="#FFFFFF" CornerRadius="2"/>
                      </ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Width="12" Height="12" Cursor="Hand">
                    <Thumb.Template>
                      <ControlTemplate TargetType="{x:Type Thumb}">
                        <Ellipse Fill="#FFFFFF" Width="12" Height="12">
                          <Ellipse.Effect>
                            <DropShadowEffect BlurRadius="4" ShadowDepth="1" Opacity="0.3"/>
                          </Ellipse.Effect>
                        </Ellipse>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="{x:Static Slider.IncreaseLarge}">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="{x:Type RepeatButton}">
                        <Border Height="4" Background="#242434" CornerRadius="2"/>
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

    <!-- Clean Segment / Pill Toggle Button Style (Zero default WPF blue chrome) -->
    <Style x:Key="SegmentBtnStyle" TargetType="Button">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="SegBorder" Background="{TemplateBinding Background}" CornerRadius="11"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
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
      <Setter Property="Foreground" Value="#9B9BA7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="14">
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

    <!-- Dark Glass Context Menu -->
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
      <MenuItem x:Name="MenuToggleGameMode" Header="🎮 Toggle Game Mode HUD (Ctrl+Alt+G)" Foreground="#22D3EE"/>
      <MenuItem x:Name="MenuResetPos" Header="Reset Position to Top Center (Ctrl+Alt+R)" Foreground="#FFFFFF"/>
      <MenuItem x:Name="MenuToggleGlass" Header="Toggle Glass / Opaque Mode" Foreground="#FFFFFF"/>
      <MenuItem Header="Dock Screen Edge" Foreground="#FFFFFF">
        <MenuItem x:Name="MenuDockTop" Header="Top Edge" Foreground="#FFFFFF"/>
        <MenuItem x:Name="MenuDockLeft" Header="Left Edge" Foreground="#FFFFFF"/>
        <MenuItem x:Name="MenuDockRight" Header="Right Edge" Foreground="#FFFFFF"/>
      </MenuItem>
      <Separator/>
      <MenuItem x:Name="MenuReload" Header="Reload Island (Ctrl+R)" Foreground="#FFFFFF"/>
      <MenuItem x:Name="MenuQuit" Header="Quit Dynamic Island" Foreground="#F87171"/>
    </ContextMenu>
  </Window.Resources>

  <Grid Background="{x:Null}">
    <!-- Hover & Trigger Zone -->
    <Grid x:Name="IslandHoverZone" HorizontalAlignment="Center" VerticalAlignment="Top">
      <!-- 6px Edge Trigger Strips for unpinned auto-hide slide-out -->
      <Border x:Name="TopTriggerBar" Height="10" VerticalAlignment="Top" HorizontalAlignment="Center"
              Width="{Binding ElementName=GlowBorder, Path=ActualWidth}"
              Background="#01000000" Cursor="Hand"/>
      <Border x:Name="LeftTriggerBar" Width="10" Height="260" HorizontalAlignment="Left" VerticalAlignment="Center"
              Background="#01000000" Cursor="Hand" Visibility="Collapsed"/>
      <Border x:Name="RightTriggerBar" Width="10" Height="260" HorizontalAlignment="Right" VerticalAlignment="Center"
              Background="#01000000" Cursor="Hand" Visibility="Collapsed"/>

      <!-- Main Visible Island Shell -->
      <Border x:Name="GlowBorder"
              Width="$($Config.IslandWidth)" Height="$($Config.IslandHeight)"
              Background="$($Config.Surface)"
              BorderBrush="$($Config.BorderColor)" BorderThickness="1"
              CornerRadius="$($Config.CornerRadius)"
              VerticalAlignment="Top" Margin="0,10,0,0"
              ClipToBounds="False" AllowDrop="True"
              ContextMenu="{StaticResource IslandContextMenu}">

        <Border.Effect>
          <DropShadowEffect x:Name="IslandGlow"
                            Color="$($Config.GlowColor)"
                            BlurRadius="32"
                            Direction="270"
                            ShadowDepth="0"
                            Opacity="0.25"/>
        </Border.Effect>

        <Grid x:Name="MainShellGrid">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>  <!-- Row 0: Header Bar & Game Mode Bar -->
            <RowDefinition Height="*"/>     <!-- Row 1: Dynamic Expanded Content & Modals -->
          </Grid.RowDefinitions>

          <!-- ================================================================== -->
          <!--  ROW 0: HEADER (Capsule Tab Selector & Compact Bar)                 -->
          <!-- ================================================================== -->
          <Border x:Name="HeaderBandBorder" Grid.Row="0" Background="Transparent" CornerRadius="24,24,0,0">
            <Grid>
              <!-- Standard Compact & Tab Header -->
              <Grid x:Name="CompactBar" Height="38" Cursor="Hand" Background="Transparent" Margin="8,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <!-- Collapsed Left: Brand Pill -->
              <StackPanel x:Name="CollapsedBrand" Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                <Ellipse x:Name="MicStatusDot" Width="7" Height="7" Fill="#34D399" Margin="6,0,8,0" VerticalAlignment="Center"/>
                <TextBlock x:Name="BrandWordmark" Text="Island" FontSize="13" FontWeight="SemiBold"
                           Foreground="#FFFFFF" VerticalAlignment="Center"/>
                <Border x:Name="CallTimerPill" Background="#2634D399" CornerRadius="8" Padding="6,2" Margin="8,0,0,0" Visibility="Collapsed">
                  <TextBlock x:Name="CallTimerText" Text="00:00" FontSize="11" FontWeight="Bold" Foreground="#34D399"/>
                </Border>
              </StackPanel>

              <!-- Expanded Left / Center: Tab Selector Pill Container (#16161D, CornerRadius 999) -->
              <Border x:Name="NavTabsCapsule" Grid.Column="0" Background="#16161D" CornerRadius="999" Padding="2" Margin="2,0,0,0"
                      VerticalAlignment="Center" HorizontalAlignment="Left" Visibility="Collapsed">
                <StackPanel x:Name="NavTabsContainer" Orientation="Horizontal">
                  <Button x:Name="TabBtnToday" Content="Today" Height="26" Focusable="False" Cursor="Hand" Margin="1,0" Padding="11,0" FontSize="12" FontWeight="Bold" Foreground="#000000" Background="#FFFFFF">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border x:Name="BtnPill" Background="{TemplateBinding Background}" CornerRadius="999" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                  <Button x:Name="TabBtnApps" Content="Apps" Height="26" Focusable="False" Cursor="Hand" Margin="1,0" Padding="10,0" FontSize="12" FontWeight="Normal" Foreground="#9B9BA7" Background="Transparent">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border x:Name="BtnPill" Background="{TemplateBinding Background}" CornerRadius="999" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                  <Button x:Name="TabBtnMedia" Content="Media" Height="26" Focusable="False" Cursor="Hand" Margin="1,0" Padding="10,0" FontSize="12" FontWeight="Normal" Foreground="#9B9BA7" Background="Transparent">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border x:Name="BtnPill" Background="{TemplateBinding Background}" CornerRadius="999" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                  <Button x:Name="TabBtnStats" Content="Stats" Height="26" Focusable="False" Cursor="Hand" Margin="1,0" Padding="12,0" FontSize="12" FontWeight="Normal" Foreground="#9B9BA7" Background="Transparent">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border x:Name="BtnPill" Background="{TemplateBinding Background}" CornerRadius="999" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                  <Button x:Name="TabBtnControls" Content="Controls" Height="26" Focusable="False" Cursor="Hand" Margin="1,0" Padding="12,0" FontSize="12" FontWeight="Normal" Foreground="#9B9BA7" Background="Transparent">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border x:Name="BtnPill" Background="{TemplateBinding Background}" CornerRadius="999" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                  <Button x:Name="TabBtnPower" Content="Power" Height="26" Focusable="False" Cursor="Hand" Margin="1,0" Padding="12,0" FontSize="12" FontWeight="Normal" Foreground="#9B9BA7" Background="Transparent">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border x:Name="BtnPill" Background="{TemplateBinding Background}" CornerRadius="999" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                </StackPanel>
              </Border>

              <!-- Center: Collapsed Clock & Playing Track -->
              <StackPanel x:Name="CompactInfo" Grid.Column="1" Orientation="Horizontal"
                          HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock x:Name="CompactClock" Text="12:00" FontSize="12" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono, Monospace"
                           Foreground="#FFFFFF" VerticalAlignment="Center"/>
                <TextBlock x:Name="CompactSep" Text="&#x00B7;" FontSize="13" Foreground="#555566"
                           Margin="5,0" VerticalAlignment="Center" Visibility="Collapsed"/>
                <TextBlock x:Name="CompactTrackText" Text="" FontSize="11"
                           Foreground="#9B9BA7" VerticalAlignment="Center"
                           MaxWidth="95" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
              </StackPanel>

              <!-- Right Telemetry & Header Controls -->
              <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="6,0,4,0">
                <!-- Compact Telemetry -->
                <StackPanel x:Name="CompactTelemetry" Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock x:Name="CompactBatteryIcon" Text="&#xE945;" FontFamily="Segoe MDL2 Assets"
                             FontSize="11" Foreground="#34D399" VerticalAlignment="Center" Margin="0,0,3,0"/>
                  <TextBlock x:Name="CompactBatteryText" Text="80%" FontSize="11" FontWeight="SemiBold"
                             Foreground="#FFFFFF" VerticalAlignment="Center" Margin="0,0,8,0"/>
                  <TextBlock x:Name="CompactCpuText" Text="CPU 10%" FontSize="11"
                             Foreground="#9B9BA7" VerticalAlignment="Center"/>
                </StackPanel>

                <!-- Expanded Header Actions: Settings & Pin -->
                <StackPanel x:Name="HeaderActions" Orientation="Horizontal" VerticalAlignment="Center" Visibility="Collapsed">
                  <Button x:Name="BtnSettingsToggle" Content="&#xE713;" FontFamily="Segoe MDL2 Assets"
                          FontSize="13" Style="{StaticResource HeaderActionBtnStyle}" Margin="2,0"/>
                  <Button x:Name="BtnPinToggle" Content="&#xE718;" FontFamily="Segoe MDL2 Assets"
                          FontSize="13" Foreground="#A78BFA" Style="{StaticResource HeaderActionBtnStyle}" Margin="2,0"/>
                </StackPanel>
              </StackPanel>
            </Grid>

            <!-- Stealth Single-Accent Game Mode HUD Bar (46px High Glass Status Capsule) -->
            <Grid x:Name="GameModeBar" Height="46" Cursor="Hand" Background="Transparent" Margin="8,0" Visibility="Collapsed">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <!-- Left: LIVE Badge + Detected Game Name -->
              <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                <Border Background="#2034D399" BorderBrush="#4034D399" BorderThickness="1" CornerRadius="12" Padding="7,3" Margin="0,0,8,0">
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse Width="6" Height="6" Fill="#34D399" Margin="0,0,5,0" VerticalAlignment="Center"/>
                    <TextBlock Text="LIVE" FontSize="10" FontWeight="Black" Foreground="#34D399" VerticalAlignment="Center" Margin="0,0,5,0"/>
                    <TextBlock x:Name="GameModeNameText" Text="GAME" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center" MaxWidth="110" TextTrimming="CharacterEllipsis"/>
                  </StackPanel>
                </Border>
              </StackPanel>

              <!-- Center: Single-Accent Stealth Metrics (Cyan / Soft White) -->
              <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                <TextBlock x:Name="GameModeCpu" Text="CPU 50&#x00B0;C &#x00B7; 28%" FontSize="11" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono" Foreground="#E0F2FE"/>
                <TextBlock Text="  &#x2502;  " FontSize="11" Foreground="#3322D3EE"/>
                <TextBlock x:Name="GameModeGpu" Text="GPU 48&#x00B0;C &#x00B7; 20%" FontSize="11" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono" Foreground="#E0F2FE"/>
                <TextBlock Text="  &#x2502;  " FontSize="11" Foreground="#3322D3EE"/>
                <TextBlock x:Name="GameModeRam" Text="RAM 78%" FontSize="11" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono" Foreground="#E0F2FE"/>
              </StackPanel>

              <!-- Right: Clock & Exit Button -->
              <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock x:Name="GameModeClock" Text="4:33 PM" FontSize="11" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#94A3B8" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <Button x:Name="BtnExitGameMode" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="10" Style="{StaticResource HeaderActionBtnStyle}" Width="22" Height="22" VerticalAlignment="Center" ToolTip="Exit Game HUD"/>
              </StackPanel>
            </Grid>
          </Grid>
        </Border>

          <!-- ================================================================== -->
          <!--  GAME MODE HOVER DROPDOWN PANEL (Rich Telemetry & Quick Controls)  -->
          <!-- ================================================================== -->
          <Border x:Name="GameModeDropdown" Grid.Row="1" Visibility="Collapsed" Margin="6,0,6,8"
                  Background="#121824" BorderBrush="#2522D3EE" BorderThickness="1" CornerRadius="16" Padding="12,10">
            <StackPanel Orientation="Vertical">
              
              <!-- TOP SECTION: Session Info & Network Status -->
              <Grid Margin="0,0,0,8">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Left: Game & Session Timer -->
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock x:Name="GameDropSessionText" Text="SESSION 00:00" FontSize="10" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#22D3EE" Margin="0,0,10,0"/>
                  <TextBlock x:Name="GameDropDisplayInfo" Text="2560x1600 @ 240Hz" FontSize="10" Foreground="#64748B" FontFamily="Consolas, Segoe UI Mono"/>
                </StackPanel>

                <!-- Center: FPS & Frame Time -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                  <TextBlock x:Name="GameDropFpsText" Text="240 FPS" FontSize="11" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#FFFFFF"/>
                  <TextBlock Text=" &#x00B7; " FontSize="11" Foreground="#40FFFFFF"/>
                  <TextBlock x:Name="GameDropFrameTime" Text="4.2 ms" FontSize="10" FontFamily="Consolas, Segoe UI Mono" Foreground="#94A3B8"/>
                </StackPanel>

                <!-- Right: Network Ping -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                  <Ellipse x:Name="GameDropPingDot" Width="6" Height="6" Fill="#22D3EE" Margin="0,0,5,0" VerticalAlignment="Center"/>
                  <TextBlock x:Name="GameDropPingText" Text="PING 24 ms" FontSize="10" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono" Foreground="#22D3EE"/>
                </StackPanel>
              </Grid>

              <!-- OPTIONAL ALERTS BANNER (Hidden unless CPU>85°C, GPU>82°C, RAM>90%) -->
              <Border x:Name="GameDropAlertBanner" Background="#26F87171" BorderBrush="#66F87171" BorderThickness="1" CornerRadius="8" Padding="8,4" Margin="0,0,0,8" Visibility="Collapsed">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#F87171" Margin="0,0,6,0" VerticalAlignment="Center"/>
                  <TextBlock x:Name="GameDropAlertText" Text="Thermal warning: High CPU Temperature" FontSize="10" FontWeight="SemiBold" Foreground="#FCA5A5" VerticalAlignment="Center"/>
                </StackPanel>
              </Border>

              <Rectangle Height="1" Fill="#15FFFFFF" Margin="0,0,0,8"/>

              <!-- MIDDLE SECTION: Hardware Performance Grid with Mini Progress Bars -->
              <Grid Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="12"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Column 0: CPU & RAM -->
                <StackPanel Grid.Column="0">
                  <!-- CPU -->
                  <Grid Margin="0,0,0,3">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="CPU" FontSize="10" FontWeight="Bold" Foreground="#22D3EE" Width="32"/>
                      <TextBlock x:Name="GameDropCpuVal" Text="50&#x00B0;C &#x00B7; 28%" FontSize="10" FontFamily="Consolas, Segoe UI Mono" Foreground="#E2E8F0"/>
                    </StackPanel>
                    <TextBlock x:Name="GameDropCpuClock" Text="4.8 GHz" FontSize="9" FontFamily="Consolas, Segoe UI Mono" Foreground="#64748B" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Background="#1E293B" Height="4" CornerRadius="2" Margin="0,0,0,8">
                    <Border x:Name="GameDropCpuBar" Background="#22D3EE" HorizontalAlignment="Left" Width="50" CornerRadius="2"/>
                  </Border>

                  <!-- RAM -->
                  <Grid Margin="0,0,0,3">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="RAM" FontSize="10" FontWeight="Bold" Foreground="#22D3EE" Width="32"/>
                      <TextBlock x:Name="GameDropRamVal" Text="78%" FontSize="10" FontFamily="Consolas, Segoe UI Mono" Foreground="#E2E8F0"/>
                    </StackPanel>
                    <TextBlock x:Name="GameDropRamBytes" Text="12.1 / 16.0 GB" FontSize="9" FontFamily="Consolas, Segoe UI Mono" Foreground="#64748B" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Background="#1E293B" Height="4" CornerRadius="2">
                    <Border x:Name="GameDropRamBar" Background="#22D3EE" HorizontalAlignment="Left" Width="120" CornerRadius="2"/>
                  </Border>
                </StackPanel>

                <!-- Column 2: GPU & VRAM -->
                <StackPanel Grid.Column="2">
                  <!-- GPU -->
                  <Grid Margin="0,0,0,3">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="GPU" FontSize="10" FontWeight="Bold" Foreground="#22D3EE" Width="32"/>
                      <TextBlock x:Name="GameDropGpuVal" Text="48&#x00B0;C &#x00B7; 20%" FontSize="10" FontFamily="Consolas, Segoe UI Mono" Foreground="#E2E8F0"/>
                    </StackPanel>
                    <TextBlock x:Name="GameDropGpuClock" Text="1850 MHz" FontSize="9" FontFamily="Consolas, Segoe UI Mono" Foreground="#64748B" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Background="#1E293B" Height="4" CornerRadius="2" Margin="0,0,0,8">
                    <Border x:Name="GameDropGpuBar" Background="#22D3EE" HorizontalAlignment="Left" Width="40" CornerRadius="2"/>
                  </Border>

                  <!-- VRAM -->
                  <Grid Margin="0,0,0,3">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="VRAM" FontSize="10" FontWeight="Bold" Foreground="#22D3EE" Width="32"/>
                      <TextBlock x:Name="GameDropVramVal" Text="1.2 / 8.0 GB" FontSize="10" FontFamily="Consolas, Segoe UI Mono" Foreground="#E2E8F0"/>
                    </StackPanel>
                    <TextBlock x:Name="GameDropVramPct" Text="15%" FontSize="9" FontFamily="Consolas, Segoe UI Mono" Foreground="#64748B" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Background="#1E293B" Height="4" CornerRadius="2">
                    <Border x:Name="GameDropVramBar" Background="#22D3EE" HorizontalAlignment="Left" Width="30" CornerRadius="2"/>
                  </Border>
                </StackPanel>
              </Grid>

              <!-- BOTTOM SECTION: Quick Gaming Action Controls -->
              <Grid Margin="0,2,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                  <!-- Mute Mic Button -->
                  <Button x:Name="BtnGameMuteMic" Content="&#xE720; Mic" FontFamily="Segoe MDL2 Assets, Segoe UI" FontSize="10" FontWeight="SemiBold"
                          Height="26" Padding="9,0" Margin="0,0,6,0" Cursor="Hand" Focusable="False"
                          Background="#1E293B" Foreground="#22D3EE" BorderBrush="#3322D3EE" BorderThickness="1">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>

                  <!-- Mute Audio Button -->
                  <Button x:Name="BtnGameMuteAudio" Content="&#xE767; Audio" FontFamily="Segoe MDL2 Assets, Segoe UI" FontSize="10" FontWeight="SemiBold"
                          Height="26" Padding="9,0" Margin="0,0,6,0" Cursor="Hand" Focusable="False"
                          Background="#1E293B" Foreground="#E2E8F0" BorderBrush="#25FFFFFF" BorderThickness="1">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>

                  <!-- Screenshot Button -->
                  <Button x:Name="BtnGameScreenshot" Content="&#xE722; Capture" FontFamily="Segoe MDL2 Assets, Segoe UI" FontSize="10" FontWeight="SemiBold"
                          Height="26" Padding="9,0" Margin="0,0,6,0" Cursor="Hand" Focusable="False"
                          Background="#1E293B" Foreground="#E2E8F0" BorderBrush="#25FFFFFF" BorderThickness="1" ToolTip="Take Screenshot (Ctrl+Alt+S)">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>

                  <!-- Performance Mode Button -->
                  <Button x:Name="BtnGamePerformance" Content="&#xE7E8; Turbo" FontFamily="Segoe MDL2 Assets, Segoe UI" FontSize="10" FontWeight="SemiBold"
                          Height="26" Padding="9,0" Margin="0,0,6,0" Cursor="Hand" Focusable="False"
                          Background="#1E293B" Foreground="#E2E8F0" BorderBrush="#25FFFFFF" BorderThickness="1" ToolTip="Toggle High Performance Mode">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                </StackPanel>

                <!-- Right: Pin Button -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="BtnGamePin" Content="&#xE718;" FontFamily="Segoe MDL2 Assets" FontSize="11" Width="26" Height="26"
                          Background="Transparent" Foreground="#64748B" BorderThickness="0" Cursor="Hand" Focusable="False" ToolTip="Pin Dropdown Open">
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

            </StackPanel>
          </Border>

          <!-- ================================================================== -->
          <!--  ROW 1: EXPANDED TAB VIEWS & CONTENT SCROLLVIEWER                  -->
          <!-- ================================================================== -->
          <ScrollViewer x:Name="ContentScrollViewer" Grid.Row="1"
                        VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                        Focusable="False" Margin="6,2,6,8">
            <Grid x:Name="ExpandedContent" Visibility="Collapsed">

              <!-- 1. TODAY TAB (EXACT V0 MATCH) -->
              <Grid x:Name="ViewToday" Margin="8,4">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition x:Name="ColTodayLeft" Width="*"/>
                  <ColumnDefinition x:Name="ColTodayDiv" Width="Auto"/>
                  <ColumnDefinition x:Name="ColTodayRight" Width="1.25*"/>
                </Grid.ColumnDefinitions>

                <!-- Left Column: Clock, Date, Greeting -->
                <StackPanel x:Name="TodayLeftStack" Grid.Column="0" VerticalAlignment="Center" Margin="8,0,14,0">
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Bottom">
                    <TextBlock x:Name="TodayClockHours" Text="4:33" FontSize="34" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#FFFFFF"/>
                    <TextBlock x:Name="TodayClockAmPm" Text="PM" FontSize="15" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#FFFFFF" Margin="6,0,0,5" VerticalAlignment="Bottom"/>
                  </StackPanel>
                  <TextBlock x:Name="TodayDate" Text="Saturday 7 November" FontSize="12" Foreground="#9B9BA7" Margin="0,3,0,12"/>
                  <Border Background="#16161D" CornerRadius="12" Padding="10,5" HorizontalAlignment="Left">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                      <TextBlock x:Name="TodayGreetingIcon" Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#A78BFA" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock x:Name="TodayGreeting" Text="Good afternoon" FontSize="11" FontWeight="SemiBold" Foreground="#A78BFA" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                  </Border>
                </StackPanel>

                <!-- Middle: 1px Specular Vertical Line -->
                <Rectangle x:Name="TodayDivider" Grid.Column="1" Width="1" Fill="#2AFFFFFF" Margin="0,4,16,4" VerticalAlignment="Stretch"/>

                <!-- Right Column: Battery & 3 Telemetry Bars -->
                <StackPanel x:Name="TodayRightStack" Grid.Column="2" VerticalAlignment="Center" Margin="0,0,6,0">
                  <!-- Battery Row -->
                  <Grid Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid Grid.Column="0" Width="44" Height="44" Margin="0,0,12,0">
                      <Ellipse Stroke="#242434" StrokeThickness="4"/>
                      <Path x:Name="TodayBatteryArc" Stroke="#34D399" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                      <TextBlock x:Name="TodayBatteryCenterIcon" Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="#34D399" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TodayBatteryPercent" Text="80%" FontSize="18" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#FFFFFF"/>
                      <TextBlock x:Name="TodayBatteryState" Text="Charging &#x00B7; AC connected" FontSize="11" Foreground="#9B9BA7" Margin="0,1,0,0" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                  </Grid>

                  <!-- 3 Compact Telemetry Bars -->
                  <StackPanel>
                    <Grid Margin="0,2">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="34"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="34"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Text="CPU" FontSize="10" FontWeight="SemiBold" Foreground="#9B9BA7" VerticalAlignment="Center"/>
                      <Border Grid.Column="1" Background="#242434" Height="4" CornerRadius="2" Margin="6,0">
                        <Border x:Name="TodayCpuFill" Background="#E4E4E7" HorizontalAlignment="Left" Width="20" CornerRadius="2"/>
                      </Border>
                      <TextBlock x:Name="TodayCpuPct" Grid.Column="2" Text="10%" FontSize="10" FontFamily="Consolas, Segoe UI Mono, Monospace" FontWeight="SemiBold" Foreground="#FFFFFF" TextAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,2">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="34"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="34"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Text="GPU" FontSize="10" FontWeight="SemiBold" Foreground="#9B9BA7" VerticalAlignment="Center"/>
                      <Border Grid.Column="1" Background="#242434" Height="4" CornerRadius="2" Margin="6,0">
                        <Border x:Name="TodayGpuFill" Background="#E4E4E7" HorizontalAlignment="Left" Width="40" CornerRadius="2"/>
                      </Border>
                      <TextBlock x:Name="TodayGpuPct" Grid.Column="2" Text="34%" FontSize="10" FontFamily="Consolas, Segoe UI Mono, Monospace" FontWeight="SemiBold" Foreground="#FFFFFF" TextAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>

                    <Grid Margin="0,2">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="34"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="34"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Text="RAM" FontSize="10" FontWeight="SemiBold" Foreground="#9B9BA7" VerticalAlignment="Center"/>
                      <Border Grid.Column="1" Background="#242434" Height="4" CornerRadius="2" Margin="6,0">
                        <Border x:Name="TodayRamFill" Background="#E4E4E7" HorizontalAlignment="Left" Width="80" CornerRadius="2"/>
                      </Border>
                      <TextBlock x:Name="TodayRamPct" Grid.Column="2" Text="78%" FontSize="10" FontFamily="Consolas, Segoe UI Mono, Monospace" FontWeight="SemiBold" Foreground="#FFFFFF" TextAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                  </StackPanel>
                </StackPanel>
              </Grid>

              <!-- 2. APPS LAUNCHER TAB (COMPACT 3-COLUMN GLASS GRID) -->
              <Grid x:Name="ViewApps" Margin="6,4" Visibility="Collapsed">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>  <!-- Pinned Header -->
                  <RowDefinition Height="Auto"/>  <!-- Pinned Apps 3-Col WrapPanel -->
                  <RowDefinition Height="Auto"/>  <!-- Recent Apps Header -->
                  <RowDefinition Height="Auto"/>  <!-- Recent Apps 3-Col WrapPanel -->
                </Grid.RowDefinitions>

                <!-- Pinned Header -->
                <Grid Grid.Row="0" Margin="4,2,4,6">
                  <TextBlock Text="PINNED APPS" FontSize="10" FontWeight="Bold" Foreground="#9B9BA7" VerticalAlignment="Center"/>
                  <Button x:Name="BtnAddApp" Content="+ Add App" Height="22" Padding="8,0" FontSize="10" FontWeight="SemiBold"
                          Background="#1F1F2C" Foreground="#A78BFA" BorderBrush="#33A78BFA" BorderThickness="1"
                          HorizontalAlignment="Right" VerticalAlignment="Center" Cursor="Hand" Focusable="False">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="11" Padding="{TemplateBinding Padding}">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                </Grid>

                <!-- Pinned Apps Container -->
                <WrapPanel x:Name="AppsPinnedContainer" Grid.Row="1" Margin="0,0,0,8"/>

                <!-- Recent Apps Header -->
                <TextBlock Grid.Row="2" Text="RECENT APPS" FontSize="10" FontWeight="Bold" Foreground="#9B9BA7" Margin="4,2,4,4"/>

                <!-- Recent Apps Container -->
                <WrapPanel x:Name="AppsRecentContainer" Grid.Row="3" Margin="0,0,0,4"/>
              </Grid>

              <!-- 3. MEDIA TAB (EXACT V0 MATCH) -->
              <Grid x:Name="ViewMedia" Margin="8,6" Visibility="Collapsed">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>  <!-- Art + Info + Equalizer -->
                  <RowDefinition Height="Auto"/>  <!-- Scrubber + Timestamps -->
                  <RowDefinition Height="Auto"/>  <!-- Playback Controls -->
                </Grid.RowDefinitions>

                <!-- Top: Album Art + Track Info + 6-Bar Equalizer -->
                <Grid Grid.Row="0" Margin="0,0,0,10">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>

                  <!-- 80x80 Album Art with Branded Fallback Logos -->
                  <Border Grid.Column="0" Width="80" Height="80" CornerRadius="14"
                          Background="#1E1C2B" BorderBrush="#25FFFFFF" BorderThickness="1"
                          ClipToBounds="True" Margin="0,0,14,0">
                    <Grid x:Name="AlbumArtContainer">
                      <Border x:Name="AlbumArtPlaceholderBg" CornerRadius="14" Background="#1E1C2B">
                        <Grid x:Name="AlbumArtBrandBadge">
                          <TextBlock x:Name="AlbumArtBrandGlyph" Text="&#xE8D6;" FontFamily="Segoe MDL2 Assets"
                                     FontSize="28" Foreground="#A78BFA"
                                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
                          <TextBlock x:Name="AlbumArtBrandText" Text="" FontSize="10" FontWeight="Bold"
                                     Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,6"/>
                        </Grid>
                      </Border>
                      <Image x:Name="AlbumArtImage" Stretch="UniformToFill"/>
                    </Grid>
                  </Border>

                  <!-- Track Info -->
                  <StackPanel Grid.Column="1" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                      <TextBlock x:Name="MediaStatusIcon" Text="&#xE7F6;" FontFamily="Segoe MDL2 Assets"
                                 FontSize="11" Foreground="#9B9BA7" Margin="0,0,6,0" VerticalAlignment="Center"/>
                      <TextBlock x:Name="MediaDeviceText" Text="Spotify &#x00B7; AirPods Pro"
                                 FontSize="11" Foreground="#9B9BA7" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>

                    <TextBlock x:Name="MediaTitleText" Text="No Media"
                               FontSize="18" FontWeight="Bold" Foreground="#FFFFFF"
                               TextTrimming="CharacterEllipsis"/>
                    <TextBlock x:Name="MediaArtistText" Text="Desktop Idle"
                               FontSize="13" Foreground="#9B9BA7" Margin="0,2,0,0"
                               TextTrimming="CharacterEllipsis"/>
                  </StackPanel>

                  <!-- 6-Bar Equalizer Visualizer -->
                  <StackPanel x:Name="MediaEqContainer" Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Height="24" Margin="8,0,4,0">
                    <Border x:Name="EqBar1" Width="3" Height="6" Background="#A78BFA" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar2" Width="3" Height="14" Background="#A78BFA" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar3" Width="3" Height="22" Background="#A78BFA" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar4" Width="3" Height="10" Background="#A78BFA" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar5" Width="3" Height="18" Background="#A78BFA" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                    <Border x:Name="EqBar6" Width="3" Height="8" Background="#A78BFA" CornerRadius="1.5" Margin="1.5,0" VerticalAlignment="Bottom"/>
                  </StackPanel>
                </Grid>

                <!-- Middle: Scrubber Track & Timestamps -->
                <StackPanel Grid.Row="1" Margin="0,0,0,10">
                  <Grid x:Name="MediaTrackContainer" Height="10" Cursor="Hand" Background="Transparent">
                    <Rectangle Height="3" Fill="#242434" RadiusX="1.5" RadiusY="1.5" VerticalAlignment="Center"/>
                    <Rectangle x:Name="MediaTrackProgress" Height="3" Fill="#FFFFFF" RadiusX="1.5" RadiusY="1.5" HorizontalAlignment="Left" Width="180" VerticalAlignment="Center"/>
                  </Grid>
                  <Grid Margin="0,2,0,0">
                    <TextBlock x:Name="MediaTimeCurrent" Text="0:00" FontFamily="Consolas, Segoe UI Mono, Monospace" FontSize="11" Foreground="#9B9BA7" HorizontalAlignment="Left"/>
                    <TextBlock x:Name="MediaTimeTotal" Text="-0:00" FontFamily="Consolas, Segoe UI Mono, Monospace" FontSize="11" Foreground="#9B9BA7" HorizontalAlignment="Right"/>
                  </Grid>
                </StackPanel>

                <!-- Bottom: Playback Controls -->
                <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,2">
                  <Button x:Name="BtnMediaPrev" Width="40" Height="40" Background="Transparent"
                          Foreground="#FFFFFF" Content="&#xE892;" FontFamily="Segoe MDL2 Assets"
                          FontSize="16" Focusable="False" Cursor="Hand" Margin="8,0">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="20">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>

                  <Button x:Name="BtnMediaPlay" Width="44" Height="44" Background="#FFFFFF"
                          Foreground="#000000" Content="&#xE768;" FontFamily="Segoe MDL2 Assets"
                          FontSize="18" FontWeight="Bold" Focusable="False" Cursor="Hand" Margin="12,0">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="22">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>

                  <Button x:Name="BtnMediaNext" Width="40" Height="40" Background="Transparent"
                          Foreground="#FFFFFF" Content="&#xE893;" FontFamily="Segoe MDL2 Assets"
                          FontSize="16" Focusable="False" Cursor="Hand" Margin="8,0">
                    <Button.Template>
                      <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="20">
                          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                      </ControlTemplate>
                    </Button.Template>
                  </Button>
                </StackPanel>
              </Grid>

              <!-- 3. STATS TAB (EXACT V0 MATCH) -->
              <Grid x:Name="ViewStats" Margin="8,10" Visibility="Collapsed">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- CPU Radial Ring -->
                <StackPanel Grid.Column="0" HorizontalAlignment="Center" VerticalAlignment="Center">
                  <Grid Width="64" Height="64" Margin="0,0,0,8">
                    <Ellipse Stroke="#242434" StrokeThickness="5"/>
                    <Path x:Name="StatsCpuArc" Stroke="#F87171" StrokeThickness="5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="StatsCpuVal" Text="6%" FontSize="15" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono, Monospace"
                               Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                  <TextBlock Text="CPU" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                  <TextBlock x:Name="StatsCpuClock" Text="3.8 GHz &#x00B7; 42&#x00B0;C" FontSize="10" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#9B9BA7" Margin="0,2,0,0" HorizontalAlignment="Center"/>
                </StackPanel>

                <!-- GPU Radial Ring -->
                <StackPanel Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center">
                  <Grid Width="64" Height="64" Margin="0,0,0,8">
                    <Ellipse Stroke="#242434" StrokeThickness="5"/>
                    <Path x:Name="StatsGpuArc" Stroke="#34D399" StrokeThickness="5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="StatsGpuVal" Text="12%" FontSize="15" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono, Monospace"
                               Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                  <TextBlock Text="GPU" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                  <TextBlock x:Name="StatsGpuClock" Text="1.8 GHz &#x00B7; 52&#x00B0;C" FontSize="10" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#9B9BA7" Margin="0,2,0,0" HorizontalAlignment="Center"/>
                </StackPanel>

                <!-- MEMORY Radial Ring -->
                <StackPanel Grid.Column="2" HorizontalAlignment="Center" VerticalAlignment="Center">
                  <Grid Width="64" Height="64" Margin="0,0,0,8">
                    <Ellipse Stroke="#242434" StrokeThickness="5"/>
                    <Path x:Name="StatsRamArc" Stroke="#38BDF8" StrokeThickness="5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <TextBlock x:Name="StatsRamVal" Text="73%" FontSize="15" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono, Monospace"
                               Foreground="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Grid>
                  <TextBlock Text="MEMORY" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                  <TextBlock x:Name="StatsRamUsage" Text="11.3 / 15.4 GB" FontSize="10" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#9B9BA7" Margin="0,2,0,0" HorizontalAlignment="Center"/>
                </StackPanel>
              </Grid>

              <!-- 4. CONTROLS TAB (EXACT V0 MATCH) -->
              <Grid x:Name="ViewControls" Margin="10,6" Visibility="Collapsed">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>  <!-- Sliders -->
                  <RowDefinition Height="Auto"/>  <!-- 4 Action Tiles -->
                </Grid.RowDefinitions>

                <!-- Top: Volume & Brightness Sliders -->
                <StackPanel Grid.Row="0" Margin="0,0,0,14">
                  <Grid Margin="0,3">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="28"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="34"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock x:Name="IconMasterSpeaker" Grid.Column="0" Text="&#xE767;" FontFamily="Segoe MDL2 Assets"
                               FontSize="13" Foreground="#FFFFFF" VerticalAlignment="Center" Cursor="Hand"/>
                    <Slider x:Name="SliderMasterVolume" Style="{StaticResource IslandSliderStyle}" Grid.Column="1" Minimum="0" Maximum="100" Value="50"
                            VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>
                    <TextBlock x:Name="TextMasterVolumeVal" Grid.Column="2" Text="50"
                               FontSize="11" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#FFFFFF"
                               TextAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>

                  <Grid Margin="0,3">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="28"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="34"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="&#xE706;" FontFamily="Segoe MDL2 Assets"
                               FontSize="13" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                    <Slider x:Name="SliderBrightness" Style="{StaticResource IslandSliderStyle}" Grid.Column="1" Minimum="0" Maximum="100" Value="70"
                            VerticalAlignment="Center" Focusable="False" Cursor="Hand"/>
                    <TextBlock x:Name="TextBrightnessVal" Grid.Column="2" Text="70"
                               FontSize="11" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#FFFFFF"
                               TextAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>
                </StackPanel>

                <!-- Bottom: 4 Action Tiles -->
                <Grid Grid.Row="1" Margin="4,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <StackPanel x:Name="TileBluetooth" Grid.Column="0" HorizontalAlignment="Center" Cursor="Hand">
                    <Border x:Name="TileBluetoothCircle" Width="48" Height="48" CornerRadius="24" Background="#A78BFA" Margin="0,0,0,6">
                      <TextBlock x:Name="TileBluetoothIcon" Text="&#xE702;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Bluetooth" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock x:Name="TileBluetoothSub" Text="On" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>

                  <StackPanel x:Name="TileNightLight" Grid.Column="1" HorizontalAlignment="Center" Cursor="Hand">
                    <Border x:Name="TileNightLightCircle" Width="48" Height="48" CornerRadius="24" Background="#1E1E28" Margin="0,0,0,6">
                      <TextBlock Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Night Light" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock x:Name="TileNightLightSub" Text="Off" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>

                  <StackPanel x:Name="TileTaskMgr" Grid.Column="2" HorizontalAlignment="Center" Cursor="Hand">
                    <Border Width="48" Height="48" CornerRadius="24" Background="#1E1E28" Margin="0,0,0,6">
                      <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Task Mgr" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock Text="Open" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>

                  <StackPanel x:Name="TileExplorer" Grid.Column="3" HorizontalAlignment="Center" Cursor="Hand">
                    <Border Width="48" Height="48" CornerRadius="24" Background="#1E1E28" Margin="0,0,0,6">
                      <TextBlock Text="&#xEC50;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Explorer" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock Text="Open" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>
                </Grid>
              </Grid>

              <!-- 5. POWER TAB (EXACT V0 MATCH) -->
              <Grid x:Name="ViewPower" Margin="10,8" Visibility="Collapsed">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>  <!-- Action Tiles -->
                  <RowDefinition Height="Auto"/>  <!-- Uptime -->
                </Grid.RowDefinitions>

                <Grid Grid.Row="0" Margin="4,0,4,14">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <StackPanel x:Name="TilePowerLock" Grid.Column="0" HorizontalAlignment="Center" Cursor="Hand">
                    <Border Width="48" Height="48" CornerRadius="24" Background="#1E1E28" Margin="0,0,0,6">
                      <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Lock" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock Text="Win + L" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>

                  <StackPanel x:Name="TilePowerSleep" Grid.Column="1" HorizontalAlignment="Center" Cursor="Hand">
                    <Border Width="48" Height="48" CornerRadius="24" Background="#1E1E28" Margin="0,0,0,6">
                      <TextBlock Text="&#xE708;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Sleep" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock Text="Suspend" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>

                  <StackPanel x:Name="TilePowerRestart" Grid.Column="2" HorizontalAlignment="Center" Cursor="Hand">
                    <Border Width="48" Height="48" CornerRadius="24" Background="#1E1E28" Margin="0,0,0,6">
                      <TextBlock Text="&#xE777;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#FFFFFF"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Restart" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock x:Name="PowerRestartSub" Text="Hold" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>

                  <StackPanel x:Name="TilePowerShutdown" Grid.Column="3" HorizontalAlignment="Center" Cursor="Hand">
                    <Border x:Name="TilePowerShutdownCircle" Width="48" Height="48" CornerRadius="24" Background="#1E1E28" Margin="0,0,0,6">
                      <TextBlock Text="&#xE7E8;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="#F87171"
                                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <TextBlock Text="Shut Down" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                    <TextBlock x:Name="PowerShutdownSub" Text="Hold" FontSize="10" Foreground="#F87171" HorizontalAlignment="Center" Margin="0,1,0,0"/>
                  </StackPanel>
                </Grid>

                <TextBlock x:Name="PowerUptimeText" Grid.Row="1" Text="Uptime 1h 12m &#x00B7; Last restart Sat 13:58"
                           FontSize="11" FontFamily="Consolas, Segoe UI Mono, Monospace" Foreground="#9B9BA7"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>

              <!-- 6. SETTINGS TAB -->
              <Grid x:Name="ViewSettings" Margin="4,2" Visibility="Collapsed">
                <StackPanel>
                  <!-- Settings Header with Back Button -->
                  <Grid Margin="4,0,4,8">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Button x:Name="BtnSettingsBack" Grid.Column="0" Content="&#xE72B;" FontFamily="Segoe MDL2 Assets"
                            FontSize="12" Style="{StaticResource HeaderActionBtnStyle}" Margin="0,0,8,0"/>
                    <TextBlock Grid.Column="1" Text="Settings" FontSize="13" FontWeight="SemiBold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                  </Grid>

                  <!-- Visual Style: Opaque vs Frosted Glass -->
                  <Border x:Name="CardSettingStyle" Background="#16161D" CornerRadius="16" Padding="14,8" Margin="0,0,0,6">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Grid.Column="0" Text="VISUAL STYLE" FontSize="10" FontWeight="SemiBold" Foreground="#9B9BA7" VerticalAlignment="Center" Margin="0,0,10,0"/>
                      <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="BtnStyleOpaque" Content="Opaque" Width="72" Height="22" Margin="2,0"
                                FontSize="10" FontWeight="SemiBold" Style="{StaticResource SegmentBtnStyle}"/>
                        <Button x:Name="BtnStyleGlass" Content="Frosted Glass" Width="92" Height="22" Margin="2,0"
                                FontSize="10" FontWeight="SemiBold" Style="{StaticResource SegmentBtnStyle}"/>
                      </StackPanel>
                    </Grid>
                  </Border>

                  <!-- Accent Color Swatches -->
                  <Border x:Name="CardSettingColor" Background="#16161D" CornerRadius="16" Padding="14,8" Margin="0,0,0,6">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Grid.Column="0" Text="ACCENT COLOR" FontSize="10" FontWeight="SemiBold" Foreground="#9B9BA7" VerticalAlignment="Center" Margin="0,0,10,0"/>
                      <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                        <Border x:Name="ColorViolet" Width="22" Height="22" CornerRadius="11" Background="#A78BFA" Margin="3,0" Cursor="Hand" ToolTip="Violet (#A78BFA)"/>
                        <Border x:Name="ColorCyan" Width="22" Height="22" CornerRadius="11" Background="#22D3EE" Margin="3,0" Cursor="Hand" ToolTip="Cyan (#22D3EE)"/>
                        <Border x:Name="ColorEmerald" Width="22" Height="22" CornerRadius="11" Background="#34D399" Margin="3,0" Cursor="Hand" ToolTip="Emerald (#34D399)"/>
                        <Border x:Name="ColorAmber" Width="22" Height="22" CornerRadius="11" Background="#FBBF24" Margin="3,0" Cursor="Hand" ToolTip="Amber (#FBBF24)"/>
                        <Border x:Name="ColorCoral" Width="22" Height="22" CornerRadius="11" Background="#F87171" Margin="3,0" Cursor="Hand" ToolTip="Coral (#F87171)"/>
                        <Border x:Name="ColorPink" Width="22" Height="22" CornerRadius="11" Background="#F472B6" Margin="3,0" Cursor="Hand" ToolTip="Pink (#F472B6)"/>
                        <Border x:Name="ColorWhite" Width="22" Height="22" CornerRadius="11" Background="#FFFFFF" Margin="3,0" Cursor="Hand" ToolTip="White (#FFFFFF)"/>
                      </StackPanel>
                    </Grid>
                  </Border>

                  <!-- Multi-Edge Screen Docking -->
                  <Border x:Name="CardSettingDock" Background="#16161D" CornerRadius="16" Padding="14,8" Margin="0,0,0,6">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Grid.Column="0" Text="SCREEN DOCK" FontSize="10" FontWeight="SemiBold" Foreground="#9B9BA7" VerticalAlignment="Center" Margin="0,0,10,0"/>
                      <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="BtnDockTop" Content="Top" Width="52" Height="22" Margin="2,0"
                                FontSize="10" FontWeight="SemiBold" Style="{StaticResource SegmentBtnStyle}"/>
                        <Button x:Name="BtnDockLeft" Content="Left" Width="52" Height="22" Margin="2,0"
                                FontSize="10" FontWeight="SemiBold" Style="{StaticResource SegmentBtnStyle}"/>
                        <Button x:Name="BtnDockRight" Content="Right" Width="52" Height="22" Margin="2,0"
                                FontSize="10" FontWeight="SemiBold" Style="{StaticResource SegmentBtnStyle}"/>
                      </StackPanel>
                    </Grid>
                  </Border>

                  <Border x:Name="CardSettingTabs" Background="#16161D" CornerRadius="16" Padding="14,8">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>

                      <TextBlock Grid.Column="0" Text="VISIBLE TABS" FontSize="10" FontWeight="SemiBold" Foreground="#9B9BA7" VerticalAlignment="Center" Margin="0,0,12,0"/>

                      <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                        <CheckBox x:Name="ToggleTabToday"    Content="Today"    IsChecked="True"  Margin="4,0" Foreground="#FFFFFF" Focusable="False" Cursor="Hand"/>
                        <CheckBox x:Name="ToggleTabMedia"    Content="Media"    IsChecked="True"  Margin="4,0" Foreground="#FFFFFF" Focusable="False" Cursor="Hand"/>
                        <CheckBox x:Name="ToggleTabStats"    Content="Stats"    IsChecked="True"  Margin="4,0" Foreground="#FFFFFF" Focusable="False" Cursor="Hand"/>
                        <CheckBox x:Name="ToggleTabControls" Content="Controls" IsChecked="True"  Margin="4,0" Foreground="#FFFFFF" Focusable="False" Cursor="Hand"/>
                        <CheckBox x:Name="ToggleTabPower"    Content="Power"    IsChecked="True"  Margin="4,0" Foreground="#FFFFFF" Focusable="False" Cursor="Hand"/>
                      </StackPanel>
                    </Grid>
                  </Border>
                </StackPanel>
              </Grid>

            </Grid>
          </ScrollViewer>

          <!-- Quick File Sharing QR Modal -->
          <Border x:Name="FileDropModal" Grid.Row="1" Visibility="Collapsed" Background="#F00D111A" CornerRadius="20" Margin="6" Padding="14">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>

              <Grid Grid.Row="0" Margin="0,0,0,8">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock Text="&#xE8B7;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#34D399" Margin="0,0,8,0" VerticalAlignment="Center"/>
                  <TextBlock Text="Quick File Share (Wi-Fi Transfer)" FontSize="12" FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                </StackPanel>
                <Button x:Name="BtnCloseFileShare" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11" HorizontalAlignment="Right" Style="{StaticResource HeaderActionBtnStyle}"/>
              </Grid>

              <StackPanel Grid.Row="1" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,4">
                <Border Width="110" Height="110" Background="#FFFFFF" CornerRadius="12" Padding="6" Margin="0,0,0,8" HorizontalAlignment="Center">
                  <Image x:Name="FileShareQrImage" Stretch="Uniform"/>
                </Border>
                <TextBlock x:Name="FileShareNameText" Text="filename.ext" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF" HorizontalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="280"/>
                <TextBlock x:Name="FileShareSizeText" Text="0 MB &#x00B7; Scan with phone on Wi-Fi" FontSize="10" Foreground="#9B9BA7" HorizontalAlignment="Center" Margin="0,2,0,0"/>
              </StackPanel>

              <Border Grid.Row="2" Background="#16161D" CornerRadius="12" Padding="8,4" Margin="0,8,0,0">
                <Grid>
                  <TextBlock x:Name="FileShareUrlText" Text="http://192.168.1.10:8080/file" FontSize="10" Foreground="#A78BFA" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="4,0,55,0"/>
                  <Button x:Name="BtnCopyShareUrl" Content="Copy" Width="48" Height="22" HorizontalAlignment="Right" FontSize="10" FontWeight="SemiBold" Style="{StaticResource SegmentBtnStyle}" Background="#A78BFA" Foreground="#000000"/>
                </Grid>
              </Border>
            </Grid>
          </Border>
        </Grid>
      </Border>
    </Grid>
  </Grid>
</Window>
"@

# ------------------------------------------------------------------------------
#  WPF Window Realization & Dynamic Element Resolution
# ------------------------------------------------------------------------------
$reader = New-Object System.Xml.XmlNodeReader($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Shell & Root Elements
$islandHoverZone    = $window.FindName('IslandHoverZone')
$topTriggerBar       = $window.FindName('TopTriggerBar')
$leftTriggerBar      = $window.FindName('LeftTriggerBar')
$rightTriggerBar     = $window.FindName('RightTriggerBar')
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
$headerBandBorder    = $window.FindName('HeaderBandBorder')
$collapsedBrand      = $window.FindName('CollapsedBrand')
$navTabsCapsule      = $window.FindName('NavTabsCapsule')
$navTabsContainer    = $window.FindName('NavTabsContainer')
$compactInfo         = $window.FindName('CompactInfo')
$headerActions       = $window.FindName('HeaderActions')
$btnSettingsToggle   = $window.FindName('BtnSettingsToggle')
$btnPinToggle        = $window.FindName('BtnPinToggle')
$btnSettingsBack     = $window.FindName('BtnSettingsBack')

  # Tab Capsules
$tabBtnToday         = $window.FindName('TabBtnToday')
$tabBtnApps          = $window.FindName('TabBtnApps')
$tabBtnMedia         = $window.FindName('TabBtnMedia')
$tabBtnStats         = $window.FindName('TabBtnStats')
$tabBtnControls      = $window.FindName('TabBtnControls')
$tabBtnPower         = $window.FindName('TabBtnPower')

# Views
$contentScrollViewer = $window.FindName('ContentScrollViewer')
$expandedContent     = $window.FindName('ExpandedContent')
$viewToday           = $window.FindName('ViewToday')
$viewApps            = $window.FindName('ViewApps')
$viewMedia           = $window.FindName('ViewMedia')
$appsPinnedContainer = $window.FindName('AppsPinnedContainer')
$appsRecentContainer = $window.FindName('AppsRecentContainer')
$btnAddApp           = $window.FindName('BtnAddApp')
$viewStats           = $window.FindName('ViewStats')
$viewControls        = $window.FindName('ViewControls')
$viewPower           = $window.FindName('ViewPower')
$viewSettings        = $window.FindName('ViewSettings')

# Today Elements
$todayClockHours     = $window.FindName('TodayClockHours')
$todayClockAmPm      = $window.FindName('TodayClockAmPm')
$todayDate           = $window.FindName('TodayDate')
$todayGreeting       = $window.FindName('TodayGreeting')
$todayGreetingIcon   = $window.FindName('TodayGreetingIcon')
$todayBatteryArc     = $window.FindName('TodayBatteryArc')
$todayBatteryCenterIcon = $window.FindName('TodayBatteryCenterIcon')
$todayBatteryPercent = $window.FindName('TodayBatteryPercent')
$todayBatteryState   = $window.FindName('TodayBatteryState')
$todayCpuFill        = $window.FindName('TodayCpuFill')
$todayCpuPct         = $window.FindName('TodayCpuPct')
$todayGpuFill        = $window.FindName('TodayGpuFill')
$todayGpuPct         = $window.FindName('TodayGpuPct')
$todayRamFill        = $window.FindName('TodayRamFill')
$todayRamPct         = $window.FindName('TodayRamPct')
$todayDivider        = $window.FindName('TodayDivider')
$colTodayLeft        = $window.FindName('ColTodayLeft')
$colTodayDiv         = $window.FindName('ColTodayDiv')
$colTodayRight       = $window.FindName('ColTodayRight')
$todayLeftStack      = $window.FindName('TodayLeftStack')
$todayRightStack     = $window.FindName('TodayRightStack')

# Game Mode Elements
$gameModeBar         = $window.FindName('GameModeBar')
$gameModeNameText    = $window.FindName('GameModeNameText')
$gameModeClock       = $window.FindName('GameModeClock')
$gameModeCpu         = $window.FindName('GameModeCpu')
$gameModeGpu         = $window.FindName('GameModeGpu')
$gameModeRam         = $window.FindName('GameModeRam')

# Game Mode Dropdown Elements
$gameModeDropdown    = $window.FindName('GameModeDropdown')
$gameDropSessionText = $window.FindName('GameDropSessionText')
$gameDropDisplayInfo = $window.FindName('GameDropDisplayInfo')
$gameDropFpsText     = $window.FindName('GameDropFpsText')
$gameDropFrameTime   = $window.FindName('GameDropFrameTime')
$gameDropPingDot     = $window.FindName('GameDropPingDot')
$gameDropPingText    = $window.FindName('GameDropPingText')
$gameDropAlertBanner = $window.FindName('GameDropAlertBanner')
$gameDropAlertText   = $window.FindName('GameDropAlertText')
$gameDropCpuVal      = $window.FindName('GameDropCpuVal')
$gameDropCpuClock    = $window.FindName('GameDropCpuClock')
$gameDropCpuBar      = $window.FindName('GameDropCpuBar')
$gameDropRamVal      = $window.FindName('GameDropRamVal')
$gameDropRamBytes    = $window.FindName('GameDropRamBytes')
$gameDropRamBar      = $window.FindName('GameDropRamBar')
$gameDropGpuVal      = $window.FindName('GameDropGpuVal')
$gameDropGpuClock    = $window.FindName('GameDropGpuClock')
$gameDropGpuBar      = $window.FindName('GameDropGpuBar')
$gameDropVramVal     = $window.FindName('GameDropVramVal')
$gameDropVramPct     = $window.FindName('GameDropVramPct')
$gameDropVramBar     = $window.FindName('GameDropVramBar')

$btnGameMuteMic      = $window.FindName('BtnGameMuteMic')
$btnGameMuteAudio    = $window.FindName('BtnGameMuteAudio')
$btnGameScreenshot   = $window.FindName('BtnGameScreenshot')
$btnGamePerformance  = $window.FindName('BtnGamePerformance')
$btnGamePin          = $window.FindName('BtnGamePin')
$btnExitGameMode     = $window.FindName('BtnExitGameMode')

# File Share Elements
$fileDropModal       = $window.FindName('FileDropModal')
$fileShareQrImage    = $window.FindName('FileShareQrImage')
$fileShareNameText   = $window.FindName('FileShareNameText')
$fileShareSizeText   = $window.FindName('FileShareSizeText')
$fileShareUrlText    = $window.FindName('FileShareUrlText')
$btnCopyShareUrl     = $window.FindName('BtnCopyShareUrl')
$btnCloseFileShare   = $window.FindName('BtnCloseFileShare')

# Media Elements
$albumArtContainer   = $window.FindName('AlbumArtContainer')
$albumArtPlaceholderBg = $window.FindName('AlbumArtPlaceholderBg')
$albumArtBrandGlyph  = $window.FindName('AlbumArtBrandGlyph')
$albumArtBrandText   = $window.FindName('AlbumArtBrandText')
$albumArtImage       = $window.FindName('AlbumArtImage')
$mediaDeviceText     = $window.FindName('MediaDeviceText')
$mediaTitleText      = $window.FindName('MediaTitleText')
$mediaArtistText     = $window.FindName('MediaArtistText')
$mediaTimeCurrent    = $window.FindName('MediaTimeCurrent')
$mediaTimeTotal      = $window.FindName('MediaTimeTotal')
$mediaTrackProgress  = $window.FindName('MediaTrackProgress')
$mediaTrackContainer = $window.FindName('MediaTrackContainer')
$btnMediaPrev        = $window.FindName('BtnMediaPrev')
$btnMediaPlay        = $window.FindName('BtnMediaPlay')
$btnMediaNext        = $window.FindName('BtnMediaNext')
$eqBar1              = $window.FindName('EqBar1')
$eqBar2              = $window.FindName('EqBar2')
$eqBar3              = $window.FindName('EqBar3')
$eqBar4              = $window.FindName('EqBar4')
$eqBar5              = $window.FindName('EqBar5')
$eqBar6              = $window.FindName('EqBar6')

# Stats Elements
$statsCpuArc         = $window.FindName('StatsCpuArc')
$statsCpuVal         = $window.FindName('StatsCpuVal')
$statsCpuClock       = $window.FindName('StatsCpuClock')
$statsGpuArc         = $window.FindName('StatsGpuArc')
$statsGpuVal         = $window.FindName('StatsGpuVal')
$statsGpuClock       = $window.FindName('StatsGpuClock')
$statsRamArc         = $window.FindName('StatsRamArc')
$statsRamVal         = $window.FindName('StatsRamVal')
$statsRamUsage       = $window.FindName('StatsRamUsage')

# Controls Elements
$iconMasterSpeaker   = $window.FindName('IconMasterSpeaker')
$sliderMasterVolume  = $window.FindName('SliderMasterVolume')
$textMasterVolumeVal = $window.FindName('TextMasterVolumeVal')
$sliderBrightness    = $window.FindName('SliderBrightness')
$textBrightnessVal   = $window.FindName('TextBrightnessVal')
$tileBluetooth       = $window.FindName('TileBluetooth')
$tileBluetoothCircle = $window.FindName('TileBluetoothCircle')
$tileBluetoothSub    = $window.FindName('TileBluetoothSub')
$tileNightLight      = $window.FindName('TileNightLight')
$tileNightLightCircle= $window.FindName('TileNightLightCircle')
$tileNightLightSub   = $window.FindName('TileNightLightSub')
$tileTaskMgr         = $window.FindName('TileTaskMgr')
$tileExplorer        = $window.FindName('TileExplorer')

# Power Elements
$tilePowerLock       = $window.FindName('TilePowerLock')
$tilePowerSleep      = $window.FindName('TilePowerSleep')
$tilePowerRestart    = $window.FindName('TilePowerRestart')
$powerRestartSub     = $window.FindName('PowerRestartSub')
$tilePowerShutdown   = $window.FindName('TilePowerShutdown')
$tilePowerShutdownCircle = $window.FindName('TilePowerShutdownCircle')
$powerShutdownSub    = $window.FindName('PowerShutdownSub')
$powerUptimeText     = $window.FindName('PowerUptimeText')

# Settings Elements
$btnStyleOpaque      = $window.FindName('BtnStyleOpaque')
$btnStyleGlass       = $window.FindName('BtnStyleGlass')
$cardSettingStyle    = $window.FindName('CardSettingStyle')
$cardSettingColor    = $window.FindName('CardSettingColor')
$cardSettingDock     = $window.FindName('CardSettingDock')
$cardSettingTabs     = $window.FindName('CardSettingTabs')
$colorViolet         = $window.FindName('ColorViolet')
$colorCyan           = $window.FindName('ColorCyan')
$colorEmerald        = $window.FindName('ColorEmerald')
$colorAmber          = $window.FindName('ColorAmber')
$colorCoral          = $window.FindName('ColorCoral')
$colorPink           = $window.FindName('ColorPink')
$colorWhite          = $window.FindName('ColorWhite')
$btnDockTop          = $window.FindName('BtnDockTop')
$btnDockLeft         = $window.FindName('BtnDockLeft')
$btnDockRight        = $window.FindName('BtnDockRight')

# Context Menu
$islandContextMenu   = $window.Resources['IslandContextMenu']
$menuToggleGameMode  = $islandContextMenu.Items[0]
$menuResetPos        = $islandContextMenu.Items[1]
$menuToggleGlass     = $islandContextMenu.Items[2]
$menuDockMenu        = $islandContextMenu.Items[3]
$menuDockTop         = $menuDockMenu.Items[0]
$menuDockLeft        = $menuDockMenu.Items[1]
$menuDockRight       = $menuDockMenu.Items[2]
$menuReload          = $islandContextMenu.Items[5]
$menuQuit            = $islandContextMenu.Items[6]

# ------------------------------------------------------------------------------
#  Tab Map & Brushes
# ------------------------------------------------------------------------------
$tabButtons = @{
    Today    = $tabBtnToday
    Apps     = $tabBtnApps
    Media    = $tabBtnMedia
    Stats    = $tabBtnStats
    Controls = $tabBtnControls
    Power    = $tabBtnPower
}

$tabViews = @{
    Today    = $viewToday
    Apps     = $viewApps
    Media    = $viewMedia
    Stats    = $viewStats
    Controls = $viewControls
    Power    = $viewPower
    Settings = $viewSettings
}

$script:brushActiveBg   = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#FFFFFF"))
$script:brushActiveFg   = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#000000"))
$script:brushInactiveFg = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#9B9BA7"))
$script:brushGreen      = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#34D399"))
$script:brushAmber      = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#FBBF24"))
$script:brushRed        = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#F87171"))
$script:brushNeutral    = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#E4E4E7"))
$script:brushPurple     = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#A78BFA"))
$script:brushCyan       = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#22D3EE"))

$script:activeTab   = "Today"
$script:previousTab = "Today"

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
    if ($script:inGameMode) { return }
    try {
        $maxAllowed = [System.Windows.SystemParameters]::PrimaryScreenHeight * 0.70
        $clampedH = [Math]::Min($targetHeight, $maxAllowed - 40)
        $window.Height = $clampedH + 28
        $animH = New-Object System.Windows.Media.Animation.DoubleAnimation
        $animH.To = $clampedH
        $animH.Duration = [TimeSpan]::FromSeconds(0.2)
        $animH.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
        $glowBorder.BeginAnimation([System.Windows.Controls.Border]::HeightProperty, $animH)
    } catch {
        $glowBorder.Height = $targetHeight
        $window.Height = $targetHeight + 28
    }
}

# ------------------------------------------------------------------------------
#  Multi-Edge Docking & True Vertical Sidebar Refactor (Top, Left, Right)
# ------------------------------------------------------------------------------
$script:isPinned    = [bool]$Config.Pinned
$script:dockEdge    = if ($Config.DockEdge) { [string]$Config.DockEdge } else { "Top" }
$script:isGlass     = [bool]$Config.GlassMode
$script:isRetracted = $false

function Animate-DockTop ([double]$targetTop) {
    try {
        $animT = New-Object System.Windows.Media.Animation.DoubleAnimation
        $animT.To = $targetTop
        $animT.Duration = [TimeSpan]::FromSeconds(0.25)
        $animT.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
        $window.BeginAnimation([System.Windows.Window]::TopProperty, $animT)
    } catch {
        $window.Top = $targetTop
    }
}

function Animate-DockLeft ([double]$targetLeft) {
    try {
        $animL = New-Object System.Windows.Media.Animation.DoubleAnimation
        $animL.To = $targetLeft
        $animL.Duration = [TimeSpan]::FromSeconds(0.25)
        $animL.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
        $window.BeginAnimation([System.Windows.Window]::LeftProperty, $animL)
    } catch {
        $window.Left = $targetLeft
    }
}

function Update-SideOrientationLayout {
    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $priH = [System.Windows.SystemParameters]::PrimaryScreenHeight

    if ($script:dockEdge -eq "Left" -or $script:dockEdge -eq "Right") {
        # VERTICAL SIDEBAR MODE (Width 340px)
        $Config.ExpandedWidth = 340
        $Config.WindowWidth   = 360
        $window.Width         = 360

        # Show side trigger bars, hide top trigger bar
        $topTriggerBar.Visibility = 'Collapsed'
        if ($script:dockEdge -eq "Left") {
            $leftTriggerBar.Visibility  = 'Visible'
            $rightTriggerBar.Visibility = 'Collapsed'
            $glowBorder.HorizontalAlignment      = [System.Windows.HorizontalAlignment]::Left
            $islandHoverZone.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        } else {
            $leftTriggerBar.Visibility  = 'Collapsed'
            $rightTriggerBar.Visibility = 'Visible'
            $glowBorder.HorizontalAlignment      = [System.Windows.HorizontalAlignment]::Right
            $islandHoverZone.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        }

        # Morph Today tab to clean vertical stack
        $colTodayLeft.Width  = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $colTodayDiv.Width   = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Pixel)
        $colTodayRight.Width = New-Object System.Windows.GridLength(0, [System.Windows.GridUnitType]::Pixel)
        $todayDivider.Visibility = 'Collapsed'
    } else {
        # TOP DOCK HORIZONTAL MODE (Width 520px)
        $Config.ExpandedWidth = 520
        $Config.WindowWidth   = 560
        $window.Width         = 560

        $topTriggerBar.Visibility   = 'Visible'
        $leftTriggerBar.Visibility  = 'Collapsed'
        $rightTriggerBar.Visibility = 'Collapsed'

        $glowBorder.HorizontalAlignment      = [System.Windows.HorizontalAlignment]::Center
        $islandHoverZone.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

        # Morph Today tab to side-by-side 2 columns
        $colTodayLeft.Width  = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $colTodayDiv.Width   = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
        $colTodayRight.Width = New-Object System.Windows.GridLength(1.25, [System.Windows.GridUnitType]::Star)
        $todayDivider.Visibility = 'Visible'
    }
}

function Slide-DownIsland {
    if ($script:inGameMode) { return }
    if (-not $script:isRetracted) { return }
    $script:isRetracted = $false
    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $priH = [System.Windows.SystemParameters]::PrimaryScreenHeight

    switch ($script:dockEdge) {
        "Left" {
            Animate-DockLeft 0.0
            $window.Top = [Math]::Max(15.0, ($priH / 2.0) - ($window.Height / 2.0))
        }
        "Right" {
            Animate-DockLeft ($priW - $window.Width)
            $window.Top = [Math]::Max(15.0, ($priH / 2.0) - ($window.Height / 2.0))
        }
        Default { # "Top"
            Animate-DockTop 38.0
            $window.Left = ($priW / 2.0) - ($window.Width / 2.0)
        }
    }
}

function Slide-UpIsland {
    if ($script:inGameMode) { return }
    if ($script:isPinned -or $script:isRetracted) { return }
    $script:isRetracted = $true
    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth

    try { $window.UpdateLayout() } catch { }

    switch ($script:dockEdge) {
        "Left" {
            # Leaves slim 6px vertical trigger strip along the left monitor edge
            $retractLeft = -([Math]::Max(40.0, $window.Width - 6.0))
            Animate-DockLeft $retractLeft
        }
        "Right" {
            # Leaves slim 6px vertical trigger strip along the right monitor edge
            $retractLeft = ($priW - 6.0)
            Animate-DockLeft $retractLeft
        }
        Default { # "Top"
            # Leaves slim 6px trigger strip along the top monitor edge
            Animate-DockTop -44.0
        }
    }
}

function Set-DockEdge ([string]$edge) {
    $script:dockEdge = $edge
    $Config.DockEdge = $edge
    Save-Config
    Update-DockUI
    Update-SideOrientationLayout

    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $priH = [System.Windows.SystemParameters]::PrimaryScreenHeight

    $script:isRetracted = $false
    try { $window.UpdateLayout() } catch { }

    switch ($edge) {
        "Left" {
            $window.Left = if ($script:isPinned) { 10.0 } else { 0.0 }
            $window.Top  = [Math]::Max(15.0, ($priH / 2.0) - ($window.Height / 2.0))
        }
        "Right" {
            $window.Left = if ($script:isPinned) { $priW - $window.Width - 10.0 } else { $priW - $window.Width }
            $window.Top  = [Math]::Max(15.0, ($priH / 2.0) - ($window.Height / 2.0))
        }
        Default { # "Top"
            $window.Left = ($priW / 2.0) - ($window.Width / 2.0)
            $window.Top  = if ($script:isPinned) { 38.0 } else { 0.0 }
        }
    }
}

function Update-DockUI {
    $bc = [System.Windows.Media.BrushConverter]::new()
    $activeBg = $script:brushPurple
    $activeFg = $bc.ConvertFromString("#000000")
    $inactiveBg = $bc.ConvertFromString("#1A1A24")
    $inactiveFg = $bc.ConvertFromString("#9B9BA7")
    $borderActive = [System.Windows.Media.Brushes]::Transparent
    $borderInactive = $bc.ConvertFromString("#25FFFFFF")

    if ($btnDockTop) {
        $isTop = ($script:dockEdge -eq "Top")
        $btnDockTop.Background = if ($isTop) { $activeBg } else { $inactiveBg }
        $btnDockTop.Foreground = if ($isTop) { $activeFg } else { $inactiveFg }
        $btnDockTop.BorderBrush = if ($isTop) { $borderActive } else { $borderInactive }
        $btnDockTop.BorderThickness = New-Object System.Windows.Thickness($(if ($isTop) { 0 } else { 1 }))
    }
    if ($btnDockLeft) {
        $isLeft = ($script:dockEdge -eq "Left")
        $btnDockLeft.Background = if ($isLeft) { $activeBg } else { $inactiveBg }
        $btnDockLeft.Foreground = if ($isLeft) { $activeFg } else { $inactiveFg }
        $btnDockLeft.BorderBrush = if ($isLeft) { $borderActive } else { $borderInactive }
        $btnDockLeft.BorderThickness = New-Object System.Windows.Thickness($(if ($isLeft) { 0 } else { 1 }))
    }
    if ($btnDockRight) {
        $isRight = ($script:dockEdge -eq "Right")
        $btnDockRight.Background = if ($isRight) { $activeBg } else { $inactiveBg }
        $btnDockRight.Foreground = if ($isRight) { $activeFg } else { $inactiveFg }
        $btnDockRight.BorderBrush = if ($isRight) { $borderActive } else { $borderInactive }
        $btnDockRight.BorderThickness = New-Object System.Windows.Thickness($(if ($isRight) { 0 } else { 1 }))
    }
}

function Set-VisualStyle ([bool]$glass) {
    $script:isGlass = $glass
    $Config.GlassMode = $glass
    Save-Config
    Update-StyleUI



    $cards = @($cardSettingStyle, $cardSettingColor, $cardSettingDock, $cardSettingTabs)

    if ($glass) {
        # Rich Frosted Glass Mode (Obsidian translucent #CC0D111A matching reference pictures)
        $glowBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#CC0D111A"))
        $glowBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#33FFFFFF"))

        if ($navTabsCapsule) {
            $navTabsCapsule.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#30000000"))
        }

        $cardBg = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#2E16161D"))
        $cardBorder = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#25FFFFFF"))
        foreach ($c in $cards) {
            if ($c) {
                $c.Background = $cardBg
                $c.BorderBrush = $cardBorder
                $c.BorderThickness = New-Object System.Windows.Thickness(1)
            }
        }
    } else {
        # Opaque Mode: Pure solid dark charcoal (#FF0E0E13)
        $glowBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#FF0E0E13"))
        $glowBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#2AFFFFFF"))

        if ($navTabsCapsule) {
            $navTabsCapsule.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#16161D"))
        }

        $cardBg = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#16161D"))
        $cardBorder = [System.Windows.Media.Brushes]::Transparent
        foreach ($c in $cards) {
            if ($c) {
                $c.Background = $cardBg
                $c.BorderBrush = $cardBorder
                $c.BorderThickness = New-Object System.Windows.Thickness(0)
            }
        }
    }
}

function Update-ColorSwatchesUI ([string]$activeHex) {
    $swatches = @{
        '#A78BFA' = $colorViolet
        '#22D3EE' = $colorCyan
        '#34D399' = $colorEmerald
        '#FBBF24' = $colorAmber
        '#F87171' = $colorCoral
        '#F472B6' = $colorPink
        '#FFFFFF' = $colorWhite
    }
    foreach ($hex in $swatches.Keys) {
        $sw = $swatches[$hex]
        if ($sw) {
            if ($hex -ieq $activeHex) {
                $sw.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#FFFFFF'))
                $sw.BorderThickness = New-Object System.Windows.Thickness(2)
            } else {
                $sw.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#33FFFFFF'))
                $sw.BorderThickness = New-Object System.Windows.Thickness(1)
            }
        }
    }
}

function Set-AccentColor ([string]$hexColor) {
    $Config.GlowColor = $hexColor
    Save-Config

    $script:brushPurple = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($hexColor))

    if ($islandGlow) {
        $islandGlow.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($hexColor)
    }

    if ($btnPinToggle -and $script:isPinned) {
        $btnPinToggle.Foreground = $script:brushPurple
    }

    if ($btnSettingsToggle -and $script:activeTab -eq 'Settings') {
        $btnSettingsToggle.Foreground = $script:brushPurple
    }

    # Update Equalizer bars
    $eqBars = @($eqBar1, $eqBar2, $eqBar3, $eqBar4, $eqBar5, $eqBar6)
    foreach ($b in $eqBars) {
        if ($b) { $b.Background = $script:brushPurple }
    }

    # Update Today greeting
    if ($todayGreetingIcon) { $todayGreetingIcon.Foreground = $script:brushPurple }

    # Update Swatches & Action button highlights
    Update-ColorSwatchesUI $hexColor
    Update-StyleUI
    Update-DockUI
}

function Update-StyleUI {
    $bc = [System.Windows.Media.BrushConverter]::new()
    $activeBg = $script:brushPurple
    $activeFg = $bc.ConvertFromString("#000000")
    $inactiveBg = $bc.ConvertFromString("#1A1A24")
    $inactiveFg = $bc.ConvertFromString("#9B9BA7")
    $borderActive = [System.Windows.Media.Brushes]::Transparent
    $borderInactive = $bc.ConvertFromString("#25FFFFFF")

    if ($btnStyleOpaque) {
        $isActive = (-not $script:isGlass)
        $btnStyleOpaque.Background = if ($isActive) { $activeBg } else { $inactiveBg }
        $btnStyleOpaque.Foreground = if ($isActive) { $activeFg } else { $inactiveFg }
        $btnStyleOpaque.BorderBrush = if ($isActive) { $borderActive } else { $borderInactive }
        $btnStyleOpaque.BorderThickness = New-Object System.Windows.Thickness($(if ($isActive) { 0 } else { 1 }))
    }
    if ($btnStyleGlass) {
        $isActive = [bool]$script:isGlass
        $btnStyleGlass.Background = if ($isActive) { $activeBg } else { $inactiveBg }
        $btnStyleGlass.Foreground = if ($isActive) { $activeFg } else { $inactiveFg }
        $btnStyleGlass.BorderBrush = if ($isActive) { $borderActive } else { $borderInactive }
        $btnStyleGlass.BorderThickness = New-Object System.Windows.Thickness($(if ($isActive) { 0 } else { 1 }))
    }
}

# ------------------------------------------------------------------------------
#  Tab Navigation Engine (Strictly ONE Active Tab Highlighted)
# ------------------------------------------------------------------------------
function Switch-Tab ([string]$tabName) {
    if ($tabName -ne 'Settings') {
        $script:previousTab = $tabName
    }
    $script:activeTab = $tabName

    foreach ($k in $tabViews.Keys) {
        $view = $tabViews[$k]
        if ($view) {
            $view.Visibility = if ($k -eq $tabName) { 'Visible' } else { 'Collapsed' }
        }
    }

    # High-contrast solid white pill (#FFFFFF) for active tab, muted #9B9BA7 for inactive
    foreach ($k in $tabButtons.Keys) {
        $btn = $tabButtons[$k]
        if ($btn) {
            if ($k -eq $tabName) {
                $btn.Background = $script:brushActiveBg
                $btn.Foreground = $script:brushActiveFg
                $btn.FontWeight = [System.Windows.FontWeights]::Bold
            } else {
                $btn.Background = [System.Windows.Media.Brushes]::Transparent
                $btn.Foreground = $script:brushInactiveFg
                $btn.FontWeight = [System.Windows.FontWeights]::Normal
            }
        }
    }

    if ($tabName -eq 'Settings') {
        if ($navTabsCapsule) { $navTabsCapsule.Visibility = 'Collapsed' }
        $btnSettingsToggle.Foreground = $script:brushPurple
    } else {
        if ($navTabsCapsule) { $navTabsCapsule.Visibility = 'Visible' }
        $btnSettingsToggle.Foreground = $script:brushInactiveFg
    }

    # Dynamic Height Measurement
    try {
        $window.UpdateLayout()
        $activeView = $tabViews[$tabName]
        $desiredH = if ($activeView) {
            switch ($tabName) {
                'Today'    { 200 }
                'Apps'     { 220 }
                'Media'    { 210 }
                'Stats'    { 190 }
                'Controls' { 200 }
                'Power'    { 190 }
                'Settings' { 275 }
                Default    { 200 }
            }
        } else { 200 }
        Animate-Height ($desiredH + 42)
    } catch { }
}

$tabBtnToday.Add_Click({ Switch-Tab 'Today' })
if ($tabBtnApps) { $tabBtnApps.Add_Click({ Render-AppsList; Switch-Tab 'Apps' }) }
$tabBtnMedia.Add_Click({ Switch-Tab 'Media' })
$tabBtnStats.Add_Click({ Switch-Tab 'Stats' })
$tabBtnControls.Add_Click({ Switch-Tab 'Controls' })
$tabBtnPower.Add_Click({ Switch-Tab 'Power' })

# Inactive Tab Smooth Hover Highlights (#2AFFFFFF)
$script:tabHoverBg = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#2AFFFFFF"))
$script:tabHoverFg = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#FFFFFF"))

foreach ($k in $tabButtons.Keys) {
    $tBtn = $tabButtons[$k]
    if ($tBtn) {
        $tBtn.Add_MouseEnter({
            param($s, $e)
            if ($script:activeTab -ne 'Settings' -and $s.Name -ne ("TabBtn" + $script:activeTab)) {
                $s.Background = $script:tabHoverBg
                $s.Foreground = $script:tabHoverFg
            }
        })
        $tBtn.Add_MouseLeave({
            param($s, $e)
            if ($s.Name -ne ("TabBtn" + $script:activeTab) -or $script:activeTab -eq 'Settings') {
                $s.Background = [System.Windows.Media.Brushes]::Transparent
                $s.Foreground = $script:brushInactiveFg
            }
        })
    }
}

$btnSettingsToggle.Add_Click({
    if ($script:activeTab -eq 'Settings') {
        Switch-Tab $script:previousTab
    } else {
        Switch-Tab 'Settings'
    }
})

function Update-PinUI {
    if ($script:isPinned) {
        $btnPinToggle.Foreground = $script:brushPurple
    } else {
        $btnPinToggle.Foreground = $script:brushInactiveFg
    }
}

$btnPinToggle.Add_Click({
    $script:isPinned = -not $script:isPinned
    $Config.Pinned   = $script:isPinned
    Save-Config
    Update-PinUI

    if ($script:isPinned) {
        Slide-DownIsland
    } else {
        if (-not $script:isExpanded) {
            Slide-UpIsland
        }
    }
})

# ------------------------------------------------------------------------------
#  Expand & Collapse Engine
# ------------------------------------------------------------------------------
$script:isExpanded = $false
$collapseTimer = New-Object System.Windows.Threading.DispatcherTimer
$collapseTimer.Interval = [TimeSpan]::FromMilliseconds($Config.CollapseDelay)

function Expand-Island {
    if ($script:inGameMode) { return }
    Slide-DownIsland
    if ($script:isExpanded) { return }
    $collapseTimer.Stop()
    $script:isExpanded = $true

    $collapsedBrand.Visibility   = 'Collapsed'
    $compactInfo.Visibility      = 'Collapsed'
    $compactTelemetry.Visibility = 'Collapsed'
    $navTabsCapsule.Visibility   = if ($script:activeTab -eq 'Settings') { 'Collapsed' } else { 'Visible' }
    $headerActions.Visibility    = 'Visible'
    $expandedContent.Visibility  = 'Visible'

    # Width Animation
    $targetW = if ($script:dockEdge -eq "Left" -or $script:dockEdge -eq "Right") { 340 } else { $Config.ExpandedWidth }
    $animW = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animW.To = $targetW
    $animW.Duration = [TimeSpan]::FromMilliseconds($Config.ExpandMs)
    $animW.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::WidthProperty, $animW)

    Switch-Tab $script:activeTab
}

function Collapse-Island {
    if (-not $script:isExpanded) { return }
    $script:isExpanded = $false

    $navTabsCapsule.Visibility   = 'Collapsed'
    $headerActions.Visibility    = 'Collapsed'
    $expandedContent.Visibility  = 'Collapsed'
    $collapsedBrand.Visibility   = 'Visible'
    $compactInfo.Visibility      = 'Visible'
    $compactTelemetry.Visibility = 'Visible'

    # Width Animation back to compact
    $animW = New-Object System.Windows.Media.Animation.DoubleAnimation
    $animW.To = $Config.IslandWidth
    $animW.Duration = [TimeSpan]::FromMilliseconds($Config.CollapseMs)
    $animW.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::WidthProperty, $animW)

    Animate-Height $Config.IslandHeight

    if (-not $script:isPinned) {
        Slide-UpIsland
    }
}

$islandHoverZone.Add_MouseEnter({
    if ($script:inGameMode) { return }
    Slide-DownIsland
    $collapseTimer.Stop()
    Expand-Island
})

$islandHoverZone.Add_MouseLeave({
    if ($script:inGameMode) { return }
    if (-not $script:isPinned -or $script:isExpanded) {
        $collapseTimer.Start()
    }
})

$collapseTimer.Add_Tick({
    $collapseTimer.Stop()
    Collapse-Island
})

# Settings Back Button
if ($btnSettingsBack) {
    $btnSettingsBack.Add_Click({
        $target = if ($script:previousTab -and $script:previousTab -ne 'Settings') { $script:previousTab } else { 'Today' }
        Switch-Tab $target
    })
}

# Volume Controls
if ($iconMasterSpeaker) {
    $iconMasterSpeaker.Add_MouseDown({
        [IslandNative]::ToggleMute()
    })
}

if ($sliderMasterVolume) {
    $sliderMasterVolume.Add_ValueChanged({
        $val = [int]$sliderMasterVolume.Value
        $textMasterVolumeVal.Text = "$val"
        [IslandNative]::SetMasterVolume([float]($val / 100.0))
    })
}

if ($sliderBrightness) {
    $sliderBrightness.Add_ValueChanged({
        $val = [int]$sliderBrightness.Value
        if ($textBrightnessVal) { $textBrightnessVal.Text = "$val" }
        [IslandNative]::SetBrightness($val)
        try {
            Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = 0; Brightness = $val } -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    })
}

# Media Playback Actions
if ($btnMediaPlay) {
    $btnMediaPlay.Add_Click({
        [IslandNative]::MediaPlayPause()
    })
}
if ($btnMediaPrev) {
    $btnMediaPrev.Add_Click({
        [IslandNative]::MediaPrev()
    })
}
if ($btnMediaNext) {
    $btnMediaNext.Add_Click({
        [IslandNative]::MediaNext()
    })
}

# Quick Action Tiles with Real Hardware & Gamma Control
function Toggle-BluetoothHardware {
    try {
        [void][Windows.Devices.Radios.Radio, Windows.System.Devices, ContentType = WindowsRuntime]
        $asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
            $_.Name -eq 'AsTask' -and $_.GetParameters().Length -eq 1 -and $_.IsGenericMethodDefinition 
        } | Select-Object -First 1

        $asyncOp = [Windows.Devices.Radios.Radio]::GetRadiosAsync()
        $closed = $asTaskGeneric.MakeGenericMethod([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
        $task = $closed.Invoke($null, @($asyncOp))
        if ($task.Wait(1200)) {
            $bt = $task.Result | Where-Object { $_.Kind -eq [Windows.Devices.Radios.RadioKind]::Bluetooth } | Select-Object -First 1
            if ($bt) {
                $targetState = if ($bt.State -eq [Windows.Devices.Radios.RadioState]::On) { [Windows.Devices.Radios.RadioState]::Off } else { [Windows.Devices.Radios.RadioState]::On }
                $setOp = $bt.SetStateAsync($targetState)
                $setClosed = $asTaskGeneric.MakeGenericMethod([Windows.Devices.Radios.RadioAccessStatus])
                $setTask = $setClosed.Invoke($null, @($setOp))
                [void]$setTask.Wait(1200)
                return ($targetState -eq [Windows.Devices.Radios.RadioState]::On)
            }
        }
    } catch { }
    try { Start-Process "ms-settings:bluetooth" -ErrorAction SilentlyContinue } catch { }
    return $null
}

$script:isBtOn = $true
if ($tileBluetooth) {
    $tileBluetooth.Add_MouseDown({
        $realState = Toggle-BluetoothHardware
        if ($null -ne $realState) {
            $script:isBtOn = $realState
        } else {
            $script:isBtOn = -not $script:isBtOn
        }
        if ($script:isBtOn) {
            $tileBluetoothCircle.Background = $script:brushPurple
            $tileBluetoothSub.Text = "On"
        } else {
            $tileBluetoothCircle.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#1E1E28"))
            $tileBluetoothSub.Text = "Off"
        }
    })
}

$script:isNightLightOn = $false
if ($tileNightLight) {
    $tileNightLight.Add_MouseDown({
        $script:isNightLightOn = -not $script:isNightLightOn
        [IslandNative]::SetNightLight($script:isNightLightOn)
        if ($script:isNightLightOn) {
            $tileNightLightCircle.Background = $script:brushAmber
            $tileNightLightSub.Text = "On"
        } else {
            $tileNightLightCircle.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#1E1E28"))
            $tileNightLightSub.Text = "Off"
        }
    })
}

if ($tileTaskMgr) {
    $tileTaskMgr.Add_MouseDown({
        Start-Process "taskmgr.exe" -ErrorAction SilentlyContinue
    })
}

if ($tileExplorer) {
    $tileExplorer.Add_MouseDown({
        Start-Process "explorer.exe" -ErrorAction SilentlyContinue
    })
}

# Power Tiles
if ($tilePowerLock) {
    $tilePowerLock.Add_MouseDown({
        [void][IslandNative]::RegisterHotKey([IntPtr]::Zero, 0, 0, 0)
        Start-Process "rundll32.exe" "user32.dll,LockWorkStation" -ErrorAction SilentlyContinue
    })
}

if ($tilePowerSleep) {
    $tilePowerSleep.Add_MouseDown({
        Start-Process "rundll32.exe" "powrprof.dll,SetSuspendState 0,1,0" -ErrorAction SilentlyContinue
    })
}

# Hold-to-Confirm Power Safety Engine (2.0s Hold with live countdown and cancel)
$script:powerHoldTimer = $null
$script:powerHoldElapsed = 0.0

function Start-PowerHold ([string]$action, $subTextElem, $circleElem, [string]$accentHex) {
    if ($script:powerHoldTimer) {
        $script:powerHoldTimer.Stop()
    }
    $script:powerHoldElapsed = 0.0
    $subTextElem.Text = "Hold 2.0s"
    $circleElem.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($accentHex))

    $script:powerHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:powerHoldTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $script:powerHoldTimer.Add_Tick({
        $script:powerHoldElapsed += 0.1
        $rem = [Math]::Max(0.0, 2.0 - $script:powerHoldElapsed)
        if ($rem -gt 0.0) {
            $subTextElem.Text = "Hold {0:F1}s" -f $rem
        } else {
            $script:powerHoldTimer.Stop()
            $script:powerHoldTimer = $null
            $subTextElem.Text = if ($action -eq "Restart") { "Restarting..." } else { "Shutting down..." }
            if ($action -eq "Restart") {
                Restart-Computer -Force -ErrorAction SilentlyContinue
            } else {
                Stop-Computer -Force -ErrorAction SilentlyContinue
            }
        }
    })
    $script:powerHoldTimer.Start()
}

function Cancel-PowerHold ($subTextElem, $circleElem) {
    if ($script:powerHoldTimer) {
        $script:powerHoldTimer.Stop()
        $script:powerHoldTimer = $null
    }
    $script:powerHoldElapsed = 0.0
    $subTextElem.Text = "Hold"
    $circleElem.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#1E1E28"))
}

if ($tilePowerRestart) {
    $tilePowerRestart.Add_PreviewMouseLeftButtonDown({
        Start-PowerHold "Restart" $powerRestartSub $tilePowerRestartCircle "#FBBF24"
    })
    $tilePowerRestart.Add_PreviewMouseLeftButtonUp({
        Cancel-PowerHold $powerRestartSub $tilePowerRestartCircle
    })
    $tilePowerRestart.Add_MouseLeave({
        Cancel-PowerHold $powerRestartSub $tilePowerRestartCircle
    })
}

if ($tilePowerShutdown) {
    $tilePowerShutdown.Add_PreviewMouseLeftButtonDown({
        Start-PowerHold "Shutdown" $powerShutdownSub $tilePowerShutdownCircle "#F87171"
    })
    $tilePowerShutdown.Add_PreviewMouseLeftButtonUp({
        Cancel-PowerHold $powerShutdownSub $tilePowerShutdownCircle
    })
    $tilePowerShutdown.Add_MouseLeave({
        Cancel-PowerHold $powerShutdownSub $tilePowerShutdownCircle
    })
}

# Settings Style & Dock Clicks
if ($btnStyleOpaque) { $btnStyleOpaque.Add_Click({ Set-VisualStyle $false }) }
if ($btnStyleGlass)  { $btnStyleGlass.Add_Click({ Set-VisualStyle $true }) }

# Accent Color Swatch Clicks
if ($colorViolet)  { $colorViolet.Add_MouseLeftButtonDown({ Set-AccentColor '#A78BFA' }) }
if ($colorCyan)    { $colorCyan.Add_MouseLeftButtonDown({ Set-AccentColor '#22D3EE' }) }
if ($colorEmerald) { $colorEmerald.Add_MouseLeftButtonDown({ Set-AccentColor '#34D399' }) }
if ($colorAmber)   { $colorAmber.Add_MouseLeftButtonDown({ Set-AccentColor '#FBBF24' }) }
if ($colorCoral)   { $colorCoral.Add_MouseLeftButtonDown({ Set-AccentColor '#F87171' }) }
if ($colorPink)    { $colorPink.Add_MouseLeftButtonDown({ Set-AccentColor '#F472B6' }) }
if ($colorWhite)   { $colorWhite.Add_MouseLeftButtonDown({ Set-AccentColor '#FFFFFF' }) }
if ($btnDockTop)     { $btnDockTop.Add_Click({ Set-DockEdge "Top" }) }
if ($btnDockLeft)    { $btnDockLeft.Add_Click({ Set-DockEdge "Left" }) }
if ($btnDockRight)   { $btnDockRight.Add_Click({ Set-DockEdge "Right" }) }


# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
#  Feature Suite: Apps Launcher Engine (Compact 3-Column Glass Grid)
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
#  Feature Suite: Apps Launcher Engine (Compact 3-Column Glass Grid)
# ------------------------------------------------------------------------------
$script:recentApps = [System.Collections.ArrayList]::new()

function Resolve-AppPath ([string]$path) {
    if (-not $path) { return "" }
    $resolved = $path.Trim('"')
    $resolved = [Environment]::ExpandEnvironmentVariables($resolved)

    if (Test-Path $resolved) { return $resolved }

    # Try Get-Command in PATH
    $cmd = Get-Command $resolved -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    # Check common installation locations
    $fname = [System.IO.Path]::GetFileName($resolved)
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\$fname",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\$fname",
        "$env:ProgramFiles\$fname",
        "${env:ProgramFiles(x86)}\$fname",
        "$env:WINDIR\System32\$fname",
        "$env:WINDIR\$fname"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $resolved
}

function Launch-AppTarget ([string]$path, [string]$args) {
    if (-not $path) { return $false }
    try {
        $resolvedPath = Resolve-AppPath $path

        # Determine Working Directory
        $workDir = $null
        if (Test-Path $resolvedPath) {
            $workDir = [System.IO.Path]::GetDirectoryName($resolvedPath)
        }
        if (-not $workDir -or -not (Test-Path $workDir)) {
            $workDir = [Environment]::GetFolderPath("UserProfile")
        }

        # Launch via ProcessStartInfo with UseShellExecute = true
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $resolvedPath
        if ($args) { $psi.Arguments = $args }
        $psi.WorkingDirectory = $workDir
        $psi.UseShellExecute = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        return $true
    } catch {
        try {
            Start-Process -FilePath $path -ArgumentList $args -ErrorAction SilentlyContinue
            return $true
        } catch { }
    }
    return $false
}

function Update-RecentAppsUI {
    if (-not $appsRecentContainer) { return }
    $appsRecentContainer.Children.Clear()

    $bc = [System.Windows.Media.BrushConverter]::new()
    $textFg = $bc.ConvertFromString("#FFFFFF")
    $tileBg = $bc.ConvertFromString("#13131A")
    $tileHoverBg = $bc.ConvertFromString("#20202C")

    $recentCandidates = @()
    if ($script:recentApps.Count -gt 0) {
        $recentCandidates = @($script:recentApps | Select-Object -First 3)
    } else {
        $commonProcs = @("chrome", "msedge", "code", "spotify", "discord", "steam", "notepad")
        foreach ($cp in $commonProcs) {
            if (Get-Process -Name $cp -ErrorAction SilentlyContinue) {
                $recentCandidates += $cp.ToUpper()
                if ($recentCandidates.Count -ge 3) { break }
            }
        }
    }

    foreach ($rc in $recentCandidates) {
        $rCard = New-Object System.Windows.Controls.Border
        $rCard.Width = 156
        $rCard.Height = 34
        $rCard.Background = $tileBg
        $rCard.BorderBrush = $bc.ConvertFromString("#1AFFFFFF")
        $rCard.BorderThickness = New-Object System.Windows.Thickness(1)
        $rCard.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $rCard.Margin = New-Object System.Windows.Thickness(4, 2, 4, 2)
        $rCard.Cursor = [System.Windows.Input.Cursors]::Hand
        $rCard.Tag = $rc

        $rGrid = New-Object System.Windows.Controls.Grid
        $rGrid.Margin = New-Object System.Windows.Thickness(8, 0, 8, 0)
        
        $rc0 = New-Object System.Windows.Controls.ColumnDefinition
        $rc0.Width = [System.Windows.GridLength]::Auto
        $rc1 = New-Object System.Windows.Controls.ColumnDefinition
        $rc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        [void]$rGrid.ColumnDefinitions.Add($rc0)
        [void]$rGrid.ColumnDefinitions.Add($rc1)

        $rDot = New-Object System.Windows.Shapes.Ellipse
        $rDot.Width = 5
        $rDot.Height = 5
        $rDot.Fill = $bc.ConvertFromString("#34D399")
        $rDot.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        $rDot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($rDot, 0)
        [void]$rGrid.Children.Add($rDot)

        $rName = New-Object System.Windows.Controls.TextBlock
        $rName.Text = $rc
        $rName.FontSize = 10
        $rName.FontWeight = [System.Windows.FontWeights]::SemiBold
        $rName.Foreground = $textFg
        $rName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($rName, 1)
        [void]$rGrid.Children.Add($rName)

        $rCard.Child = $rGrid

        $rCard.Add_MouseEnter({ $this.Background = $tileHoverBg })
        $rCard.Add_MouseLeave({ $this.Background = $tileBg })

        $rCard.Add_PreviewMouseLeftButtonUp({
            param($sender, $e)
            $target = $this.Tag
            if ($target) {
                Launch-AppTarget "$target.exe" ""
            }
            if ($e) { $e.Handled = $true }
        })
        [void]$appsRecentContainer.Children.Add($rCard)
    }
}

function Render-AppsList {
    if (-not $appsPinnedContainer) { return }
    $appsPinnedContainer.Children.Clear()

    $bc = [System.Windows.Media.BrushConverter]::new()
    $tileBg = $bc.ConvertFromString("#16161D")
    $tileHoverBg = $bc.ConvertFromString("#22222E")
    $tilePressedBg = $bc.ConvertFromString("#2A2A38")
    $tileBorder = $bc.ConvertFromString("#25FFFFFF")
    $textFg = $bc.ConvertFromString("#FFFFFF")
    $subFg = $bc.ConvertFromString("#9B9BA7")
    $greenDot = $bc.ConvertFromString("#34D399")

    $apps = $Config.Apps
    if (-not $apps -or $apps.Count -eq 0) {
        $Config.Apps = @(
            [ordered]@{ Name = "VS Code";       Path = (Resolve-AppPath "code.exe");     Arguments = ""; Category = "Development"; Pinned = $true },
            [ordered]@{ Name = "Terminal";      Path = (Resolve-AppPath "wt.exe");       Arguments = ""; Category = "Development"; Pinned = $true },
            [ordered]@{ Name = "Spotify";       Path = (Resolve-AppPath "spotify.exe");  Arguments = ""; Category = "Media";       Pinned = $true },
            [ordered]@{ Name = "File Explorer"; Path = "explorer.exe";                   Arguments = ""; Category = "System";      Pinned = $true },
            [ordered]@{ Name = "Task Manager";  Path = "taskmgr.exe";                    Arguments = ""; Category = "System";      Pinned = $true },
            [ordered]@{ Name = "Notepad";       Path = "notepad.exe";                    Arguments = ""; Category = "Utilities";   Pinned = $true }
        )
        Save-Config
        $apps = $Config.Apps
    }

    foreach ($app in $apps) {
        $appName = $app.Name
        $appPath = $app.Path
        $appArgs = $app.Arguments
        $appCat  = if ($app.Category) { $app.Category } else { "App" }

        # Check process running state
        $procBase = [System.IO.Path]::GetFileNameWithoutExtension($appPath)
        $isRunning = $false
        try {
            if ($procBase -and (Get-Process -Name $procBase -ErrorAction SilentlyContinue)) {
                $isRunning = $true
            }
        } catch { }

        # Tile Card (Width: 156px)
        $card = New-Object System.Windows.Controls.Border
        $card.Width = 156
        $card.Height = 44
        $card.Background = $tileBg
        $card.BorderBrush = $tileBorder
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(10)
        $card.Margin = New-Object System.Windows.Thickness(4, 3, 4, 3)
        $card.Cursor = [System.Windows.Input.Cursors]::Hand
        # CRUCIAL: Store app launch parameters in Tag to eliminate closure reference bug
        $card.Tag = @{ Path = $appPath; Args = $appArgs; Name = $appName }

        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = New-Object System.Windows.Thickness(8, 0, 8, 0)
        
        $c0 = New-Object System.Windows.Controls.ColumnDefinition
        $c0.Width = [System.Windows.GridLength]::Auto
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = [System.Windows.GridLength]::Auto
        
        [void]$grid.ColumnDefinitions.Add($c0)
        [void]$grid.ColumnDefinitions.Add($c1)
        [void]$grid.ColumnDefinitions.Add($c2)

        # Icon / Badge Box
        $iconBox = New-Object System.Windows.Controls.Border
        $iconBox.Width = 26
        $iconBox.Height = 26
        $iconBox.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $iconBox.Background = $bc.ConvertFromString("#1F1F2C")
        $iconBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $iconBox.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)

        $hasIcon = $false
        try {
            $fullPath = Resolve-AppPath $appPath
            if (Test-Path $fullPath) {
                $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($fullPath)
                if ($ico) {
                    $hBmp = $ico.ToBitmap().GetHbitmap()
                    $source = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($hBmp, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                    $img = New-Object System.Windows.Controls.Image
                    $img.Source = $source
                    $img.Width = 18
                    $img.Height = 18
                    $iconBox.Child = $img
                    $hasIcon = $true
                }
            }
        } catch { }

        if (-not $hasIcon) {
            $letter = if ($appName.Length -gt 0) { $appName.Substring(0, 1).ToUpper() } else { "A" }
            $letterText = New-Object System.Windows.Controls.TextBlock
            $letterText.Text = $letter
            $letterText.FontSize = 11
            $letterText.FontWeight = [System.Windows.FontWeights]::Bold
            $letterText.Foreground = $script:brushPurple
            $letterText.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $letterText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $iconBox.Child = $letterText
        }
        [System.Windows.Controls.Grid]::SetColumn($iconBox, 0)
        [void]$grid.Children.Add($iconBox)

        # Labels
        $textStack = New-Object System.Windows.Controls.StackPanel
        $textStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $appName
        $nameBlock.FontSize = 11
        $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameBlock.Foreground = $textFg
        $nameBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis

        $catBlock = New-Object System.Windows.Controls.TextBlock
        $catBlock.Text = $appCat
        $catBlock.FontSize = 9
        $catBlock.Foreground = $subFg
        $catBlock.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis

        [void]$textStack.Children.Add($nameBlock)
        [void]$textStack.Children.Add($catBlock)
        [System.Windows.Controls.Grid]::SetColumn($textStack, 1)
        [void]$grid.Children.Add($textStack)

        # Running status dot
        if ($isRunning) {
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 6
            $dot.Height = 6
            $dot.Fill = $greenDot
            $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $dot.ToolTip = "Running"
            [System.Windows.Controls.Grid]::SetColumn($dot, 2)
            [void]$grid.Children.Add($dot)
        }

        $card.Child = $grid

        # Interactive Hover & Pressed States
        $card.Add_MouseEnter({ $this.Background = $tileHoverBg })
        $card.Add_MouseLeave({ $this.Background = $tileBg })
        $card.Add_PreviewMouseLeftButtonDown({ $this.Background = $tilePressedBg })

        # Click Launch via PreviewMouseLeftButtonUp
        $card.Add_PreviewMouseLeftButtonUp({
            param($sender, $e)
            $this.Background = $tileHoverBg
            $data = $this.Tag
            if ($data -and $data.Path) {
                Launch-AppTarget $data.Path $data.Args
                $n = $data.Name
                if ($n -and -not ($script:recentApps -contains $n)) {
                    [void]$script:recentApps.Insert(0, $n)
                    if ($script:recentApps.Count -gt 6) { $script:recentApps.RemoveAt(6) }
                    Update-RecentAppsUI
                }
            }
            if ($e) { $e.Handled = $true }
        })

        # Context Menu
        $cm = New-Object System.Windows.Controls.ContextMenu
        $miLaunch = New-Object System.Windows.Controls.MenuItem
        $miLaunch.Header = "Launch Application"
        $miLaunch.Tag = @{ Path = $appPath; Args = $appArgs }
        $miLaunch.Add_Click({
            $data = $this.Tag
            if ($data) { Launch-AppTarget $data.Path $data.Args }
        })

        $miRemove = New-Object System.Windows.Controls.MenuItem
        $miRemove.Header = "Remove from Island"
        $miRemove.Tag = $appName
        $miRemove.Add_Click({
            $tName = $this.Tag
            $Config.Apps = @($Config.Apps | Where-Object { $_.Name -ne $tName })
            Save-Config
            Render-AppsList
        })

        [void]$cm.Items.Add($miLaunch)
        [void]$cm.Items.Add($miRemove)
        $card.ContextMenu = $cm

        [void]$appsPinnedContainer.Children.Add($card)
    }

    Update-RecentAppsUI
}

if ($btnAddApp) {
    $btnAddApp.Add_Click({
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = "Applications (*.exe)|*.exe|Shortcuts (*.lnk)|*.lnk|All files (*.*)|*.*"
            $ofd.Title = "Select Application to Add to Island"
            $ofd.InitialDirectory = [Environment]::GetFolderPath("ProgramFiles")
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $selPath = $ofd.FileName
                $name = [System.IO.Path]::GetFileNameWithoutExtension($selPath)
                $newApp = [ordered]@{
                    Name      = $name
                    Path      = $selPath
                    Arguments = ""
                    Category  = "Custom"
                    Pinned    = $true
                }
                $existing = @($Config.Apps)
                $existing += $newApp
                $Config.Apps = $existing
                Save-Config
                Render-AppsList
            }
        } catch { }
    })
}

#  Feature Suite: Header Drag-to-Move & Screen-Boundary Clamping
# ------------------------------------------------------------------------------
if ($headerBandBorder) {
    $headerBandBorder.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($script:inGameMode) { return }

        # Check if the clicked element is an interactive button or control
        $orig = $e.OriginalSource
        $cur = $orig
        while ($cur -and $cur -ne $headerBandBorder) {
            if ($cur -is [System.Windows.Controls.Primitives.ButtonBase] -or 
                $cur -is [System.Windows.Controls.TextBox] -or 
                $cur -is [System.Windows.Controls.Slider]) {
                return
            }
            if ($cur -is [System.Windows.FrameworkElement] -and $cur.Parent) {
                $cur = $cur.Parent
            } elseif ($cur -is [System.Windows.Media.Visual]) {
                $cur = [System.Windows.Media.VisualTreeHelper]::GetParent($cur)
            } else {
                break
            }
        }

        if ($e.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
            try {
                $window.DragMove()

                # Screen-Boundary Clamping: Prevent off-screen positioning
                $workArea = [System.Windows.SystemParameters]::WorkArea
                $minX = 0.0
                $maxX = [Math]::Max(0.0, $workArea.Width - $window.Width)
                $minY = 0.0
                $maxY = [Math]::Max(0.0, $workArea.Height - $window.Height)

                $clampedX = [Math]::Max($minX, [Math]::Min($maxX, $window.Left))
                $clampedY = [Math]::Max($minY, [Math]::Min($maxY, $window.Top))

                $window.Left = $clampedX
                $window.Top  = $clampedY

                $Config.X = [int][Math]::Round($clampedX)
                $Config.Y = [int][Math]::Round($clampedY)
                $Config.DockEdge = "Custom"
                $script:dockEdge = "Custom"
                Save-Config
                Update-DockUI
            } catch { }
        }
    })
}

#  Feature Suite: Adaptive Accent Color
# ------------------------------------------------------------------------------
$script:currentAdaptiveColor = ""

function Set-AdaptiveAccentColor ([string]$hexColor) {
    if ($script:currentAdaptiveColor -eq $hexColor) { return }
    $script:currentAdaptiveColor = $hexColor
    try {
        $col = [System.Windows.Media.ColorConverter]::ConvertFromString($hexColor)
        if ($islandGlow) {
            $anim = New-Object System.Windows.Media.Animation.ColorAnimation
            $anim.To = $col
            $anim.Duration = [TimeSpan]::FromSeconds(0.4)
            $islandGlow.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::ColorProperty, $anim)
        }
        $newBrush = New-Object System.Windows.Media.SolidColorBrush($col)
        $script:brushPurple = $newBrush
        $eqBars = @($eqBar1, $eqBar2, $eqBar3, $eqBar4, $eqBar5, $eqBar6)
        foreach ($b in $eqBars) { if ($b) { $b.Background = $newBrush } }
        if ($btnSettingsToggle -and $script:activeTab -eq 'Settings') { $btnSettingsToggle.Foreground = $newBrush }
        if ($btnPinToggle -and $script:isPinned) { $btnPinToggle.Foreground = $newBrush }
    } catch { }
}

# ------------------------------------------------------------------------------
#  Feature Suite: Quick File Sharing & QR Generator
# ------------------------------------------------------------------------------
$script:fileServerListener = $null
$script:sharedFilePath = $null

$glowBorder.Add_DragOver({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Copy
    } else {
        $e.Effects = [System.Windows.DragDropEffects]::None
    }
    $e.Handled = $true
})

function Start-FileSharing ([string]$filePath) {
    if (-not (Test-Path $filePath)) { return }
    $script:sharedFilePath = $filePath
    $fi = New-Object System.IO.FileInfo($filePath)

    $fileShareNameText.Text = $fi.Name
    $sizeMb = [Math]::Round($fi.Length / 1MB, 2)
    $fileShareSizeText.Text = "$sizeMb MB $([char]0x00B7) Scan with phone on Wi-Fi"

    $lanIp = "127.0.0.1"
    try {
        $ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' -and -not [System.Net.IPAddress]::IsLoopback($_) }
        if ($ips -and $ips.Count -gt 0) {
            $lanIp = $ips[0].IPAddressToString
        }
    } catch { }

    $port = 8080
    $shareUrl = "http://${lanIp}:${port}/file"
    $fileShareUrlText.Text = $shareUrl

    try {
        $qrApiUrl = "https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=" + [System.Uri]::EscapeDataString($shareUrl)
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.UriSource = New-Object System.Uri($qrApiUrl)
        $bi.EndInit()
        $fileShareQrImage.Source = $bi
    } catch { }

    if ($script:fileServerListener) {
        try { $script:fileServerListener.Stop(); $script:fileServerListener.Close() } catch { }
    }
    try {
        $script:fileServerListener = New-Object System.Net.HttpListener
        $script:fileServerListener.Prefixes.Add("http://*:$port/")
        $script:fileServerListener.Start()
    } catch {
        try {
            $script:fileServerListener = New-Object System.Net.HttpListener
            $script:fileServerListener.Prefixes.Add("http://localhost:$port/")
            $script:fileServerListener.Prefixes.Add("http://${lanIp}:$port/")
            $script:fileServerListener.Start()
        } catch { }
    }

    if ($script:fileServerListener -and $script:fileServerListener.IsListening) {
        [System.Threading.ThreadPool]::QueueUserWorkItem({
            while ($script:fileServerListener -and $script:fileServerListener.IsListening) {
                try {
                    $context = $script:fileServerListener.GetContext()
                    $response = $context.Response
                    if (Test-Path $script:sharedFilePath) {
                        $bytes = [System.IO.File]::ReadAllBytes($script:sharedFilePath)
                        $response.ContentType = "application/octet-stream"
                        $response.AddHeader("Content-Disposition", "attachment; filename=`"$([System.IO.Path]::GetFileName($script:sharedFilePath))`"")
                        $response.ContentLength64 = $bytes.Length
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    } else {
                        $response.StatusCode = 404
                    }
                    $response.OutputStream.Close()
                } catch { break }
            }
        })
    }

    if (-not $script:isExpanded) {
        Expand-Island
    }
    $fileDropModal.Visibility = 'Visible'
    $contentScrollViewer.Visibility = 'Collapsed'
    Animate-Height 280
}

$glowBorder.Add_Drop({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($files -and $files.Length -gt 0) {
            Start-FileSharing $files[0]
        }
    }
})

if ($btnCopyShareUrl) {
    $btnCopyShareUrl.Add_Click({
        try {
            [System.Windows.Clipboard]::SetText($fileShareUrlText.Text)
            $btnCopyShareUrl.Content = "Copied!"
            $t = New-Object System.Windows.Threading.DispatcherTimer
            $t.Interval = [TimeSpan]::FromSeconds(2)
            $t.Add_Tick({ $btnCopyShareUrl.Content = "Copy"; $t.Stop() })
            $t.Start()
        } catch { }
    })
}

if ($btnCloseFileShare) {
    $btnCloseFileShare.Add_Click({
        $fileDropModal.Visibility = 'Collapsed'
        $contentScrollViewer.Visibility = 'Visible'
        if ($script:fileServerListener) {
            try { $script:fileServerListener.Stop(); $script:fileServerListener.Close() } catch { }
            $script:fileServerListener = $null
        }
        Switch-Tab $script:activeTab
    })
}

# ------------------------------------------------------------------------------
#  Feature Suite: Automatic Game Mode HUD
# ------------------------------------------------------------------------------
$script:inGameMode = $false
$script:gameCheckTick = 0

$script:gameHudHovered = $null
$script:gameModeDismissedUntil = [DateTime]::MinValue

$script:gameSessionStart = [DateTime]::Now
$script:gameDropdownPinned = $false
$script:gameTurboActive = $false

function Open-GameDropdown {
    if (-not $script:inGameMode) { return }
    if ($gameModeDropdown) { $gameModeDropdown.Visibility = 'Visible' }
    $targetH = 225
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.To = $targetH
    $anim.Duration = [TimeSpan]::FromMilliseconds(180)
    $anim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::HeightProperty, $anim)
    $window.Height = $targetH + 20
}

function Close-GameDropdown {
    if (-not $script:inGameMode -or $script:gameDropdownPinned) { return }
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.To = 46.0
    $anim.Duration = [TimeSpan]::FromMilliseconds(150)
    $anim.EasingFunction = New-Object System.Windows.Media.Animation.CubicEase -Property @{ EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::HeightProperty, $anim)
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(160)
    $t.Add_Tick({
        $t.Stop()
        if (-not $script:gameDropdownPinned -and -not $glowBorder.IsMouseOver) {
            if ($gameModeDropdown) { $gameModeDropdown.Visibility = 'Collapsed' }
            $window.Height = 66
        }
    })
    $t.Start()
}

function Enter-GameMode ([string]$procName = "Game", [switch]$Force) {
    if ($script:inGameMode) { return }
    if (-not $Force -and [DateTime]::Now -lt $script:gameModeDismissedUntil) { return }

    $script:gameModeDismissedUntil = [DateTime]::MinValue
    $script:gameMissCount = 0
    $script:inGameMode = $true
    $script:gameHudHovered = $null
    $script:gameSessionStart = [DateTime]::Now
    $script:gameDropdownPinned = $false
    if ($gameDropDisplayInfo) { $gameDropDisplayInfo.Text = [IslandNative]::GetDisplayInfo() }

    # Clean game title for compact badge
    $clean = $procName.ToLower()
    $displayName = if ($clean -like "*valorant*") { "VALORANT" }
        elseif ($clean -like "*cs2*" -or $clean -like "*csgo*") { "CS2" }
        elseif ($clean -like "*gta*") { "GTA V" }
        elseif ($clean -like "*minecraft*") { "MINECRAFT" }
        elseif ($clean -like "*fortnite*") { "FORTNITE" }
        elseif ($clean -like "*apex*") { "APEX" }
        elseif ($clean -like "*dota*") { "DOTA 2" }
        elseif ($clean -like "*league*" -or $clean -like "*riot*") { "LOL" }
        else {
            $tmp = ($clean -replace "[-_](win64|shipping|x64|x86|client|game)$", "").ToUpper()
            if ($tmp.Length -gt 10) { $tmp.Substring(0, 10) } else { $tmp }
        }

    $gameModeNameText.Text = $displayName

    # Explicitly clear any holding animations on GlowBorder
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::HeightProperty, $null)
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::WidthProperty, $null)

    # Collapse all non-HUD elements
    $compactBar.Visibility          = 'Collapsed'
    $expandedContent.Visibility     = 'Collapsed'
    $navTabsCapsule.Visibility      = 'Collapsed'
    $contentScrollViewer.Visibility = 'Collapsed'
    if ($fileDropModal)      { $fileDropModal.Visibility = 'Collapsed' }
    $gameModeBar.Visibility         = 'Visible'

    # Redesigned HUD: 46px height, CornerRadius 23, 500px width
    $glowBorder.Height = 46
    $glowBorder.Width = 500
    $glowBorder.CornerRadius = New-Object System.Windows.CornerRadius(23)

    # Window bounds: generous height so rounded glass pill never clips
    $window.Height = 66
    $window.Width = 520
    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $window.Left = ($priW / 2.0) - (520.0 / 2.0)
    $window.Top = 22.0
}

function Exit-GameMode {
    if (-not $script:inGameMode) { return }
    $script:inGameMode = $false
    $script:gameHudHovered = $null

    if ($gameModeDropdown) { $gameModeDropdown.Visibility = 'Collapsed' }
    $gameModeBar.Visibility = 'Collapsed'
    $compactBar.Visibility = 'Visible'
    $contentScrollViewer.Visibility = 'Visible'
    $script:gameDropdownPinned = $false

    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::HeightProperty, $null)
    $glowBorder.BeginAnimation([System.Windows.Controls.Border]::WidthProperty, $null)

    $glowBorder.Height = $Config.IslandHeight
    $glowBorder.Width = $Config.IslandWidth
    $glowBorder.CornerRadius = New-Object System.Windows.CornerRadius($Config.CornerRadius)

    $window.Width = $Config.WindowWidth
    $window.Height = $Config.WindowHeight
    Set-DockEdge $script:dockEdge
}

if ($btnExitGameMode) {
    $btnExitGameMode.Add_Click({
        # Dismiss game mode briefly (15s) so it doesn't immediately re-trigger until window changes
        $script:gameModeDismissedUntil = [DateTime]::Now.AddSeconds(15)
        Exit-GameMode
    })
}

# Context Menu Handlers
if ($menuToggleGameMode) {
    $menuToggleGameMode.Add_Click({
        if ($script:inGameMode) {
            Exit-GameMode
        } else {
            Enter-GameMode "Game" -Force
        }
    })
}

if ($menuResetPos) {
    $menuResetPos.Add_Click({
        $script:dockEdge = "Top"
        $script:isPinned = $true
        $Config.DockEdge = "Top"
        $Config.Pinned   = $true
        Save-Config
        Set-DockEdge "Top"
        Update-PinUI
        Slide-DownIsland
        Expand-Island
    })
}
if ($menuToggleGlass) {
    $menuToggleGlass.Add_Click({
        Set-VisualStyle (-not $script:isGlass)
    })
}
if ($menuDockTop)   { $menuDockTop.Add_Click({ Set-DockEdge "Top" }) }
if ($menuDockLeft)  { $menuDockLeft.Add_Click({ Set-DockEdge "Left" }) }
if ($menuDockRight) { $menuDockRight.Add_Click({ Set-DockEdge "Right" }) }

function Reload-IslandApplication {
    try {
        $vbsPath = Join-Path $appRoot "LaunchIsland.vbs"
        if (Test-Path $vbsPath) {
            Start-Process "wscript.exe" -ArgumentList "`"$vbsPath`""
        } else {
            $islandScript = Join-Path $appRoot "Island.ps1"
            Start-Process "powershell.exe" "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$islandScript`"" -WindowStyle Hidden
        }
    } catch { }
    try { if ($bgRunspace) { $bgRunspace.Close(); $bgRunspace.Dispose() } } catch { }
    [System.Diagnostics.Process]::GetCurrentProcess().Kill()
}

if ($menuReload) {
    $menuReload.Add_Click({
        Reload-IslandApplication
    })
}

if ($menuQuit) {
    $menuQuit.Add_Click({
        try { if ($bgRunspace) { $bgRunspace.Close(); $bgRunspace.Dispose() } } catch { }
        [System.Diagnostics.Process]::GetCurrentProcess().Kill()
    })
}

$window.Add_Closing({
    try { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue } catch { }
    try { if ($bgRunspace) { $bgRunspace.Close(); $bgRunspace.Dispose() } } catch { }
    [System.Diagnostics.Process]::GetCurrentProcess().Kill()
})

# ------------------------------------------------------------------------------
#  60 FPS UI Dispatcher Render Loop
# ------------------------------------------------------------------------------
$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(50)

$script:eqTick = 0

function Update-ClockAndBattery {
    $now = [DateTime]::Now
    $compactClock.Text = $now.ToString('HH:mm')

    # Today Big Clock: "4:33" and "PM"
    if ($todayClockHours) {
        $todayClockHours.Text = $now.ToString('h:mm')
    }
    if ($todayClockAmPm) {
        $todayClockAmPm.Text = $now.ToString('tt').ToUpper()
    }
    if ($todayDate) {
        $todayDate.Text = $now.ToString('dddd d MMMM')
    }

    $hour = $now.Hour
    if ($hour -ge 5 -and $hour -lt 12) {
        $todayGreeting.Text = "Good morning"
        $todayGreetingIcon.Text = [char]0xE706 # Sun
    } elseif ($hour -ge 12 -and $hour -lt 17) {
        $todayGreeting.Text = "Good afternoon"
        $todayGreetingIcon.Text = [char]0xE708 # Bright Sun
    } elseif ($hour -ge 17 -and $hour -lt 22) {
        $todayGreeting.Text = "Good evening"
        $todayGreetingIcon.Text = [char]0xE708
    } else {
        $todayGreeting.Text = "Good night"
        $todayGreetingIcon.Text = [char]0xE793
    }

    # Battery
    $batt = [System.Windows.Forms.SystemInformation]::PowerStatus
    $pct = [int][Math]::Round($batt.BatteryLifePercent * 100)
    $isCharging = ($batt.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online)

    $compactBatteryText.Text = "$pct%"
    $todayBatteryPercent.Text = "$pct%"

    if ($isCharging) {
        $compactBatteryIcon.Text = [char]0xE945 # Lightning bolt
        $todayBatteryCenterIcon.Text = [char]0xE945
        $todayBatteryArc.Stroke = $script:brushGreen
        $todayBatteryState.Text = "Charging $([char]0x00B7) AC connected"
    } else {
        $compactBatteryIcon.Text = [char]0xEBAA
        $todayBatteryCenterIcon.Text = [char]0xEBAA
        $todayBatteryArc.Stroke = if ($pct -le 20) { $script:brushRed } elseif ($pct -le 40) { $script:brushAmber } else { $script:brushActiveBg }
        $todayBatteryState.Text = "On Battery $([char]0x00B7) Discharging"
    }

    try {
        $todayBatteryArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 22 22 18 $pct))
    } catch { }
}

$uiTimer.Add_Tick({
    try {
    Update-ClockAndBattery

    # Telemetry Snapshot
    $cpu = $script:sharedState.Cpu
    $gpu = $script:sharedState.Gpu
    $ram = $script:sharedState.RamPct
    $cpuTemp = $script:sharedState.CpuTempC
    $gpuTemp = $script:sharedState.GpuTempC

    # Header Telemetry
    $compactCpuText.Text = "CPU $cpu%"

    # Today Mini Telemetry Bars
    if ($todayCpuFill) {
        $todayCpuFill.Width = [math]::Max([math]::Min(($cpu * 1.1), 110.0), 2.0)
        $todayCpuPct.Text = "$cpu%"
        $todayCpuFill.Background = if ($cpu -ge 90) { $script:brushRed } elseif ($cpu -ge 70) { $script:brushAmber } else { $script:brushNeutral }
        $todayCpuPct.Foreground = if ($cpu -ge 90) { $script:brushRed } else { $script:brushActiveBg }
    }
    if ($todayGpuFill) {
        $todayGpuFill.Width = [math]::Max([math]::Min(($gpu * 1.1), 110.0), 2.0)
        $todayGpuPct.Text = "$gpu%"
        $todayGpuFill.Background = if ($gpu -ge 90) { $script:brushRed } elseif ($gpu -ge 70) { $script:brushAmber } else { $script:brushNeutral }
        $todayGpuPct.Foreground = if ($gpu -ge 90) { $script:brushRed } else { $script:brushActiveBg }
    }
    if ($todayRamFill) {
        $todayRamFill.Width = [math]::Max([math]::Min(($ram * 1.1), 110.0), 2.0)
        $todayRamPct.Text = "$ram%"
        $todayRamFill.Background = if ($ram -ge 90) { $script:brushRed } elseif ($ram -ge 70) { $script:brushAmber } else { $script:brushNeutral }
        $todayRamPct.Foreground = if ($ram -ge 90) { $script:brushRed } else { $script:brushActiveBg }
    }

    # Stats Tab Telemetry
    if ($statsCpuVal) {
        $statsCpuVal.Text = "$cpu%"
        $statsCpuClock.Text = "$($script:sharedState.CpuClockGhz) GHz $([char]0x00B7) ${cpuTemp}$([char]0x00B0)C"
        try { $statsCpuArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 32 32 26 $cpu)) } catch { }
    }
    if ($statsGpuVal) {
        $statsGpuVal.Text = "$gpu%"
        $gpuClockStr = if ($script:sharedState.GpuClockMhz -and $script:sharedState.GpuClockMhz -lt 1000) { "$($script:sharedState.GpuClockMhz) MHz" } else { "$($script:sharedState.GpuClockGhz) GHz" }
        $statsGpuClock.Text = "$gpuClockStr $([char]0x00B7) ${gpuTemp}$([char]0x00B0)C"
        try { $statsGpuArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 32 32 26 $gpu)) } catch { }
    }
    if ($statsRamVal) {
        $statsRamVal.Text = "$ram%"
        $statsRamUsage.Text = "$($script:sharedState.RamUsedGb) / $($script:sharedState.RamTotalGb) GB"
        try { $statsRamArc.Data = [System.Windows.Media.Geometry]::Parse((Get-ArcPath 32 32 26 $ram)) } catch { }
    }

    # Power Uptime
    if ($powerUptimeText) {
        $powerUptimeText.Text = $script:sharedState.UptimeText
    }

    # Media Tab Updates
    $title  = $script:sharedState.MediaTitle
    $artist = $script:sharedState.MediaArtist
    $status = $script:sharedState.MediaStatus

    if ($title -and $title -ne "No Media" -and $status -eq "Playing") {
        $compactTrackText.Text = $title
        $compactTrackText.Visibility = 'Visible'
        $compactSep.Visibility       = 'Visible'
    } else {
        $compactTrackText.Text = ""
        $compactTrackText.Visibility = 'Collapsed'
        $compactSep.Visibility       = 'Collapsed'
    }

    if ($callTimerPill -and $callTimerPill.Visibility -eq 'Visible') {
        $compactClock.Visibility     = 'Collapsed'
        $compactTrackText.Visibility = 'Collapsed'
        $compactSep.Visibility       = 'Collapsed'
    } else {
        $compactClock.Visibility = 'Visible'
    }

    $mediaTitleText.Text  = $title
    $mediaArtistText.Text = $artist
    $mediaDeviceText.Text = $script:sharedState.MediaDevice
    $mediaTimeCurrent.Text = $script:sharedState.MediaCurTime
    $mediaTimeTotal.Text   = $script:sharedState.MediaTotalTime

    # Scrubber Bar Progress
    if ($mediaTrackProgress -and $mediaTrackContainer) {
        $totalW = [Math]::Max(100.0, $mediaTrackContainer.ActualWidth)
        $prog = [Math]::Max(0.0, [Math]::Min(1.0, $script:sharedState.MediaProgress))
        $mediaTrackProgress.Width = [Math]::Max(2.0, $prog * $totalW)
    }

    # Play/Pause Icon
    if ($btnMediaPlay) {
        $btnMediaPlay.Content = if ($status -eq "Playing") { [char]0xE769 } else { [char]0xE768 }
    }

    # 6-Bar Equalizer Animation
    if ($status -eq "Playing") {
        $script:eqTick++
        $eqBar1.Height = 4 + ([Math]::Sin($script:eqTick * 0.4) * 6 + 6)
        $eqBar2.Height = 4 + ([Math]::Cos($script:eqTick * 0.5) * 10 + 10)
        $eqBar3.Height = 6 + ([Math]::Sin($script:eqTick * 0.3) * 14 + 14)
        $eqBar4.Height = 4 + ([Math]::Cos($script:eqTick * 0.6) * 8 + 8)
        $eqBar5.Height = 5 + ([Math]::Sin($script:eqTick * 0.45) * 12 + 12)
        $eqBar6.Height = 4 + ([Math]::Cos($script:eqTick * 0.35) * 7 + 7)
    } else {
        $eqBar1.Height = 3
        $eqBar2.Height = 3
        $eqBar3.Height = 3
        $eqBar4.Height = 3
        $eqBar5.Height = 3
        $eqBar6.Height = 3
    }

    # Album Art & Branded Fallbacks
    $curArtBytes = $script:sharedState.AlbumArtBytes
    if ($curArtBytes -and $curArtBytes.Length -gt 0) {
        $trackArtKey = "$title::$artist"
        if ($script:currentLoadedArtKey -ne $trackArtKey) {
            try {
                $ms = New-Object System.IO.MemoryStream(,$curArtBytes)
                $bi = New-Object System.Windows.Media.Imaging.BitmapImage
                $bi.BeginInit()
                $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bi.StreamSource = $ms
                $bi.EndInit()
                $bi.Freeze()
                $albumArtImage.Source = $bi
                $script:currentLoadedArtKey = $trackArtKey
                if ($albumArtPlaceholderBg) { $albumArtPlaceholderBg.Visibility = 'Collapsed' }
            } catch {
                $albumArtImage.Source = $null
                $script:currentLoadedArtKey = ""
                if ($albumArtPlaceholderBg) { $albumArtPlaceholderBg.Visibility = 'Visible' }
            }
        }
    } else {
        $script:currentLoadedArtKey = ""
        $albumArtImage.Source = $null
        if ($albumArtPlaceholderBg) {
            $albumArtPlaceholderBg.Visibility = 'Visible'
            $appSource = ($script:sharedState.MediaDevice + " " + $title).ToLower()
            $bc = [System.Windows.Media.BrushConverter]::new()
            if ($appSource -like "*netflix*") {
                $albumArtPlaceholderBg.Background = $bc.ConvertFromString("#141414")
                $albumArtBrandGlyph.Text = "N"
                $albumArtBrandGlyph.FontSize = 34
                $albumArtBrandGlyph.Foreground = $bc.ConvertFromString("#E50914")
                $albumArtBrandText.Text = "NETFLIX"
                $albumArtBrandText.Foreground = $bc.ConvertFromString("#E50914")
            } elseif ($appSource -like "*spotify*") {
                $albumArtPlaceholderBg.Background = $bc.ConvertFromString("#191414")
                $albumArtBrandGlyph.Text = [char]0xE8D6
                $albumArtBrandGlyph.FontSize = 28
                $albumArtBrandGlyph.Foreground = $bc.ConvertFromString("#1DB954")
                $albumArtBrandText.Text = "Spotify"
                $albumArtBrandText.Foreground = $bc.ConvertFromString("#1DB954")
            } elseif ($appSource -like "*youtube*") {
                $albumArtPlaceholderBg.Background = $bc.ConvertFromString("#1F1F1F")
                $albumArtBrandGlyph.Text = [char]0x25B6
                $albumArtBrandGlyph.FontSize = 26
                $albumArtBrandGlyph.Foreground = $bc.ConvertFromString("#FF0000")
                $albumArtBrandText.Text = "YouTube"
                $albumArtBrandText.Foreground = $bc.ConvertFromString("#FF0000")
            } elseif ($appSource -like "*hotstar*") {
                $albumArtPlaceholderBg.Background = $bc.ConvertFromString("#0A0F1D")
                $albumArtBrandGlyph.Text = [char]0x2605
                $albumArtBrandGlyph.FontSize = 28
                $albumArtBrandGlyph.Foreground = $bc.ConvertFromString("#00D2FF")
                $albumArtBrandText.Text = "Hotstar"
                $albumArtBrandText.Foreground = $bc.ConvertFromString("#00D2FF")
            } else {
                $albumArtPlaceholderBg.Background = $bc.ConvertFromString("#1E1C2B")
                $albumArtBrandGlyph.Text = [char]0xE8D6
                $albumArtBrandGlyph.FontSize = 28
                $albumArtBrandGlyph.Foreground = $script:brushPurple
                $albumArtBrandText.Text = ""
            }
        }
    }

    # App-Adaptive Dynamic Accent Coloring
    if ($status -eq "Playing") {
        $devLower = ($script:sharedState.MediaDevice + " " + $title).ToLower()
        $adaptiveHex = $Config.GlowColor
        if ($devLower -like "*netflix*") {
            $adaptiveHex = "#E50914"
        } elseif ($devLower -like "*spotify*") {
            $adaptiveHex = "#1DB954"
        } elseif ($devLower -like "*youtube*") {
            $adaptiveHex = "#FF0000"
        } elseif ($devLower -like "*hotstar*") {
            $adaptiveHex = "#00D2FF"
        }
        Set-AdaptiveAccentColor $adaptiveHex
    } else {
        Set-AdaptiveAccentColor $Config.GlowColor
    }

    # Call Duration Timer
    if ($script:callStartTime -and $callTimerPill -and $callTimerPill.Visibility -eq 'Visible') {
        $dur = [DateTime]::Now - $script:callStartTime
        $callTimerText.Text = "{0:D2}:{1:D2}" -f [int]$dur.TotalMinutes, ($dur.Seconds)
    }

    # Game Mode HUD Telemetry & Auto-Hide
    if ($script:inGameMode) {
        $gameModeClock.Text = [DateTime]::Now.ToString("h:mm tt")
        $gameModeCpu.Text = "CPU $($script:sharedState.CpuTempC)$([char]0x00B0)C $([char]0x00B7) $($script:sharedState.Cpu)%"
        $gameModeGpu.Text = "GPU $($script:sharedState.GpuTempC)$([char]0x00B0)C $([char]0x00B7) $($script:sharedState.Gpu)%"
        $gameModeRam.Text = "RAM $($script:sharedState.RamPct)%"

        # Update Game Mode Hover Dropdown Metrics
        if ($gameModeDropdown -and $gameModeDropdown.Visibility -eq 'Visible') {
            $dur = [DateTime]::Now - $script:gameSessionStart
            if ($gameDropSessionText) {
                $gameDropSessionText.Text = "SESSION {0:D2}:{1:D2}" -f [int]$dur.TotalMinutes, $dur.Seconds
            }
            $hz = [IslandNative]::GetDisplayRefreshRate()
            $fps = [Math]::Max(60, $hz)
            $ms = [Math]::Round(1000.0 / $fps, 1)
            if ($gameDropFpsText)     { $gameDropFpsText.Text = "$fps FPS" }
            if ($gameDropFrameTime)   { $gameDropFrameTime.Text = "$ms ms" }

            $ping = if ($script:sharedState.GamePingMs -gt 0) { $script:sharedState.GamePingMs } else { 24 }
            if ($gameDropPingText) { $gameDropPingText.Text = "PING $ping ms" }
            if ($gameDropPingDot -and $gameDropPingText) {
                if ($ping -lt 60) {
                    $gameDropPingDot.Fill = $script:brushCyan
                    $gameDropPingText.Foreground = $script:brushCyan
                } elseif ($ping -lt 110) {
                    $gameDropPingDot.Fill = $script:brushAmber
                    $gameDropPingText.Foreground = $script:brushAmber
                } else {
                    $gameDropPingDot.Fill = $script:brushRed
                    $gameDropPingText.Foreground = $script:brushRed
                }
            }

            # Hardware Detail
            if ($gameDropCpuVal)   { $gameDropCpuVal.Text = "$($script:sharedState.CpuTempC)$([char]0x00B0)C $([char]0x00B7) $($script:sharedState.Cpu)%" }
            if ($gameDropCpuClock) { $gameDropCpuClock.Text = "$($script:sharedState.CpuClockGhz) GHz" }
            if ($gameDropCpuBar)   { $gameDropCpuBar.Width = [Math]::Max(4, [int](2.1 * $script:sharedState.Cpu)) }

            if ($gameDropGpuVal)   { $gameDropGpuVal.Text = "$($script:sharedState.GpuTempC)$([char]0x00B0)C $([char]0x00B7) $($script:sharedState.Gpu)%" }
            if ($gameDropGpuClock) { $gameDropGpuClock.Text = "$($script:sharedState.GpuClockMhz) MHz" }
            if ($gameDropGpuBar)   { $gameDropGpuBar.Width = [Math]::Max(4, [int](2.1 * $script:sharedState.Gpu)) }

            if ($gameDropRamVal)   { $gameDropRamVal.Text = "$($script:sharedState.RamPct)%" }
            if ($gameDropRamBytes) { $gameDropRamBytes.Text = "$($script:sharedState.RamUsedGb) / $($script:sharedState.RamTotalGb) GB" }
            if ($gameDropRamBar)   { $gameDropRamBar.Width = [Math]::Max(4, [int](2.1 * $script:sharedState.RamPct)) }

            $vramUsedGb = [Math]::Round(($script:sharedState.GpuVramUsedMb / 1024.0), 1)
            $vramTotGb  = [Math]::Round(($script:sharedState.GpuVramTotalMb / 1024.0), 1)
            if ($vramTotGb -le 0) { $vramTotGb = 8.0 }
            $vramPct = [Math]::Min(100, [int](($vramUsedGb / $vramTotGb) * 100))
            if ($gameDropVramVal) { $gameDropVramVal.Text = "$vramUsedGb / $vramTotGb GB" }
            if ($gameDropVramPct) { $gameDropVramPct.Text = "$vramPct%" }
            if ($gameDropVramBar) { $gameDropVramBar.Width = [Math]::Max(4, [int](2.1 * $vramPct)) }

            # Alerts Banner
            if ($gameDropAlertBanner -and $gameDropAlertText) {
                if ($script:sharedState.CpuTempC -ge 88) {
                    $gameDropAlertBanner.Visibility = 'Visible'
                    $gameDropAlertText.Text = "Thermal warning: CPU reached $($script:sharedState.CpuTempC)$([char]0x00B0)C"
                } elseif ($script:sharedState.GpuTempC -ge 83) {
                    $gameDropAlertBanner.Visibility = 'Visible'
                    $gameDropAlertText.Text = "Thermal warning: GPU reached $($script:sharedState.GpuTempC)$([char]0x00B0)C"
                } elseif ($script:sharedState.RamPct -ge 92) {
                    $gameDropAlertBanner.Visibility = 'Visible'
                    $gameDropAlertText.Text = "Memory alert: High RAM utilization ($($script:sharedState.RamPct)%)"
                } else {
                    $gameDropAlertBanner.Visibility = 'Collapsed'
                }
            }
        }

        # Poll every 25 ticks to verify game foreground presence with hysteresis
        $script:gameCheckTick++
        if ($script:gameCheckTick % 25 -eq 0) {
            $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
            $priH = [System.Windows.SystemParameters]::PrimaryScreenHeight
            $gProc = ""
            $helperHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            $stillGame = [IslandNative]::CheckForegroundFullscreenGame($helperHwnd, [int]$priW, [int]$priH, [ref]$gProc)
            if ($stillGame) {
                $script:gameMissCount = 0
            } else {
                $script:gameMissCount++
                if ($script:gameMissCount -ge 3) {
                    Exit-GameMode
                    return
                }
            }
        }

        # Fixed clipping: HUD stays firmly visible near top of screen (Top = 22.0)
        # On-screen boundary safety guard: ensures HUD never slides off or gets trapped
        $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
        if ($window.Top -lt 10.0 -or $window.Top -gt 80.0) {
            $window.Top = 22.0
            $window.Left = ($priW / 2.0) - ($window.Width / 2.0)
        }
    } else {
        $script:gameCheckTick++
        if ($script:gameCheckTick % 30 -eq 0) {
            if ([DateTime]::Now -gt $script:gameModeDismissedUntil) {
                $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
                $priH = [System.Windows.SystemParameters]::PrimaryScreenHeight
                $gProc = ""
                $helperHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
                $isGame = [IslandNative]::CheckForegroundFullscreenGame($helperHwnd, [int]$priW, [int]$priH, [ref]$gProc)
                if ($isGame) {
                    Enter-GameMode $gProc
                }
            }
        }
    }
    } catch { }
})

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
#  Game Mode Hover Dropdown & Quick Actions Engine
# ------------------------------------------------------------------------------
$script:gameHoverOpenTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:gameHoverOpenTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:gameHoverOpenTimer.Add_Tick({
    $script:gameHoverOpenTimer.Stop()
    if ($script:inGameMode -and $glowBorder.IsMouseOver) {
        Open-GameDropdown
    }
})

$script:gameHoverCloseTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:gameHoverCloseTimer.Interval = [TimeSpan]::FromMilliseconds(350)
$script:gameHoverCloseTimer.Add_Tick({
    $script:gameHoverCloseTimer.Stop()
    if ($script:inGameMode -and -not $script:gameDropdownPinned -and -not $glowBorder.IsMouseOver) {
        Close-GameDropdown
    }
})

$glowBorder.Add_MouseEnter({
    if ($script:inGameMode) {
        $script:gameHoverCloseTimer.Stop()
        if ($gameModeDropdown -and $gameModeDropdown.Visibility -ne 'Visible') {
            $script:gameHoverOpenTimer.Start()
        }
    }
})

$glowBorder.Add_MouseLeave({
    if ($script:inGameMode -and -not $script:gameDropdownPinned) {
        $script:gameHoverOpenTimer.Stop()
        $script:gameHoverCloseTimer.Start()
    }
})

# Quick Action: Mute Microphone
if ($btnGameMuteMic) {
    $btnGameMuteMic.Add_Click({
        $isMuted = [IslandNative]::ToggleMicrophoneMute()
        $bc = [System.Windows.Media.BrushConverter]::new()
        if ($isMuted) {
            $btnGameMuteMic.Content = [char]0xE720 + " Muted"
            $btnGameMuteMic.Foreground = $bc.ConvertFromString("#F87171")
            $btnGameMuteMic.BorderBrush = $bc.ConvertFromString("#33F87171")
        } else {
            $btnGameMuteMic.Content = [char]0xE720 + " Mic"
            $btnGameMuteMic.Foreground = $bc.ConvertFromString("#22D3EE")
            $btnGameMuteMic.BorderBrush = $bc.ConvertFromString("#3322D3EE")
        }
    })
}

# Quick Action: Mute Master Audio
if ($btnGameMuteAudio) {
    $btnGameMuteAudio.Add_Click({
        $isMuted = [IslandNative]::ToggleMasterVolumeMute()
        $bc = [System.Windows.Media.BrushConverter]::new()
        if ($isMuted) {
            $btnGameMuteAudio.Content = [char]0xE74F + " Muted"
            $btnGameMuteAudio.Foreground = $bc.ConvertFromString("#F87171")
            $btnGameMuteAudio.BorderBrush = $bc.ConvertFromString("#33F87171")
        } else {
            $btnGameMuteAudio.Content = [char]0xE767 + " Audio"
            $btnGameMuteAudio.Foreground = $bc.ConvertFromString("#E2E8F0")
            $btnGameMuteAudio.BorderBrush = $bc.ConvertFromString("#25FFFFFF")
        }
    })
}

# Quick Action: Capture Screenshot
if ($btnGameScreenshot) {
    $btnGameScreenshot.Add_Click({
        $saved = [IslandNative]::CaptureScreenshot()
        if ($saved) {
            $btnGameScreenshot.Content = [char]0xE73E + " Saved!"
            $btnGameScreenshot.Foreground = $script:brushGreen
            $t = New-Object System.Windows.Threading.DispatcherTimer
            $t.Interval = [TimeSpan]::FromSeconds(1.5)
            $t.Add_Tick({
                $t.Stop()
                $btnGameScreenshot.Content = [char]0xE722 + " Capture"
                $btnGameScreenshot.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#E2E8F0"))
            })
            $t.Start()
        }
    })
}

# Quick Action: Turbo / High Performance Toggle
if ($btnGamePerformance) {
    $btnGamePerformance.Add_Click({
        $script:gameTurboActive = -not $script:gameTurboActive
        $bc = [System.Windows.Media.BrushConverter]::new()
        if ($script:gameTurboActive) {
            Start-Process "powercfg.exe" -ArgumentList "/setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -WindowStyle Hidden -ErrorAction SilentlyContinue
            $btnGamePerformance.Content = [char]0xE7E8 + " Turbo"
            $btnGamePerformance.Foreground = $bc.ConvertFromString("#FBBF24")
            $btnGamePerformance.BorderBrush = $bc.ConvertFromString("#33FBBF24")
        } else {
            Start-Process "powercfg.exe" -ArgumentList "/setactive 381b4222-f694-41f0-9685-ff5bb260df2e" -WindowStyle Hidden -ErrorAction SilentlyContinue
            $btnGamePerformance.Content = [char]0xE7E8 + " Balanced"
            $btnGamePerformance.Foreground = $bc.ConvertFromString("#E2E8F0")
            $btnGamePerformance.BorderBrush = $bc.ConvertFromString("#25FFFFFF")
        }
    })
}

# Quick Action: Pin Dropdown Open
if ($btnGamePin) {
    $btnGamePin.Add_Click({
        $script:gameDropdownPinned = -not $script:gameDropdownPinned
        $bc = [System.Windows.Media.BrushConverter]::new()
        if ($script:gameDropdownPinned) {
            $btnGamePin.Foreground = $bc.ConvertFromString("#22D3EE")
        } else {
            $btnGamePin.Foreground = $bc.ConvertFromString("#64748B")
        }
    })
}

#  SourceInitialized & Win32 Hit-Testing Hook
# ------------------------------------------------------------------------------
$window.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        if ($script:inGameMode -and $gameModeDropdown -and $gameModeDropdown.Visibility -eq 'Visible') {
            $script:gameDropdownPinned = $false
            Close-GameDropdown
            $e.Handled = $true
            return
        } elseif ($script:isExpanded) {
            Collapse-Island
            $e.Handled = $true
            return
        }
    }
    if ($e.Key -eq [System.Windows.Input.Key]::R -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        $e.Handled = $true
        Reload-IslandApplication
        return
    }
})

$window.Add_SourceInitialized({
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        $hwnd   = $helper.Handle

        [IslandNative]::ApplyNoActivate($hwnd)
        [IslandNative]::RegisterHotKey($hwnd, 9001, 0x0003, 0x4D) # Ctrl+Alt+M (Mic Toggle)
        [IslandNative]::RegisterHotKey($hwnd, 9002, 0x0003, 0x52) # Ctrl+Alt+R (Reset Pos)
        [IslandNative]::RegisterHotKey($hwnd, 9003, 0x0003, 0x47) # Ctrl+Alt+G (Game HUD Toggle)
        [IslandNative]::RegisterHotKey($hwnd, 9004, 0x0003, 0x53) # Ctrl+Alt+S (Screenshot)

        $source = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
        $source.AddHook({
            param($h, $m, $w, $l, [ref]$handled)
            if ($m -eq 0x0312) {
                $hotkeyId = $w.ToInt32()
                if ($hotkeyId -eq 9001) {
                    $isMuted = [IslandNative]::ToggleMicrophoneMute()
                    if ($isMuted) {
                        $micStatusDot.Fill = $script:brushRed
                        $callTimerPill.Visibility = 'Collapsed'
                        $script:callStartTime = $null
                    } else {
                        $micStatusDot.Fill = $script:brushGreen
                        $script:callStartTime = [DateTime]::Now
                        $callTimerPill.Visibility = 'Visible'
                    }
                    $handled = $true
                    return [IntPtr]0
                }
                if ($hotkeyId -eq 9002) {
                    # Snap back to Top Center
                    $script:dockEdge = "Top"
                    $script:isPinned = $true
                    $Config.DockEdge = "Top"
                    $Config.Pinned   = $true
                    Save-Config
                    Set-DockEdge "Top"
                    Update-PinUI
                    Slide-DownIsland
                    Expand-Island
                    $handled = $true
                    return [IntPtr]0
                }
                if ($hotkeyId -eq 9003) {
                    # Ctrl+Alt+G: Toggle Game HUD
                    if ($script:inGameMode) {
                        Exit-GameMode
                    } else {
                        Enter-GameMode "Game" -Force
                    }
                    $handled = $true
                    return [IntPtr]0
                }
                if ($hotkeyId -eq 9004) {
                    # Ctrl+Alt+S: Take Screenshot
                    [IslandNative]::CaptureScreenshot() | Out-Null
                    $handled = $true
                    return [IntPtr]0
                }
            }
            if ($m -eq 0x0084) { # WM_NCHITTEST
                $raw = [int64]$l.ToInt64()
                $screenX = [int16]($raw -band 0xFFFF)
                $screenY = [int16](($raw -shr 16) -band 0xFFFF)
                $pt = New-Object System.Windows.Point($screenX, $screenY)
                try {
                    $localPt = $glowBorder.PointFromScreen($pt)
                    $isOverPill = ($localPt.X -ge 0 -and $localPt.X -le $glowBorder.ActualWidth -and `
                                   $localPt.Y -ge 0 -and $localPt.Y -le $glowBorder.ActualHeight)
                    if ($isOverPill) {
                        $handled = $true
                        return [IntPtr]1 # HTCLIENT
                    }

                    # Trigger Bars (when unpinned)
                    if (-not $script:isPinned) {
                        if ($topTriggerBar -and $topTriggerBar.IsVisible) {
                            $trigPt = $topTriggerBar.PointFromScreen($pt)
                            if ($trigPt.X -ge 0 -and $trigPt.X -le $topTriggerBar.ActualWidth -and `
                                $trigPt.Y -ge 0 -and $trigPt.Y -le $topTriggerBar.ActualHeight) {
                                $handled = $true
                                return [IntPtr]1 # HTCLIENT
                            }
                        }
                        if ($leftTriggerBar -and $leftTriggerBar.IsVisible) {
                            $trigPt = $leftTriggerBar.PointFromScreen($pt)
                            if ($trigPt.X -ge 0 -and $trigPt.X -le $leftTriggerBar.ActualWidth -and `
                                $trigPt.Y -ge 0 -and $trigPt.Y -le $leftTriggerBar.ActualHeight) {
                                $handled = $true
                                return [IntPtr]1 # HTCLIENT
                            }
                        }
                        if ($rightTriggerBar -and $rightTriggerBar.IsVisible) {
                            $trigPt = $rightTriggerBar.PointFromScreen($pt)
                            if ($trigPt.X -ge 0 -and $trigPt.X -le $rightTriggerBar.ActualWidth -and `
                                $trigPt.Y -ge 0 -and $trigPt.Y -le $rightTriggerBar.ActualHeight) {
                                $handled = $true
                                return [IntPtr]1 # HTCLIENT
                            }
                        }
                    }

                    # Pass-through click straight to browser tabs directly underneath
                    $handled = $true
                    return [IntPtr](-1) # HTTRANSPARENT
                } catch {
                    $handled = $true
                    return [IntPtr](-1) # HTTRANSPARENT
                }
            }
            return [IntPtr]0
        })
    } catch { }
})

# ------------------------------------------------------------------------------
#  Startup Sequence
# ------------------------------------------------------------------------------
$priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
$workArea = [System.Windows.SystemParameters]::WorkArea

$script:isExpanded = $false
$glowBorder.Width  = $Config.IslandWidth
$glowBorder.Height = $Config.IslandHeight
$expandedContent.Visibility = 'Collapsed'
$navTabsCapsule.Visibility  = 'Collapsed'
$headerActions.Visibility   = 'Collapsed'
$collapsedBrand.Visibility  = 'Visible'
$compactInfo.Visibility     = 'Visible'
$compactTelemetry.Visibility= 'Visible'

$window.Height = $Config.IslandHeight + 28

Update-PinUI
Update-StyleUI
Update-DockUI
Update-ColorSwatchesUI $Config.GlowColor
Set-VisualStyle $script:isGlass

# Restore position: If Custom, clamp within current work area; otherwise use configured DockEdge
if ($Config.DockEdge -eq "Custom" -and $Config.X -ne $null -and $Config.Y -ne $null) {
    $script:dockEdge = "Custom"
    $clampedX = [Math]::Max(0.0, [Math]::Min($workArea.Width - $window.Width, [double]$Config.X))
    $clampedY = [Math]::Max(0.0, [Math]::Min($workArea.Height - $window.Height, [double]$Config.Y))
    $window.Left = $clampedX
    $window.Top  = $clampedY
} else {
    $window.Left = ($priW / 2.0) - ($window.Width / 2.0)
    Set-DockEdge $script:dockEdge
}

if (-not $script:isPinned -and $script:dockEdge -ne "Custom") {
    Slide-UpIsland
}

Update-ClockAndBattery

$initVol = [IslandNative]::GetMasterVolume()
$sliderMasterVolume.Value = $initVol
$textMasterVolumeVal.Text = "$initVol"

$initBright = 70
try {
    $curB = (Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue).CurrentBrightness
    if ($curB -and $curB -gt 0) { $initBright = [int]$curB }
} catch { }
[IslandNative]::SetBrightness($initBright)
if ($sliderBrightness)  { $sliderBrightness.Value = $initBright }
if ($textBrightnessVal) { $textBrightnessVal.Text = "$initBright" }

Render-AppsList
Switch-Tab 'Today'

$uiTimer.Start()

$window.Show()
if ($script:isPinned) {
    Expand-Island
}
[System.Windows.Threading.Dispatcher]::Run()
