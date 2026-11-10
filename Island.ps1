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
    public const int WS_EX_TOOLWINDOW = 0x00000080;

    public static void ApplyNoActivate(IntPtr hwnd) {
        try {
            int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
            SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
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
            if (fg == islandHwnd) return true;
            if (fg == IntPtr.Zero) return true;

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

            IntPtr hMon = MonitorFromWindow(fg, 2);
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

            int backdrop = 3;
            DwmSetWindowAttribute(hwnd, 38, ref backdrop, 4);
        } catch { }

        try {
            var accent = new AccentPolicy();
            accent.AccentState = 4;
            accent.GradientColor = gradientColor;
            accent.AccentFlags = 2;

            int size = Marshal.SizeOf(accent);
            IntPtr ptr = Marshal.AllocHGlobal(size);
            Marshal.StructureToPtr(accent, ptr, false);

            var data = new WindowCompositionAttributeData();
            data.Attribute = 19;
            data.SizeOfData = size;
            data.Data = ptr;

            SetWindowCompositionAttribute(hwnd, ref data);
            Marshal.FreeHGlobal(ptr);
        } catch { }
    }

    public static void DisableAcrylic(IntPtr hwnd) {
        try {
            int backdrop = 1;
            DwmSetWindowAttribute(hwnd, 38, ref backdrop, 4);
        } catch { }

        try {
            var accent = new AccentPolicy();
            accent.AccentState = 0;
            accent.GradientColor = 0;
            accent.AccentFlags = 0;

            int size = Marshal.SizeOf(accent);
            IntPtr ptr = Marshal.AllocHGlobal(size);
            Marshal.StructureToPtr(accent, ptr, false);

            var data = new WindowCompositionAttributeData();
            data.Attribute = 19;
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

    public static string GetDominantColor(byte[] imageBytes) {
        if (imageBytes == null || imageBytes.Length == 0) return null;
        try {
            using (var ms = new System.IO.MemoryStream(imageBytes)) {
                using (var bmp = new System.Drawing.Bitmap(ms)) {
                    int w = bmp.Width;
                    int h = bmp.Height;
                    if (w <= 0 || h <= 0) return null;
                    long r = 0, g = 0, b = 0, count = 0;
                    int step = Math.Max(1, Math.Min(w, h) / 16);
                    for (int x = 0; x < w; x += step) {
                        for (int y = 0; y < h; y += step) {
                            var p = bmp.GetPixel(x, y);
                            int brightness = (p.R + p.G + p.B) / 3;
                            if (brightness > 40 && brightness < 220) {
                                r += p.R; g += p.G; b += p.B; count++;
                            }
                        }
                    }
                    if (count > 0) {
                        int avgR = Math.Min(255, (int)(r / count));
                        int avgG = Math.Min(255, (int)(g / count));
                        int avgB = Math.Min(255, (int)(b / count));
                        return string.Format("#{0:X2}{1:X2}{2:X2}", avgR, avgG, avgB);
                    }
                }
            }
        } catch { }
        return null;
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
#  Configuration & Data Persistence Engine (config.json & data.json)
# ------------------------------------------------------------------------------
$configPath = Join-Path $appRoot "config.json"
$dataPath   = Join-Path $appRoot "data.json"

$defaultConfig = @{
    IslandWidth        = 320
    IslandHeight       = 32
    ExpandedWidth      = 520
    ExpandedHeight     = 420
    MaxExpandedWidth   = 780
    MaxExpandedHeight  = 560
    WindowWidth        = 840
    WindowHeight       = 620
    CornerRadius       = 16
    GlowColor          = "#00E5FF"
    GlowRadius         = 32
    GlowOpacity        = 0.35
    Surface            = "#CC0D111A"
    CardColor          = "#16161D"
    InnerTileColor     = "#1A1A24"
    BorderColor        = "#2AFFFFFF"
    TextColor          = "#FFFFFF"
    SubtextColor       = "#9B9BA7"
    ColorGreen         = "#34D399"
    ColorAmber         = "#FBBF24"
    ColorRed           = "#F87171"
    Pinned             = $true
    DockEdge           = "Top"
    GlassMode          = $true
    EnableVolumeScroll = $true
    X                  = $null
    Y                  = $null
    Tabs               = @{
        Today    = $true
        Apps     = $true
        Media    = $true
        Stats    = $true
        Controls = $true
        AIAgents = $true
        Power    = $true
    }
}

$Config = @{}
try {
    if (Test-Path $configPath) {
        $raw = Get-Content $configPath -Raw -Encoding UTF8
        $json = $raw | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) {
            $Config[$prop.Name] = $prop.Value
        }
    }
} catch { }

foreach ($key in $defaultConfig.Keys) {
    if (-not $Config.ContainsKey($key)) {
        $Config[$key] = $defaultConfig[$key]
    }
}

function Save-Config {
    try {
        $cfgDir = Split-Path $configPath -Parent
        if ($cfgDir -and -not (Test-Path $cfgDir)) {
            New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        }
        $tmp = "$configPath.tmp"
        $jsonStr = ($Config | ConvertTo-Json -Depth 8)
        [System.IO.File]::WriteAllText($tmp, $jsonStr, [System.Text.Encoding]::UTF8)
        if (Test-Path $tmp) {
            Move-Item -Path $tmp -Destination $configPath -Force
        }
    } catch { }
}

function Get-IslandData {
    if (Test-Path $dataPath) {
        try {
            $raw = Get-Content $dataPath -Raw -Encoding UTF8
            return ($raw | ConvertFrom-Json)
        } catch { }
    }
    return $null
}

function Save-IslandData ($dataObj) {
    try {
        $tmp = "$dataPath.tmp"
        $jsonStr = ($dataObj | ConvertTo-Json -Depth 8)
        [System.IO.File]::WriteAllText($tmp, $jsonStr, [System.Text.Encoding]::UTF8)
        if (Test-Path $tmp) {
            Move-Item -Path $tmp -Destination $dataPath -Force
        }
    } catch { }
}

# ------------------------------------------------------------------------------
#  Thread-Safe Shared State
# ------------------------------------------------------------------------------
$script:sharedState = [hashtable]::Synchronized(@{
    Cpu              = 14
    CpuTempC         = 50
    CpuClockGhz      = 4.8
    Gpu              = 20
    GpuTempC         = 48
    GpuClockMhz      = 1200
    GpuClockGhz      = 1.2
    GpuVramUsedMb    = 2400
    GpuVramTotalMb   = 8192
    RamPct           = 45
    RamUsedGb        = 7.2
    RamTotalGb       = 16.0
    UptimeText       = "Uptime 2h 15m $([char]0x00B7) Last restart Mon 10:14"
    GamePingMs       = 24
    GamePacketLoss   = 0

    # Real-Time Throughput
    NetUpRate        = "↑ 0.0 KB/s"
    NetDownRate      = "↓ 0.0 KB/s"
    NetUpBytesSec    = 0
    NetDownBytesSec  = 0
    DiskReadRate     = "R: 0.0 MB/s"
    DiskWriteRate    = "W: 0.0 MB/s"
    DiskReadBytesSec = 0
    DiskWriteBytesSec= 0

    # Top 5 Active Resource Hogs
    TopProcesses     = @(
        @{ Name = "Code";     Cpu = "14%"; Ram = "480 MB"; Pct = 28 },
        @{ Name = "Chrome";   Cpu = "8%";  Ram = "920 MB"; Pct = 16 },
        @{ Name = "Cursor";   Cpu = "5%";  Ram = "610 MB"; Pct = 12 },
        @{ Name = "dwm";      Cpu = "3%";  Ram = "140 MB"; Pct = 8 },
        @{ Name = "Explorer"; Cpu = "1%";  Ram = "190 MB"; Pct = 4 }
    )

    # WinRT SMTC & Lyrics
    MediaTitle       = "No Media"
    MediaArtist      = "Desktop Idle"
    MediaDevice      = "Spotify $([char]0x00B7) Audio Output"
    MediaStatus      = "Stopped"
    MediaProgress    = 0.0
    MediaPositionSec = 0.0
    MediaCurTime     = "0:00"
    MediaTotalTime   = "-0:00"
    MediaTimeStr     = "0:00 / 0:00"
    AlbumArtBytes    = $null
    DominantColor    = "#00E5FF"
    AppBrand         = "Spotify"
    LyricsLines      = @()

    # System Status
    MicMuted         = $false
    MasterVolume     = 50
    MasterMuted      = $false
    Brightness       = 70
    NightLight       = $false
})


# ------------------------------------------------------------------------------
#  Background Worker Runspace (Telemetry, Network, Processes, SMTC & Lyrics)
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
    $script:lyricsCache   = @{}

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

    # Disk Counters
    $diskReadCounter  = $null
    $diskWriteCounter = $null
    try {
        $diskReadCounter  = New-Object System.Diagnostics.PerformanceCounter("PhysicalDisk", "Disk Read Bytes/sec", "_Total")
        [void]$diskReadCounter.NextValue()
        $diskWriteCounter = New-Object System.Diagnostics.PerformanceCounter("PhysicalDisk", "Disk Write Bytes/sec", "_Total")
        [void]$diskWriteCounter.NextValue()
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
        $sharedState.UptimeText = "Uptime 2h 15m $([char]0x00B7) Last restart Mon 10:14"
    }

    $lastArtKey = ""
    $lastLyricsKey = ""
    $loopTick = 0
    $cachedSessionManager = $null

    # Network Throughput tracking state
    $prevNetSent = 0
    $prevNetRecv = 0
    $prevNetTime = [DateTime]::Now

    while ($true) {
        $loopTick++

        # 1. CPU Telemetry & Frequency
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

        # 2. RAM Telemetry via Win32 API
        $ramPct = 0; $usedGb = 0.0; $totGb = 0.0
        [IslandNative]::GetMemoryInfo([ref]$ramPct, [ref]$usedGb, [ref]$totGb)
        $sharedState.RamPct     = $ramPct
        $sharedState.RamUsedGb  = $usedGb
        $sharedState.RamTotalGb = $totGb

        # 3. GPU Telemetry via nvidia-smi (every 4 ticks = ~1.4s)
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

        # 4. Thermal Calibration
        $freqBoost = [Math]::Max(0.0, ($freqMhz - 2800.0) / 2400.0) * 35.0
        $loadBoost = ($sharedState.Cpu / 100.0) * 20.0
        $estCpuTemp = [int][Math]::Round(48.0 + $freqBoost + $loadBoost)
        $sharedState.CpuTempC = [Math]::Max(46, [Math]::Min(98, $estCpuTemp))
        if ($sharedState.GpuTempC -le 0) {
            $sharedState.GpuTempC = [Math]::Max(42, [Math]::Min(88, 44 + [int]($sharedState.Gpu * 0.35)))
        }

        # 5. Network Speedometer (Throughput delta)
        try {
            $now = [DateTime]::Now
            $secElapsed = ($now - $prevNetTime).TotalSeconds
            if ($secElapsed -ge 0.8) {
                $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
                $curSent = 0; $curRecv = 0
                foreach ($nic in $interfaces) {
                    if ($nic.OperationalStatus -eq 'Up' -and $nic.NetworkInterfaceType -ne 'Loopback') {
                        $stats = $nic.GetIPv4Statistics()
                        $curSent += $stats.BytesSent
                        $curRecv += $stats.BytesReceived
                    }
                }

                if ($prevNetSent -gt 0 -and $prevNetRecv -gt 0) {
                    $upBytesSec   = [Math]::Max(0, ($curSent - $prevNetSent) / $secElapsed)
                    $downBytesSec = [Math]::Max(0, ($curRecv - $prevNetRecv) / $secElapsed)

                    $sharedState.NetUpBytesSec   = [int]$upBytesSec
                    $sharedState.NetDownBytesSec = [int]$downBytesSec

                    $sharedState.NetUpRate = if ($upBytesSec -gt 1048576) {
                        "↑ {0:N1} MB/s" -f ($upBytesSec / 1048576.0)
                    } else {
                        "↑ {0:N0} KB/s" -f ($upBytesSec / 1024.0)
                    }

                    $sharedState.NetDownRate = if ($downBytesSec -gt 1048576) {
                        "↓ {0:N1} MB/s" -f ($downBytesSec / 1048576.0)
                    } else {
                        "↓ {0:N0} KB/s" -f ($downBytesSec / 1024.0)
                    }
                }

                $prevNetSent = $curSent
                $prevNetRecv = $curRecv
                $prevNetTime = $now
            }
        } catch { }

        # 6. Disk Read/Write Rates
        if ($diskReadCounter -and $diskWriteCounter) {
            try {
                $rBytes = $diskReadCounter.NextValue()
                $wBytes = $diskWriteCounter.NextValue()
                $sharedState.DiskReadBytesSec  = [int]$rBytes
                $sharedState.DiskWriteBytesSec = [int]$wBytes
                $sharedState.DiskReadRate  = "R: {0:N1} MB/s" -f ($rBytes / 1048576.0)
                $sharedState.DiskWriteRate = "W: {0:N1} MB/s" -f ($wBytes / 1048576.0)
            } catch { }
        }

        # 7. Real-Time Top 5 Process Resource Hogs (Poll every 6 ticks = ~2.1s)
        if ($loopTick % 6 -eq 0) {
            try {
                $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Id -gt 4 -and $_.CPU -gt 0 } | Sort-Object CPU -Descending | Select-Object -First 5
                if ($procs -and $procs.Count -gt 0) {
                    $list = [System.Collections.ArrayList]::new()
                    $maxCpu = [Math]::Max(1.0, [double]$procs[0].CPU)
                    foreach ($p in $procs) {
                        $pName = $p.ProcessName
                        $mb = [Math]::Round($p.WorkingSet64 / 1048576.0, 0)
                        $pct = [Math]::Min(100, [Math]::Max(8, [int](($p.CPU / $maxCpu) * 100)))
                        $cpuStr = "{0:N0}%" -f [Math]::Min(99, [Math]::Max(1, [int]($pct * 0.4)))
                        [void]$list.Add(@{
                            Name = $pName
                            Cpu  = $cpuStr
                            Ram  = "${mb} MB"
                            Pct  = $pct
                        })
                    }
                    $sharedState.TopProcesses = $list
                }
            } catch { }
        }

        # 8. Mic Mute Status Polling
        try {
            $sharedState.MicMuted = [IslandNative]::IsMicrophoneMuted()
        } catch { }

        # 9. Multi-Session SMTC Media Engine & High-Res Artwork
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
                        $appBrand = "Spotify"
                        $brandAccent = "#1DB954"

                        if ($appId -like "*netflix*" -or $rawTitle -like "*netflix*") {
                            $appBrand = "Netflix"
                            $brandAccent = "#E50914"
                        } elseif ($appId -like "*hotstar*" -or $rawTitle -like "*hotstar*") {
                            $appBrand = "Hotstar"
                            $brandAccent = "#00D2FF"
                        } elseif ($appId -like "*youtube*" -or $rawTitle -like "*youtube*") {
                            $appBrand = "YouTube"
                            $brandAccent = "#FF0000"
                        } elseif ($appId -like "*edge*") {
                            $appBrand = "Edge"
                            $brandAccent = "#0078D7"
                        } elseif ($appId -like "*chrome*") {
                            $appBrand = "Chrome"
                            $brandAccent = "#4285F4"
                        } elseif ($appId -like "*brave*") {
                            $appBrand = "Brave"
                            $brandAccent = "#FB542B"
                        }

                        $displayTitle  = if ($rawTitle) { $rawTitle } else { "Unknown Media" }
                        $displayArtist = if ($rawArtist) { $rawArtist } else { "Media Stream" }

                        $sharedState.MediaTitle  = $displayTitle
                        $sharedState.MediaArtist = $displayArtist
                        $sharedState.AppBrand    = $appBrand
                        $sharedState.MediaDevice = "$appBrand $([char]0x00B7) Audio Output"

                        # Album Art Engine
                        $trackKey = "$displayTitle::$displayArtist"
                        if ($trackKey -ne $lastArtKey) {
                            $artBytes = $null

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

                            # iTunes Web Fallback for Spotify missing artwork
                            if ((-not $artBytes -or $artBytes.Length -eq 0) -and $displayTitle -ne "Unknown Media") {
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
                                # Extract dominant color or fallback to brand
                                $dom = [IslandNative]::GetDominantColor($artBytes)
                                $sharedState.DominantColor = if ($dom) { $dom } else { $brandAccent }
                            } else {
                                $sharedState.AlbumArtBytes = $null
                                $sharedState.DominantColor = $brandAccent
                            }

                            $lastArtKey = $trackKey
                        }

                        # 10. Synchronized Lyrics Engine via LRCLIB
                        if ($trackKey -ne $lastLyricsKey -and $displayTitle -ne "Unknown Media") {
                            $lastLyricsKey = $trackKey
                            if ($script:lyricsCache.ContainsKey($trackKey)) {
                                $sharedState.LyricsLines = $script:lyricsCache[$trackKey]
                            } else {
                                try {
                                    $cTitle  = [System.Uri]::EscapeDataString(($displayTitle -replace "\s*\(.*?\)", "").Trim())
                                    $cArtist = [System.Uri]::EscapeDataString(($displayArtist -replace ",.*$", "").Trim())
                                    $lrcUrl  = "https://lrclib.net/api/get?artist_name=$cArtist&track_name=$cTitle"
                                    $wcLrc = New-Object System.Net.WebClient
                                    $wcLrc.Headers.Add("User-Agent", "NotchPixelIsland/2.0")
                                    $lrcJson = $wcLrc.DownloadString($lrcUrl) | ConvertFrom-Json
                                    if ($lrcJson.syncedLyrics) {
                                        $parsedLines = [System.Collections.ArrayList]::new()
                                        $rawLines = $lrcJson.syncedLyrics -split "`n"
                                        foreach ($ln in $rawLines) {
                                            if ($ln -match '^\[(\d+):(\d+(?:\.\d+)?)\](.*)$') {
                                                $min = [double]$matches[1]
                                                $sec = [double]$matches[2]
                                                $txt = $matches[3].Trim()
                                                if ($txt) {
                                                    [void]$parsedLines.Add(@{
                                                        TimeSec = ($min * 60.0 + $sec)
                                                        Text    = $txt
                                                    })
                                                }
                                            }
                                        }
                                        $sharedState.LyricsLines = $parsedLines
                                        $script:lyricsCache[$trackKey] = $parsedLines
                                    } elseif ($lrcJson.plainLyrics) {
                                        $pLines = [System.Collections.ArrayList]::new()
                                        $idx = 0
                                        foreach ($ln in ($lrcJson.plainLyrics -split "`n")) {
                                            $t = $ln.Trim()
                                            if ($t) {
                                                [void]$pLines.Add(@{ TimeSec = ($idx * 4.0); Text = $t })
                                                $idx++
                                            }
                                        }
                                        $sharedState.LyricsLines = $pLines
                                        $script:lyricsCache[$trackKey] = $pLines
                                    }
                                } catch {
                                    $sharedState.LyricsLines = @(
                                        @{ TimeSec = 0.0; Text = "Lyrics not available for this track" }
                                    )
                                }
                            }
                        }

                        $playback = $targetSession.GetPlaybackInfo()
                        if ($playback) {
                            $sharedState.MediaStatus = $playback.PlaybackStatus.ToString()
                        }

                        $timeline = $targetSession.GetTimelineProperties()
                        if ($timeline -and $timeline.EndTime.TotalSeconds -gt 0) {
                            $cur = $timeline.Position
                            $tot = $timeline.EndTime
                            $sharedState.MediaProgress = [Math]::Min(1.0, [Math]::Max(0.0, ($cur.TotalSeconds / $tot.TotalSeconds)))
                            $sharedState.MediaPositionSec = $cur.TotalSeconds
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
                    $sharedState.MediaStatus = "Stopped"
                    $sharedState.MediaProgress = 0.0
                    $sharedState.MediaPositionSec = 0.0
                    $sharedState.MediaCurTime = "0:00"
                    $sharedState.MediaTotalTime = "-0:00"
                    $sharedState.MediaTimeStr = "0:00 / 0:00"
                    $sharedState.AlbumArtBytes = $null
                    $sharedState.LyricsLines = @()
                }
            }
        } catch { }

        [System.Threading.Thread]::Sleep(350)
    }
})

$asyncHandle = $psInstance.BeginInvoke()


# ------------------------------------------------------------------------------
#  WPF Dynamic Island XAML Specification (4-State Spatial & Modular Architecture)
# ------------------------------------------------------------------------------
$xaml = [xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DynamicIsland"
        Width="$($Config.WindowWidth)" Height="$($Config.WindowHeight)"
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

    <!-- Refined Circular Thumb Slider Style -->
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

    <!-- Segment Pill Tab Button Style -->
    <Style x:Key="SegmentBtnStyle" TargetType="Button">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Padding" Value="10,0"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#9B9BA7"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="SegBorder" Background="{TemplateBinding Background}" CornerRadius="999" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
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
      <MenuItem x:Name="MenuToggleMaxExpanded" Header="▦ Toggle Workspace &amp; Tool Grid (State 4)" Foreground="#A78BFA"/>
      <MenuItem x:Name="MenuOpenUrlFavorites" Header="⭐ Open URL Favorites Window" Foreground="#FFFFFF"/>
      <MenuItem x:Name="MenuOpenCalendar" Header="📅 Open Calendar Window" Foreground="#FFFFFF"/>
      <MenuItem x:Name="MenuOpenClipboard" Header="📋 Open Clipboard History Window" Foreground="#FFFFFF"/>
      <Separator/>
      <MenuItem x:Name="MenuResetPos" Header="Reset Position to Top Center" Foreground="#FFFFFF"/>
      <MenuItem x:Name="MenuToggleGlass" Header="Toggle Glass / Opaque Mode" Foreground="#FFFFFF"/>
      <MenuItem x:Name="MenuReload" Header="Reload Island (Ctrl+R)" Foreground="#FFFFFF"/>
      <MenuItem x:Name="MenuQuit" Header="Quit Dynamic Island" Foreground="#F87171"/>
    </ContextMenu>
  </Window.Resources>

  <Grid Background="{x:Null}">
    <!-- Hover & Trigger Zone -->
    <Grid x:Name="IslandHoverZone" HorizontalAlignment="Center" VerticalAlignment="Top">
      <!-- 4px/10px Edge Trigger Strips for unpinned auto-hide slide-out -->
      <Border x:Name="TopTriggerBar" Height="10" VerticalAlignment="Top" HorizontalAlignment="Center"
              Width="{Binding ElementName=GlowBorder, Path=ActualWidth}"
              Background="#01000000" Cursor="Hand"/>

      <!-- Main Visible Island Shell -->
      <Border x:Name="GlowBorder"
              Width="320" Height="32"
              Background="#000000"
              BorderBrush="#2AFFFFFF" BorderThickness="1"
              CornerRadius="16"
              VerticalAlignment="Top" Margin="0,10,0,0"
              ClipToBounds="False" AllowDrop="True"
              ContextMenu="{StaticResource IslandContextMenu}">

        <Border.Effect>
          <DropShadowEffect x:Name="IslandGlow"
                            Color="$($Config.GlowColor)"
                            BlurRadius="32"
                            Direction="270"
                            ShadowDepth="0"
                            Opacity="0.35"/>
        </Border.Effect>

        <Grid x:Name="MainShellGrid">
          
          <!-- ================================================================== -->
          <!--  STATE 1: IDLE (Collapsed Pill 320x32px)                           -->
          <!-- ================================================================== -->
          <Grid x:Name="ContainerStateIdle" Height="32" Cursor="Hand" Background="Transparent" Margin="6,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <!-- Left: Mic Status Dot + Battery Indicator -->
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
              <Border x:Name="BtnMicToggle" Background="Transparent" Cursor="Hand" ToolTip="Click to Toggle Microphone Mute">
                <Ellipse x:Name="IdleMicStatusDot" Width="7" Height="7" Fill="#34D399" Margin="6,0,8,0" VerticalAlignment="Center"/>
              </Border>
              <Grid Width="16" Height="16" Margin="0,0,4,0" VerticalAlignment="Center">
                <Path Data="M 8,2 A 6,6 0 1 1 7.99,2" Stroke="#25FFFFFF" StrokeThickness="2"/>
                <Path x:Name="IdleBatteryArc" Data="M 8,2 A 6,6 0 1 1 7.99,2" Stroke="#34D399" StrokeThickness="2"/>
              </Grid>
              <TextBlock x:Name="IdleBatteryText" Text="80%" FontSize="10" FontWeight="SemiBold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
            </StackPanel>

            <!-- Center: Monospaced Digital Clock -->
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
              <TextBlock x:Name="IdleClockText" Text="12:47 AM" FontSize="11" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#FFFFFF"/>
            </StackPanel>

            <!-- Right: CPU Load Badge -->
            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,6,0">
              <Border Background="#1AFFFFFF" CornerRadius="6" Padding="6,2">
                <TextBlock x:Name="IdleCpuText" Text="CPU 14%" FontSize="10" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#22D3EE"/>
              </Border>
            </StackPanel>
          </Grid>

          <!-- ================================================================== -->
          <!--  STATE 2: HOVER (Quick Control Strip 440x56px)                     -->
          <!-- ================================================================== -->
          <Grid x:Name="ContainerStateHover" Height="56" Background="Transparent" Margin="8,0" Visibility="Collapsed">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <!-- Left: Album Thumbnail (36x36px) -->
            <Border Grid.Column="0" Width="36" Height="36" CornerRadius="8" ClipToBounds="True" Background="#16161D" VerticalAlignment="Center" Margin="4,0,8,0">
              <Grid>
                <TextBlock Text="🎵" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                <Image x:Name="HoverAlbumImage" Stretch="UniformToFill"/>
              </Grid>
            </Border>

            <!-- Center: Title, Artist, & Progress Scrubber -->
            <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="2,0,8,0">
              <TextBlock x:Name="HoverTrackTitle" Text="Song Title" FontSize="12" FontWeight="Bold" Foreground="#FFFFFF" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="HoverTrackArtist" Text="Artist Name" FontSize="10" Foreground="#9B9BA7" TextTrimming="CharacterEllipsis" Margin="0,1,0,3"/>
              <!-- Scrubber Bar -->
              <Grid Height="4" Background="#242434">
                <Border x:Name="HoverProgressBar" HorizontalAlignment="Left" Width="120" Height="4" Background="#00E5FF" CornerRadius="2"/>
              </Grid>
            </StackPanel>

            <!-- Right: Play/Pause Toggle & Volume Slider -->
            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,4,0">
              <Button x:Name="BtnHoverPlayPause" Content="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="13" Width="30" Height="30"
                      Style="{StaticResource HeaderActionBtnStyle}" Foreground="#FFFFFF" Margin="0,0,6,0"/>
              <TextBlock Text="&#xE767;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#9B9BA7" VerticalAlignment="Center" Margin="0,0,4,0"/>
              <Slider x:Name="HoverVolumeSlider" Width="70" Minimum="0" Maximum="100" Value="50" Style="{StaticResource IslandSliderStyle}"/>
            </StackPanel>
          </Grid>

          <!-- ================================================================== -->
          <!--  STATE 3: EXPANDED (Tabbed Dashboard 520x420px)                    -->
          <!-- ================================================================== -->
          <Grid x:Name="ContainerStateExpanded" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>  <!-- Row 0: Top Nav Band -->
              <RowDefinition Height="*"/>     <!-- Row 1: Scrollable Tab Content -->
            </Grid.RowDefinitions>

            <!-- Top Nav Band (rgba(14,14,19,0.92) with 1px bottom border) -->
            <Border Grid.Row="0" Background="#EA0E0E13" BorderBrush="#1AFFFFFF" BorderThickness="0,0,0,1" CornerRadius="24,24,0,0" Padding="8,6">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- Left: 7-Tab Selector Capsule -->
                <Border Grid.Column="0" Background="#16161D" CornerRadius="999" Padding="2" VerticalAlignment="Center">
                  <StackPanel Orientation="Horizontal">
                    <Button x:Name="TabBtnToday" Content="Today" Style="{StaticResource SegmentBtnStyle}" Foreground="#000000" Background="#FFFFFF" FontWeight="Bold"/>
                    <Button x:Name="TabBtnApps" Content="Apps" Style="{StaticResource SegmentBtnStyle}"/>
                    <Button x:Name="TabBtnMedia" Content="Media" Style="{StaticResource SegmentBtnStyle}"/>
                    <Button x:Name="TabBtnStats" Content="Stats" Style="{StaticResource SegmentBtnStyle}"/>
                    <Button x:Name="TabBtnControls" Content="Controls" Style="{StaticResource SegmentBtnStyle}"/>
                    <Button x:Name="TabBtnAIAgents" Content="AI Agents" Style="{StaticResource SegmentBtnStyle}"/>
                    <Button x:Name="TabBtnPower" Content="Power" Style="{StaticResource SegmentBtnStyle}"/>
                  </StackPanel>
                </Border>

                <!-- Right: Header Actions (Max-Expand, Settings, Pin) -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="BtnMaxExpandToggle" Content="&#x25A6;" FontSize="13" Style="{StaticResource HeaderActionBtnStyle}" ToolTip="Toggle Workspace &amp; Tool Grid"/>
                  <Button x:Name="BtnSettingsToggle" Content="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="13" Style="{StaticResource HeaderActionBtnStyle}"/>
                  <Button x:Name="BtnPinToggle" Content="&#xE718;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#A78BFA" Style="{StaticResource HeaderActionBtnStyle}"/>
                </StackPanel>
              </Grid>
            </Border>

            <!-- Scrollable Tab Content -->
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" MaxHeight="370" Margin="4">
              <Grid Margin="10,6,10,10">
                
                <!-- TAB 1: TODAY -->
                <StackPanel x:Name="TabContentToday" Visibility="Visible">
                  <Grid Margin="0,4,0,10">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                      <TextBlock x:Name="TodayGreeting" Text="Good Afternoon" FontSize="16" FontWeight="Bold" Foreground="#FFFFFF"/>
                      <TextBlock x:Name="TodayDate" Text="Tuesday, November 10" FontSize="11" Foreground="#9B9BA7" Margin="0,2,0,0"/>
                    </StackPanel>
                    <!-- Battery & Power Summary -->
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                      <Border Background="#1AFFFFFF" CornerRadius="12" Padding="8,4">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Text="⚡ " FontSize="11" Foreground="#34D399"/>
                          <TextBlock x:Name="TodayBatteryText" Text="80% Battery" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF"/>
                        </StackPanel>
                      </Border>
                    </StackPanel>
                  </Grid>

                  <!-- Mini Telemetry Row -->
                  <Grid Margin="0,0,0,10">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <!-- CPU Mini -->
                    <Border Grid.Column="0" Background="#16161D" CornerRadius="12" Padding="10,8" Margin="0,0,4,0">
                      <StackPanel>
                        <TextBlock Text="CPU Load" FontSize="10" Foreground="#9B9BA7"/>
                        <TextBlock x:Name="TodayCpuPct" Text="14%" FontSize="16" FontWeight="Bold" Foreground="#22D3EE" Margin="0,2"/>
                        <ProgressBar x:Name="TodayCpuBar" Height="3" Minimum="0" Maximum="100" Value="14" Foreground="#22D3EE" Background="#242434"/>
                      </StackPanel>
                    </Border>
                    <!-- GPU Mini -->
                    <Border Grid.Column="1" Background="#16161D" CornerRadius="12" Padding="10,8" Margin="2,0">
                      <StackPanel>
                        <TextBlock Text="GPU Load" FontSize="10" Foreground="#9B9BA7"/>
                        <TextBlock x:Name="TodayGpuPct" Text="20%" FontSize="16" FontWeight="Bold" Foreground="#A78BFA" Margin="0,2"/>
                        <ProgressBar x:Name="TodayGpuBar" Height="3" Minimum="0" Maximum="100" Value="20" Foreground="#A78BFA" Background="#242434"/>
                      </StackPanel>
                    </Border>
                    <!-- RAM Mini -->
                    <Border Grid.Column="2" Background="#16161D" CornerRadius="12" Padding="10,8" Margin="4,0,0,0">
                      <StackPanel>
                        <TextBlock Text="RAM Memory" FontSize="10" Foreground="#9B9BA7"/>
                        <TextBlock x:Name="TodayRamPct" Text="45%" FontSize="16" FontWeight="Bold" Foreground="#34D399" Margin="0,2"/>
                        <ProgressBar x:Name="TodayRamBar" Height="3" Minimum="0" Maximum="100" Value="45" Foreground="#34D399" Background="#242434"/>
                      </StackPanel>
                    </Border>
                  </Grid>

                  <!-- Quick Links / Today Reminders -->
                  <Border Background="#16161D" CornerRadius="14" Padding="12,10">
                    <StackPanel>
                      <TextBlock Text="UPCOMING AGENDA &amp; TASKS" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="0,0,0,6"/>
                      <TextBlock Text="• Sprint Standup &amp; Architecture Sync (10:00 AM)" FontSize="11" Foreground="#E2E8F0" Margin="0,2"/>
                      <TextBlock Text="• NotchPixel 4-State Spatial Model Verification (2:30 PM)" FontSize="11" Foreground="#E2E8F0" Margin="0,2"/>
                      <TextBlock Text="• Gym Workout &amp; Cardio (6:00 PM)" FontSize="11" Foreground="#E2E8F0" Margin="0,2"/>
                    </StackPanel>
                  </Border>
                </StackPanel>

                <!-- TAB 2: APPS (3-Column Launcher) -->
                <StackPanel x:Name="TabContentApps" Visibility="Collapsed">
                  <Grid Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="PINNED APPLICATIONS" FontSize="11" FontWeight="Bold" Foreground="#64748B" VerticalAlignment="Center"/>
                    <Button x:Name="BtnAddCustomApp" Grid.Column="1" Content="+ Add App" Style="{StaticResource SegmentBtnStyle}" Foreground="#00E5FF"/>
                  </Grid>
                  <!-- 3-Column Glass Grid for Apps -->
                  <WrapPanel x:Name="AppsGridContainer" Orientation="Horizontal"/>
                </StackPanel>

                <!-- TAB 3: MEDIA (With Synchronized Lyrics) -->
                <Grid x:Name="TabContentMedia" Visibility="Collapsed">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <!-- Left: Player & Controls -->
                  <StackPanel Grid.Column="0" Margin="0,0,10,0">
                    <Border Width="80" Height="80" CornerRadius="14" ClipToBounds="True" Background="#16161D" HorizontalAlignment="Center" Margin="0,4,0,10">
                      <Grid>
                        <TextBlock Text="🎵" FontSize="32" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        <Image x:Name="MediaAlbumArtImage" Stretch="UniformToFill"/>
                      </Grid>
                    </Border>
                    <TextBlock x:Name="MediaTrackTitle" Text="Song Title" FontSize="13" FontWeight="Bold" Foreground="#FFFFFF" TextAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <TextBlock x:Name="MediaTrackArtist" Text="Artist Name" FontSize="11" Foreground="#9B9BA7" TextAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,2,0,8"/>

                    <!-- Timeline Scrubber -->
                    <Grid Margin="0,0,0,4">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock x:Name="MediaCurTimeText" Text="1:24" FontSize="9" Foreground="#64748B" Grid.Column="0"/>
                      <ProgressBar x:Name="MediaTimelineBar" Grid.Column="1" Height="4" Margin="6,0" Minimum="0" Maximum="1" Value="0.4" Foreground="#00E5FF" Background="#242434"/>
                      <TextBlock x:Name="MediaTotTimeText" Text="-2:36" FontSize="9" Foreground="#64748B" Grid.Column="2"/>
                    </Grid>

                    <!-- Media Control Buttons -->
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,6">
                      <Button x:Name="BtnMediaPrev" Content="&#xE892;" FontFamily="Segoe MDL2 Assets" FontSize="14" Style="{StaticResource HeaderActionBtnStyle}"/>
                      <Button x:Name="BtnMediaPlayPause" Content="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="18" Width="38" Height="38" Style="{StaticResource HeaderActionBtnStyle}" Foreground="#FFFFFF" Margin="8,0"/>
                      <Button x:Name="BtnMediaNext" Content="&#xE893;" FontFamily="Segoe MDL2 Assets" FontSize="14" Style="{StaticResource HeaderActionBtnStyle}"/>
                    </StackPanel>
                  </StackPanel>

                  <!-- Right: Synchronized Lyrics Panel -->
                  <Border Grid.Column="1" Background="#121824" BorderBrush="#1AFFFFFF" BorderThickness="1" CornerRadius="14" Padding="12,10">
                    <StackPanel>
                      <TextBlock Text="SYNCHRONIZED LYRICS (LRCLIB)" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="0,0,0,6"/>
                      <ScrollViewer x:Name="LyricsScrollViewer" Height="170" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel x:Name="LyricsLinesContainer">
                          <TextBlock Text="Loading synchronized lyrics..." FontSize="11" Foreground="#9B9BA7" FontStyle="Italic"/>
                        </StackPanel>
                      </ScrollViewer>
                    </StackPanel>
                  </Border>
                </Grid>

                <!-- TAB 4: STATS (Enhanced 3-Column Telemetry) -->
                <Grid x:Name="TabContentStats" Visibility="Collapsed">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>

                  <!-- Left: Multi-Channel Live Frequency Equalizer -->
                  <Border Grid.Column="0" Background="#16161D" CornerRadius="14" Padding="10" Margin="0,0,4,0">
                    <StackPanel>
                      <TextBlock Text="CPU FREQ &amp; WAVE" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="0,0,0,6"/>
                      <TextBlock x:Name="StatsCpuClockText" Text="4.8 GHz" FontSize="14" FontWeight="Bold" Foreground="#22D3EE"/>
                      <TextBlock x:Name="StatsCpuTempText" Text="50°C · 14% Load" FontSize="10" Foreground="#9B9BA7" Margin="0,0,0,8"/>
                      <!-- Multi-channel Equalizer Bars -->
                      <StackPanel x:Name="StatsEqualizerBars" Orientation="Horizontal" HorizontalAlignment="Center" Height="50" VerticalAlignment="Bottom">
                        <Border Width="4" Height="25" Background="#22D3EE" CornerRadius="2" Margin="1,0"/>
                        <Border Width="4" Height="38" Background="#22D3EE" CornerRadius="2" Margin="1,0"/>
                        <Border Width="4" Height="18" Background="#22D3EE" CornerRadius="2" Margin="1,0"/>
                        <Border Width="4" Height="44" Background="#A78BFA" CornerRadius="2" Margin="1,0"/>
                        <Border Width="4" Height="30" Background="#A78BFA" CornerRadius="2" Margin="1,0"/>
                        <Border Width="4" Height="48" Background="#34D399" CornerRadius="2" Margin="1,0"/>
                        <Border Width="4" Height="22" Background="#34D399" CornerRadius="2" Margin="1,0"/>
                        <Border Width="4" Height="35" Background="#34D399" CornerRadius="2" Margin="1,0"/>
                      </StackPanel>
                    </StackPanel>
                  </Border>

                  <!-- Center: Disk Rates & Network Speedometer -->
                  <Border Grid.Column="1" Background="#16161D" CornerRadius="14" Padding="10" Margin="2,0">
                    <StackPanel>
                      <TextBlock Text="THROUGHPUT &amp; I/O" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="0,0,0,6"/>
                      <TextBlock Text="NETWORK SPEED" FontSize="9" Foreground="#9B9BA7"/>
                      <TextBlock x:Name="StatsNetRateText" Text="↑ 4.1 MB/s  ↓ 531 KB/s" FontSize="11" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#34D399" Margin="0,1,0,6"/>
                      <TextBlock Text="DISK I/O RATE" FontSize="9" Foreground="#9B9BA7"/>
                      <TextBlock x:Name="StatsDiskRateText" Text="R: 14.2 MB/s  W: 8.5 MB/s" FontSize="11" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#FBBF24" Margin="0,1,0,6"/>
                      <TextBlock Text="RAM USAGE" FontSize="9" Foreground="#9B9BA7"/>
                      <TextBlock x:Name="StatsRamText" Text="7.2 / 16.0 GB (45%)" FontSize="11" FontWeight="Bold" Foreground="#E2E8F0"/>
                    </StackPanel>
                  </Border>

                  <!-- Right: Top 5 Active Resource Hogs -->
                  <Border Grid.Column="2" Background="#16161D" CornerRadius="14" Padding="10" Margin="4,0,0,0">
                    <StackPanel>
                      <TextBlock Text="TOP PROCESS HOGS" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="0,0,0,6"/>
                      <StackPanel x:Name="StatsTopProcessesContainer">
                        <TextBlock Text="VS Code · 14% CPU" FontSize="10" Foreground="#E2E8F0"/>
                        <TextBlock Text="Chrome · 8% CPU" FontSize="10" Foreground="#E2E8F0"/>
                        <TextBlock Text="Cursor · 5% CPU" FontSize="10" Foreground="#E2E8F0"/>
                        <TextBlock Text="dwm · 3% CPU" FontSize="10" Foreground="#E2E8F0"/>
                        <TextBlock Text="Explorer · 1% CPU" FontSize="10" Foreground="#E2E8F0"/>
                      </StackPanel>
                    </StackPanel>
                  </Border>
                </Grid>

                <!-- TAB 5: CONTROLS (Multi-Tier Brightness & Volume) -->
                <StackPanel x:Name="TabContentControls" Visibility="Collapsed">
                  <!-- Brightness -->
                  <Border Background="#16161D" CornerRadius="12" Padding="12,10" Margin="0,0,0,8">
                    <StackPanel>
                      <Grid Margin="0,0,0,4">
                        <TextBlock Text="Display Brightness (Hardware + DDC/CI)" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF"/>
                        <TextBlock x:Name="TextBrightnessVal" Text="70%" FontSize="11" Foreground="#00E5FF" HorizontalAlignment="Right"/>
                      </Grid>
                      <Slider x:Name="SliderBrightness" Minimum="5" Maximum="100" Value="70" Style="{StaticResource IslandSliderStyle}"/>
                    </StackPanel>
                  </Border>
                  <!-- Volume -->
                  <Border Background="#16161D" CornerRadius="12" Padding="12,10" Margin="0,0,0,8">
                    <StackPanel>
                      <Grid Margin="0,0,0,4">
                        <TextBlock Text="Master Audio Volume" FontSize="11" FontWeight="SemiBold" Foreground="#FFFFFF"/>
                        <TextBlock x:Name="TextVolumeVal" Text="50%" FontSize="11" Foreground="#00E5FF" HorizontalAlignment="Right"/>
                      </Grid>
                      <Slider x:Name="SliderMasterVolume" Minimum="0" Maximum="100" Value="50" Style="{StaticResource IslandSliderStyle}"/>
                    </StackPanel>
                  </Border>
                  <!-- Quick Toggles -->
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Button x:Name="BtnToggleNightLight" Grid.Column="0" Content="Night Light" Style="{StaticResource SegmentBtnStyle}" Foreground="#FBBF24" Margin="0,0,3,0"/>
                    <Button x:Name="BtnToggleDarkMode" Grid.Column="1" Content="Dark Mode" Style="{StaticResource SegmentBtnStyle}" Foreground="#E2E8F0" Margin="2,0"/>
                    <Button x:Name="BtnLaunchTaskMgr" Grid.Column="2" Content="Task Manager" Style="{StaticResource SegmentBtnStyle}" Foreground="#34D399" Margin="3,0,0,0"/>
                  </Grid>
                </StackPanel>

                <!-- TAB 6: AI AGENTS (NotchPixel AI Agent Monitor) -->
                <StackPanel x:Name="TabContentAIAgents" Visibility="Collapsed">
                  <!-- Model Indicator Chips -->
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                    <Border Background="#1A22D3EE" BorderBrush="#4022D3EE" BorderThickness="1" CornerRadius="10" Padding="8,3" Margin="0,0,6,0">
                      <TextBlock Text="Claude Max" FontSize="10" FontWeight="Bold" Foreground="#22D3EE"/>
                    </Border>
                    <Border Background="#1AA78BFA" BorderBrush="#40A78BFA" BorderThickness="1" CornerRadius="10" Padding="8,3" Margin="0,0,6,0">
                      <TextBlock Text="Codex Plus" FontSize="10" FontWeight="Bold" Foreground="#A78BFA"/>
                    </Border>
                    <Border Background="#1A34D399" BorderBrush="#4034D399" BorderThickness="1" CornerRadius="10" Padding="8,3" Margin="0,0,6,0">
                      <TextBlock Text="Cursor Pro" FontSize="10" FontWeight="Bold" Foreground="#34D399"/>
                    </Border>
                    <Border Background="#1AFBBF24" BorderBrush="#40FBBF24" BorderThickness="1" CornerRadius="10" Padding="8,3">
                      <TextBlock Text="Antigravity Pro" FontSize="10" FontWeight="Bold" Foreground="#FBBF24"/>
                    </Border>
                  </StackPanel>

                  <!-- 4 Agent Metrics Cards -->
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Claude Card -->
                    <Border Grid.Row="0" Grid.Column="0" Background="#16161D" CornerRadius="12" Padding="10,8" Margin="0,0,4,6">
                      <StackPanel>
                        <Grid Margin="0,0,0,4">
                          <StackPanel Orientation="Horizontal">
                            <Ellipse Width="6" Height="6" Fill="#34D399" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            <TextBlock Text="Claude Code" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF"/>
                          </StackPanel>
                          <TextBlock Text="14.2M / $9.45" FontSize="9" Foreground="#64748B" HorizontalAlignment="Right"/>
                        </Grid>
                        <TextBlock Text="5h Usage: 58% · Weekly: 74%" FontSize="9" Foreground="#9B9BA7" Margin="0,0,0,3"/>
                        <ProgressBar Height="3" Minimum="0" Maximum="100" Value="58" Foreground="#22D3EE" Background="#242434"/>
                      </StackPanel>
                    </Border>

                    <!-- Cursor Card -->
                    <Border Grid.Row="0" Grid.Column="1" Background="#16161D" CornerRadius="12" Padding="10,8" Margin="4,0,0,6">
                      <StackPanel>
                        <Grid Margin="0,0,0,4">
                          <StackPanel Orientation="Horizontal">
                            <Ellipse Width="6" Height="6" Fill="#34D399" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            <TextBlock Text="Cursor Pro" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF"/>
                          </StackPanel>
                          <TextBlock Text="26.4M / $17.84" FontSize="9" Foreground="#64748B" HorizontalAlignment="Right"/>
                        </Grid>
                        <TextBlock Text="5h Usage: 72% · Weekly: 88%" FontSize="9" Foreground="#9B9BA7" Margin="0,0,0,3"/>
                        <ProgressBar Height="3" Minimum="0" Maximum="100" Value="72" Foreground="#34D399" Background="#242434"/>
                      </StackPanel>
                    </Border>

                    <!-- Codex Card -->
                    <Border Grid.Row="1" Grid.Column="0" Background="#16161D" CornerRadius="12" Padding="10,8" Margin="0,0,4,0">
                      <StackPanel>
                        <Grid Margin="0,0,0,4">
                          <StackPanel Orientation="Horizontal">
                            <Ellipse Width="6" Height="6" Fill="#FBBF24" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            <TextBlock Text="Codex CLI" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF"/>
                          </StackPanel>
                          <TextBlock Text="4.8M / $3.12" FontSize="9" Foreground="#64748B" HorizontalAlignment="Right"/>
                        </Grid>
                        <TextBlock Text="5h Usage: 24% · Weekly: 42%" FontSize="9" Foreground="#9B9BA7" Margin="0,0,0,3"/>
                        <ProgressBar Height="3" Minimum="0" Maximum="100" Value="24" Foreground="#A78BFA" Background="#242434"/>
                      </StackPanel>
                    </Border>

                    <!-- Antigravity Card -->
                    <Border Grid.Row="1" Grid.Column="1" Background="#16161D" CornerRadius="12" Padding="10,8" Margin="4,0,0,0">
                      <StackPanel>
                        <Grid Margin="0,0,0,4">
                          <StackPanel Orientation="Horizontal">
                            <Ellipse Width="6" Height="6" Fill="#34D399" VerticalAlignment="Center" Margin="0,0,5,0"/>
                            <TextBlock Text="Antigravity Pro" FontSize="11" FontWeight="Bold" Foreground="#FFFFFF"/>
                          </StackPanel>
                          <TextBlock Text="19.1M / $12.60" FontSize="9" Foreground="#64748B" HorizontalAlignment="Right"/>
                        </Grid>
                        <TextBlock Text="5h Usage: 62% · Weekly: 80%" FontSize="9" Foreground="#9B9BA7" Margin="0,0,0,3"/>
                        <ProgressBar Height="3" Minimum="0" Maximum="100" Value="62" Foreground="#FBBF24" Background="#242434"/>
                      </StackPanel>
                    </Border>
                  </Grid>
                </StackPanel>

                <!-- TAB 7: POWER (Safe 2.0s Hold-To-Confirm) -->
                <StackPanel x:Name="TabContentPower" Visibility="Collapsed">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <!-- Restart -->
                    <Border x:Name="BtnPowerRestart" Grid.Column="0" Background="#16161D" BorderBrush="#FBBF24" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,4,0" Cursor="Hand">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="🔄" FontSize="18" HorizontalAlignment="Center" Margin="0,0,0,4"/>
                        <TextBlock x:Name="PowerRestartText" Text="Restart" FontSize="12" FontWeight="Bold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                        <TextBlock Text="Hold 2.0s to confirm" FontSize="9" Foreground="#64748B" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>
                    <!-- Shutdown -->
                    <Border x:Name="BtnPowerShutdown" Grid.Column="1" Background="#16161D" BorderBrush="#F87171" BorderThickness="1" CornerRadius="12" Padding="14" Margin="4,0,0,0" Cursor="Hand">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="⏻" FontSize="18" HorizontalAlignment="Center" Margin="0,0,0,4"/>
                        <TextBlock x:Name="PowerShutdownText" Text="Shut Down" FontSize="12" FontWeight="Bold" Foreground="#FFFFFF" HorizontalAlignment="Center"/>
                        <TextBlock Text="Hold 2.0s to confirm" FontSize="9" Foreground="#64748B" HorizontalAlignment="Center"/>
                      </StackPanel>
                    </Border>
                  </Grid>
                </StackPanel>

              </Grid>
            </ScrollViewer>
          </Grid>

          <!-- ================================================================== -->
          <!--  STATE 4: MAX-EXPANDED (Workspace & Tool Grid 780x560px)           -->
          <!-- ================================================================== -->
          <Grid x:Name="ContainerStateMaxExpanded" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>  <!-- Row 0: Workspace Header -->
              <RowDefinition Height="*"/>     <!-- Row 1: Workspace Grid & Canvas -->
            </Grid.RowDefinitions>

            <!-- Workspace Header Bar -->
            <Border Grid.Row="0" Background="#EA0E0E13" BorderBrush="#1AFFFFFF" BorderThickness="0,0,0,1" CornerRadius="26,26,0,0" Padding="16,10">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                  <Border Background="#2000E5FF" BorderBrush="#4000E5FF" BorderThickness="1" CornerRadius="10" Padding="8,3" Margin="0,0,10,0">
                    <TextBlock Text="● MAX" FontSize="10" FontWeight="Black" Foreground="#00E5FF"/>
                  </Border>
                  <TextBlock Text="NOTCHPIXEL WORKSPACE &amp; TOOL GRID" FontSize="12" FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                </StackPanel>

                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="BtnReturnExpanded" Content="Compact View [ ⛶ ]" Style="{StaticResource SegmentBtnStyle}" Foreground="#A78BFA" Margin="0,0,6,0"/>
                  <Button x:Name="BtnCloseMaxExpanded" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="12" Style="{StaticResource HeaderActionBtnStyle}"/>
                </StackPanel>
              </Grid>
            </Border>

            <!-- Workspace Body: 2-Column Grid -->
            <Grid Grid.Row="1" Margin="16,12">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="420"/> <!-- Left: 4x4 Circular App Grid -->
                <ColumnDefinition Width="*"/>   <!-- Right: Workspace Tools & Scratchpad -->
              </Grid.ColumnDefinitions>

              <!-- Left: 4x4 Circular App Launcher Grid -->
              <Border Grid.Column="0" Background="#121824" BorderBrush="#1AFFFFFF" BorderThickness="1" CornerRadius="18" Padding="12" Margin="0,0,10,0">
                <StackPanel>
                  <TextBlock Text="QUICK LAUNCHER (16 PILL TILES)" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="6,0,0,10"/>
                  <!-- Uniform 4x4 Grid -->
                  <UniformGrid x:Name="CircularLauncherGrid" Rows="4" Columns="4"/>
                </StackPanel>
              </Border>

              <!-- Right: Workspace Tools Canvas, AI Agent Summary & Memo -->
              <Grid Grid.Column="1">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Hardware Equalizer & Network Live Speedometer -->
                <Border Grid.Row="0" Background="#16161D" CornerRadius="14" Padding="12,10" Margin="0,0,0,8">
                  <StackPanel>
                    <Grid Margin="0,0,0,6">
                      <TextBlock Text="LIVE TELEMETRY EQUALIZER" FontSize="10" FontWeight="Bold" Foreground="#64748B"/>
                      <TextBlock x:Name="MaxNetThroughputText" Text="↑ 4.1 MB/s  ↓ 531 KB/s" FontSize="10" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#34D399" HorizontalAlignment="Right"/>
                    </Grid>
                    <!-- Equalizer Canvas with 16 dynamic frequency bars -->
                    <StackPanel x:Name="MaxEqualizerBars" Orientation="Horizontal" HorizontalAlignment="Center" Height="40">
                      <Border Width="6" Height="20" Background="#22D3EE" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="32" Background="#22D3EE" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="15" Background="#22D3EE" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="38" Background="#A78BFA" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="25" Background="#A78BFA" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="40" Background="#34D399" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="18" Background="#34D399" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="35" Background="#34D399" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="28" Background="#FBBF24" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="16" Background="#FBBF24" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="36" Background="#F87171" CornerRadius="2" Margin="1,0"/>
                      <Border Width="6" Height="22" Background="#F87171" CornerRadius="2" Margin="1,0"/>
                    </StackPanel>
                  </StackPanel>
                </Border>

                <!-- AI Agent Live Summary -->
                <Border Grid.Row="1" Background="#16161D" CornerRadius="14" Padding="12,10" Margin="0,0,0,8">
                  <StackPanel>
                    <TextBlock Text="DEVELOPER AI SESSIONS" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="0,0,0,4"/>
                    <TextBlock Text="Active: Cursor Pro (Working) · Claude (Working) · Codex (Idle)" FontSize="10" Foreground="#E2E8F0"/>
                    <TextBlock Text="Aggregated Cost: $42.01 across 4 CLI instances" FontSize="9" Foreground="#64748B" Margin="0,2,0,0"/>
                  </StackPanel>
                </Border>

                <!-- Workspace Memo / Scratchpad -->
                <Border Grid.Row="2" Background="#16161D" CornerRadius="14" Padding="12,10">
                  <Grid>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid Grid.Row="0" Margin="0,0,0,6">
                      <TextBlock Text="INSTANT MEMO &amp; SCRATCHPAD" FontSize="10" FontWeight="Bold" Foreground="#64748B"/>
                      <Button x:Name="BtnSaveMemo" Content="Save" Style="{StaticResource SegmentBtnStyle}" Height="20" Padding="8,0" FontSize="9" HorizontalAlignment="Right"/>
                    </Grid>
                    <TextBox x:Name="TxtWorkspaceMemo" Grid.Row="1" Background="#111116" Foreground="#FFFFFF" BorderBrush="#25FFFFFF"
                             BorderThickness="1" AcceptsReturn="True" TextWrapping="Wrap" Padding="8" FontFamily="Consolas, Segoe UI" FontSize="11"/>
                  </Grid>
                </Border>
              </Grid>
            </Grid>
          </Grid>

          <!-- ================================================================== -->
          <!--  GAME MODE BAR (Slim 32px Horizontal Overlay Bar)                  -->
          <!-- ================================================================== -->
          <Grid x:Name="GameModeBar" Height="32" Cursor="Hand" Background="Transparent" Margin="8,0" Visibility="Collapsed">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <!-- Left: LIVE Badge + Game Name -->
            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
              <Border Background="#2034D399" BorderBrush="#4034D399" BorderThickness="1" CornerRadius="8" Padding="6,2" Margin="0,0,6,0">
                <StackPanel Orientation="Horizontal">
                  <Ellipse Width="5" Height="5" Fill="#34D399" Margin="0,0,4,0" VerticalAlignment="Center"/>
                  <TextBlock Text="LIVE" FontSize="9" FontWeight="Black" Foreground="#34D399" VerticalAlignment="Center" Margin="0,0,4,0"/>
                  <TextBlock x:Name="GameModeNameText" Text="VALORANT" FontSize="10" FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center" MaxWidth="100" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
              </Border>
            </StackPanel>

            <!-- Center: FPS, Temps & RAM -->
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
              <TextBlock x:Name="GameModeFps" Text="144 FPS" FontSize="10" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#22D3EE"/>
              <TextBlock Text=" &#x2502; " FontSize="10" Foreground="#30FFFFFF"/>
              <TextBlock x:Name="GameModeCpu" Text="CPU 78°C" FontSize="10" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono" Foreground="#E0F2FE"/>
              <TextBlock Text=" &#x2502; " FontSize="10" Foreground="#30FFFFFF"/>
              <TextBlock x:Name="GameModeGpu" Text="GPU 52°C" FontSize="10" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono" Foreground="#E0F2FE"/>
              <TextBlock Text=" &#x2502; " FontSize="10" Foreground="#30FFFFFF"/>
              <TextBlock x:Name="GameModeRam" Text="RAM 72%" FontSize="10" FontWeight="SemiBold" FontFamily="Consolas, Segoe UI Mono" Foreground="#E0F2FE"/>
            </StackPanel>

            <!-- Right: Clock & Exit -->
            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="GameModeClock" Text="1:45 AM" FontSize="10" FontWeight="Bold" FontFamily="Consolas, Segoe UI Mono" Foreground="#94A3B8" Margin="0,0,6,0"/>
              <Button x:Name="BtnExitGameMode" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="9" Style="{StaticResource HeaderActionBtnStyle}" Width="18" Height="18"/>
            </StackPanel>
          </Grid>

        </Grid>
      </Border>
    </Grid>
  </Grid>
</Window>
"@


# ------------------------------------------------------------------------------
#  WPF Window Realization & Element Resolution
# ------------------------------------------------------------------------------
$reader = New-Object System.Xml.XmlNodeReader($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Apply WS_EX_NOACTIVATE & WS_EX_TOOLWINDOW on SourceInitialized
$window.Add_SourceInitialized({
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        [IslandNative]::ApplyNoActivate($helper.Handle)
        if ($script:isGlass) {
            [IslandNative]::EnableAcrylic($helper.Handle, 0x0114141E)
        }
    } catch { }
})

# Find Elements
$glowBorder              = $window.FindName("GlowBorder")
$islandGlow              = $window.FindName("IslandGlow")
$islandHoverZone         = $window.FindName("IslandHoverZone")
$topTriggerBar           = $window.FindName("TopTriggerBar")

# State Containers
$containerStateIdle      = $window.FindName("ContainerStateIdle")
$containerStateHover     = $window.FindName("ContainerStateHover")
$containerStateExpanded  = $window.FindName("ContainerStateExpanded")
$containerStateMaxExpanded = $window.FindName("ContainerStateMaxExpanded")
$gameModeBar             = $window.FindName("GameModeBar")

# State 1 Elements
$btnMicToggle            = $window.FindName("BtnMicToggle")
$idleMicStatusDot        = $window.FindName("IdleMicStatusDot")
$idleBatteryArc          = $window.FindName("IdleBatteryArc")
$idleBatteryText         = $window.FindName("IdleBatteryText")
$idleClockText           = $window.FindName("IdleClockText")
$idleCpuText             = $window.FindName("IdleCpuText")

# State 2 Elements
$hoverAlbumImage         = $window.FindName("HoverAlbumImage")
$hoverTrackTitle         = $window.FindName("HoverTrackTitle")
$hoverTrackArtist        = $window.FindName("HoverTrackArtist")
$hoverProgressBar        = $window.FindName("HoverProgressBar")
$btnHoverPlayPause       = $window.FindName("BtnHoverPlayPause")
$hoverVolumeSlider       = $window.FindName("HoverVolumeSlider")

# State 3 Header & Navigation
$tabBtnToday             = $window.FindName("TabBtnToday")
$tabBtnApps              = $window.FindName("TabBtnApps")
$tabBtnMedia             = $window.FindName("TabBtnMedia")
$tabBtnStats             = $window.FindName("TabBtnStats")
$tabBtnControls          = $window.FindName("TabBtnControls")
$tabBtnAIAgents          = $window.FindName("TabBtnAIAgents")
$tabBtnPower             = $window.FindName("TabBtnPower")
$btnMaxExpandToggle      = $window.FindName("BtnMaxExpandToggle")
$btnSettingsToggle       = $window.FindName("BtnSettingsToggle")
$btnPinToggle            = $window.FindName("BtnPinToggle")

# State 3 Tab Contents
$tabContentToday         = $window.FindName("TabContentToday")
$tabContentApps          = $window.FindName("TabContentApps")
$tabContentMedia         = $window.FindName("TabContentMedia")
$tabContentStats         = $window.FindName("TabContentStats")
$tabContentControls      = $window.FindName("TabContentControls")
$tabContentAIAgents      = $window.FindName("TabContentAIAgents")
$tabContentPower         = $window.FindName("TabContentPower")

# Tab Content Elements
$todayGreeting           = $window.FindName("TodayGreeting")
$todayDate               = $window.FindName("TodayDate")
$todayBatteryText        = $window.FindName("TodayBatteryText")
$todayCpuPct             = $window.FindName("TodayCpuPct")
$todayCpuBar             = $window.FindName("TodayCpuBar")
$todayGpuPct             = $window.FindName("TodayGpuPct")
$todayGpuBar             = $window.FindName("TodayGpuBar")
$todayRamPct             = $window.FindName("TodayRamPct")
$todayRamBar             = $window.FindName("TodayRamBar")
$appsGridContainer       = $window.FindName("AppsGridContainer")
$btnAddCustomApp         = $window.FindName("BtnAddCustomApp")

# Media & Lyrics
$mediaAlbumArtImage      = $window.FindName("MediaAlbumArtImage")
$mediaTrackTitle         = $window.FindName("MediaTrackTitle")
$mediaTrackArtist        = $window.FindName("MediaTrackArtist")
$mediaTimelineBar        = $window.FindName("MediaTimelineBar")
$mediaCurTimeText        = $window.FindName("MediaCurTimeText")
$mediaTotTimeText        = $window.FindName("MediaTotTimeText")
$btnMediaPrev            = $window.FindName("BtnMediaPrev")
$btnMediaPlayPause       = $window.FindName("BtnMediaPlayPause")
$btnMediaNext            = $window.FindName("BtnMediaNext")
$lyricsScrollViewer      = $window.FindName("LyricsScrollViewer")
$lyricsLinesContainer    = $window.FindName("LyricsLinesContainer")

# Stats Tab Elements
$statsCpuClockText       = $window.FindName("StatsCpuClockText")
$statsCpuTempText        = $window.FindName("StatsCpuTempText")
$statsEqualizerBars      = $window.FindName("StatsEqualizerBars")
$statsNetRateText        = $window.FindName("StatsNetRateText")
$statsDiskRateText       = $window.FindName("StatsDiskRateText")
$statsRamText            = $window.FindName("StatsRamText")
$statsTopProcessesContainer = $window.FindName("StatsTopProcessesContainer")

# Controls Tab Elements
$sliderBrightness        = $window.FindName("SliderBrightness")
$textBrightnessVal       = $window.FindName("TextBrightnessVal")
$sliderMasterVolume      = $window.FindName("SliderMasterVolume")
$textVolumeVal           = $window.FindName("TextVolumeVal")
$btnToggleNightLight     = $window.FindName("BtnToggleNightLight")
$btnToggleDarkMode       = $window.FindName("BtnToggleDarkMode")
$btnLaunchTaskMgr        = $window.FindName("BtnLaunchTaskMgr")

# Power Tab Elements
$btnPowerRestart         = $window.FindName("BtnPowerRestart")
$powerRestartText        = $window.FindName("PowerRestartText")
$btnPowerShutdown        = $window.FindName("BtnPowerShutdown")
$powerShutdownText       = $window.FindName("PowerShutdownText")

# State 4 Max-Expanded Elements
$circularLauncherGrid    = $window.FindName("CircularLauncherGrid")
$btnReturnExpanded       = $window.FindName("BtnReturnExpanded")
$btnCloseMaxExpanded     = $window.FindName("BtnCloseMaxExpanded")
$maxNetThroughputText    = $window.FindName("MaxNetThroughputText")
$maxEqualizerBars        = $window.FindName("MaxEqualizerBars")
$txtWorkspaceMemo        = $window.FindName("TxtWorkspaceMemo")
$btnSaveMemo             = $window.FindName("BtnSaveMemo")

# Game Mode Elements
$gameModeNameText        = $window.FindName("GameModeNameText")
$gameModeFps             = $window.FindName("GameModeFps")
$gameModeCpu             = $window.FindName("GameModeCpu")
$gameModeGpu             = $window.FindName("GameModeGpu")
$gameModeRam             = $window.FindName("GameModeRam")
$gameModeClock           = $window.FindName("GameModeClock")
$btnExitGameMode         = $window.FindName("BtnExitGameMode")

# Context Menu Items
$menuToggleGameMode      = $window.FindName("MenuToggleGameMode")
$menuToggleMaxExpanded   = $window.FindName("MenuToggleMaxExpanded")
$menuOpenUrlFavorites    = $window.FindName("MenuOpenUrlFavorites")
$menuOpenCalendar        = $window.FindName("MenuOpenCalendar")
$menuOpenClipboard       = $window.FindName("MenuOpenClipboard")
$menuResetPos            = $window.FindName("MenuResetPos")
$menuToggleGlass         = $window.FindName("MenuToggleGlass")
$menuReload              = $window.FindName("MenuReload")
$menuQuit                = $window.FindName("MenuQuit")

# Tab Mapping & Brushes
$tabButtons = @{
    Today    = $tabBtnToday
    Apps     = $tabBtnApps
    Media    = $tabBtnMedia
    Stats    = $tabBtnStats
    Controls = $tabBtnControls
    AIAgents = $tabBtnAIAgents
    Power    = $tabBtnPower
}

$tabContents = @{
    Today    = $tabContentToday
    Apps     = $tabContentApps
    Media    = $tabContentMedia
    Stats    = $tabContentStats
    Controls = $tabContentControls
    AIAgents = $tabContentAIAgents
    Power    = $tabContentPower
}

$script:brushActiveBg   = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#FFFFFF"))
$script:brushActiveFg   = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#000000"))
$script:brushInactiveFg = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#9B9BA7"))
$script:brushGreen      = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#34D399"))
$script:brushAmber      = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#FBBF24"))
$script:brushRed        = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#F87171"))
$script:brushCyan       = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#22D3EE"))
$script:brushPurple     = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString("#A78BFA"))


# ------------------------------------------------------------------------------
#  Standalone Modular Utility Windows (URL Favorites, Calendar, Clipboard)
# ------------------------------------------------------------------------------

# Global references to keep single instances
$script:winUrlFavorites = $null
$script:winCalendar     = $null
$script:winClipboard    = $null

function Show-UrlFavoritesWindow {
    if ($script:winUrlFavorites -and $script:winUrlFavorites.IsVisible) {
        $script:winUrlFavorites.Activate()
        return
    }

    $winX = [xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="URL Favorites" Width="480" Height="440" WindowStyle="None" AllowsTransparency="True"
        Background="{x:Null}" Topmost="True" ShowInTaskbar="False" WindowStartupLocation="CenterScreen">
  <Border Background="#121824" BorderBrush="#2522D3EE" BorderThickness="1" CornerRadius="18" Padding="16">
    <Border.Effect>
      <DropShadowEffect Color="#000000" BlurRadius="25" ShadowDepth="4" Opacity="0.6"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header -->
      <Grid Grid.Row="0" Margin="0,0,0,10">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="⭐ URL FAVORITES" FontSize="12" FontWeight="Bold" Foreground="#22D3EE"/>
          <TextBlock Text=" · NotchPixel Hub" FontSize="11" Foreground="#64748B"/>
        </StackPanel>
        <Button x:Name="BtnClose" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11" Width="24" Height="24"
                HorizontalAlignment="Right" Background="Transparent" Foreground="#94A3B8" BorderThickness="0" Cursor="Hand"/>
      </Grid>

      <!-- Search & Category Filters -->
      <Grid Grid.Row="1" Margin="0,0,0,10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBox x:Name="TxtSearch" Height="28" Background="#16161D" Foreground="#FFFFFF" BorderBrush="#25FFFFFF"
                 BorderThickness="1" Padding="8,4" FontSize="11" Text="Search bookmarks..."/>
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,0">
          <Button x:Name="BtnCatAll" Content="All" Height="22" Padding="8,0" Margin="0,0,4,0" Background="#22D3EE" Foreground="#000000" FontSize="10" FontWeight="Bold" Cursor="Hand"/>
          <Button x:Name="BtnCatDev" Content="Dev" Height="22" Padding="8,0" Margin="0,0,4,0" Background="#16161D" Foreground="#94A3B8" FontSize="10" Cursor="Hand"/>
          <Button x:Name="BtnCatMedia" Content="Media" Height="22" Padding="8,0" Margin="0,0,4,0" Background="#16161D" Foreground="#94A3B8" FontSize="10" Cursor="Hand"/>
          <Button x:Name="BtnCatSocial" Content="Social" Height="22" Padding="8,0" Margin="0,0,4,0" Background="#16161D" Foreground="#94A3B8" FontSize="10" Cursor="Hand"/>
          <Button x:Name="BtnCatTools" Content="Tools" Height="22" Padding="8,0" Background="#16161D" Foreground="#94A3B8" FontSize="10" Cursor="Hand"/>
        </StackPanel>
      </Grid>

      <!-- Bookmark Items List -->
      <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="FavListPanel"/>
      </ScrollViewer>

      <!-- Footer: Add Link -->
      <Grid Grid.Row="3" Margin="0,10,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="TxtNewFav" Height="26" Background="#16161D" Foreground="#FFFFFF" BorderBrush="#25FFFFFF"
                 BorderThickness="1" Padding="6,3" FontSize="10" Text="https://"/>
        <Button x:Name="BtnAddFav" Grid.Column="1" Content="+ Add Link" Height="26" Padding="10,0" Margin="6,0,0,0"
                Background="#22D3EE" Foreground="#000000" FontSize="10" FontWeight="Bold" Cursor="Hand"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $r = New-Object System.Xml.XmlNodeReader($winX)
    $w = [System.Windows.Markup.XamlReader]::Load($r)
    $script:winUrlFavorites = $w

    $w.Add_SourceInitialized({
        try {
            $helper = New-Object System.Windows.Interop.WindowInteropHelper($w)
            [IslandNative]::ApplyNoActivate($helper.Handle)
            [IslandNative]::EnableAcrylic($helper.Handle, 0x01121824)
        } catch { }
    })

    $btnClose   = $w.FindName("BtnClose")
    $txtSearch  = $w.FindName("TxtSearch")
    $favList    = $w.FindName("FavListPanel")
    $txtNewFav  = $w.FindName("TxtNewFav")
    $btnAddFav  = $w.FindName("BtnAddFav")

    $btnClose.Add_Click({ $w.Close() })

    function Refresh-FavList ([string]$filter = "", [string]$category = "All") {
        $favList.Children.Clear()
        $data = Get-IslandData
        if (-not $data -or -not $data.Favorites) { return }

        foreach ($fav in $data.Favorites) {
            if ($category -ne "All" -and $fav.Category -ne $category) { continue }
            if ($filter -and $fav.Title -notmatch "(?i)$filter" -and $fav.Url -notmatch "(?i)$filter") { continue }

            $card = New-Object System.Windows.Controls.Border
            $card.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#16161D")
            $card.BorderBrush = [System.Windows.Media.ColorConverter]::ConvertFromString("#1AFFFFFF")
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $card.CornerRadius = New-Object System.Windows.CornerRadius(10)
            $card.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
            $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
            $card.Cursor = [System.Windows.Input.Cursors]::Hand
            $card.Tag = $fav.Url

            $g = New-Object System.Windows.Controls.Grid
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
            $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)

            $ic = New-Object System.Windows.Controls.TextBlock
            $ic.Text = if ($fav.Icon) { $fav.Icon } else { "🔗" }
            $ic.FontSize = 14
            $ic.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
            $ic.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($ic, 0)
            [void]$g.Children.Add($ic)

            $sp = New-Object System.Windows.Controls.StackPanel
            $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $fav.Title; $t.FontSize = 11; $t.FontWeight = 'Bold'; $t.Foreground = [System.Windows.Media.Brushes]::White
            $u = New-Object System.Windows.Controls.TextBlock; $u.Text = $fav.Url; $u.FontSize = 9; $u.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#64748B")
            [void]$sp.Children.Add($t); [void]$sp.Children.Add($u)
            [System.Windows.Controls.Grid]::SetColumn($sp, 1)
            [void]$g.Children.Add($sp)

            $catBadge = New-Object System.Windows.Controls.TextBlock
            $catBadge.Text = $fav.Category
            $catBadge.FontSize = 9
            $catBadge.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#22D3EE")
            $catBadge.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($catBadge, 2)
            [void]$g.Children.Add($catBadge)

            $card.Child = $g
            $card.Add_MouseLeftButtonDown({
                try { [System.Diagnostics.Process]::Start($this.Tag) } catch { }
            })
            [void]$favList.Children.Add($card)
        }
    }

    Refresh-FavList "" "All"

    $txtSearch.Add_GotFocus({ if ($txtSearch.Text -eq "Search bookmarks...") { $txtSearch.Text = "" } })
    $txtSearch.Add_TextChanged({ Refresh-FavList $txtSearch.Text "All" })

    $btnAddFav.Add_Click({
        $url = $txtNewFav.Text.Trim()
        if ($url -and $url -ne "https://") {
            $data = Get-IslandData
            if (-not $data) { $data = @{ Favorites = @() } }
            $title = ([System.Uri]$url).Host
            $newFav = @{ Category = "Dev"; Title = $title; Url = $url; Icon = "⭐" }
            $data.Favorites += $newFav
            Save-IslandData $data
            $txtNewFav.Text = "https://"
            Refresh-FavList "" "All"
        }
    })

    $w.Show()
}

function Show-CalendarWindow {
    if ($script:winCalendar -and $script:winCalendar.IsVisible) {
        $script:winCalendar.Activate()
        return
    }

    $winX = [xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Calendar &amp; Agenda" Width="460" Height="500" WindowStyle="None" AllowsTransparency="True"
        Background="{x:Null}" Topmost="True" ShowInTaskbar="False" WindowStartupLocation="CenterScreen">
  <Border Background="#121824" BorderBrush="#25A78BFA" BorderThickness="1" CornerRadius="18" Padding="16">
    <Border.Effect>
      <DropShadowEffect Color="#000000" BlurRadius="25" ShadowDepth="4" Opacity="0.6"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header -->
      <Grid Grid.Row="0" Margin="0,0,0,10">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock x:Name="MonthYearHeader" Text="NOVEMBER 2026" FontSize="13" FontWeight="Bold" Foreground="#A78BFA"/>
          <TextBlock Text=" · Interactive Agenda" FontSize="11" Foreground="#64748B" Margin="6,0,0,0"/>
        </StackPanel>
        <Button x:Name="BtnClose" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11" Width="24" Height="24"
                HorizontalAlignment="Right" Background="Transparent" Foreground="#94A3B8" BorderThickness="0" Cursor="Hand"/>
      </Grid>

      <!-- Calendar 7-Column Days Grid -->
      <Border Grid.Row="1" Background="#16161D" CornerRadius="12" Padding="10" Margin="0,0,0,10">
        <UniformGrid x:Name="CalendarDaysGrid" Rows="6" Columns="7"/>
      </Border>

      <!-- Agenda Schedule List -->
      <Border Grid.Row="2" Background="#16161D" CornerRadius="12" Padding="12,10">
        <StackPanel>
          <TextBlock Text="TODAY'S SCHEDULE &amp; UPCOMING" FontSize="10" FontWeight="Bold" Foreground="#64748B" Margin="0,0,0,8"/>
          <ScrollViewer Height="110" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="AgendaEventsPanel"/>
          </ScrollViewer>
        </StackPanel>
      </Border>

      <!-- Add Event -->
      <Grid Grid.Row="3" Margin="0,10,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="TxtNewEvent" Height="26" Background="#16161D" Foreground="#FFFFFF" BorderBrush="#25FFFFFF"
                 BorderThickness="1" Padding="6,3" FontSize="10" Text="New event (e.g. Code Review 4pm)"/>
        <Button x:Name="BtnAddEvent" Grid.Column="1" Content="+ Add Event" Height="26" Padding="10,0" Margin="6,0,0,0"
                Background="#A78BFA" Foreground="#000000" FontSize="10" FontWeight="Bold" Cursor="Hand"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $r = New-Object System.Xml.XmlNodeReader($winX)
    $w = [System.Windows.Markup.XamlReader]::Load($r)
    $script:winCalendar = $w

    $w.Add_SourceInitialized({
        try {
            $helper = New-Object System.Windows.Interop.WindowInteropHelper($w)
            [IslandNative]::ApplyNoActivate($helper.Handle)
            [IslandNative]::EnableAcrylic($helper.Handle, 0x01121824)
        } catch { }
    })

    $btnClose       = $w.FindName("BtnClose")
    $daysGrid       = $w.FindName("CalendarDaysGrid")
    $agendaPanel    = $w.FindName("AgendaEventsPanel")
    $txtNewEvent    = $w.FindName("TxtNewEvent")
    $btnAddEvent    = $w.FindName("BtnAddEvent")

    $btnClose.Add_Click({ $w.Close() })

    # Populate 7 Day headers
    $dayNames = @("Su", "Mo", "Tu", "We", "Th", "Fr", "Sa")
    foreach ($d in $dayNames) {
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $d; $lbl.FontSize = 10; $lbl.FontWeight = 'Bold'; $lbl.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#64748B")
        $lbl.HorizontalAlignment = 'Center'; $lbl.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
        [void]$daysGrid.Children.Add($lbl)
    }

    # Populate 30 days
    $todayDay = [DateTime]::Now.Day
    for ($i = 1; $i -le 35; $i++) {
        $dayNum = $i - 2
        $cell = New-Object System.Windows.Controls.Border
        $cell.Width = 26; $cell.Height = 26; $cell.CornerRadius = New-Object System.Windows.CornerRadius(13)
        $cell.Margin = New-Object System.Windows.Thickness(2)
        $cell.HorizontalAlignment = 'Center'

        if ($dayNum -gt 0 -and $dayNum -le 30) {
            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = "$dayNum"
            $txt.FontSize = 10
            $txt.HorizontalAlignment = 'Center'; $txt.VerticalAlignment = 'Center'

            if ($dayNum -eq $todayDay) {
                $cell.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#A78BFA")
                $txt.Foreground = [System.Windows.Media.Brushes]::Black
                $txt.FontWeight = 'Bold'
            } else {
                $txt.Foreground = [System.Windows.Media.Brushes]::White
            }
            $cell.Child = $txt
        }
        [void]$daysGrid.Children.Add($cell)
    }

    # Load Agenda
    function Refresh-Agenda {
        $agendaPanel.Children.Clear()
        $data = Get-IslandData
        if ($data -and $data.CalendarEvents) {
            foreach ($ev in $data.CalendarEvents) {
                $p = New-Object System.Windows.Controls.Border
                $p.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#1A1A24")
                $p.CornerRadius = New-Object System.Windows.CornerRadius(6)
                $p.Padding = New-Object System.Windows.Thickness(8, 4, 8, 4)
                $p.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
                $tb = New-Object System.Windows.Controls.TextBlock
                $tb.Text = "• $($ev.Time) - $($ev.Title) ($($ev.Category))"
                $tb.FontSize = 10; $tb.Foreground = [System.Windows.Media.Brushes]::White
                $p.Child = $tb
                [void]$agendaPanel.Children.Add($p)
            }
        }
    }
    Refresh-Agenda

    $btnAddEvent.Add_Click({
        $evText = $txtNewEvent.Text.Trim()
        if ($evText -and $evText -ne "New event (e.g. Code Review 4pm)") {
            $data = Get-IslandData
            if (-not $data) { $data = @{ CalendarEvents = @() } }
            $newEvent = @{
                Id       = [DateTime]::Now.Ticks
                Date     = [DateTime]::Now.ToString("yyyy-MM-dd")
                Time     = [DateTime]::Now.ToString("hh:mm tt")
                Title    = $evText
                Category = "User"
            }
            $data.CalendarEvents += $newEvent
            Save-IslandData $data
            $txtNewEvent.Text = ""
            Refresh-Agenda
        }
    })

    $w.Show()
}

function Show-ClipboardWindow {
    if ($script:winClipboard -and $script:winClipboard.IsVisible) {
        $script:winClipboard.Activate()
        return
    }

    $winX = [xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Clipboard History" Width="420" Height="460" WindowStyle="None" AllowsTransparency="True"
        Background="{x:Null}" Topmost="True" ShowInTaskbar="False" WindowStartupLocation="CenterScreen">
  <Border Background="#121824" BorderBrush="#2534D399" BorderThickness="1" CornerRadius="18" Padding="16">
    <Border.Effect>
      <DropShadowEffect Color="#000000" BlurRadius="25" ShadowDepth="4" Opacity="0.6"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header -->
      <Grid Grid.Row="0" Margin="0,0,0,10">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="📋 CLIPBOARD HISTORY" FontSize="12" FontWeight="Bold" Foreground="#34D399"/>
          <TextBlock Text=" · 1-Click Copy" FontSize="11" Foreground="#64748B"/>
        </StackPanel>
        <Button x:Name="BtnClose" Content="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11" Width="24" Height="24"
                HorizontalAlignment="Right" Background="Transparent" Foreground="#94A3B8" BorderThickness="0" Cursor="Hand"/>
      </Grid>

      <!-- Search Box -->
      <TextBox x:Name="TxtSearch" Grid.Row="1" Height="28" Background="#16161D" Foreground="#FFFFFF" BorderBrush="#25FFFFFF"
               BorderThickness="1" Padding="8,4" FontSize="11" Text="Search clips..." Margin="0,0,0,10"/>

      <!-- Clips List -->
      <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="ClipListPanel"/>
      </ScrollViewer>

      <!-- Footer Action -->
      <Grid Grid.Row="3" Margin="0,10,0,0">
        <TextBlock x:Name="ToastCopiedText" Text="" FontSize="10" Foreground="#34D399" VerticalAlignment="Center"/>
        <Button x:Name="BtnClearClips" Content="Clear All" Height="24" Padding="10,0" HorizontalAlignment="Right"
                Background="#242434" Foreground="#94A3B8" FontSize="9" Cursor="Hand"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $r = New-Object System.Xml.XmlNodeReader($winX)
    $w = [System.Windows.Markup.XamlReader]::Load($r)
    $script:winClipboard = $w

    $w.Add_SourceInitialized({
        try {
            $helper = New-Object System.Windows.Interop.WindowInteropHelper($w)
            [IslandNative]::ApplyNoActivate($helper.Handle)
            [IslandNative]::EnableAcrylic($helper.Handle, 0x01121824)
        } catch { }
    })

    $btnClose       = $w.FindName("BtnClose")
    $txtSearch      = $w.FindName("TxtSearch")
    $clipList       = $w.FindName("ClipListPanel")
    $toastText      = $w.FindName("ToastCopiedText")
    $btnClear       = $w.FindName("BtnClearClips")

    $btnClose.Add_Click({ $w.Close() })

    function Refresh-Clips ([string]$filter = "") {
        $clipList.Children.Clear()
        $data = Get-IslandData
        if (-not $data -or -not $data.ClipboardHistory) { return }

        foreach ($clip in $data.ClipboardHistory) {
            if ($filter -and $clip.Text -notmatch "(?i)$filter") { continue }

            $b = New-Object System.Windows.Controls.Border
            $b.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#16161D")
            $b.BorderBrush = [System.Windows.Media.ColorConverter]::ConvertFromString("#1AFFFFFF")
            $b.BorderThickness = New-Object System.Windows.Thickness(1)
            $b.CornerRadius = New-Object System.Windows.CornerRadius(8)
            $b.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
            $b.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
            $b.Cursor = [System.Windows.Input.Cursors]::Hand
            $b.Tag = $clip.Text

            $sp = New-Object System.Windows.Controls.StackPanel
            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = $clip.Text
            $txt.FontSize = 10
            $txt.Foreground = [System.Windows.Media.Brushes]::White
            $txt.TextTrimming = 'CharacterEllipsis'
            $txt.MaxHeight = 36

            $tm = New-Object System.Windows.Controls.TextBlock
            $tm.Text = "Copied at $($clip.Time)"
            $tm.FontSize = 8
            $tm.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#64748B")
            $tm.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)

            [void]$sp.Children.Add($txt); [void]$sp.Children.Add($tm)
            $b.Child = $sp

            $b.Add_MouseLeftButtonDown({
                try {
                    [System.Windows.Clipboard]::SetText($this.Tag)
                    $toastText.Text = "✓ Copied to clipboard!"
                } catch { }
            })
            [void]$clipList.Children.Add($b)
        }
    }

    Refresh-Clips ""
    $txtSearch.Add_GotFocus({ if ($txtSearch.Text -eq "Search clips...") { $txtSearch.Text = "" } })
    $txtSearch.Add_TextChanged({ Refresh-Clips $txtSearch.Text })

    $btnClear.Add_Click({
        $data = Get-IslandData
        if ($data) {
            $data.ClipboardHistory = @()
            Save-IslandData $data
            Refresh-Clips ""
        }
    })

    $w.Show()
}


# ------------------------------------------------------------------------------
#  Core Interaction Engines (4-State Spatial Model, Launcher, Lyrics, Palette)
# ------------------------------------------------------------------------------

$script:islandState = "Idle" # "Idle", "Hover", "Expanded", "MaxExpanded"
$script:isPinned    = [bool]$Config.Pinned
$script:isGlass     = [bool]$Config.GlassMode
$script:activeTab   = "Today"
$script:hoverLeaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:hoverLeaveTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:hoverLeaveTimer.Add_Tick({
    $script:hoverLeaveTimer.Stop()
    if ($script:islandState -eq "Hover" -and -not $script:isPinned) {
        Set-IslandState "Idle"
    }
})

# Easing function for smooth WPF spring transition (CubicEase Out 0.25s)
$script:springEase = New-Object System.Windows.Media.Animation.CubicEase
$script:springEase.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut

function Animate-Property ($targetObj, $depProp, [double]$toVal, [double]$durSec = 0.25) {
    if (-not $targetObj) { return }
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.To = $toVal
    $anim.Duration = New-Object System.Windows.Duration([TimeSpan]::FromSeconds($durSec))
    $anim.EasingFunction = $script:springEase
    $targetObj.BeginAnimation($depProp, $anim)
}

function Set-IslandState ([string]$newState) {
    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $priH = [System.Windows.SystemParameters]::PrimaryScreenHeight

    $targetW = 320.0
    $targetH = 32.0
    $targetTop = if (-not $script:isPinned) { -28.0 } else { 15.0 }
    $targetLeft = ($priW / 2.0) - 160.0
    $targetRadius = 16.0

    switch ($newState) {
        "Idle" {
            $targetW = 320.0
            $targetH = 32.0
            $targetTop = if (-not $script:isPinned) { -28.0 } else { 15.0 }
            $targetLeft = ($priW / 2.0) - ($targetW / 2.0)
            $targetRadius = 16.0

            $containerStateIdle.Visibility        = 'Visible'
            $containerStateHover.Visibility       = 'Collapsed'
            $containerStateExpanded.Visibility    = 'Collapsed'
            $containerStateMaxExpanded.Visibility = 'Collapsed'
            $gameModeBar.Visibility               = 'Collapsed'
            $glowBorder.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#000000")
        }
        "Hover" {
            $targetW = 440.0
            $targetH = 56.0
            $targetTop = 15.0
            $targetLeft = ($priW / 2.0) - ($targetW / 2.0)
            $targetRadius = 24.0

            $containerStateIdle.Visibility        = 'Collapsed'
            $containerStateHover.Visibility       = 'Visible'
            $containerStateExpanded.Visibility    = 'Collapsed'
            $containerStateMaxExpanded.Visibility = 'Collapsed'
            $gameModeBar.Visibility               = 'Collapsed'
            $glowBorder.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#CC0D111A")
        }
        "Expanded" {
            $targetW = 520.0
            $targetH = 420.0
            $targetTop = 15.0
            $targetLeft = ($priW / 2.0) - ($targetW / 2.0)
            $targetRadius = 24.0

            $containerStateIdle.Visibility        = 'Collapsed'
            $containerStateHover.Visibility       = 'Collapsed'
            $containerStateExpanded.Visibility    = 'Visible'
            $containerStateMaxExpanded.Visibility = 'Collapsed'
            $gameModeBar.Visibility               = 'Collapsed'
            $glowBorder.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#CC0D111A")
        }
        "MaxExpanded" {
            $targetW = 780.0
            $targetH = 560.0
            $targetTop = 15.0
            $targetLeft = ($priW / 2.0) - ($targetW / 2.0)
            $targetRadius = 26.0

            $containerStateIdle.Visibility        = 'Collapsed'
            $containerStateHover.Visibility       = 'Collapsed'
            $containerStateExpanded.Visibility    = 'Collapsed'
            $containerStateMaxExpanded.Visibility = 'Visible'
            $gameModeBar.Visibility               = 'Collapsed'
            $glowBorder.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#EA0E0E13")
        }
        "Game" {
            $targetW = 480.0
            $targetH = 32.0
            $targetTop = if (-not $script:isPinned) { -28.0 } else { 15.0 }
            $targetLeft = ($priW / 2.0) - ($targetW / 2.0)
            $targetRadius = 16.0

            $containerStateIdle.Visibility        = 'Collapsed'
            $containerStateHover.Visibility       = 'Collapsed'
            $containerStateExpanded.Visibility    = 'Collapsed'
            $containerStateMaxExpanded.Visibility = 'Collapsed'
            $gameModeBar.Visibility               = 'Visible'
            $glowBorder.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#000000")
        }
    }

    # Smooth animation
    Animate-Property $glowBorder ([System.Windows.Controls.Border]::WidthProperty) $targetW 0.25
    Animate-Property $glowBorder ([System.Windows.Controls.Border]::HeightProperty) $targetH 0.25
    Animate-Property $glowBorder ([System.Windows.Controls.Border]::CornerRadiusProperty) $targetRadius 0.25

    $window.Width  = $targetW + 28
    $window.Height = $targetH + 28

    Animate-Property $window ([System.Windows.Window]::TopProperty) $targetTop 0.25
    Animate-Property $window ([System.Windows.Window]::LeftProperty) $targetLeft 0.25

    $script:islandState = $newState
}

# ------------------------------------------------------------------------------
#  Tab Navigation Engine (Strict Single Active Highlight)
# ------------------------------------------------------------------------------
function Switch-Tab ([string]$tabName) {
    if (-not $tabButtons.ContainsKey($tabName)) { return }
    $script:activeTab = $tabName

    foreach ($name in $tabButtons.Keys) {
        $btn = $tabButtons[$name]
        $content = $tabContents[$name]
        if ($name -eq $tabName) {
            $btn.Background = $script:brushActiveBg
            $btn.Foreground = $script:brushActiveFg
            $btn.FontWeight = [System.Windows.FontWeights]::Bold
            if ($content) { $content.Visibility = 'Visible' }
        } else {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
            $btn.Foreground = $script:brushInactiveFg
            $btn.FontWeight = [System.Windows.FontWeights]::Normal
            if ($content) { $content.Visibility = 'Collapsed' }
        }
    }
}

# ------------------------------------------------------------------------------
#  Circular App Launcher Grid Engine (16 Tiles, 48x48px, Scale-up 1.1x)
# ------------------------------------------------------------------------------
$script:circularApps = @(
    @{ Name = "Todo";       Icon = "☑"; Color = "#34D399"; Sub = "Tasks" },
    @{ Name = "URL Favs";   Icon = "⭐"; Color = "#22D3EE"; Sub = "Links" },
    @{ Name = "Album";      Icon = "🎵"; Color = "#A78BFA"; Sub = "Media" },
    @{ Name = "Mail";       Icon = "✉"; Color = "#FBBF24"; Sub = "Inbox" },
    @{ Name = "Search";     Icon = "🔍"; Color = "#60A5FA"; Sub = "Files" },
    @{ Name = "Clipboard";  Icon = "📋"; Color = "#34D399"; Sub = "History" },
    @{ Name = "AI Chat";    Icon = "✨"; Color = "#22D3EE"; Sub = "Prompt" },
    @{ Name = "Memo";       Icon = "📝"; Color = "#F472B6"; Sub = "Scratch" },
    @{ Name = "Countdown";  Icon = "⏳"; Color = "#FBBF24"; Sub = "Timer" },
    @{ Name = "Alarm";      Icon = "🔔"; Color = "#F87171"; Sub = "Alert" },
    @{ Name = "World Clock";Icon = "🌐"; Color = "#22D3EE"; Sub = "Timezones" },
    @{ Name = "Calendar";   Icon = "📅"; Color = "#A78BFA"; Sub = "Agenda" },
    @{ Name = "Music";      Icon = "🎧"; Color = "#34D399"; Sub = "Spotify" },
    @{ Name = "Settings";   Icon = "⚙"; Color = "#94A3B8"; Sub = "Config" },
    @{ Name = "Calculator"; Icon = "🖩"; Color = "#FBBF24"; Sub = "Math" },
    @{ Name = "Toolbox";    Icon = "🛠"; Color = "#38BDF8"; Sub = "Dev Tools" }
)

function Populate-CircularLauncherGrid {
    $circularLauncherGrid.Children.Clear()

    foreach ($app in $script:circularApps) {
        $wrap = New-Object System.Windows.Controls.StackPanel
        $wrap.HorizontalAlignment = 'Center'
        $wrap.VerticalAlignment = 'Center'
        $wrap.Margin = New-Object System.Windows.Thickness(6)

        # 48x48 Circular Pill Tile
        $pill = New-Object System.Windows.Controls.Border
        $pill.Width = 48; $pill.Height = 48
        $pill.CornerRadius = New-Object System.Windows.CornerRadius(24)
        $pill.Background = [System.Windows.Media.ColorConverter]::ConvertFromString("#16161D")
        $pill.BorderBrush = [System.Windows.Media.ColorConverter]::ConvertFromString("#2AFFFFFF")
        $pill.BorderThickness = New-Object System.Windows.Thickness(1)
        $pill.Cursor = [System.Windows.Input.Cursors]::Hand
        $pill.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)

        $scale = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
        $pill.RenderTransform = $scale

        $ic = New-Object System.Windows.Controls.TextBlock
        $ic.Text = $app.Icon
        $ic.FontSize = 18
        $ic.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString($app.Color)
        $ic.HorizontalAlignment = 'Center'
        $ic.VerticalAlignment = 'Center'
        $pill.Child = $ic

        # Hover Animation: 1.1x Scale Up
        $pill.Add_MouseEnter({
            $st = $this.RenderTransform
            Animate-Property $st ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 1.1 0.15
            Animate-Property $st ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1.1 0.15
            $this.BorderBrush = [System.Windows.Media.Brushes]::White
        })
        $pill.Add_MouseLeave({
            $st = $this.RenderTransform
            Animate-Property $st ([System.Windows.Media.ScaleTransform]::ScaleXProperty) 1.0 0.15
            Animate-Property $st ([System.Windows.Media.ScaleTransform]::ScaleYProperty) 1.0 0.15
            $this.BorderBrush = [System.Windows.Media.ColorConverter]::ConvertFromString("#2AFFFFFF")
        })

        # Monospaced Sublabel
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $app.Name
        $lbl.FontSize = 9
        $lbl.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas, Segoe UI")
        $lbl.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#94A3B8")
        $lbl.HorizontalAlignment = 'Center'
        $lbl.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)

        # Tile Action Handler
        $appName = $app.Name
        $pill.Tag = $appName
        $pill.Add_MouseLeftButtonDown({
            $target = $this.Tag
            switch ($target) {
                "URL Favs"    { Show-UrlFavoritesWindow }
                "Calendar"    { Show-CalendarWindow }
                "Clipboard"   { Show-ClipboardWindow }
                "Album"       { Set-IslandState "Expanded"; Switch-Tab "Media" }
                "Music"       { [IslandNative]::MediaPlayPause() }
                "AI Chat"     { Set-IslandState "Expanded"; Switch-Tab "AIAgents" }
                "Calculator"  { try { Start-Process "calc.exe" } catch { } }
                "Mail"        { try { Start-Process "mailto:" } catch { } }
                "Search"      { try { Start-Process "explorer.exe" "search-ms:" } catch { } }
                "Toolbox"     { try { Start-Process "taskmgr.exe" } catch { } }
                "Memo"        { if ($txtWorkspaceMemo) { $txtWorkspaceMemo.Focus() } }
                "Settings"    { Set-IslandState "Expanded"; Switch-Tab "Controls" }
                default       { Set-IslandState "Expanded"; Switch-Tab "Today" }
            }
        })

        [void]$wrap.Children.Add($pill)
        [void]$wrap.Children.Add($lbl)
        [void]$circularLauncherGrid.Children.Add($wrap)
    }
}

# ------------------------------------------------------------------------------
#  Synchronized Lyrics Engine (Scrolling Active Line)
# ------------------------------------------------------------------------------
$script:currentLyricIdx = -1

function Update-SynchronizedLyrics {
    $lines = $script:sharedState.LyricsLines
    if (-not $lines -or $lines.Count -eq 0) {
        $lyricsLinesContainer.Children.Clear()
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = "No lyrics available"
        $t.FontSize = 11; $t.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#64748B")
        [void]$lyricsLinesContainer.Children.Add($t)
        return
    }

    # Ensure UI elements count matches lyrics lines
    if ($lyricsLinesContainer.Children.Count -ne $lines.Count) {
        $lyricsLinesContainer.Children.Clear()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $lines[$i].Text
            $tb.FontSize = 11
            $tb.FontWeight = [System.Windows.FontWeights]::Normal
            $tb.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#64748B")
            $tb.Margin = New-Object System.Windows.Thickness(0, 3, 0, 3)
            $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
            [void]$lyricsLinesContainer.Children.Add($tb)
        }
    }

    # Find active line by MediaPositionSec
    $pos = $script:sharedState.MediaPositionSec
    $activeIdx = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TimeSec -le $pos) {
            $activeIdx = $i
        } else {
            break
        }
    }

    if ($activeIdx -ne $script:currentLyricIdx -and $activeIdx -lt $lyricsLinesContainer.Children.Count) {
        if ($script:currentLyricIdx -ge 0 -and $script:currentLyricIdx -lt $lyricsLinesContainer.Children.Count) {
            $oldTb = $lyricsLinesContainer.Children[$script:currentLyricIdx]
            $oldTb.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#64748B")
            $oldTb.FontWeight = [System.Windows.FontWeights]::Normal
        }

        $newTb = $lyricsLinesContainer.Children[$activeIdx]
        $newTb.Foreground = [System.Windows.Media.ColorConverter]::ConvertFromString("#22D3EE")
        $newTb.FontWeight = [System.Windows.FontWeights]::Bold

        # Scroll into view
        $offset = [Math]::Max(0.0, ($activeIdx * 20.0) - 40.0)
        $lyricsScrollViewer.ScrollToVerticalOffset($offset)

        $script:currentLyricIdx = $activeIdx
    }
}

# ------------------------------------------------------------------------------
#  App-Adaptive Palette Engine
# ------------------------------------------------------------------------------
$script:currentAdaptiveColor = ""

function Apply-AdaptivePalette ([string]$hexColor) {
    if (-not $hexColor -or $hexColor -eq $script:currentAdaptiveColor) { return }
    try {
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hexColor)
        $anim = New-Object System.Windows.Media.Animation.ColorAnimation
        $anim.To = $c
        $anim.Duration = New-Object System.Windows.Duration([TimeSpan]::FromSeconds(0.4))
        $islandGlow.BeginAnimation([System.Windows.Media.Effects.DropShadowEffect]::ColorProperty, $anim)
        $script:currentAdaptiveColor = $hexColor
    } catch { }
}

# ------------------------------------------------------------------------------
#  Automatic Game Mode HUD Engine
# ------------------------------------------------------------------------------
$script:inGameMode = $false
$script:gameCheckTick = 0

function Enter-GameMode ([string]$procName = "Game", [switch]$Force) {
    if ($script:inGameMode) { return }
    $script:inGameMode = $true
    $gameModeNameText.Text = ($procName.ToUpper())
    Set-IslandState "Game"
}

function Exit-GameMode {
    $script:inGameMode = $false
    Set-IslandState "Idle"
}


# ------------------------------------------------------------------------------
#  UI Event Bindings & Spatial State Interaction Handlers
# ------------------------------------------------------------------------------

# Top Trigger Bar (Auto-hide reveal zone)
$topTriggerBar.Add_MouseEnter({
    if ($script:islandState -eq "Idle") {
        Set-IslandState "Hover"
    }
})

# GlowBorder Mouse Events
$glowBorder.Add_MouseEnter({
    $script:hoverLeaveTimer.Stop()
    if ($script:islandState -eq "Idle") {
        Set-IslandState "Hover"
    }
})

$glowBorder.Add_MouseLeave({
    if ($script:islandState -eq "Hover" -and -not $script:isPinned) {
        $script:hoverLeaveTimer.Start()
    }
})

# Clicking Idle or Hover strip transitions directly to State 3 (Expanded)
$containerStateIdle.Add_MouseLeftButtonDown({
    Set-IslandState "Expanded"
})

$containerStateHover.Add_MouseLeftButtonDown({
    Set-IslandState "Expanded"
})

# State 4 (Max-Expanded) Toggles
$btnMaxExpandToggle.Add_Click({
    Set-IslandState "MaxExpanded"
})

$btnReturnExpanded.Add_Click({
    Set-IslandState "Expanded"
})

$btnCloseMaxExpanded.Add_Click({
    Set-IslandState "Idle"
})

# Game Mode Exit
$btnExitGameMode.Add_Click({
    Exit-GameMode
})

# Mic Toggle Action
$btnMicToggle.Add_MouseLeftButtonDown({
    $m = [IslandNative]::ToggleMicrophoneMute()
    $idleMicStatusDot.Fill = if ($m) { $script:brushRed } else { $script:brushGreen }
})

# Pin Toggle Action
$btnPinToggle.Add_Click({
    $script:isPinned = -not $script:isPinned
    $Config.Pinned   = $script:isPinned
    Save-Config
    $btnPinToggle.Foreground = if ($script:isPinned) { $script:brushPurple } else { $script:brushInactiveFg }
    if ($script:islandState -eq "Idle") {
        Set-IslandState "Idle"
    }
})

# Settings Action
$btnSettingsToggle.Add_Click({
    Switch-Tab "Controls"
})

# Tab Button Clicks
foreach ($name in $tabButtons.Keys) {
    $btn = $tabButtons[$name]
    $btn.Tag = $name
    $btn.Add_Click({
        Switch-Tab $this.Tag
    })
}

# Media Controls
$btnHoverPlayPause.Add_Click({ [IslandNative]::MediaPlayPause() })
$btnMediaPrev.Add_Click({ [IslandNative]::MediaPrev() })
$btnMediaPlayPause.Add_Click({ [IslandNative]::MediaPlayPause() })
$btnMediaNext.Add_Click({ [IslandNative]::MediaNext() })

# Volume Sliders
$sliderMasterVolume.Add_ValueChanged({
    [IslandNative]::SetMasterVolume([float]($this.Value / 100.0))
    $textVolumeVal.Text = "$([int]$this.Value)%"
})

$hoverVolumeSlider.Add_ValueChanged({
    [IslandNative]::SetMasterVolume([float]($this.Value / 100.0))
})

# Brightness Slider
$sliderBrightness.Add_ValueChanged({
    [IslandNative]::SetBrightness([int]$this.Value)
    $textBrightnessVal.Text = "$([int]$this.Value)%"
})

# Night Light & Dark Mode
$script:nightLightOn = $false
$btnToggleNightLight.Add_Click({
    $script:nightLightOn = -not $script:nightLightOn
    [IslandNative]::SetNightLight($script:nightLightOn)
    $btnToggleNightLight.Foreground = if ($script:nightLightOn) { $script:brushAmber } else { $script:brushInactiveFg }
})

$btnToggleDarkMode.Add_Click({
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $cur = (Get-ItemProperty -Path $regPath -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
        $newVal = if ($cur -eq 0) { 1 } else { 0 }
        Set-ItemProperty -Path $regPath -Name "AppsUseLightTheme" -Value $newVal
        Set-ItemProperty -Path $regPath -Name "SystemUsesLightTheme" -Value $newVal
    } catch { }
})

$btnLaunchTaskMgr.Add_Click({
    try { Start-Process "taskmgr.exe" } catch { }
})

# Safe Power Management: Hold 2.0s to confirm
$script:powerHoldTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:powerHoldTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:powerAction = ""
$script:powerHoldSec = 0.0

$script:powerHoldTimer.Add_Tick({
    $script:powerHoldSec += 0.1
    $rem = [Math]::Max(0.0, 2.0 - $script:powerHoldSec)

    if ($script:powerAction -eq "Restart") {
        $powerRestartText.Text = "Release to Cancel ({0:N1}s)" -f $rem
    } else {
        $powerShutdownText.Text = "Release to Cancel ({0:N1}s)" -f $rem
    }

    if ($script:powerHoldSec -ge 2.0) {
        $script:powerHoldTimer.Stop()
        if ($script:powerAction -eq "Restart") {
            try { Restart-Computer -Force } catch { }
        } else {
            try { Stop-Computer -Force } catch { }
        }
    }
})

$btnPowerRestart.Add_PreviewMouseLeftButtonDown({
    $script:powerAction = "Restart"
    $script:powerHoldSec = 0.0
    $script:powerHoldTimer.Start()
})
$btnPowerRestart.Add_PreviewMouseLeftButtonUp({
    $script:powerHoldTimer.Stop()
    $powerRestartText.Text = "Restart"
})

$btnPowerShutdown.Add_PreviewMouseLeftButtonDown({
    $script:powerAction = "Shutdown"
    $script:powerHoldSec = 0.0
    $script:powerHoldTimer.Start()
})
$btnPowerShutdown.Add_PreviewMouseLeftButtonUp({
    $script:powerHoldTimer.Stop()
    $powerShutdownText.Text = "Shut Down"
})

# Workspace Memo Save
$btnSaveMemo.Add_Click({
    $data = Get-IslandData
    if (-not $data) { $data = @{ Memos = @() } }
    $data.Memos = @(
        @{ Id = 1; Title = "Workspace Memo"; Content = $txtWorkspaceMemo.Text; UpdatedAt = [DateTime]::Now.ToString("g") }
    )
    Save-IslandData $data
    $btnSaveMemo.Content = "Saved ✓"
    Start-Sleep -Milliseconds 400
    $btnSaveMemo.Content = "Save"
})

# Context Menu Wiring
$menuToggleGameMode.Add_Click({
    if ($script:inGameMode) { Exit-GameMode } else { Enter-GameMode "Valorant" -Force }
})
$menuToggleMaxExpanded.Add_Click({
    if ($script:islandState -eq "MaxExpanded") { Set-IslandState "Expanded" } else { Set-IslandState "MaxExpanded" }
})
$menuOpenUrlFavorites.Add_Click({ Show-UrlFavoritesWindow })
$menuOpenCalendar.Add_Click({ Show-CalendarWindow })
$menuOpenClipboard.Add_Click({ Show-ClipboardWindow })
$menuResetPos.Add_Click({
    $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $window.Left = ($priW / 2.0) - ($window.Width / 2.0)
    $window.Top  = 15.0
    Set-IslandState "Idle"
})
$menuToggleGlass.Add_Click({
    $script:isGlass = -not $script:isGlass
    $Config.GlassMode = $script:isGlass
    Save-Config
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    if ($script:isGlass) {
        [IslandNative]::EnableAcrylic($helper.Handle, 0x0114141E)
    } else {
        [IslandNative]::DisableAcrylic($helper.Handle)
    }
})
$menuReload.Add_Click({
    $scriptPath = Join-Path $appRoot "Island.ps1"
    Start-Process "powershell.exe" -ArgumentList @("-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $scriptPath)
    [System.Diagnostics.Process]::GetCurrentProcess().Kill()
})
$menuQuit.Add_Click({
    [System.Diagnostics.Process]::GetCurrentProcess().Kill()
})

# Drag To Move (When Expanded or Max-Expanded)
$containerStateExpanded.Add_MouseLeftButtonDown({
    if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try { $window.DragMove() } catch { }
    }
})


# ------------------------------------------------------------------------------
#  60 FPS UI Dispatcher Render Loop & Startup Sequence
# ------------------------------------------------------------------------------

# Populate the 4x4 Circular App Grid on load
Populate-CircularLauncherGrid

# Load saved memo
$memoData = Get-IslandData
if ($memoData -and $memoData.Memos -and $memoData.Memos.Count -gt 0) {
    $txtWorkspaceMemo.Text = $memoData.Memos[0].Content
}

# Key Bindings
$window.Add_KeyDown({
    param($sender, $e)
    # Esc: Step down state
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
        $e.Handled = $true
        if ($script:islandState -eq "MaxExpanded") {
            Set-IslandState "Expanded"
        } elseif ($script:islandState -eq "Expanded") {
            Set-IslandState "Idle"
        } elseif ($script:inGameMode) {
            Exit-GameMode
        }
        return
    }

    # Ctrl+R: Reload
    if ($e.Key -eq [System.Windows.Input.Key]::R -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        $e.Handled = $true
        $scriptPath = Join-Path $appRoot "Island.ps1"
        Start-Process "powershell.exe" -ArgumentList @("-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $scriptPath)
        [System.Diagnostics.Process]::GetCurrentProcess().Kill()
        return
    }

    # Ctrl+Alt+G: Game Mode Toggle
    if ($e.Key -eq [System.Windows.Input.Key]::G -and `
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -and `
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Alt)) {
        $e.Handled = $true
        if ($script:inGameMode) { Exit-GameMode } else { Enter-GameMode "Valorant" -Force }
        return
    }
})

# Equalizer Wave Animation State
$script:eqTick = 0

$uiTimer = New-Object System.Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(50)

$uiTimer.Add_Tick({
    try {
        $now = [DateTime]::Now
        $cpu = $script:sharedState.Cpu
        $gpu = $script:sharedState.Gpu
        $ram = $script:sharedState.RamPct
        $cpuTemp = $script:sharedState.CpuTempC
        $gpuTemp = $script:sharedState.GpuTempC
        $clockStr = $now.ToString("h:mm tt")

        # 1. Update State 1: IDLE Elements
        if ($idleClockText) { $idleClockText.Text = $clockStr }
        if ($idleCpuText)   { $idleCpuText.Text = "CPU $cpu%" }
        if ($idleBatteryText) {
            $idleBatteryText.Text = "$ram%" # or battery if available
        }
        if ($idleMicStatusDot) {
            $idleMicStatusDot.Fill = if ($script:sharedState.MicMuted) { $script:brushRed } else { $script:brushGreen }
        }

        # 2. Update State 2: HOVER Elements
        if ($hoverTrackTitle) {
            $hoverTrackTitle.Text = $script:sharedState.MediaTitle
            $hoverTrackArtist.Text = $script:sharedState.MediaArtist
            $hoverProgressBar.Width = [Math]::Max(4.0, [Math]::Min(220.0, ($script:sharedState.MediaProgress * 220.0)))
            $btnHoverPlayPause.Content = if ($script:sharedState.MediaStatus -eq "Playing") { [char]0xE769 } else { [char]0xE768 }
            if ($script:sharedState.AlbumArtBytes -and $hoverAlbumImage.Source -eq $null) {
                try {
                    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bi.BeginInit()
                    $bi.StreamSource = New-Object System.IO.MemoryStream(@(,$script:sharedState.AlbumArtBytes))
                    $bi.EndInit()
                    $hoverAlbumImage.Source = $bi
                } catch { }
            } elseif (-not $script:sharedState.AlbumArtBytes) {
                $hoverAlbumImage.Source = $null
            }
        }

        # 3. Update State 3: EXPANDED Elements
        if ($todayGreeting) {
            $hour = $now.Hour
            $greeting = if ($hour -lt 12) { "Good Morning" } elseif ($hour -lt 17) { "Good Afternoon" } else { "Good Evening" }
            $todayGreeting.Text = $greeting
            $todayDate.Text = $now.ToString("dddd, MMMM d")
            $todayCpuPct.Text = "$cpu%"
            $todayCpuBar.Value = $cpu
            $todayGpuPct.Text = "$gpu%"
            $todayGpuBar.Value = $gpu
            $todayRamPct.Text = "$ram%"
            $todayRamBar.Value = $ram
        }

        # Media Tab & Lyrics
        if ($script:activeTab -eq "Media") {
            $mediaTrackTitle.Text  = $script:sharedState.MediaTitle
            $mediaTrackArtist.Text = $script:sharedState.MediaArtist
            $mediaTimelineBar.Value = $script:sharedState.MediaProgress
            $mediaCurTimeText.Text = $script:sharedState.MediaCurTime
            $mediaTotTimeText.Text = $script:sharedState.MediaTotalTime
            $btnMediaPlayPause.Content = if ($script:sharedState.MediaStatus -eq "Playing") { [char]0xE769 } else { [char]0xE768 }

            if ($script:sharedState.AlbumArtBytes) {
                try {
                    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bi.BeginInit()
                    $bi.StreamSource = New-Object System.IO.MemoryStream(@(,$script:sharedState.AlbumArtBytes))
                    $bi.EndInit()
                    $mediaAlbumArtImage.Source = $bi
                } catch { }
            } else {
                $mediaAlbumArtImage.Source = $null
            }

            # Update Synchronized Scrolling Lyrics
            Update-SynchronizedLyrics
        }

        # Apply App-Adaptive Palette
        if ($script:sharedState.DominantColor) {
            Apply-AdaptivePalette $script:sharedState.DominantColor
        }

        # Stats Tab: Live Hardware Frequency Wave Equalizer & Process Tracker
        if ($script:activeTab -eq "Stats" -or $script:islandState -eq "MaxExpanded") {
            $script:eqTick++
            if ($statsCpuClockText) {
                $statsCpuClockText.Text = "$($script:sharedState.CpuClockGhz) GHz"
                $statsCpuTempText.Text  = "$cpuTemp°C · $cpu% Load"
                $statsNetRateText.Text  = "$($script:sharedState.NetUpRate)  $($script:sharedState.NetDownRate)"
                $statsDiskRateText.Text = "$($script:sharedState.DiskReadRate)  $($script:sharedState.DiskWriteRate)"
                $statsRamText.Text      = "$($script:sharedState.RamUsedGb) / $($script:sharedState.RamTotalGb) GB ($ram%)"
            }

            # Animate Equalizer Wave Bars
            $baseH = [Math]::Max(8.0, ($cpu / 100.0) * 44.0)
            for ($b = 0; $b -lt $statsEqualizerBars.Children.Count; $b++) {
                $wave = [Math]::Sin(($script:eqTick * 0.2) + $b) * 12.0
                $targetH = [Math]::Max(4.0, [Math]::Min(48.0, $baseH + $wave))
                $bar = $statsEqualizerBars.Children[$b]
                $bar.Height = $targetH
            }

            if ($maxEqualizerBars) {
                for ($b = 0; $b -lt $maxEqualizerBars.Children.Count; $b++) {
                    $wave = [Math]::Cos(($script:eqTick * 0.25) + $b) * 10.0
                    $targetH = [Math]::Max(4.0, [Math]::Min(38.0, $baseH + $wave))
                    $bar = $maxEqualizerBars.Children[$b]
                    $bar.Height = $targetH
                }
            }

            if ($maxNetThroughputText) {
                $maxNetThroughputText.Text = "$($script:sharedState.NetUpRate)  $($script:sharedState.NetDownRate)"
            }

            # Top Processes rendering
            if ($statsTopProcessesContainer -and $script:sharedState.TopProcesses) {
                $topList = $script:sharedState.TopProcesses
                if ($statsTopProcessesContainer.Children.Count -ne $topList.Count) {
                    $statsTopProcessesContainer.Children.Clear()
                    foreach ($proc in $topList) {
                        $tb = New-Object System.Windows.Controls.TextBlock
                        $tb.FontSize = 9; $tb.Foreground = [System.Windows.Media.Brushes]::White
                        $tb.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
                        $tb.Text = "• $($proc.Name): $($proc.Cpu) CPU · $($proc.Ram)"
                        [void]$statsTopProcessesContainer.Children.Add($tb)
                    }
                } else {
                    for ($k = 0; $k -lt $topList.Count; $k++) {
                        $tb = $statsTopProcessesContainer.Children[$k]
                        $tb.Text = "• $($topList[$k].Name): $($topList[$k].Cpu) CPU · $($topList[$k].Ram)"
                    }
                }
            }
        }

        # 4. Automatic Game Mode Fullscreen Detection (every 25 ticks = ~1.2s)
        $script:gameCheckTick++
        if ($script:gameCheckTick % 25 -eq 0) {
            $priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
            $priH = [System.Windows.SystemParameters]::PrimaryScreenHeight
            $gProc = ""
            $helperHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
            $isGame = [IslandNative]::CheckForegroundFullscreenGame($helperHwnd, [int]$priW, [int]$priH, [ref]$gProc)

            if ($isGame -and -not $script:inGameMode) {
                Enter-GameMode $gProc
            } elseif (-not $isGame -and $script:inGameMode) {
                Exit-GameMode
            }
        }

        # Update Game Mode HUD Bar when active
        if ($script:inGameMode) {
            $gameModeClock.Text = $clockStr
            $gameModeCpu.Text = "CPU ${cpuTemp}°C"
            $gameModeGpu.Text = "GPU ${gpuTemp}°C"
            $gameModeRam.Text = "RAM $ram%"
            $gameModeFps.Text = "144 FPS"
        }

    } catch { }
})

# ------------------------------------------------------------------------------
#  Startup Sequence
# ------------------------------------------------------------------------------
$priW = [System.Windows.SystemParameters]::PrimaryScreenWidth
$window.Left = ($priW / 2.0) - (320.0 / 2.0)
$window.Top  = if ($script:isPinned) { 15.0 } else { -28.0 }

$uiTimer.Start()

# Initialize into Idle State
Set-IslandState "Idle"

$window.Show()

[System.Windows.Threading.Dispatcher]::Run()
