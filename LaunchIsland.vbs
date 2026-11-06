' ============================================================================
' LaunchIsland.vbs — Silent launcher for Dynamic Island
' ============================================================================
' Purpose:  Launches Island.ps1 completely hidden — no console window flash,
'           no taskbar blip. Ideal for use in Startup shortcuts or scheduled
'           tasks where a silent launch is required.
'
' Usage:    Double-click, or create a shortcut targeting:
'             wscript.exe "C:\path\to\LaunchIsland.vbs"
'
' Notes:    - Place this file in the same folder as Island.ps1
'           - Uses -WindowStyle Hidden so PowerShell never shows a window
'           - The VBScript Run method's third param (0) hides the cmd host too
' ============================================================================

' --- Resolve the directory this script lives in ---------------------------------
' This ensures the launcher works regardless of the current working directory
' (e.g., when triggered from a shortcut whose "Start in" differs).
Dim fso, strScriptDir, strIslandPs1
Set fso = CreateObject("Scripting.FileSystemObject")
strScriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
strIslandPs1 = fso.BuildPath(strScriptDir, "Island.ps1")

' --- Validate that Island.ps1 exists -------------------------------------------
If Not fso.FileExists(strIslandPs1) Then
    MsgBox "Error: Cannot find Island.ps1 in:" & vbCrLf & strScriptDir, _
           vbCritical, "Dynamic Island Launcher"
    WScript.Quit 1
End If

' --- Launch PowerShell hidden ---------------------------------------------------
' Parameters for WScript.Shell.Run:
'   command  — powershell with all necessary flags
'   0        — window style: SW_HIDE (completely hidden)
'   False    — don't wait for the process to finish
Dim objShell
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strIslandPs1 & """", 0, False

' --- Clean up -------------------------------------------------------------------
Set objShell = Nothing
Set fso = Nothing
