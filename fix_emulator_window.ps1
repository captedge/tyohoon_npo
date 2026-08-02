# Typhoon Ship Tracker - workaround for the Android emulator window
# sometimes opening off-screen. Launched in the background by
# run_android.bat / run_android_personal.bat. Once the emulator window is
# found, it is forced to a fixed on-screen position and size.
# Carried over as-is from the ShipsTime project (same shared AVD,
# ShipsTime_Test - see docs/flutter-android-env-notes.md), which uses the
# same window-title match and has this working already.

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinTool {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@

$global:targetFound = $false

for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 2

    [WinTool]::EnumWindows({
        param($hWnd, $lParam)
        if ([WinTool]::IsWindowVisible($hWnd)) {
            $sb = New-Object System.Text.StringBuilder 256
            [WinTool]::GetWindowText($hWnd, $sb, 256) | Out-Null
            $title = $sb.ToString()
            if ($title -match "ShipsTime_Test" -or $title -match "Android Emulator") {
                [WinTool]::ShowWindow($hWnd, 9) | Out-Null   # SW_RESTORE
                [WinTool]::MoveWindow($hWnd, 100, 60, 420, 820, $true) | Out-Null
                [WinTool]::SetForegroundWindow($hWnd) | Out-Null
                $global:targetFound = $true
            }
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null

    if ($global:targetFound) { break }
}
