<!-- : Begin batch script Install_Patch.bat
@ECHO OFF

Set BatchFileName="%~f0"
Set BatchFileDir=%~dp0

cscript //nologo "%~f0?.wsf"
rem cscript //nologo //D //x "%~f0?.wsf" ^""%1"^" 'debug version
exit /b

----- Begin wsf script --->

<job><script language="VBScript">
On Error Resume Next

'Admin privileges required!
MakeSureWeAreAdmin

WScript.Echo ""
WScript.Echo "Patch Installation XPhone Connect Server"
WScript.Echo "========================================"
WScript.Echo "Version 1.3"
WScript.Echo ""
WScript.Echo "Patching the XPhone Server will require shutdown of *ALL* XPhone services and applications!"
WScript.Echo "You will be prompted again to verify the shutdown of the services later."
WScript.Echo ""
WScript.Echo "UNDO OPTION: This patch can be completely rolled back! Use Install_Patch.Bat from .\UNDO folder."
WScript.Echo ""
WScript.Echo "Please, press <Enter> to continue..."
WScript.StdIn.ReadLine

Dim HasError
HasError = False

'Global Script Variables
Dim fs
Set fs = CreateObject("Scripting.FileSystemObject")
Dim wsh
Set wsh = CreateObject("WScript.Shell")

INSTALLDIR_XPHONE = ReadFromRegistry("HKEY_LOCAL_MACHINE\SOFTWARE\C4B\XPhoneServer\InstallDir","") ' & "\"
if fs.FolderExists(INSTALLDIR_XPHONE) = False then
	WScript.Echo "XPhone installation folder not found: " & INSTALLDIR_XPHONE,,"ERROR"
	WScript.Quit
End If

INSTALLDIR_COMMON64   = wsh.ExpandEnvironmentStrings("%CommonProgramFiles%") & "\C4B\"
INSTALLDIR_COMMON32   = wsh.ExpandEnvironmentStrings("%CommonProgramFiles(x86)%") & "\C4B\"
INSTALLDIR_POWERSHELL = wsh.ExpandEnvironmentStrings("%ProgramFiles%") & "\WindowsPowerShell\Modules\"

'Set working directory
wsh.CurrentDirectory = wsh.Environment("Process")("BatchFileDir")

'Create UNDO Patch (only if it does not yet exist!)
If fs.FolderExists(wsh.CurrentDirectory & "\UNDO\") = False Then
	WScript.Echo "Create UNDO Patch:"
	CreateUndoFolder "\bin\", INSTALLDIR_XPHONE
	CreateUndoFolder "\common64\", INSTALLDIR_COMMON64
	CreateUndoFolder "\common32\", INSTALLDIR_COMMON32
	CreateUndoFolder "\powershell\", INSTALLDIR_POWERSHELL
	CreateUndoFolderGAC
End If

'Stop Applications
WScript.Echo vbcrlf & "Stopping XPhone applications..."
StopXPhoneApplications
WScript.Echo "...done!"

'Stop Services. Request confirmation!
If AtlasServicesToStop(False) > 0 Then
	WScript.Echo vbcrlf & "Stopping XPhone services:"
	captchaQuery = CreateCaptcha()
	captcha = ""
	Do While captcha <> captchaQuery
		WScript.Echo "PLEASE, CONFIRM SHUTDOWN of all XPhone services:"
		WScript.Echo "   - XPhone Clients will be disconnected"
		WScript.Echo "   - XPhone meetings"
		WScript.Echo "   - XPhone softphone calls"
		WScript.Echo "   - XPhone voicemail and auto-attendants"
		WScript.Echo "   - XPhone fax services"
		WScript.Echo "   - XPhone IIS ApplicationPools"
		WScript.Echo "Type this number now to confirm shutdown: " & captchaQuery
		captcha = WScript.StdIn.ReadLine
		if captcha = captchaQuery then Exit Do
	Loop

	WScript.Echo "Stopping IIS application pools..."
	StopApplicationPools

	WScript.Echo "Stopping services..."
	StopXPhoneServices
	WScript.Echo "...done!"
End If

'Copy files
Err.Clear
WScript.Echo vbcrlf & "Patch(es) will now be installed:" 
XCopyFilesEnum wsh.CurrentDirectory & "\bin\", 			INSTALLDIR_XPHONE, 		" - Program installation folder: "
XCopyFilesEnum wsh.CurrentDirectory & "\common64\", 	INSTALLDIR_COMMON64, 	" - Common files folder (x64): " & vbTab
XCopyFilesEnum wsh.CurrentDirectory & "\common32\", 	INSTALLDIR_COMMON32, 	" - Common files folder (x86): " & vbTab
XCopyFilesEnum wsh.CurrentDirectory & "\powershell\", 	INSTALLDIR_POWERSHELL, 	" - Powershell Extension: " & vbTab

if fs.FileExists(wsh.CurrentDirectory & "\gac\GAC_Install.Bat") then 
	WScript.Echo vbTab & " - Global Assembly Cache (GAC):"
	set gacFolder = fs.GetFolder(wsh.CurrentDirectory & "\gac\")
	Set gacFiles = gacFolder.Files
	For Each gacFile in gacFiles
		if InStr(1, gacFile.Name, ".dll") > 0 Then
			WScript.Echo vbTab & "   " & gacFile.Name
		End If
	Next
	cmd = """" & wsh.CurrentDirectory & "\gac\GAC_Install.Bat"""
	wsh.Run cmd, 1, True
	if Err <> 0 then
		WScript.Echo "ERROR: " & Err.Description
		Err.Clear
	End If
End If

if Err <> 0 or HasError then
	WScript.Echo vbcrlf & "ERROR while installing the patch. Have a closer look at the console output!"
else	
	WScript.Echo vbcrlf & "The patch has been installed successfully!"
End If

WScript.Echo "Starting IIS application pools..."
StartApplicationPools


WScript.Echo vbcrlf & "Press <Enter> to close the console window and start the XPhone Connect Server Manager..."
WScript.StdIn.ReadLine
wsh.run """" & INSTALLDIR_XPHONE & "ServerMng.exe" & """"
WScript.Quit

'--------------------------------------------------------------------------------------------------------------------------
' Helper Functions
'--------------------------------------------------------------------------------------------------------------------------

Private Sub MakeSureWeAreAdmin
	if IsAdmin() = False then
		'WScript.Echo "This script requires admin privileges."
		'WScript.Echo "Press <Enter> to continue..."
		'WScript.StdIn.ReadLine

		'Restart with Admin privileges
		BatchFileName = CreateObject("WScript.Shell").Environment("Process")("BatchFileName")
		CreateObject("Shell.Application").ShellExecute "cmd.exe", "/c """ & BatchFileName & """", "", "runas", 1

		WScript.Quit
	end if
End Sub

Private Function IsAdmin()
    On Error Resume Next
    CreateObject("WScript.Shell").RegRead("HKEY_USERS\S-1-5-19\Environment\TEMP")
	IsAdmin = (Err.number = 0)
    Err.Clear
End Function

Private Function ReadFromRegistry(ByVal strRegistryKey, ByVal strDefault)
	Dim  value

	On Error Resume Next
	value = CreateObject("WScript.Shell").RegRead( strRegistryKey )

	If Err.Number <> 0 then
	ReadFromRegistry = strDefault
		Err.Clear
	else
		ReadFromRegistry = value
	End if
End Function

Private Function AtlasServicesToStop(ByVal bStopService)
	On Error Resume Next
	count = 0
	
	Dim wmi
	Set wmi = GetObject("winmgmts:")

    Set qsvc = wmi.ExecQuery( _
        "SELECT * FROM Win32_Service " & _
        "WHERE Name Like 'Atlas%'")

    For Each svc In qsvc
		if svc.Started then
			count = count + 1
			'WScript.ECHO svc.Name & ": " & svc.State
			if svc.State = "Running" then 
				if bStopService then svc.StopService
			End If
		End If
    Next

	AtlasServicesToStop = count
End Function

Private Sub StopXPhoneApplications
	On Error Resume Next
	wsh.Run "taskkill /f /im ServerMng.Exe", 0, True
	wsh.Run "taskkill /f /im VDirAdmin.Exe", 0, True
	wsh.Run "taskkill /f /im DBExplorer.Exe", 0, True
	wsh.Run "taskkill /f /im SupportInfoCollector.Exe", 0, True
	wsh.Run "taskkill /f /im DialParamMng.Exe", 0, True
	Err.Clear
End Sub

Private Sub StopXPhoneServices
	On Error Resume Next
	ServerStartupMeterOld = "undefined" 
	MustStopCountOld = 0
	MustStopCount = AtlasServicesToStop(True)
	While MustStopCount > 0
		if MustStopCount <> MustStopCountOld then 
			WScript.Echo "   #XPhone services to stop: " & MustStopCount & ", please wait..."
		End If
		If MustStopCount = 1 then
			ServerStartupMeter = ReadFromRegistry("HKEY_LOCAL_MACHINE\SOFTWARE\C4B\XPhoneServer\ServerState\ServerStartupMeter", "0")
			ServerStartupInfo = ReadFromRegistry("HKEY_LOCAL_MACHINE\SOFTWARE\C4B\XPhoneServer\ServerState\ServerStartupInfo", "")
			if ServerStartupMeter <> ServerStartupMeterOld Then
				WScript.Echo "   " & ServerStartupMeter & "% - " & ServerStartupInfo
				ServerStartupMeterOld = ServerStartupMeter
			End If
		End If
		WScript.Sleep 200
		
		MustStopCountOld = MustStopCount
		MustStopCount = AtlasServicesToStop(True)
	WEnd
	Err.Clear
End Sub

Private Sub XCopyFilesEnum(ByVal sourceDir, ByVal targetDir, ByVal description)
	if fs.FolderExists(sourceDir) then 
		If description <> "" then WScript.Echo vbTab & description & targetDir

		EnumFolderAndCopy fs.GetFolder(sourceDir), fs.GetFolder(targetDir), fs.GetFolder(sourceDir)
	End If
End Sub

Private Sub EnumFolderAndCopy(PatchFolder, XPhoneFolder, RootFolder)
	On Error Resume Next
	
    Set PatchFiles = PatchFolder.Files
    For Each PatchFile in PatchFiles
		SourcePath = PatchFolder.Path & "\" & PatchFile.Name
		TargetPath = Replace(SourcePath, RootFolder.Path, XPhoneFolder.Path)

        Log "SourcePath = " & SourcePath
        Log "TargetPath = " & TargetPath
		
		DumpPath = SourcePath
		DumpPath = Replace(DumpPath, RootFolder, ".")
		Wscript.Echo vbTab & "   " & DumpPath

		if fs.FileExists(TargetPath) then
			Err.Clear
			fs.DeleteFile TargetPath, True
			if (Err <> 0) Or fs.FileExists(TargetPath) Then
				WScript.Echo "ERROR DeleteFile(): " & TargetPath
				Err.Clear
			Else
				Log "DELETE " & TargetPath
			End If 
		End If
		
		Err.Clear
		fs.CopyFile SourcePath, TargetPath, True

		if Err <> 0 then
			WScript.Echo "ERROR CopyFile(): " & TargetPath
			HasError = True
			Err.Clear
		Else
        	Log "COPY FROM " & SourcePath & " ==> " & TargetPath
		End If

		Log ""
    Next
	
    For Each Subfolder in PatchFolder.SubFolders
        EnumFolderAndCopy Subfolder, XPhoneFolder, RootFolder
    Next
End Sub


Private Sub XCopyFiles (ByVal sourceDir, ByVal targetDir, ByVal description)
	if fs.FolderExists(sourceDir) then 
		If description <> "" then WScript.Echo vbTab & description & targetDir
		cmd = "cmd /c xcopy """ & sourceDir & "*.*"" """ & targetDir & """ /S/Y"
		wsh.Run cmd, 0, True
		if Err <> 0 then
			'WScript.Echo "ERROR: " & Err.Description
			Err.Clear
		End If
	End If
End Sub

Private Sub CreateUndoFolder(ByVal FolderShortcut, Byval XPhoneFolderPath)
	On Error Resume Next
	folder = wsh.CurrentDirectory & FolderShortcut
	if fs.FolderExists(folder) Then
		Err.Clear
		UndoFolderDir = wsh.CurrentDirectory & "\UNDO\"
		UndoFolderPath = wsh.CurrentDirectory & "\UNDO" & FolderShortcut
		If fs.FolderExists(UndoFolderPath) = False Then
			WScript.Echo "Create UNDO Folder: " & ".\UNDO" & FolderShortcut
			fs.CreateFolder UndoFolderDir
			fs.CreateFolder UndoFolderPath
			fs.CopyFile wsh.CurrentDirectory & "\Install_Patch.Bat", UndoFolderDir & "Install_Patch.Bat", True
			EnumFolder fs.GetFolder(folder), fs.GetFolder(UndoFolderPath), fs.GetFolder(XPhoneFolderPath), fs.GetFolder(folder)
		End If
	End If
End Sub

Private Sub Log (ByVal txt)
	'Wscript.Echo txt
End Sub

Private Sub EnumFolder(PatchFolder, UndoFolder, XPhoneFolder, RootFolder)
	On Error Resume Next
	
	undoDir = Replace(PatchFolder.Path, RootFolder.Path, UndoFolder.Path)
	fs.CreateFolder undoDir
	Log "undoDir = " & undoDir
	
    Set PatchFiles = PatchFolder.Files
    For Each PatchFile in PatchFiles
		SourcePath = PatchFolder.Path & "\" & PatchFile.Name
        Log "SourcePath = " & SourcePath
		
		SourceXphone = Replace(SourcePath, RootFolder.Path, XPhoneFolder.Path)
        Log "SourceXphone = " & SourceXphone
		
		TargetBackup = Replace(SourceXphone, XPhoneFolder.Path, UndoFolder.Path)
        Log "TargetBackup = " & TargetBackup
		
		TargetDir = Replace(TargetBackup, PatchFile.Name, "")
        Log "TargetDir = " & TargetDir
		fs.CreateFolder TargetDir
		
		Err.Clear
        Log "COPY FROM " & SourceXphone & " TO " & TargetBackup
		fs.CopyFile SourceXphone, TargetBackup, True
		if Err <> 0 then
			WScript.Echo "ERROR file copy: " & SourceXphone
			Err.Clear
		End If

		Log ""
    Next
	
    For Each Subfolder in PatchFolder.SubFolders
        EnumFolder Subfolder, UndoFolder, XPhoneFolder, RootFolder
    Next
End Sub

Private Function CreateCaptcha()
	c = ""
	dim r
	for i = 1 to 4 
		randomize
		r = int(rnd*9) + 1
		c = c & CStr(r)
	next
	
	CreateCaptcha = c
End Function

Private Function FindAssemblyInGAC(component)
	On Error Resume Next
	assemblyPath = ""
	
	component = Replace(component, ".dll", "")

	gacRoot = fs.GetSpecialFolder(0).Path & "\Microsoft.NET\assembly\GAC_MSIL\" & component & "\"
	Set gacFolder = fs.GetFolder(gacRoot)
	
	For Each Subfolder in gacFolder.SubFolders
		Set gacFiles = Subfolder.Files
		For Each gacFile in gacFiles
			if InStr(1, gacFile.Name, component) > 0 Then
				assemblyPath =  gacFile.Path
			End If
		Next
	Next
	
	FindAssemblyInGAC = assemblyPath
End Function

Private Sub CreateUndoFolderGAC
	Err.Clear
	On Error Resume Next
	FolderShortcut = "\gac\"

	UndoFolderDir = wsh.CurrentDirectory & "\UNDO\"
	UndoFolderPath = wsh.CurrentDirectory & "\UNDO" & FolderShortcut
	If fs.FolderExists(UndoFolderPath) = False Then
		gacPatchDir = wsh.CurrentDirectory & FolderShortcut
		if fs.FolderExists(gacPatchDir) Then

			WScript.Echo "Create UNDO Folder: " & ".\UNDO" & FolderShortcut
			fs.CreateFolder UndoFolderDir
			fs.CreateFolder UndoFolderPath
			
			XCopyFiles gacPatchDir,	UndoFolderPath, ""

			Set gacPatchFolder = fs.GetFolder(gacPatchDir)
			Set gacPatchFiles = gacPatchFolder.Files
			for Each gacPatchFile in gacPatchFiles
				if Instr(1, gacPatchFile, ".dll") then
					'MsgBox FindAssemblyInGAC(gacPatchFile.Name)
					Err.Clear
					fs.CopyFile FindAssemblyInGAC(gacPatchFile.Name), UndoFolderPath & gacPatchFile.Name, True
					fs.CopyFile wsh.CurrentDirectory & "\Install_Patch.Bat", UndoFolderDir & "Install_Patch.Bat", True
				End If
			Next
		End If

	End If
End Sub

Private Sub StopAppPoolName( ByVal AppPoolName )
	On Error Resume Next
	ComputerName = "LocalHost"

	Set objIIS = GetObject ("IIS://" & ComputerName & "/W3SVC/AppPools/" & AppPoolName)
	If objIIS is Nothing Then Exit Sub
	if Err <> 0 then
		WScript.Echo "ERROR getting IIS AppPool " & AppPoolName & ". " & Err.Description
		Err.Clear
		Exit Sub
	End If	
	objIIS.Stop
	if Err <> 0 then
		WScript.Echo "ERROR stopping IIS AppPool " & AppPoolName & ". " & Err.Description
		Err.Clear
	End If	
End Sub

Private Sub StartAppPoolName( ByVal AppPoolName )
	On Error Resume Next
	ComputerName = "LocalHost"

	Set objIIS = GetObject ("IIS://" & ComputerName & "/W3SVC/AppPools/" & AppPoolName)
	If objIIS is Nothing Then Exit Sub
	if Err <> 0 then
		WScript.Echo "ERROR getting IIS AppPool " & AppPoolName & ". " & Err.Description
		Err.Clear
		Exit Sub
	End If	
	objIIS.Start
	if Err <> 0 then
		WScript.Echo "ERROR starting IIS AppPool " & AppPoolName & ". " & Err.Description
		Err.Clear
	End If	
End Sub


Private Sub RecycleAppPoolName( ByVal AppPoolName )
	On Error Resume Next
	ComputerName = "LocalHost"

	Set objIIS = GetObject ("IIS://" & ComputerName & "/W3SVC/AppPools/" & AppPoolName)
	If objIIS is Nothing Then Exit Sub
	if Err <> 0 then
		WScript.Echo "ERROR getting IIS AppPool " & AppPoolName & ". " & Err.Description
		Err.Clear
		Exit Sub
	End If	
	objIIS.Recycle
	if Err <> 0 then
		WScript.Echo "ERROR recycling IIS AppPool " & AppPoolName & ". " & Err.Description
		Err.Clear
	End If	
End Sub

Private Sub StopApplicationPools

	StopAppPoolName "XPhoneConnectSites"
	StopAppPoolName "XPhoneConnectAnalytics"
	StopAppPoolName "XPhoneConnectMobile"
	StopAppPoolName "XPhoneConnectWebClientApi"
	StopAppPoolName "XPhoneConnectPushProxy"
	StopAppPoolName "XPhoneConnectNetCore"
	StopAppPoolName "XPhoneConnectApi"

End Sub

Private Sub StartApplicationPools

	StartAppPoolName "XPhoneConnectSites"
	StartAppPoolName "XPhoneConnectAnalytics"
	StartAppPoolName "XPhoneConnectMobile"
	StartAppPoolName "XPhoneConnectWebClientApi"
	StartAppPoolName "XPhoneConnectPushProxy"
	StartAppPoolName "XPhoneConnectNetCore"
	StartAppPoolName "XPhoneConnectApi"

End Sub

</script></job>
