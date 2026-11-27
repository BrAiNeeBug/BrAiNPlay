#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=brainplay.ico
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
;v5_ffline 27.11.2026
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <ListBoxConstants.au3>
#include <EditConstants.au3>
#include <Array.au3>
#include <Math.au3>
#include <Date.au3>
#include <File.au3>
#include <TrayConstants.au3>
#include <StructureConstants.au3>
#include <WinAPISys.au3>
#include <WinAPIGdi.au3>
#include <WinAPISysWin.au3>

Global $oComErr = ObjEvent("AutoIt.Error", "_Err") ; keep this variable: the COM error handler lives only as long as it exists
OnAutoItExitRegister("_Quit")
Opt("TrayMenuMode", 3) ; no default AutoIt tray menu
Opt("TrayIconHide", 1) ; tray icon only while minimized

Global Const $BG = 0x14141A, $PNL = 0x1E1E26, $DIM = 0x2B2B36, $OFF = 0x6A6A78, $ACC = 0x00F0B5, $TXT = 0xD0D0DA, $N = 40
Global Const $VX = 90, $VW = 140, $BX = 325, $BW = 130, $NV = 14, $NB = 13 ; volume / balance segment geometry

; --- settings + last playlist live in %APPDATA%\BrAiNPlay ---
Global $sApp = @AppDataDir & "\BrAiNPlay", $sIni = $sApp & "\brainplay.ini", $sLast = $sApp & "\last.m3u"
DirCreate($sApp)
Global $fLog = (IniRead($sIni, "general", "log", "1") = "1"), $fMKeys = (IniRead($sIni, "general", "mediakeys", "1") = "1"), $fKeepAw = (IniRead($sIni, "general", "keepawake", "1") = "1"), $fSavePL = (IniRead($sIni, "general", "saveplaylist", "1") = "1"), $fDbg = (IniRead($sIni, "general", "debug", "1") = "1") ; options window
Global $fNoShell = False, $fWine = _IsWine() ; Shell.Application missing (Wine / Linux) -> native fallbacks for length + tags
If $fWine Then $fNoShell = True ; Wine: never touch the Shell COM objects
Global $aTp[0], $aTc[0], $aTs[0], $fOpt = False ; toggle widgets of the options window
If FileGetSize($sApp & "\brainplay.log") > 1048576 Then FileMove($sApp & "\brainplay.log", $sApp & "\brainplay.log.old", 1) ; keep the log small

Global $aPl[0], $aLn[0], $iCur = -1, $iLen = 0, $tCmd = 0, $iOff = 0, $tRun = 0, $tStart = 0, $fFixed = False, $sTmp = @TempDir & "\BrAiNPlay_clean.mp3", $fPlay = False, $fPause = False, $iLit = -1, $aSeg[$N], $sNow = ""
Global $fShuf = (IniRead($sIni, "player", "shuf", "0") = "1"), $fLoop = (IniRead($sIni, "player", "loop", "0") = "1")
Global $aBR = StringSplit("0|32|40|48|56|64|80|96|112|128|160|192|224|256|320", "|", 2), $aSR[3] = [44100, 48000, 32000]
Global $iVol = _Min(_Max(Int(IniRead($sIni, "player", "vol", 80)), 0), 100), $iBal = _Min(_Max(Int(IniRead($sIni, "player", "bal", 0)), -100), 100)
Global $iPre = 80, $iDrag = 0, $iErr = 0, $iHov = 0, $aV[$NV], $aB[$NB]
Global $sExt = "mp3|wav|wma|mp4|m4v|avi|wmv|mpg|mpeg|mov|mkv|webm|vob|m2ts|ts", $sVid = "mp4|m4v|avi|wmv|mpg|mpeg|mov|mkv|webm|vob|m2ts|ts" ; playable / video extensions
Global $fVid = False, $fVidOn = (IniRead($sIni, "player", "video", "1") = "1"), $fTray = False, $iVSz = 0, $fEmb = False, $iWSt = -1 ; video: current track is video / window wanted (remembered) / minimized to tray / fitted

; --- video window: borderless panel docked at the player's side (fixed size, from the ini) or fullscreen on the player's monitor ---
Global $iWw = Int(IniRead($sIni, "video", "dockw", 640)), $iWh = Int(IniRead($sIni, "video", "dockh", 360))
If $iWw < 320 Or $iWh < 180 Then
	$iWw = 640
	$iWh = 360
EndIf
Global $hVid = 0, $fFull = (IniRead($sIni, "player", "full", "1") = "1"), $fVidShown = False, $sPos = "", $sWin = "", $iSty = 0, $iMon = 0, $fWFS = False, $fClick = (IniRead($sIni, "video", "clickmode", "1") = "1"), $tChg = 0, $bDown = False, $tPoll = 0
Global $fMq = False, $iMqSock = -1, $sMqHost = "", $iMqPort = 1883, $sMqUser = "", $sMqPass = "", $sMqBase = @ComputerName, $sMqPre = "homeassistant", $fMqDisc = True, $sMqId = "" ; MQTT settings
Global $tMqTry = 0, $tMqPing = 0, $sMqBuf = "", $sMqLast = "", $tMqPub = 0, $sTagA = "", $sTagT = "", $sTagAl = "" ; MQTT state / tags of the current track
Global $iZoom = 100, $tNote = 0, $hOsd = 0, $lblOsd = 0, $tOsd = 0, $iOsdMs = 3000, $fWK = False ; video zoom % / temporary note / on-screen display / global keys while WMP is fullscreen
Global $fPL = (IniRead($sIni, "player", "plist", "1") = "1"), $fCurOn = True, $iMx = -1, $iMy = -1, $tMouse = 0, $fAwake = False ; playlist shown / mouse cursor visible + last position / keeping the screen awake
; Video engine order: MCI first (light, uses installed codecs). Only if MCI can't play a video, the Windows Media Player control
; is created (lazily, on first need) inside the video window as a backup. Audio never touches WMP.
Global $oWMP = 0, $idWMP = 0, $fWmp = False, $iWInit = 0
; --- optional external engine: ffplay (downloaded into %APPDATA%\BrAiNPlay\ffmpeg, refreshed every 30 days) ---
; MCI stays as it is. With the option on and ffplay.exe present, ffplay plays everything (audio: hidden, video: its window sits inside our video window)
Global $fFF = (IniRead($sIni, "ffplay", "enabled", "0") = "1"), $sFFDir = $sApp & "\ffmpeg", $sFFPlay = $sFFDir & "\ffplay.exe"
Global $aFFUrl[2] = [IniRead($sIni, "ffplay", "url", "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"), "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"]
Global $iFFPid = 0, $hFF = 0, $fFFrun = False, $fFFWait = False, $sFFFile = "", $iFFw = 0, $iFFh = 0, $iFFV = 0, $iFFB = 0, $tFFSeek = 0, $tFFVol = 0, $iFFWw = 0, $iFFWh = 0, $sFFMode = "", $sFFWant = "", $tFFChg = 0, $sFFKeys = ""
Global $iFFDl = 0, $hFFDl = 0, $iFFProc = 0, $iFFTry = 0, $sFFStat = "", $sFFNew = ""
_Log("start | " & ($fWine ? "WINE | " : "") & "WMP installed: " & (RegRead("HKEY_CLASSES_ROOT\WMPlayer.OCX\CLSID", "") <> "" ? "yes" : "NO") & " | AutoIt " & @AutoItVersion & (@AutoItX64 ? " x64" : " x86") & " | OS " & @OSVersion & " " & @OSArch)

Global $hMain = GUICreate("BrAiNPlay", 480, 540, -1, -1, $WS_POPUP, $WS_EX_ACCEPTFILES)
GUISetBkColor($BG)
GUISetFont(10, 400, 0, "Segoe UI")
Local $idA = GUICtrlCreateDummy() ; marker: first control of the player window

; --- header (drag the title to move the window) ---
Global $bOpt = GUICtrlCreateLabel("B r A i N P L A Y", 20, 14, 110, 24)
GUICtrlSetColor(-1, $OFF)
GUICtrlSetFont(-1, 11, 700)
Global $bClose = _X("X", 426), $bMin = _X("-", 376) ; classic ASCII symbols for Windows/Wine compatibility
Global $bTV = _X("TV", 326) ; TV button: only visible while a video is playing
GUICtrlSetState($bTV, $GUI_HIDE)
Global $lblNow = GUICtrlCreateLabel("stopped", 20, 50, 440, 24)
GUICtrlSetColor(-1, $TXT)

; --- abstract waveform progress (click = seek) ---
Local $h
For $i = 0 To $N - 1
	$h = _Def($i)
	$aSeg[$i] = GUICtrlCreateLabel("", 20 + $i * 11, 110 - Int($h / 2), 7, $h)
	GUICtrlSetBkColor(-1, $DIM)
Next
Global $lblTime = GUICtrlCreateLabel("00:00 / --:--", 20, 150, 440, 24, $SS_CENTER)
GUICtrlSetColor(-1, $ACC)
GUICtrlSetFont(-1, 12, 700)

; --- controls ---
Global $bPrev = _B("|<", 20, 185, 60, 44, $ACC), $bPlay = _B(">", 90, 185, 100, 44, $ACC)
Global $bStop = _B("[]", 200, 185, 60, 44, $ACC), $bNext = _B(">|", 270, 185, 60, 44, $ACC)
Global $bShuf = _B("SHUF", 340, 185, 55, 44, $fShuf ? $ACC : $OFF), $bLoop = _B("LOOP", 405, 185, 55, 44, $fLoop ? $ACC : $OFF)

; --- volume + balance (segments, click / drag) ---
Global $lblVol = GUICtrlCreateLabel("", 20, 246, 66, 22, $SS_CENTERIMAGE)
GUICtrlSetColor(-1, $TXT)
Global $lblBal = GUICtrlCreateLabel("", 250, 246, 70, 22, $SS_CENTERIMAGE)
GUICtrlSetColor(-1, $TXT)
For $i = 0 To $NV - 1
	$h = 6 + $i
	$aV[$i] = GUICtrlCreateLabel("", $VX + $i * 10, 268 - $h, 8, $h)
Next
For $i = 0 To $NB - 1
	$h = ($i = 6) ? 22 : 12
	$aB[$i] = GUICtrlCreateLabel("", $BX + $i * 10, 257 - Int($h / 2), 8, $h)
Next

; --- playlist ---
Global $bPL = _B("", 20, 280, 440, 22, $TXT, 9) ; playlist toggle bar (also accepts dropped files)
GUICtrlSetState($bPL, $GUI_DROPACCEPTED)
Global $lst = GUICtrlCreateList("", 20, 306, 440, 175, BitOR($LBS_NOTIFY, $WS_VSCROLL))
GUICtrlSetBkColor(-1, $PNL)
GUICtrlSetColor(-1, $TXT)
GUICtrlSetState(-1, $GUI_DROPACCEPTED)
Global $bAddF = _B("+ FILES", 20, 490, 70, 34, $TXT, 9), $bAddD = _B("+ FOLDER", 94, 490, 70, 34, $TXT, 9)
Global $bDel = _B("REMOVE", 168, 490, 70, 34, $TXT, 9), $bClr = _B("CLEAR", 242, 490, 70, 34, $TXT, 9)
Global $bSave = _B("SAVE", 316, 490, 70, 34, $TXT, 9), $bLoad = _B("LOAD", 390, 490, 70, 34, $TXT, 9)

; --- keyboard: in-window keys (like VLC & co.) ---
Global $kPlay = GUICtrlCreateDummy(), $kStop = GUICtrlCreateDummy(), $kNext = GUICtrlCreateDummy(), $kPrev = GUICtrlCreateDummy(), $kBack = GUICtrlCreateDummy()
Global $kFwd = GUICtrlCreateDummy(), $kVU = GUICtrlCreateDummy(), $kVD = GUICtrlCreateDummy(), $kMute = GUICtrlCreateDummy(), $kDel = GUICtrlCreateDummy(), $kTV = GUICtrlCreateDummy(), $kFull = GUICtrlCreateDummy(), $kWin = GUICtrlCreateDummy(), $kEsc = GUICtrlCreateDummy(), $kZI = GUICtrlCreateDummy(), $kZO = GUICtrlCreateDummy(), $kZ0 = GUICtrlCreateDummy(), $kAud = GUICtrlCreateDummy(), $kMon = GUICtrlCreateDummy(), $kOpt = GUICtrlCreateDummy()
Local $aK[22][2] = [["{SPACE}", $kPlay], ["s", $kStop], ["n", $kNext], ["p", $kPrev], ["{LEFT}", $kBack], ["{RIGHT}", $kFwd], ["^{UP}", $kVU], ["^{DOWN}", $kVD], ["m", $kMute], ["{DEL}", $kDel], ["v", $kTV], ["f", $kFull], ["w", $kWin], ["{ESC}", $kEsc], ["{+}", $kZI], ["{NUMPADADD}", $kZI], ["-", $kZO], ["{NUMPADSUB}", $kZO], ["0", $kZ0], ["a", $kAud], ["d", $kMon], ["o", $kOpt]]
GUISetAccelerators($aK, $hMain)
Local $idZ = GUICtrlCreateDummy() ; marker: last control of the player window
For $i = $idA To $idZ
	GUICtrlSetResizing($i, $GUI_DOCKALL) ; fixed position + size: changing the window height must not squeeze the controls
Next
; --- keyboard: global multimedia keys (work while minimized to tray) ---
Global $tMK = 0, $tMKp = 0 ; media keys: time of the last key event (ignores auto-repeat of a held key)
_MediaKeys($fMKeys) ; play/pause, next (hold = fast forward), previous (hold = rewind), stop

; --- video window: owned by the player (stays above it, hides with it, no taskbar button), never takes the keyboard focus ---
$hVid = GUICreate("BrAiNPlay Video", $iWw, $iWh, -1, -1, BitOR($WS_POPUP, $WS_CLIPCHILDREN), $WS_EX_NOACTIVATE, $hMain)
GUISetBkColor(0x000000, $hVid)
$hOsd = GUICreate("", 400, 40, 0, 0, $WS_POPUP, BitOR($WS_EX_TOPMOST, $WS_EX_TOOLWINDOW, $WS_EX_NOACTIVATE), $hMain) ; OSD: topmost text strip above the video
GUISetBkColor($BG, $hOsd)
$lblOsd = GUICtrlCreateLabel("", 12, 6, 376, 28)
GUICtrlSetColor($lblOsd, $TXT)
GUICtrlSetFont($lblOsd, 15, 700, 0, "Segoe UI")
GUICtrlSetResizing($lblOsd, $GUI_DOCKALL)
WinSetTrans($hOsd, "", 225)
GUISwitch($hMain)
_PLApply()

GUISetState(@SW_SHOW, $hMain)
_Apply()
If $fSavePL And FileExists($sLast) Then _LoadList($sLast)
_MqInit()
_FFAuto()
Local $tUI = TimerInit(), $s, $a, $c, $f, $m
While 1
	$m = GUIGetMsg(1) ; advanced mode: $m[0] = event, $m[1] = window the event came from
	Switch $m[0]
		Case $GUI_EVENT_CLOSE
			If $m[1] = $hVid Then ; X on the video window only hides it
				If Not $fFull And Not $fWmp Then _MonRemember()
				$fVidOn = False
				_VidApply()
			Else
				ExitLoop
			EndIf
		Case $bClose
			ExitLoop
		Case $kFull
			_VidKey("f")
		Case $kWin
			_VidKey("w")
		Case $kEsc
			_VidKey("esc")
		Case $kZI
			_Zoom(10)
		Case $kZO
			_Zoom(-10)
		Case $kZ0
			_Zoom(0)
		Case $kAud
			_AudioTrack()
		Case $kMon
			_NextMonitor()
		Case $bOpt, $kOpt
			_Options()
		Case $bTV, $kTV ; TV button: show / hide the video window (state is remembered)
			If $fPlay And $fVid Then
				$fVidOn = Not $fVidOn
				_VidApply()
			EndIf
		Case $bMin ; minimize to tray
			GUISetState(@SW_HIDE, $hMain)
			$fTray = True
			_VidApply()
			TraySetState(1)
			_Tip()
		Case $GUI_EVENT_PRIMARYDOWN ; waveform = seek, bars = volume / balance
			$c = GUIGetCursorInfo($hMain)
			If IsArray($c) And $m[1] <> $hVid Then
				If $c[1] < 48 And $c[4] <> $bTV And $c[4] <> $bMin And $c[4] <> $bClose Then ; header (everything except the TV / - / X buttons): drag the window, click without moving = options
					_DragWin($c[4] = $bOpt)
				ElseIf $c[1] >= 75 And $c[1] <= 145 And $c[0] >= 20 And $c[0] <= 460 Then
					_Seek(($c[0] - 20) / 440)
				ElseIf $c[1] >= 240 And $c[1] <= 275 Then
					If $c[0] >= $VX - 6 And $c[0] <= $VX + $VW + 6 Then $iDrag = 1
					If $c[0] >= $BX - 6 And $c[0] <= $BX + $BW + 6 Then $iDrag = 2
				EndIf
			EndIf
		Case $bPlay, $kPlay ; play / pause
			_PlayPause()
		Case $bStop, $kStop
			_Stop()
		Case $bNext, $kNext
			_Next(1)
		Case $bPrev, $kPrev
			_Prev()
		Case $kBack
			_Skip(-5)
		Case $kFwd
			_Skip(5)
		Case $kVU
			_Vol(5)
		Case $kVD
			_Vol(-5)
		Case $kMute
			_Mute()
		Case $bShuf
			$fShuf = Not $fShuf
			GUICtrlSetColor($bShuf, $fShuf ? $ACC : $OFF)
		Case $bLoop
			$fLoop = Not $fLoop
			GUICtrlSetColor($bLoop, $fLoop ? $ACC : $OFF)
		Case $lst ; single click = play
			$s = GUICtrlSendMsg($lst, $LB_GETCURSEL, 0, 0)
			If $s >= 0 And ($s <> $iCur Or Not $fPlay) Then _Play($s)
		Case $bAddF
			$s = FileOpenDialog("Add files", "", "Media (*." & StringReplace($sExt, "|", ";*.") & ")", 5)
			If Not @error Then
				$a = StringSplit($s, "|", 2)
				If UBound($a) = 1 Then _Add($a[0])
				For $i = 1 To UBound($a) - 1
					_Add($a[0] & "\" & $a[$i])
				Next
			EndIf
		Case $bAddD
			$s = FileSelectFolder("Add folder", "")
			If Not @error Then _Add($s)
		Case $bDel, $kDel
			_DelSel()
		Case $bClr
			_Clear()
		Case $bSave
			If UBound($aPl) Then
				$s = FileSaveDialog("Save playlist", "", "Playlist (*.m3u)", 16, "playlist.m3u")
				If Not @error Then
					If Not StringRegExp($s, "(?i)\.m3u8?$") Then $s &= ".m3u"
					_SaveList($s)
				EndIf
			EndIf
		Case $bLoad
			$s = FileOpenDialog("Load playlist", "", "Playlist (*.m3u;*.m3u8)", 1)
			If Not @error Then
				_Clear()
				_LoadList($s)
			EndIf
		Case $bPL
			_PL()
		Case $GUI_EVENT_DROPPED
			For $f In StringSplit(@GUI_DragFile, "|", 2)
				_Add($f)
			Next
	EndSwitch
	Switch TrayGetMsg()
		Case $TRAY_EVENT_PRIMARYUP ; click on tray icon = restore
			GUISetState(@SW_SHOW, $hMain)
			TraySetState(2)
			$fTray = False
			_VidApply()
	EndSwitch
	If $iDrag Then _Drag()
	If $fVidShown And TimerDiff($tPoll) > 30 Then ; follow the player, double-click on the video = fullscreen
		$tPoll = TimerInit()
		_VidPoll()
	EndIf
	If TimerDiff($tUI) > 200 Then
		_Tick()
		_Hover()
		_MqPoll()
		_FFDlPoll()
		$tUI = TimerInit()
	EndIf
WEnd

; ================= player (MCI via winmm: seek, pause, volume) =================
Func _Mci($sCmd)
	Local $t = DllStructCreate("wchar[256]")
	Local $r = DllCall("winmm.dll", "dword", "mciSendStringW", "wstr", $sCmd, "ptr", DllStructGetPtr($t), "uint", 255, "ptr", 0)
	$iErr = @error ? -1 : $r[0]
	Return DllStructGetData($t, 1)
EndFunc

Func _Play($i)
	If $i < 0 Or $i >= UBound($aPl) Then Return
	$fFixed = False
	Local $ok = _Open($aPl[$i])
	If Not $ok And StringRight($aPl[$i], 4) = ".mp3" Then $ok = _Retry($i)
	$iCur = $i
	$iLen = ($i < UBound($aLn)) ? $aLn[$i] : 0 ; Explorer length (same as in the list); MCI's own length is only an estimate for many mp3s
	If $iLen <= 0 Then $iLen = Number(_Mci("status bp length")) / 1000
	$tCmd = TimerInit()
	$tStart = TimerInit()
	$iOff = 0
	$tRun = TimerInit()
	$fPlay = True
	$fPause = False
	_Apply()
	$fVid = _IsVid($aPl[$i]) And $fEmb And $ok ; TV button / window only if the video really sits in our window
	$iVSz = 0
	$sWin = "" ; (window mode: size + center the window again for this video)
	_VidApply()
	$sNow = _Tags($aPl[$i])
	GUICtrlSetData($bPlay, "||")
	GUICtrlSetData($lblNow, $sNow)
	WinSetTitle($hVid, "", $sNow) ; (window mode shows it in the title bar)
	$iZoom = 100
	_Tip()
	GUICtrlSendMsg($lst, $LB_SETCURSEL, $i, 0)
	_Wave($aPl[$i])
	_Seg(0)
EndFunc

Func _Open($f) ; open + play, True if no error. MCI first; a video MCI can't play falls back to the Windows Media Player control
	If $fWmp Then $oWMP.controls.stop()
	$fWmp = False
	If $idWMP Then GUICtrlSetState($idWMP, $GUI_HIDE) ; hide the old WMP picture while MCI plays
	If IsObj($oWMP) Then $oWMP.fullScreen = False ; leave WMP's own fullscreen (it is entered again for the next WMP video if wanted)
	_Mci("close bp")
	$fEmb = False
	_FFKill()
	If _FFReady() Then
		If _OpenFF($f, 0) Then Return True
		_Log("ffplay did not start, using MCI: " & $f)
	EndIf
	Local $vid = _IsVid($f), $c = 'open "' & $f & '" alias bp', $e
	If $vid Then
		_Log("video via MCI: " & $f)
		_Mci($c & " type mpegvideo parent " & Number(String($hVid)) & " style child")
		If $iErr Then
			_Log("open (embedded) failed: " & _MciErr($iErr) & " | " & $f)
			_Mci("close bp")
			_Mci($c & " type mpegvideo")
		Else
			$fEmb = True
		EndIf
	Else
		_Mci($c)
	EndIf
	$e = $iErr
	If $e Then
		_Log("open failed: " & _MciErr($e) & " | " & $f)
	Else
		_Mci("set bp time format milliseconds")
		_Mci("play bp")
		$e = $iErr
		If $e Then _Log("play failed: " & _MciErr($e) & " | " & $f)
	EndIf
	If $e And $vid Then ; MCI can't do this video -> Windows Media Player as backup
		_Mci("close bp")
		If _WmpInit() Then Return _OpenWmp($f)
	EndIf
	Return Not $e
EndFunc

Func _WmpInit() ; create the WMP control inside the video window on first use; False if WMP is not available
	If $fWine Then Return False ; (the Windows Media Player control is not usable under Wine)
	If $iWInit Then Return IsObj($oWMP)
	$iWInit = 1
	$oWMP = ObjCreate("WMPlayer.OCX")
	If Not IsObj($oWMP) Then
		_Log("WMP: ObjCreate failed")
		Return False
	EndIf
	GUISwitch($hVid) ; the control must be created while the video window is the current GUI
	$idWMP = GUICtrlCreateObj($oWMP, 0, 0, $iWw, $iWh) ; dock size; never resized (WMP does its own fullscreen)
	GUICtrlSetResizing($idWMP, $GUI_DOCKALL)
	GUISwitch($hMain)
	$oWMP.uiMode = "none"
	$oWMP.stretchToFit = True ; scale the video to the window (default: 100% size, cropped)
	$oWMP.enableContextMenu = False
	$oWMP.settings.enableErrorDialogs = False
	_Log("WMP control created, ctrl id " & $idWMP)
	Return True
EndFunc

Func _OpenWmp($f) ; video through the Windows Media Player control in the video window (it starts by itself)
	$fWmp = True
	$fEmb = True
	$iWSt = -1
	$fWFS = False
	GUICtrlSetState($idWMP, $GUI_SHOW)
	_Log("video via WMP (window wanted=" & $fVidOn & ", ctrl id " & $idWMP & "): " & $f)
	$oWMP.settings.volume = $iVol
	$oWMP.settings.balance = $iBal
	$oWMP.URL = $f
	Return True
EndFunc

Func _Retry($i) ; some mp3s are refused/skipped by MCI until the junk before the real MPEG stream (ID3v2, scene header ...) is cut -> play a cleaned temp copy
	_Mci("close bp") ; release a previous temp copy
	Local $g = _SoundPlayFixMP3($aPl[$i], $sTmp)
	If $g = "" Or $g = $aPl[$i] Then Return False ; nothing to cut
	$fFixed = True
	$tCmd = TimerInit()
	$tStart = TimerInit()
	$iOff = 0
	$tRun = TimerInit()
	Local $ok = _Open($g)
	If $ok Then _Apply()
	Return $ok
EndFunc

Func _PlayPause()
	If $fPlay Then
		$fPause = Not $fPause
		If $fFFrun Then
			If $fPause Then
				If $fVid Then
					_FFKillProc() ; video: pausing a process that owns a child window would hang our GUI -> stop it, restart at the same spot on resume
				Else
					_FFSusp(True)
				EndIf
			ElseIf $iFFPid Then
				_FFSusp(False)
			EndIf
		ElseIf $fWmp Then
			If $fPause Then
				$oWMP.controls.pause()
			Else
				$oWMP.controls.play()
			EndIf
		Else
			_Mci($fPause ? "pause bp" : "resume bp")
		EndIf
		If $fPause Then
			$iOff += TimerDiff($tRun) / 1000
		Else
			$tRun = TimerInit()
			If $fFFrun And (Not $iFFPid Or $iVol <> $iFFV Or $iBal <> $iFFB) Then _FFLaunch($iOff)
		EndIf
		GUICtrlSetData($bPlay, $fPause ? ">" : "||")
	Else
		Local $s = GUICtrlSendMsg($lst, $LB_GETCURSEL, 0, 0)
		_Play($s < 0 ? 0 : $s)
	EndIf
EndFunc

Func _Pos() ; own clock (MCI's position/length are unreliable for some mp3s): offset set on play/seek + time since
	If $fWmp Then Return Number($oWMP.controls.currentPosition) ; WMP knows the real position
	Return ($fPause Or $fFFWait) ? $iOff : $iOff + TimerDiff($tRun) / 1000
EndFunc

Func _Seek($f) ; $f = 0..1
	If Not $fPlay Or $iLen <= 0 Then Return
	If $fFFrun Then ; ffplay can't seek from outside: stop it, restart at the new spot shortly after the last request
		_FFKillProc()
		$iOff = $f * $iLen
		$tRun = TimerInit()
		$fFFWait = True
		$tFFSeek = TimerInit()
		$tCmd = TimerInit()
		$fPause = False
		GUICtrlSetData($bPlay, "||")
		_Tick()
		Return
	EndIf
	If $fWmp Then
		$oWMP.controls.currentPosition = $f * $iLen
		$oWMP.controls.play()
		$tCmd = TimerInit()
		$fPause = False
		GUICtrlSetData($bPlay, "||")
		_Tick()
		Return
	EndIf
	Local $l = Number(_Mci("status bp length"))
	If $l <= 0 Then Return
	_Mci("seek bp to " & Int($f * $l)) ; fraction of MCI's own timeline
	_Mci("play bp")
	$tCmd = TimerInit()
	$iOff = $f * $iLen
	$tRun = TimerInit()
	$fPause = False
	GUICtrlSetData($bPlay, "||")
	_Tick()
EndFunc

Func _Skip($d) ; seek relative, seconds
	If Not $fPlay Or $iLen <= 0 Then Return
	_Seek(_Min(_Max((_Pos() + $d) / $iLen, 0), 0.999))
EndFunc

Func _Stop()
	_FFKill()
	If $fWmp Then $oWMP.controls.stop()
	$fWmp = False
	If $idWMP Then GUICtrlSetState($idWMP, $GUI_HIDE)
	If IsObj($oWMP) Then $oWMP.fullScreen = False
	_Mci("close bp")
	$fPlay = False
	$fPause = False
	$sNow = ""
	_VidApply()
	GUICtrlSetData($bPlay, ">")
	GUICtrlSetData($lblNow, "stopped")
	WinSetTitle($hVid, "", "BrAiNPlay Video")
	_Tip()
	GUICtrlSetData($lblTime, "00:00 / --:--")
	_Wave("")
	_Seg(0)
EndFunc

Func _Next($d)
	Local $c = UBound($aPl)
	If $c Then _Play($fShuf ? Random(0, $c - 1, 1) : Mod($iCur + $d + $c, $c))
EndFunc

Func _Prev() ; hotkey callbacks must be parameterless
	_Next(-1)
EndFunc

Func _HkNext()
	_Next(1)
EndFunc

Func _MkKeyDown($vk)
	Local $r = DllCall("user32.dll", "short", "GetAsyncKeyState", "int", $vk)
	Return (Not @error) And BitAND($r[0], 0x8000) <> 0
EndFunc

Func _MkPlay() ; play/pause media key, ignoring auto-repeat while the key is held
	Local $dt = TimerDiff($tMKp)
	$tMKp = TimerInit()
	If $dt >= 400 Then _PlayPause()
EndFunc

Func _MkStop()
	Local $dt = TimerDiff($tMKp)
	$tMKp = TimerInit()
	If $dt >= 400 Then _Stop()
EndFunc

Func _MkNext() ; next: short press = next track, hold = fast forward
	_MkKey(1)
EndFunc

Func _MkPrev() ; previous: short press = previous track, hold = rewind
	_MkKey(-1)
EndFunc

Func _MkKey($dir)
	Local $dt = TimerDiff($tMK), $vk = ($dir > 0) ? 0xB0 : 0xB1, $t = TimerInit(), $bHold = False
	$tMK = TimerInit()
	If $dt < 400 Then Return ; auto-repeat of a key that is being held / rested on -> ignore
	While _MkKeyDown($vk)
		If TimerDiff($t) > 400 Then
			$bHold = True
			ExitLoop
		EndIf
		Sleep(15)
	WEnd
	If Not $bHold Then
		_Next($dir) ; short press
	Else
		While _MkKeyDown($vk) ; held: seek 5 s every 200 ms
			_Skip($dir * 5)
			$tMK = TimerInit()
			Sleep(200)
		WEnd
	EndIf
	$tMK = TimerInit() ; repeats that queued up meanwhile are ignored
EndFunc

Func _Tick()
	If $tNote And TimerDiff($tNote) > 2500 Then ; temporary note over, header shows the track again
		$tNote = 0
		GUICtrlSetData($lblNow, $fPlay ? $sNow : "stopped")
	EndIf
	If Not $fPlay Or $fPause Then Return
	Local $m, $ended
	If $fFFrun Then
		If $fFFWait And TimerDiff($tFFSeek) > 150 Then _FFLaunch($iOff)
		If $fFFWait Then
			$ended = False
		ElseIf $iVol <> $iFFV Or $iBal <> $iFFB Then ; volume / balance are command line options of ffplay -> restart at the current position once the slider is released
			If $iDrag = 0 And TimerDiff($tFFVol) > 350 Then _FFRestart()
			$ended = False
		Else
			$ended = Not ProcessExists($iFFPid)
		EndIf
	ElseIf $fWmp Then ; playState: 3 playing, 2 paused, 6/7/9 loading, 8 ended, 1 stopped, 10 ready
		$m = Number($oWMP.playState)
		If $m <> $iWSt Then
			$iWSt = $m
			_Log("wmp state " & $m & " | pos " & Round(Number($oWMP.controls.currentPosition), 1) & " " & _WmpErr())
		EndIf
		$ended = ($m = 8 Or $m = 1 Or $m = 10 Or $m = 0)
	Else
		$m = _Mci("status bp mode")
		$ended = ($m <> "playing")
	EndIf
	If $ended And TimerDiff($tCmd) > (_IsVid($aPl[$iCur]) ? 3000 : 600) Then ; track finished (or failed to open)
		Local $bad = TimerDiff($tStart) < 5000 And $iOff = 0
		If $bad Then _Log("stopped early (" & ($fWmp ? "wmp state=" & $m & " " & _WmpErr() : "mode=" & $m) & "): " & $aPl[$iCur])
		If Not $fFixed And $iOff = 0 And TimerDiff($tStart) < 3000 And StringRight($aPl[$iCur], 4) = ".mp3" Then ; died right at the start: try without ID3v2 tag
			If _Retry($iCur) Then Return
		EndIf
		If $fShuf Or $fLoop Or $iCur < UBound($aPl) - 1 Then
			_Next(1)
		Else
			_Stop()
			If $bad Then GUICtrlSetData($lblNow, (_IsVid($aPl[$iCur]) And Not IsObj($oWMP)) ? "video needs Windows Media Player (Legacy) or a codec pack" : "can't play this file (see brainplay.log)")
		EndIf
		Return
	EndIf
	If $fFFrun And $fVid And $hFF And Not $fFFWait And $sFFMode <> "" Then ; fullscreen <-> window (or another monitor): the picture is scaled by ffplay -> restart with the matching command line
		Local $wm = _FFWantMode()
		If $wm <> $sFFMode Then
			If $wm <> $sFFWant Then ; wait until the user stopped pressing + / -
				$sFFWant = $wm
				$tFFChg = TimerInit()
			ElseIf TimerDiff($tFFChg) > 400 Then
				$sFFWant = ""
				_FFRestart()
				Return
			EndIf
		Else
			$sFFWant = ""
		EndIf
	EndIf
	If $fFFrun And $fVid And $hFF And $iFFWw > 0 And $fVidShown Then ; ffplay may resize itself after the embed -> put it back
		Local $cz = WinGetClientSize($hFF)
		If IsArray($cz) Then
			If $cz[0] <> $iFFWw Or $cz[1] <> $iFFWh Then _FFSize()
		EndIf
	EndIf
	If $fFFrun And $fVid And Not $hFF And Not $fFFWait Then ; ffplay's window shows up a moment after the start (and after every seek)
		If _FFEmbed() Then
			_VideoSize()
			If $iVSz = 0 And $fFull And $fVidOn Then _Osd($sNow, 4000)
			$iVSz = 1
		ElseIf TimerDiff($tCmd) > 8000 Then ; no picture at all (audio-only file with a video extension)
			$fVid = False
			_VidApply()
		EndIf
	EndIf
	If $fVid And $iVSz = 0 And Not $fFFrun And TimerDiff($tStart) > 800 And (Not $fWmp Or $m = 3) Then ; video size is known by now (WMP: playing) -> fit it / WMP: go fullscreen
		$iVSz = 1
		_VideoSize()
		If $fFull And Not $fWmp Then _Osd($sNow, 4000) ; track title over the fullscreen video (WMP: when it enters fullscreen)
		If $fWmp Then _Log("wmp audio languages: " & Number($oWMP.controls.audioLanguageCount))
	EndIf
	If $fWmp And $iLen <= 0 Then ; length unknown from Explorer -> ask WMP
		Local $oM = $oWMP.currentMedia
		If IsObj($oM) Then $iLen = Number($oM.duration)
	EndIf
	Local $s = _Pos()
	If $iLen > 0 Then $s = _Min($s, $iLen)
	GUICtrlSetData($lblTime, _T($s) & " / " & ($iLen ? _T($iLen) : "--:--"))
	Local $k = $iLen ? _Min(Int($s / $iLen * $N), $N) : 0
	If $k <> $iLit Then _Seg($k)
EndFunc

Func _Seg($k)
	For $i = 0 To $N - 1
		GUICtrlSetBkColor($aSeg[$i], $i < $k ? $ACC : $DIM)
	Next
	$iLit = $k
EndFunc

; ================= volume / balance =================
Func _Drag()
	Local $c = GUIGetCursorInfo($hMain)
	If Not IsArray($c) Then Return
	If Not $c[2] Then ; mouse released
		$iDrag = 0
		Return
	EndIf
	If $iDrag = 1 Then
		$iVol = Int(_Min(_Max(($c[0] - $VX) / $VW * 100, 0), 100))
	Else
		$iBal = Int(_Min(_Max(($c[0] - $BX) / $BW * 200 - 100, -100), 100))
		If Abs($iBal) < 8 Then $iBal = 0 ; snap to center
	EndIf
	_Apply()
EndFunc

Func _DragWin($fTitle) ; borderless window: let Windows run its own move loop (same as dragging a title bar)
	Local $p = WinGetPos($hMain), $q
	DllCall("user32.dll", "bool", "ReleaseCapture")
	DllCall("user32.dll", "lresult", "SendMessageW", "hwnd", $hMain, "uint", 0x0112, "wparam", 0xF012, "lparam", 0) ; WM_SYSCOMMAND, SC_MOVE + HTCAPTION
	$q = WinGetPos($hMain)
	If $fTitle And IsArray($p) And IsArray($q) And $q[0] = $p[0] And $q[1] = $p[1] Then _Options() ; the title was only clicked, not dragged
EndFunc

Func _Vol($d)
	$iVol = Int(_Min(_Max($iVol + $d, 0), 100))
	_Apply()
EndFunc

Func _Mute()
	If $iVol > 0 Then
		$iPre = $iVol
		$iVol = 0
	Else
		$iVol = $iPre
	EndIf
	_Apply()
EndFunc

Func _Apply()
	Local $v = $iVol * 10, $l = $v, $r = $v, $ok = True
	If $iBal > 0 Then $l = $v * (100 - $iBal) / 100
	If $iBal < 0 Then $r = $v * (100 + $iBal) / 100
	If $fPlay Then
		If $fFFrun Then
			$tFFVol = TimerInit() ; ffplay: applied by a restart (see _Tick)
		ElseIf $fWmp Then
			$oWMP.settings.volume = $iVol
			$oWMP.settings.balance = $iBal
		ElseIf $iBal = 0 Then
			_Mci("setaudio bp volume to " & Int($v))
		Else
			_Mci("setaudio bp left volume to " & Int($l))
			If $iErr Then ; device ignores balance -> volume only
				$ok = False
				_Mci("setaudio bp volume to " & Int($v))
			Else
				_Mci("setaudio bp right volume to " & Int($r))
			EndIf
		EndIf
	EndIf
	GUICtrlSetData($lblVol, "VOL " & $iVol)
	GUICtrlSetData($lblBal, $ok ? "BAL " & ($iBal < 0 ? "L" & -$iBal : ($iBal > 0 ? "R" & $iBal : "C")) : "BAL n/a")
	Local $kv = Round($iVol / 100 * $NV), $kb = Round(($iBal + 100) / 200 * ($NB - 1))
	For $i = 0 To $NV - 1
		GUICtrlSetBkColor($aV[$i], $i < $kv ? $ACC : $DIM)
	Next
	For $i = 0 To $NB - 1
		GUICtrlSetBkColor($aB[$i], ($i >= _Min(6, $kb) And $i <= _Max(6, $kb)) ? $ACC : $DIM)
	Next
EndFunc

; ================= waveform from the file =================
; wav: real amplitude | mp3: loudness estimated from the frames' global_gain (no decoding) | else: default pattern
Func _Def($i)
	Return 10 + Int(Abs(Sin($i * 0.55) * Cos($i * 0.21)) * 50)
EndFunc

Func _Wave($f)
	Local $v[$N], $ok = False, $e = StringLower(StringRight($f, 4)), $m
	If $e = ".wav" Then $ok = _WavEnv($f, $v)
	If $e = ".mp3" Then $ok = _Mp3Env($f, $v)
	For $i = 0 To $N - 1
		$m = $ok ? 8 + Int($v[$i] * 52) : _Def($i)
		GUICtrlSetPos($aSeg[$i], 20 + $i * 11, 110 - Int($m / 2), 7, $m)
	Next
EndFunc

Func _WavEnv($f, ByRef $v) ; 16-bit PCM only, fills $v with 0..1
	Local $h = FileOpen($f, 16)
	If $h = -1 Then Return False
	Local $t = DllStructCreate("byte[4096]"), $ptr = DllStructGetPtr($t), $p = 12, $ch = 0, $bits = 0, $ds = 0, $dl = 0, $id, $sz, $mx = 0, $sum, $cnt, $b, $pos
	DllStructSetData($t, 1, FileRead($h, 4096))
	If DllStructGetData(DllStructCreate("char[4]", $ptr), 1) <> "RIFF" Then Return FileClose($h) * 0
	While $p < 4000
		$id = DllStructGetData(DllStructCreate("char[4]", $ptr + $p), 1)
		$sz = DllStructGetData(DllStructCreate("dword", $ptr + $p + 4), 1)
		If $id = "fmt " Then
			$ch = DllStructGetData(DllStructCreate("word", $ptr + $p + 10), 1)
			$bits = DllStructGetData(DllStructCreate("word", $ptr + $p + 22), 1)
		ElseIf $id = "data" Then
			$ds = $p + 8
			$dl = _Min($sz, FileGetSize($f) - $ds)
			ExitLoop
		EndIf
		$p += 8 + $sz + BitAND($sz, 1)
	WEnd
	If $ds = 0 Or $bits <> 16 Or $ch < 1 Or $dl < 8192 Then Return FileClose($h) * 0
	Local $fr = $ch * 2, $tb = DllStructCreate("byte[1024]"), $ts = DllStructCreate("short[512]", DllStructGetPtr($tb))
	For $i = 0 To $N - 1
		$sum = 0
		$cnt = 0
		For $j = 0 To 3
			$pos = $ds + Int($dl * ($i + ($j + 0.5) / 4) / $N / $fr) * $fr
			FileSetPos($h, $pos, 0)
			$b = FileRead($h, 1024)
			If @error Then ContinueLoop
			DllStructSetData($tb, 1, $b)
			For $k = 1 To 512 Step 4
				$sum += Abs(DllStructGetData($ts, 1, $k))
				$cnt += 1
			Next
		Next
		$v[$i] = $cnt ? $sum / $cnt : 0
		$mx = _Max($mx, $v[$i])
	Next
	FileClose($h)
	If $mx = 0 Then Return False
	For $i = 0 To $N - 1
		$v[$i] /= $mx
	Next
	Return True
EndFunc

Func _Mp3Env($f, ByRef $v) ; MPEG-1 Layer III, fills $v with 0..1
	Local $h = FileOpen($f, 16)
	If $h = -1 Then Return False
	Local $sz = FileGetSize($f), $lo = 0, $hi, $t = DllStructCreate("byte[4096]"), $b, $g, $sum, $cnt, $tot = 0, $mn = 9999, $mx = 0, $av = 0
	DllStructSetData($t, 1, FileRead($h, 10))
	If DllStructGetData(DllStructCreate("char[3]", DllStructGetPtr($t)), 1) = "ID3" Then ; skip ID3v2 tag
		$lo = 10 + BitShift(DllStructGetData($t, 1, 7), -21) + BitShift(DllStructGetData($t, 1, 8), -14) + BitShift(DllStructGetData($t, 1, 9), -7) + DllStructGetData($t, 1, 10)
	EndIf
	$hi = $sz - 4096 - 128
	If $hi <= $lo Then Return FileClose($h) * 0
	For $i = 0 To $N - 1
		$sum = 0
		$cnt = 0
		For $j = 0 To 5
			FileSetPos($h, $lo + Int(($hi - $lo) * ($i + ($j + 0.5) / 6) / $N), 0)
			$b = FileRead($h, 4096)
			If @error Then ContinueLoop
			DllStructSetData($t, 1, $b)
			$g = _FrameGain($t, BinaryLen($b))
			If $g >= 0 Then
				$sum += $g
				$cnt += 1
			EndIf
		Next
		$v[$i] = $cnt ? $sum / $cnt : -1
		If $cnt Then
			$tot += 1
			$av += $v[$i]
			$mn = _Min($mn, $v[$i])
			$mx = _Max($mx, $v[$i])
		EndIf
	Next
	FileClose($h)
	If $tot < $N / 2 Then Return False
	$av /= $tot
	For $i = 0 To $N - 1
		If $v[$i] < 0 Then $v[$i] = $av
		$v[$i] = ($v[$i] - $mn) / _Max($mx - $mn, 8)
	Next
	Return True
EndFunc

Func _FrameGain($t, $len) ; first valid MPEG-1 L3 frame in buffer -> mean global_gain (~ loudness in 1.5 dB steps), else -1
	Local $b1, $b2, $b3, $x, $y, $fl, $nc, $bit, $g
	For $p = 0 To $len - 4
		If DllStructGetData($t, 1, $p + 1) <> 255 Then ContinueLoop
		$b1 = DllStructGetData($t, 1, $p + 2)
		If BitAND($b1, 0xFE) <> 0xFA Then ContinueLoop
		$b2 = DllStructGetData($t, 1, $p + 3)
		$x = BitShift($b2, 4)
		$y = BitAND(BitShift($b2, 2), 3)
		If $x = 0 Or $x = 15 Or $y = 3 Then ContinueLoop
		$fl = Int(144000 * $aBR[$x] / $aSR[$y]) + BitAND(BitShift($b2, 1), 1)
		If $p + $fl + 2 > $len Then ExitLoop
		If DllStructGetData($t, 1, $p + $fl + 1) <> 255 Or BitAND(DllStructGetData($t, 1, $p + $fl + 2), 0xF0) <> 0xF0 Then ContinueLoop ; next frame must follow
		$b3 = DllStructGetData($t, 1, $p + 4)
		$nc = (BitShift($b3, 6) = 3) ? 1 : 2
		$bit = 8 * ($p + 4 + (BitAND($b1, 1) ? 0 : 2)) + ($nc = 1 ? 18 : 20)
		$g = 0
		For $k = 0 To 2 * $nc - 1
			$g += _GG($t, $bit + $k * 59 + 21)
		Next
		Return $g / (2 * $nc)
	Next
	Return -1
EndFunc

Func _GG($t, $bit) ; 8 bits at bit offset
	Local $o = BitShift($bit, 3), $v = DllStructGetData($t, 1, $o + 1) * 256 + DllStructGetData($t, 1, $o + 2)
	Return BitAND(BitShift($v, 8 - BitAND($bit, 7)), 255)
EndFunc

; ================= playlist =================
Func _Add($f, $l = 0) ; $l = known length in seconds (skips the lookup)
	If StringInStr(FileGetAttrib($f), "D") Then Return _AddDir($f)
	If Not StringRegExp($f, "(?i)\.(" & $sExt & ")$") Or Not FileExists($f) Then Return
	_Dbg("add " & $f)
	If $l <= 0 Then $l = _MP3_GetLengthSec($f)
	If Not IsNumber($l) Then $l = 0
	_Dbg("length " & $l)
	Local $k = UBound($aPl)
	ReDim $aPl[$k + 1]
	ReDim $aLn[$k + 1] ; (same size as $aPl, always)
	$aPl[$k] = $f
	$aLn[$k] = $l
	GUICtrlSetData($lst, _Item($k))
	_PLText()
EndFunc

Func _AddDir($d)
	Local $h, $f
	For $e In StringSplit($sExt, "|", 2)
		$h = FileFindFirstFile($d & "\*." & $e)
		While 1
			$f = FileFindNextFile($h)
			If @error Then ExitLoop
			_Add($d & "\" & $f)
		WEnd
		FileClose($h)
	Next
EndFunc

Func _DelSel()
	Local $s = GUICtrlSendMsg($lst, $LB_GETCURSEL, 0, 0)
	If $s < 0 Then Return
	_ArrayDelete($aPl, $s)
	_ArrayDelete($aLn, $s)
	If $iCur = $s Then
		_Stop()
		$iCur = -1
	ElseIf $iCur > $s Then
		$iCur -= 1
	EndIf
	_Refresh()
EndFunc

Func _Clear()
	_Stop()
	ReDim $aPl[0]
	ReDim $aLn[0]
	$iCur = -1
	_Refresh()
EndFunc

Func _Refresh()
	GUICtrlSetData($lst, "")
	For $i = 0 To UBound($aPl) - 1
		GUICtrlSetData($lst, _Item($i))
	Next
	If $iCur >= 0 Then GUICtrlSendMsg($lst, $LB_SETCURSEL, $iCur, 0)
	_PLText()
EndFunc

Func _Item($i)
	Return StringFormat("%02d  %s   [%s]", $i + 1, _Name($aPl[$i]), _T($i < UBound($aLn) ? $aLn[$i] : 0))
EndFunc

; ---- m3u (extended, UTF-8) ----
Func _SaveList($sPath)
	Local $h = FileOpen($sPath, 2 + 8 + 128) ; overwrite, create path, UTF-8
	If $h = -1 Then Return False
	FileWriteLine($h, "#EXTM3U")
	For $i = 0 To UBound($aPl) - 1
		FileWriteLine($h, "#EXTINF:" & Int($aLn[$i]) & "," & _Name($aPl[$i]))
		FileWriteLine($h, $aPl[$i])
	Next
	FileClose($h)
	Return True
EndFunc

Func _LoadList($sPath)
	Local $h = FileOpen($sPath, 256) ; reads UTF-8 with or without BOM
	If $h = -1 Then Return False
	Local $dir = StringLeft($sPath, StringInStr($sPath, "\", 0, -1) - 1), $l = 0, $ln, $c
	While 1
		$ln = FileReadLine($h)
		If @error Then ExitLoop
		$ln = StringStripWS(StringReplace($ln, ChrW(0xFEFF), ""), 3) ; drop BOM remnants + whitespace
		If $ln = "" Then ContinueLoop
		If StringLeft($ln, 8) = "#EXTINF:" Then
			$c = StringInStr($ln, ",")
			$l = $c > 9 ? Int(StringMid($ln, 9, $c - 9)) : 0
			ContinueLoop
		EndIf
		If StringLeft($ln, 1) = "#" Then ContinueLoop
		$ln = StringReplace($ln, "/", "\")
		If Not (StringInStr($ln, ":") Or StringLeft($ln, 2) = "\\") Then $ln = $dir & "\" & $ln ; relative path
		_Add($ln, $l)
		$l = 0
	WEnd
	FileClose($h)
	Return True
EndFunc

; ================= video window =================
Func _IsVid($f)
	Return StringRegExp($f, "(?i)\.(" & $sVid & ")$") = 1
EndFunc

Func _VidApply() ; TV button + video window follow: current track is a video? video wanted (remembered)? not in tray?
	Local $on = $fPlay And $fVid
	GUICtrlSetState($bTV, $on ? $GUI_SHOW : $GUI_HIDE)
	GUICtrlSetColor($bTV, $fVidOn ? $ACC : $OFF)
	If $on And $fVidOn And Not $fTray Then
		_VidStyle()
		_Dock()
		GUISetState(@SW_SHOWNOACTIVATE, $hVid)
		WinSetOnTop($hVid, "", ($fFull And Not $fWmp) ? 1 : 0)
		$fVidShown = True
		_VideoSize()
		If $fFull And Not $fWmp Then WinActivate($hMain) ; the keyboard stays with the player (shortcuts keep working in fullscreen)
	Else
		If IsObj($oWMP) Then $oWMP.fullScreen = False ; leave WMP's own fullscreen
		_WmpKeys(False)
		GUISetState(@SW_HIDE, $hOsd)
		$tOsd = 0
		GUISetState(@SW_HIDE, $hVid)
		$fVidShown = False
		_Cursor(True)
		_KeepAwake(False)
	EndIf
	_FFKeys()
	GUISwitch($hMain)
EndFunc

Func _Dock() ; MCI fullscreen: the video monitor | MCI window: placed by _VideoSize | WMP: invisible host window on the video monitor (its fullscreen follows it)
	Local $r = _VidMonitor()
	If $fWmp Then
		WinMove($hVid, "", $r[0] + 20, $r[1] + 20, $iWw, $iWh)
		Return
	EndIf
	Local $p = WinGetPos($hMain)
	If $fFull And IsArray($p) Then
		WinMove($hVid, "", $r[0], $r[1], $r[2], $r[3])
		$sPos = $p[0] & "," & $p[1]
	EndIf
EndFunc

Func _VidStyle() ; 0 = fullscreen (borderless) | 1 = window (title bar) | 2 = WMP host (invisible, click-through, sits on the video monitor)
	Local $m = $fWmp ? 2 : ($fFull ? 0 : 1)
	If $m = $iSty Then Return
	$iSty = $m
	If $m = 1 Then
		GUISetStyle(BitOR($WS_CAPTION, $WS_POPUP, $WS_SYSMENU, $WS_CLIPCHILDREN), $WS_EX_NOACTIVATE, $hVid)
	ElseIf $m = 2 Then
		GUISetStyle(BitOR($WS_POPUP, $WS_CLIPCHILDREN), BitOR($WS_EX_NOACTIVATE, $WS_EX_TRANSPARENT, $WS_EX_LAYERED), $hVid)
	Else
		GUISetStyle(BitOR($WS_POPUP, $WS_CLIPCHILDREN), $WS_EX_NOACTIVATE, $hVid)
	EndIf
	WinSetTrans($hVid, "", $m = 2 ? 0 : 255)
	DllCall("user32.dll", "bool", "SetWindowPos", "hwnd", $hVid, "hwnd", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37) ; frame changed
EndFunc

Func _VidKey($k) ; f = fullscreen on/off | w = window (video size) on/off | Esc = video off  (MCI videos; WMP videos are fullscreen only)
	If Not ($fPlay And $fVid) Then Return
	If $fVidShown And Not $fFull And Not $fWmp Then _MonRemember() ; window was maybe dragged to another monitor -> fullscreen goes there
	Switch $k
		Case "f"
			If $fVidOn And $fFull Then
				$fVidOn = False
			Else
				$fVidOn = True
				$fFull = True
			EndIf
		Case "w"
			If $fWmp Then Return ; WMP: no window mode
			If $fVidOn And Not $fFull Then
				$fFull = True
			Else
				$fVidOn = True
				$fFull = False
			EndIf
		Case "esc"
			$fVidOn = False
	EndSwitch
	$sWin = ""
	$tChg = TimerInit()
	_VidApply()
EndFunc

Func _VidPoll() ; called every ~30 ms while the video window is visible
	Local $q, $r, $dn = False, $mp, $now
	If $tOsd And TimerDiff($tOsd) > $iOsdMs Then ; OSD timeout
		$tOsd = 0
		GUISetState(@SW_HIDE, $hOsd)
	EndIf
	_KeepAwake(Not $fPause) ; no screensaver / display sleep while a video is shown (not while paused)
	If $fWmp Then
		If $iVSz >= 1 Then
			$now = ($oWMP.fullScreen <> 0)
			If $now Then
				If Not $fWFS Then ; WMP just went fullscreen: it owns the keyboard now -> our keys as global hotkeys, title on screen
					$fWFS = True
					_WmpKeys(True)
					_Osd($sNow, 4000)
				EndIf
			ElseIf $fWFS Then ; the user left WMP's fullscreen (Esc / double-click) -> video off
				$fWFS = False
				$fVidOn = False
				_VidApply()
			EndIf
		EndIf
		Return
	EndIf
	If $fFull Then
		$q = WinGetPos($hMain)
		If IsArray($q) Then
			If $q[0] & "," & $q[1] <> $sPos Then ; player moved (maybe to another monitor) -> fullscreen follows
				$iMon = 0
				_Dock()
				_VideoSize()
			EndIf
		EndIf
		$mp = MouseGetPos() ; mouse cursor: hidden after 3 s without movement, back on movement
		If $mp[0] <> $iMx Or $mp[1] <> $iMy Then
			$iMx = $mp[0]
			$iMy = $mp[1]
			$tMouse = TimerInit()
			_Cursor(True)
		ElseIf TimerDiff($tMouse) > 3000 Then
			If _OverVideo(False) Then _Cursor(False)
		EndIf
	Else
		_Cursor(True)
	EndIf
	$r = DllCall("user32.dll", "short", "GetAsyncKeyState", "int", 1)
	If IsArray($r) Then $dn = BitAND($r[0], 0x8000) <> 0
	If $dn And Not $bDown Then ; new left click on the video
		If _OverVideo(Not $fFull) Then
			If Not WinActive($hMain) Then WinActivate($hMain) ; keep the keyboard on the player
			If $fClick And TimerDiff($tChg) > 500 Then _VidKey("w") ; single click: fullscreen <-> window
		EndIf
	EndIf
	$bDown = $dn
EndFunc

Func _Monitors() ; [n][4] = x, y, w, h of every monitor
	Local $a = _WinAPI_EnumDisplayMonitors()
	If Not IsArray($a) Then
		Local $d[1][4] = [[0, 0, @DesktopWidth, @DesktopHeight]]
		Return $d
	EndIf
	If $a[0][0] < 1 Then
		Local $e[1][4] = [[0, 0, @DesktopWidth, @DesktopHeight]]
		Return $e
	EndIf
	Local $r[$a[0][0]][4], $t
	For $i = 1 To $a[0][0]
		$t = $a[$i][1]
		$r[$i - 1][0] = DllStructGetData($t, "Left")
		$r[$i - 1][1] = DllStructGetData($t, "Top")
		$r[$i - 1][2] = DllStructGetData($t, "Right") - $r[$i - 1][0]
		$r[$i - 1][3] = DllStructGetData($t, "Bottom") - $r[$i - 1][1]
	Next
	Return $r
EndFunc

Func _VidMonitor() ; [x, y, w, h] of the monitor the video goes to: the one chosen with D, else the player's
	If $iMon > 0 Then
		Local $m = _Monitors()
		If $iMon <= UBound($m) Then
			Local $r[4] = [$m[$iMon - 1][0], $m[$iMon - 1][1], $m[$iMon - 1][2], $m[$iMon - 1][3]]
			Return $r
		EndIf
	EndIf
	Return _MonitorRect($hMain)
EndFunc

Func _MonRemember() ; the video window sits on another monitor than the player: that monitor is the video monitor from now on
	Local $c = _MonitorRect($hVid), $mo = _Monitors()
	For $i = 0 To UBound($mo) - 1
		If $mo[$i][0] = $c[0] And $mo[$i][1] = $c[1] Then
			$iMon = $i + 1
			ExitLoop
		EndIf
	Next
EndFunc

Func _NextMonitor() ; D: send the video to the next monitor (back to "the player's monitor" as soon as the player is moved)
	If Not ($fPlay And $fVid And $fVidOn) Then Return
	Local $m = _Monitors(), $c = _VidMonitor(), $idx = 0
	If UBound($m) < 2 Then
		_Note("only one monitor")
		Return
	EndIf
	For $i = 0 To UBound($m) - 1
		If $m[$i][0] = $c[0] And $m[$i][1] = $c[1] Then $idx = $i
	Next
	$iMon = Mod($idx + 1, UBound($m)) + 1
	If $fWmp Then ; WMP picks the monitor when it enters fullscreen: leave it, move the host window, enter again
		$fWFS = False
		$oWMP.fullScreen = False
		Sleep(350)
	EndIf
	$sWin = ""
	_VidApply()
	_Note("video on monitor " & $iMon)
EndFunc

Func _Zoom($d) ; + / - / 0: zoom the video (odd resolutions, baked-in black bars); MCI videos only
	If Not ($fPlay And $fVid) Then Return
	If $fWmp Then
		_Note("zoom is not available for WMP videos")
		Return
	EndIf
	If $d = 0 Then
		$iZoom = 100
	Else
		$iZoom = _Min(_Max($iZoom + $d, 50), 300)
	EndIf
	_VideoSize()
	_Note("zoom " & $iZoom & "%")
EndFunc

Func _AudioTrack() ; A: next audio track (WMP: its audio languages; the MCI driver has no track selection)
	If Not ($fPlay And $fVid) Then Return
	If $fFFrun Then ; ffplay's own key "a" = next audio stream (posted to its window)
		If $hFF Then
			DllCall("user32.dll", "bool", "PostMessageW", "hwnd", $hFF, "uint", 0x100, "wparam", 0x41, "lparam", 0x001E0001)
			DllCall("user32.dll", "bool", "PostMessageW", "hwnd", $hFF, "uint", 0x101, "wparam", 0x41, "lparam", 0xC01E0001)
			_Note("audio: next track")
		Else
			_Note("audio track: video window not ready")
		EndIf
		Return
	EndIf
	If Not $fWmp Then
		_Note("audio track selection is not available in MCI mode")
		Return
	EndIf
	Local $c = $oWMP.controls, $cnt, $i, $nm = ""
	If Not IsObj($c) Then Return
	$cnt = Number($c.audioLanguageCount)
	If $cnt < 2 Then
		_Note("audio: only one track")
		Return
	EndIf
	$i = Number($c.currentAudioLanguageIndex) + 1
	If $i >= $cnt Then $i = 0
	$c.currentAudioLanguageIndex = $i
	$nm = $c.getLanguageName($c.getAudioLanguageID($i))
	_Note("audio " & ($i + 1) & "/" & $cnt & ($nm <> "" ? ": " & $nm : ""))
EndFunc

Func _Note($t) ; short message in the player header and (while a video is shown) on the video
	GUICtrlSetData($lblNow, $t)
	$tNote = TimerInit()
	_Osd($t, 2500)
EndFunc

Func _Osd($t, $ms = 3000) ; text strip above the video: top left of the player's monitor (window mode: of the video window)
	If Not $fVidShown Or $fTray Then Return
	Local $r = _VidMonitor(), $x = $r[0] + 24, $y = $r[1] + 24, $wd = _Max(400, Int($r[2] * 0.5)), $p
	If Not $fFull And Not $fWmp Then
		$p = WinGetPos($hVid)
		If IsArray($p) Then
			$x = $p[0] + 16
			$y = $p[1] + 16
			$wd = _Max(300, $p[2] - 32)
		EndIf
	EndIf
	GUICtrlSetData($lblOsd, $t)
	GUICtrlSetPos($lblOsd, 12, 6, $wd - 24, 28)
	WinMove($hOsd, "", $x, $y, $wd, 40)
	GUISetState(@SW_SHOWNOACTIVATE, $hOsd)
	WinSetOnTop($hOsd, "", 1)
	$tOsd = TimerInit()
	$iOsdMs = $ms
	GUISwitch($hMain)
EndFunc

Func _WmpKeys($on) ; while WMP is fullscreen it owns the keyboard: register our keys as global hotkeys (only then)
	If $on = $fWK Then Return
	$fWK = $on
	Local $k = StringSplit("{SPACE}|{LEFT}|{RIGHT}|{UP}|{DOWN}|^{UP}|^{DOWN}|n|p|s|m|f|a|d|{ESC}", "|", 2)
	Local $f = StringSplit("_PlayPause|_HkBack|_HkFwd|_HkVU|_HkVD|_HkVU|_HkVD|_HkNext|_Prev|_Stop|_Mute|_HkF|_AudioTrack|_NextMonitor|_HkEsc", "|", 2)
	For $i = 0 To UBound($k) - 1
		If $on Then
			HotKeySet($k[$i], $f[$i])
		Else
			HotKeySet($k[$i])
		EndIf
	Next
EndFunc

Func _HkBack()
	_Skip(-5)
EndFunc

Func _HkFwd()
	_Skip(5)
EndFunc

Func _HkVU()
	_Vol(5)
EndFunc

Func _HkVD()
	_Vol(-5)
EndFunc

Func _HkF()
	_VidKey("f")
EndFunc

Func _HkEsc()
	_VidKey("esc")
EndFunc

Func _Cursor($show) ; show / hide the mouse cursor (ShowCursor keeps a counter)
	If $show = $fCurOn Then Return
	$fCurOn = $show
	Local $r, $v, $i = 0
	Do
		$r = DllCall("user32.dll", "int", "ShowCursor", "bool", $show)
		$v = IsArray($r) ? $r[0] : ($show ? 0 : -1)
		$i += 1
	Until ($show ? $v >= 0 : $v < 0) Or $i > 20
EndFunc

Func _KeepAwake($on) ; no screensaver / display sleep while on (SetThreadExecutionState instead of faking input)
	$on = $on And $fKeepAw ; (option)
	If $on = $fAwake Then Return
	$fAwake = $on
	DllCall("kernel32.dll", "dword", "SetThreadExecutionState", "dword", $on ? 0x80000003 : 0x80000000) ; ES_CONTINUOUS (+ DISPLAY + SYSTEM required)
EndFunc

Func _PL() ; collapse / expand the playlist
	$fPL = Not $fPL
	_PLApply()
EndFunc

Func _PLApply() ; list + buttons shown or hidden, the window gets shorter / taller
	Local $s = $fPL ? $GUI_SHOW : $GUI_HIDE
	GUICtrlSetState($lst, $s)
	GUICtrlSetState($bAddF, $s)
	GUICtrlSetState($bAddD, $s)
	GUICtrlSetState($bDel, $s)
	GUICtrlSetState($bClr, $s)
	GUICtrlSetState($bSave, $s)
	GUICtrlSetState($bLoad, $s)
	WinMove($hMain, "", Default, Default, 480, $fPL ? 540 : 312)
	_PLText()
EndFunc

Func _PLText()
	GUICtrlSetData($bPL, "   PLAYLIST   (" & UBound($aPl) & ")")
EndFunc

Func _OverVideo($bClient = False) ; is the mouse over the (visible, not covered) video window? $bClient: only over the picture, not the title bar
	Local $m = MouseGetPos(), $t = DllStructCreate($tagPOINT)
	DllStructSetData($t, "X", $m[0])
	DllStructSetData($t, "Y", $m[1])
	Local $h = _WinAPI_WindowFromPoint($t)
	If Not $h Then Return False
	If $bClient And $h = $hVid Then
		If Not $hFF Then Return False
		Local $pf = WinGetPos($hFF) ; ffplay's window is disabled (clicks fall through to the host) -> "picture" = its rectangle
		Return IsArray($pf) And $m[0] >= $pf[0] And $m[0] < $pf[0] + $pf[2] And $m[1] >= $pf[1] And $m[1] < $pf[1] + $pf[3]
	EndIf
	Return _WinAPI_GetAncestor($h, 2) = $hVid ; GA_ROOT
EndFunc

Func _MonitorRect($hWnd) ; [x, y, w, h] of the monitor the window is on
	Local $a[4] = [0, 0, @DesktopWidth, @DesktopHeight]
	Local $r = DllCall("user32.dll", "handle", "MonitorFromWindow", "hwnd", $hWnd, "dword", 2) ; nearest monitor
	If Not IsArray($r) Then Return $a
	Local $t = DllStructCreate("dword;long;long;long;long;long;long;long;long;dword")
	DllStructSetData($t, 1, DllStructGetSize($t))
	$r = DllCall("user32.dll", "bool", "GetMonitorInfoW", "handle", $r[0], "struct*", $t)
	If Not IsArray($r) Then Return $a
	If Not $r[0] Then Return $a
	$a[0] = DllStructGetData($t, 2)
	$a[1] = DllStructGetData($t, 3)
	$a[2] = DllStructGetData($t, 4) - $a[0]
	$a[3] = DllStructGetData($t, 5) - $a[1]
	Return $a
EndFunc

Func _VideoSize() ; MCI: fullscreen = picture letterboxed into the monitor | window = client area gets the video's size. WMP: fullscreen is its own
	If Not ($fPlay And $fVid) Then Return
	If $fFFrun Then Return _FFSize()
	If $fWmp Then
		$oWMP.stretchToFit = True
		If $fVidOn And $iVSz >= 1 Then
			If Not $oWMP.fullScreen Then $oWMP.fullScreen = True
		EndIf
		Return
	EndIf
	Local $z = WinGetClientSize($hVid)
	If Not IsArray($z) Then Return
	If $z[0] < 2 Or $z[1] < 2 Then Return
	Local $a = StringSplit(_Mci("where bp source"), " ", 2), $x = 0, $y = 0, $w = $z[0], $h = $z[1], $k, $sw = 0, $sh = 0
	If UBound($a) >= 4 Then
		$sw = Number($a[2])
		$sh = Number($a[3])
	EndIf
	If Not $fFull Then ; window: client area = video size (scaled down if it does not fit the monitor)
		Local $mr = _VidMonitor(), $cw = ($sw > 0) ? $sw : 640, $ch = ($sh > 0) ? $sh : 360
		$k = _Min(1, _Min($mr[2] * 0.9 / $cw, $mr[3] * 0.9 / $ch))
		$cw = Int($cw * $k)
		$ch = Int($ch * $k)
		If $sWin <> $cw & "x" & $ch Then ; new video / mode: resize + center once (afterwards the user may move the window)
			$sWin = $cw & "x" & $ch
			Local $ps = WinGetPos($hVid)
			If IsArray($ps) Then
				Local $ex = $ps[2] - $z[0], $ey = $ps[3] - $z[1] ; title bar + borders
				WinMove($hVid, "", $mr[0] + Int(($mr[2] - $cw - $ex) / 2), $mr[1] + Int(($mr[3] - $ch - $ey) / 2), $cw + $ex, $ch + $ey)
			EndIf
		EndIf
		$w = Int($cw * $iZoom / 100) ; zoom: bigger than the window = cropped (the window clips), smaller = black border
		$h = Int($ch * $iZoom / 100)
		_Mci("put bp window at " & Int(($cw - $w) / 2) & " " & Int(($ch - $h) / 2) & " " & $w & " " & $h)
		Return
	EndIf
	If $sw > 0 And $sh > 0 Then ; fullscreen: keep the aspect ratio, black bars
		$k = _Min($z[0] / $sw, $z[1] / $sh)
		$w = Int($sw * $k)
		$h = Int($sh * $k)
	EndIf
	$w = Int($w * $iZoom / 100) ; zoom (+ / -)
	$h = Int($h * $iZoom / 100)
	$x = Int(($z[0] - $w) / 2)
	$y = Int(($z[1] - $h) / 2)
	_Mci("put bp window at " & $x & " " & $y & " " & $w & " " & $h)
EndFunc

; ================= external engine: ffplay =================
Func _FFReady() ; option on + ffplay.exe present
	Return $fFF And FileExists($sFFPlay)
EndFunc

Func _OpenFF($f, $pos) ; True if ffplay started
	$sFFFile = $f
	$fFFrun = True
	$fEmb = _IsVid($f) And Not $fWine ; (Wine: audio only, the SDL window can't be embedded there)
	$iFFw = 0
	$iFFh = 0
	$iZoom = 100 ; (a new track starts unzoomed anyway)
	$sFFWant = ""
	Return _FFLaunch($pos)
EndFunc

Func _FFLaunch($pos) ; (re)start ffplay at $pos seconds with the current volume / balance
	_FFKillProc()
	$sFFMode = _FFWantMode()
	Local $vid = _IsVid($sFFFile) And Not $fWine, $c = '"' & $sFFPlay & '" -hide_banner -loglevel quiet -nostats -autoexit -volume ' & $iVol
	If $pos > 0.05 Then $c &= " -ss " & StringFormat("%.2f", $pos)
	If $iBal <> 0 Then $c &= ' -af "aformat=channel_layouts=stereo,pan=stereo|c0=' & StringFormat("%.2f", $iBal > 0 ? (100 - $iBal) / 100 : 1) & "*c0|c1=" & StringFormat("%.2f", $iBal < 0 ? (100 + $iBal) / 100 : 1) & '*c1"'
	If $vid Then
		$c &= " -noborder -left -32000 -top -32000 -window_title BrAiNPlayFF" ; starts off-screen, we move it into the video window
		If $sFFMode <> "W" Then ; fullscreen / zoom: ffplay scales (+ crops / letterboxes) the picture itself to the host size - resizing its window alone is unreliable
			Local $fw, $fh, $mr, $zs
			If $fFull Then
				$mr = _VidMonitor()
				$fw = $mr[2]
				$fh = $mr[3]
			Else
				$zs = WinGetClientSize($hVid)
				$fw = IsArray($zs) ? $zs[0] : $iFFw
				$fh = IsArray($zs) ? $zs[1] : $iFFh
			EndIf
			Local $zw = Int($fw * $iZoom / 100), $zh = Int($fh * $iZoom / 100)
			$c &= " -x " & $fw & " -y " & $fh & ' -vf "scale=iw*sar:ih,setsar=1,scale=' & $zw & ":" & $zh & ":force_original_aspect_ratio=decrease,crop='min(iw," & $fw & ")':'min(ih," & $fh & ")',pad=" & $fw & ":" & $fh & ':(ow-iw)/2:(oh-ih)/2:black"'
		EndIf
	Else
		$c &= " -nodisp -vn"
	EndIf
	$c &= ' -i "' & $sFFFile & '"'
	_Dbg("ffplay: " & $c)
	$iFFPid = Run($c, $sFFDir, @SW_HIDE)
	If Not $iFFPid Then
		_Log("ffplay: cannot start " & $sFFPlay)
		$fFFrun = False
		$fFFWait = False
		Return False
	EndIf
	$iFFV = $iVol
	$iFFB = $iBal
	$fFFWait = False
	$iOff = _Max($pos - 0.3, 0) ; (start-up takes a moment)
	$tRun = TimerInit()
	$tCmd = TimerInit()
	Return True
EndFunc

Func _FFKeys() ; ffplay video visible: our keys as global hotkeys, so they work without focus and never reach ffplay (its Esc / q would quit it = next track).
	; fullscreen: all player keys | window: only the zoom keys (the rest would block typing in other programs)
	Local $w = ""
	If $fFFrun And $fVid And $fVidShown And Not $fTray Then
		$w = "{+}|{NUMPADADD}|-|{NUMPADSUB}|0"
		If $fFull Then $w &= "|{SPACE}|{LEFT}|{RIGHT}|{UP}|{DOWN}|^{UP}|^{DOWN}|n|p|s|m|f|w|a|d|{ESC}"
	EndIf
	If $w = $sFFKeys Then Return
	Local $k, $i
	If $sFFKeys <> "" Then
		$k = StringSplit($sFFKeys, "|", 2)
		For $i = 0 To UBound($k) - 1
			HotKeySet($k[$i])
		Next
	EndIf
	$sFFKeys = $w
	If $w = "" Then Return
	$k = StringSplit($w, "|", 2)
	For $i = 0 To UBound($k) - 1
		HotKeySet($k[$i], _FFKeyFn($k[$i]))
	Next
EndFunc

Func _FFKeyFn($k)
	Switch $k
		Case "{+}", "{NUMPADADD}"
			Return "_HkZI"
		Case "-", "{NUMPADSUB}"
			Return "_HkZO"
		Case "0"
			Return "_HkZ0"
		Case "{SPACE}"
			Return "_PlayPause"
		Case "{LEFT}"
			Return "_HkBack"
		Case "{RIGHT}"
			Return "_HkFwd"
		Case "{UP}", "^{UP}"
			Return "_HkVU"
		Case "{DOWN}", "^{DOWN}"
			Return "_HkVD"
		Case "n"
			Return "_HkNext"
		Case "p"
			Return "_Prev"
		Case "s"
			Return "_Stop"
		Case "m"
			Return "_Mute"
		Case "f"
			Return "_HkF"
		Case "w"
			Return "_HkW"
		Case "a"
			Return "_AudioTrack"
		Case "d"
			Return "_NextMonitor"
	EndSwitch
	Return "_HkEsc" ; {ESC}
EndFunc

Func _HkZI()
	_Zoom(10)
EndFunc

Func _HkZO()
	_Zoom(-10)
EndFunc

Func _HkZ0()
	_Zoom(0)
EndFunc

Func _HkW()
	_VidKey("w")
EndFunc

Func _FFWantMode() ; command line variant the current state needs: W = plain window | F... = fullscreen (monitor size) | WZ... = window with zoom
	If $fFull Then
		Local $m = _VidMonitor()
		Return "F" & $m[2] & ":" & $m[3] & "Z" & $iZoom
	EndIf
	If $iZoom <> 100 And $iFFw > 0 Then Return "WZ" & $iZoom
	Return "W"
EndFunc

Func _FFRestart()
	_FFLaunch(_Pos())
EndFunc

Func _FFKillProc()
	If $iFFPid Then ProcessClose($iFFPid)
	$iFFPid = 0
	$hFF = 0
EndFunc

Func _FFKill()
	_FFKillProc()
	$fFFrun = False
	$fFFWait = False
EndFunc

Func _FFSusp($on) ; pause an audio-only ffplay (no window, so nothing can hang on it)
	If Not $iFFPid Then Return
	Local $h = DllCall("kernel32.dll", "handle", "OpenProcess", "dword", 0x0800, "bool", False, "dword", $iFFPid)
	If @error Or Not IsArray($h) Then Return
	If Not $h[0] Then Return
	DllCall("ntdll.dll", "long", $on ? "NtSuspendProcess" : "NtResumeProcess", "handle", $h[0])
	DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $h[0])
EndFunc

Func _FFEmbed() ; find ffplay's SDL window, make it a disabled child of the video window
	Local $a = WinList("[TITLE:BrAiNPlayFF]"), $h = 0
	For $i = 1 To $a[0][0]
		If WinGetProcess($a[$i][1]) = $iFFPid Then
			$h = $a[$i][1]
			ExitLoop
		EndIf
	Next
	If Not $h Then Return False
	If Not BitAND(WinGetState($h), 2) Then Return False ; ffplay creates the window hidden and shows + sizes it (to the video) with the first frame -> embed only then, else it resizes itself afterwards
	Local $p = WinGetPos($h)
	If IsArray($p) And $p[2] > 16 And $iFFw = 0 And $sFFMode = "W" Then
		$iFFw = $p[2] ; native video size (for the window mode)
		$iFFh = $p[3]
	EndIf
	_WinAPI_SetWindowLong($h, -16, BitOR($WS_CHILD, $WS_VISIBLE, $WS_DISABLED)) ; disabled: no mouse / keys reach ffplay, clicks fall through to our video window
	_WinAPI_SetParent($h, $hVid)
	DllCall("user32.dll", "bool", "SetWindowPos", "hwnd", $h, "hwnd", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37)
	$hFF = $h
	$iFFWw = 0
	Return True
EndFunc

Func _FFSize() ; fullscreen: the picture fills the host window (SDL letterboxes) | window: host gets the video's size | zoom: bigger than the host = cropped
	If Not $hFF Then Return
	Local $z = WinGetClientSize($hVid), $w, $h, $k
	If Not IsArray($z) Then Return
	If $z[0] < 2 Or $z[1] < 2 Then Return
	$w = $z[0]
	$h = $z[1]
	If Not $fFull Then
		Local $mr = _VidMonitor(), $cw = $iFFw > 0 ? $iFFw : 640, $ch = $iFFh > 0 ? $iFFh : 360
		$k = _Min(1, _Min($mr[2] * 0.9 / $cw, $mr[3] * 0.9 / $ch))
		$cw = Int($cw * $k)
		$ch = Int($ch * $k)
		If $sWin <> $cw & "x" & $ch Then
			$sWin = $cw & "x" & $ch
			Local $ps = WinGetPos($hVid)
			If IsArray($ps) Then
				WinMove($hVid, "", $mr[0] + Int(($mr[2] - $cw - ($ps[2] - $z[0])) / 2), $mr[1] + Int(($mr[3] - $ch - ($ps[3] - $z[1])) / 2), $cw + ($ps[2] - $z[0]), $ch + ($ps[3] - $z[1]))
			EndIf
			$z = WinGetClientSize($hVid)
			If Not IsArray($z) Then Return
		EndIf
		$w = $z[0]
		$h = $z[1]
	EndIf
	$iFFWw = $w
	$iFFWh = $h
	DllCall("user32.dll", "bool", "SetWindowPos", "hwnd", $hFF, "hwnd", 0, "int", Int(($z[0] - $w) / 2), "int", Int(($z[1] - $h) / 2), "int", $w, "int", $h, "uint", 0x54) ; NOZORDER | NOACTIVATE | SHOWWINDOW
	Local $cs = WinGetClientSize($hFF)
	_Dbg("ffplay size: want " & $w & "x" & $h & " | host " & $z[0] & "x" & $z[1] & " | child now " & (IsArray($cs) ? $cs[0] & "x" & $cs[1] : "?"))
EndFunc

; --- ffplay download (background, like MultiDL): zip -> tar / PowerShell -> ffplay.exe; refreshed every 30 days ---
Func _FFAuto() ; at start: option on and ffplay missing or older than 30 days -> download
	If Not $fFF Then Return
	Local $d = IniRead($sIni, "ffplay", "updated", "")
	If Not FileExists($sFFPlay) Or Not StringRegExp($d, "^\d{4}/\d\d/\d\d$") Or _DateDiff("D", $d, _NowCalcDate()) >= 30 Then _FFDownload()
EndFunc

Func _FFDownload()
	If $iFFDl Then Return
	DirCreate($sFFDir)
	FileDelete($sFFDir & "\ff.zip")
	$iFFTry = 0
	_FFDlStart()
EndFunc

Func _FFDlStart()
	$hFFDl = InetGet($aFFUrl[$iFFTry], $sFFDir & "\ff.zip", 1, 1) ; force reload, background
	$iFFDl = 1
	$sFFStat = "downloading ..."
	_Log("ffplay: download " & $aFFUrl[$iFFTry])
EndFunc

Func _FFDlFail($t)
	$iFFDl = 0
	$sFFStat = $t
	_Log("ffplay: " & $t)
	DirRemove($sFFDir & "\tmp", 1)
	FileDelete($sFFDir & "\ff.zip")
EndFunc

Func _FFFound() ; path of the extracted ffplay.exe or ""
	Local $a = _FileListToArrayRec($sFFDir & "\tmp", "ffplay.exe", 1, 1, 0, 2)
	If @error Or Not IsArray($a) Then Return ""
	Return $a[1]
EndFunc

Func _FFDlPoll() ; every 200 ms
	If Not $iFFDl Then Return
	Local $t, $b, $ok, $z = $sFFDir & "\ff.zip", $x = $sFFDir & "\tmp"
	Switch $iFFDl
		Case 1 ; downloading
			If Not InetGetInfo($hFFDl, 2) Then
				$t = InetGetInfo($hFFDl, 1)
				$b = InetGetInfo($hFFDl, 0)
				$sFFStat = "downloading " & ($t > 0 ? Int($b / $t * 100) & " %" : Round($b / 1048576) & " MB")
				Return
			EndIf
			$ok = InetGetInfo($hFFDl, 3)
			InetClose($hFFDl)
			If Not $ok Then
				If $iFFTry + 1 < UBound($aFFUrl) Then ; second source
					$iFFTry += 1
					_FFDlStart()
				Else
					_FFDlFail("download failed (retry at next start or with UPDATE)")
				EndIf
				Return
			EndIf
			DirRemove($x, 1)
			DirCreate($x)
			$iFFProc = Run('tar -xf "' & $z & '" -C "' & $x & '"', "", @SW_HIDE)
			$iFFDl = 2
			$sFFStat = "extracting ..."
		Case 2 ; tar
			If $iFFProc And ProcessExists($iFFProc) Then Return
			$sFFNew = _FFFound()
			If $sFFNew <> "" Then
				$iFFDl = 4
			Else ; no tar (old Windows / Wine) -> PowerShell
				$iFFProc = Run('powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath ''' & $z & ''' -DestinationPath ''' & $x & ''' -Force"', "", @SW_HIDE)
				$iFFDl = 3
			EndIf
		Case 3 ; PowerShell
			If $iFFProc And ProcessExists($iFFProc) Then Return
			$sFFNew = _FFFound()
			If $sFFNew = "" Then
				_FFDlFail("extracting failed (no ffplay.exe in the archive)")
			Else
				$iFFDl = 4
			EndIf
		Case 4 ; swap in the new ffplay.exe (not while the old one is playing)
			If $iFFPid And ProcessExists($iFFPid) And FileExists($sFFPlay) Then
				$sFFStat = "update ready, waiting for the playback to stop"
				Return
			EndIf
			If FileMove($sFFNew, $sFFPlay, 1) Then
				IniWrite($sIni, "ffplay", "updated", _NowCalcDate())
				DirRemove($x, 1)
				FileDelete($z)
				$iFFDl = 0
				$sFFStat = ""
				_Log("ffplay: installed / updated")
			Else
				_FFDlFail("could not replace ffplay.exe")
			EndIf
	EndSwitch
EndFunc

Func _FFStatText() ; line for the options window
	If $iFFDl Then Return "ffplay: " & $sFFStat
	If FileExists($sFFPlay) Then
		Local $d = IniRead($sIni, "ffplay", "updated", "")
		Return "ffplay: ready" & ($d <> "" ? " (updated " & $d & ")" : "") & ($fFF ? "" : " - switched off")
	EndIf
	Return "ffplay: " & ($sFFStat <> "" ? $sFFStat : "not installed")
EndFunc

; ================= helpers =================
Func _B($t, $x, $y, $w, $h, $c, $fs = 11) ; flat "neo" button
	Local $id = GUICtrlCreateLabel($t, $x, $y, $w, $h, BitOR($SS_CENTER, $SS_CENTERIMAGE))
	GUICtrlSetBkColor($id, $PNL)
	GUICtrlSetColor($id, $c)
	GUICtrlSetFont($id, $fs, 700)
	Return $id
EndFunc

Func _X($t, $x) ; window button: just the glyph, 34x44 click area (centered in the old 50 px slot)
	Local $id = GUICtrlCreateLabel($t, $x + 8, 4, 34, 44, BitOR($SS_CENTER, $SS_CENTERIMAGE))
	GUICtrlSetBkColor($id, $GUI_BKCOLOR_TRANSPARENT)
	GUICtrlSetColor($id, $OFF)
	GUICtrlSetFont($id, 16, 400)
	Return $id
EndFunc

Func _Hover() ; highlight window button under the mouse
	Local $c = GUIGetCursorInfo($hMain), $id = IsArray($c) ? $c[4] : 0
	If $id = $iHov Then Return
	$iHov = $id
	GUICtrlSetColor($bMin, $id = $bMin ? $ACC : $OFF)
	GUICtrlSetColor($bClose, $id = $bClose ? 0xFF4D6D : $OFF)
	GUICtrlSetColor($bOpt, $id = $bOpt ? $ACC : $OFF)
EndFunc

Func _Tip() ; tray tooltip = current track
	TraySetToolTip($fPlay ? StringLeft($sNow, 120) : "BrAiNPlay")
EndFunc

Func _Name($f)
	Return StringRegExpReplace($f, "^.*\\|\.[^.]*$", "")
EndFunc

Func _T($s)
	Return StringFormat("%02d:%02d", Int($s / 60), Mod(Int($s), 60))
EndFunc

Func _Err()
EndFunc

Func _IsWine() ; Wine exports wine_get_version from ntdll
	Local $r = DllCall("ntdll.dll", "str:cdecl", "wine_get_version")
	If @error Or Not IsArray($r) Then Return False
	Return $r[0] <> ""
EndFunc

Func _Dbg($s) ; breadcrumbs for crash hunting ([general] debug=1, default on for now)
	If $fDbg Then _Log("dbg: " & $s)
EndFunc

Func _Log($s) ; %APPDATA%\BrAiNPlay\brainplay.log (can be switched off in the options)
	If Not $fLog Then Return
	FileWriteLine($sApp & "\brainplay.log", @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC & "  " & $s)
EndFunc

Func _WmpErr() ; last WMP error text (if any)
	Local $e = $oWMP.Error
	If Not IsObj($e) Then Return ""
	If $e.errorCount < 1 Then Return ""
	Local $it = $e.Item(0)
	If Not IsObj($it) Then Return ""
	Return $it.errorDescription
EndFunc

Func _MciErr($n) ; MCI error code -> text
	Local $t = DllStructCreate("wchar[256]")
	DllCall("winmm.dll", "int", "mciGetErrorStringW", "dword", $n, "ptr", DllStructGetPtr($t), "uint", 255)
	Return $n & " " & DllStructGetData($t, 1)
EndFunc

Func _Quit()
	_MqQuit()
	_FFKill()
	$fFFrun = False
	_FFKeys()
	If $iFFDl = 1 Then InetClose($hFFDl)
	_WmpKeys(False)
	_Cursor(True)
	_KeepAwake(False)
	If IsObj($oWMP) Then $oWMP.controls.stop()
	_Mci("close bp")
	IniWrite($sIni, "player", "video", $fVidOn ? "1" : "0")
	IniWrite($sIni, "player", "full", $fFull ? "1" : "0")
	IniWrite($sIni, "player", "plist", $fPL ? "1" : "0")
	FileDelete($sTmp)
	IniWrite($sIni, "player", "vol", $iVol)
	IniWrite($sIni, "player", "bal", $iBal)
	IniWrite($sIni, "player", "shuf", $fShuf ? "1" : "0")
	IniWrite($sIni, "player", "loop", $fLoop ? "1" : "0")
	If $fSavePL And UBound($aPl) Then
		_SaveList($sLast)
	Else
		FileDelete($sLast)
	EndIf
EndFunc

; ================= MP3 stream fixer =================
; Some mp3s play in VLC but not via MCI / SoundPlay(): the real MPEG stream does not start at byte 0 or right after the
; ID3v2 tag (scene-release ASCII-art headers, junk, oversized/broken tags ...).
; Writes a copy that starts at the first real MPEG frame to %TEMP% (one reused file, no re-encoding, original untouched).
; Returns: temp path | original path if there is nothing to cut | "" on error
Func _SoundPlayFixMP3($sFile, $sOut = "")
	If $sOut = "" Then $sOut = @TempDir & "\SoundPlay_clean.mp3"
	If Not FileExists($sFile) Then Return ""
	Local $hIn = FileOpen($sFile, 16)
	If $hIn = -1 Then Return ""
	Local $iSize = FileGetSize($sFile), $iStart = 0, $iAudioStart, $bHeader = FileRead($hIn, 10), $b1, $b2, $b3, $b4
	If BinaryLen($bHeader) = 10 And BinaryToString(BinaryMid($bHeader, 1, 3)) = "ID3" Then ; skip the ID3v2 block (syncsafe size)
		$b1 = Dec(Hex(BinaryMid($bHeader, 7, 1)))
		$b2 = Dec(Hex(BinaryMid($bHeader, 8, 1)))
		$b3 = Dec(Hex(BinaryMid($bHeader, 9, 1)))
		$b4 = Dec(Hex(BinaryMid($bHeader, 10, 1)))
		If Not (BitAND($b1, 0x80) Or BitAND($b2, 0x80) Or BitAND($b3, 0x80) Or BitAND($b4, 0x80)) Then
			$iStart = 10 + $b1 * 2097152 + $b2 * 16384 + $b3 * 128 + $b4
			If BitAND(Dec(Hex(BinaryMid($bHeader, 6, 1))), 0x10) Then $iStart += 10 ; ID3v2 footer
			If $iStart >= $iSize Then $iStart = 0
		EndIf
	EndIf
	$iAudioStart = _FindStream($hIn, $iStart, $iSize) ; first real MPEG stream (3 matching frames in a row)
	If $iAudioStart < 0 Then $iAudioStart = $iStart ; none found: at least drop the ID3v2 block
	If $iAudioStart <= 0 Then ; file already starts with audio
		FileClose($hIn)
		Return $sFile
	EndIf
	FileDelete($sOut)
	Local $hOut = FileOpen($sOut, 18)
	If $hOut = -1 Then
		FileClose($hIn)
		Return ""
	EndIf
	FileSetPos($hIn, $iAudioStart, 0)
	Local $iRemaining = $iSize - $iAudioStart, $iChunk = 1024 * 1024, $iRead, $bData
	While $iRemaining > 0
		$iRead = ($iRemaining < $iChunk) ? $iRemaining : $iChunk
		$bData = FileRead($hIn, $iRead)
		If @error Or BinaryLen($bData) = 0 Then
			FileClose($hIn)
			FileClose($hOut)
			FileDelete($sOut)
			Return ""
		EndIf
		FileWrite($hOut, $bData)
		$iRemaining -= BinaryLen($bData)
	WEnd
	FileClose($hIn)
	FileClose($hOut)
	If Not FileExists($sOut) Or FileGetSize($sOut) = 0 Then
		FileDelete($sOut)
		Return ""
	EndIf
	Return $sOut
EndFunc

Func _FindStream($hIn, $iFrom, $iSize) ; file offset of the first valid MPEG stream at/after $iFrom, or -1 (scans max. 1 MB)
	Local $iCh = 65536, $iLa = 8192, $t = DllStructCreate("byte[" & ($iCh + $iLa) & "]")
	Local $iPos = $iFrom, $iLim = ($iSize < $iFrom + 1048576) ? $iSize : $iFrom + 1048576, $b, $iLen, $iEnd, $p
	While $iPos < $iLim
		FileSetPos($hIn, $iPos, 0)
		$b = FileRead($hIn, $iCh + $iLa)
		If @error Then ExitLoop
		$iLen = BinaryLen($b)
		DllStructSetData($t, 1, $b)
		$iEnd = ($iLen < $iCh + $iLa) ? $iLen - 4 : $iCh - 1 ; last chunk: scan to the end
		For $p = 0 To $iEnd
			If DllStructGetData($t, 1, $p + 1) <> 255 Then ContinueLoop
			If _IsStream($t, $p, $iLen) Then Return $iPos + $p
		Next
		If $iLen < $iCh + $iLa Then ExitLoop
		$iPos += $iCh
	WEnd
	Return -1
EndFunc

Func _IsStream($t, $p, $iLen) ; True if 3 consecutive frames with the same version/layer/samplerate start at $p
	Local $q = $p, $fl, $sig, $s1 = 0
	For $k = 1 To 3
		If $q + 4 > $iLen Then Return False
		$fl = _FrameLen($t, $q, $sig)
		If $fl < 24 Then Return False
		If $k = 1 Then $s1 = $sig
		If $sig <> $s1 Then Return False
		$q += $fl
	Next
	Return True
EndFunc

Func _FrameLen($t, $p, ByRef $sig) ; MPEG audio frame header at buffer offset $p -> frame length in bytes (0 = no valid header), $sig = version/layer/samplerate
	Local $a = _MpegHdr($t, $p)
	$sig = $a[5]
	Return $a[0]
EndFunc

Func _MpegHdr($t, $p) ; [frame length, bitrate (bit/s), samplerate, samples per frame, channels, signature] - all 0 if there is no valid header
	Local $r[6] = [0, 0, 0, 0, 0, 0]
	If DllStructGetData($t, 1, $p + 1) <> 255 Then Return $r
	Local $b1 = DllStructGetData($t, 1, $p + 2), $b2 = DllStructGetData($t, 1, $p + 3), $b3 = DllStructGetData($t, 1, $p + 4)
	If BitAND($b1, 0xE0) <> 0xE0 Then Return $r
	Local $v = BitAND(BitShift($b1, 3), 3), $l = BitAND(BitShift($b1, 1), 3) ; v: 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5 | l: 3 = L1, 2 = L2, 1 = L3
	Local $bi = BitShift($b2, 4), $si = BitAND(BitShift($b2, 2), 3), $pad = BitAND(BitShift($b2, 1), 1)
	If $v = 1 Or $l = 0 Or $bi = 0 Or $bi = 15 Or $si = 3 Then Return $r
	Local $m1 = ($v = 3), $tb, $ts, $a, $br, $sr, $fl, $spf
	Local $sBT = "0|32|64|96|128|160|192|224|256|288|320|352|384|416|448;0|32|48|56|64|80|96|112|128|160|192|224|256|320|384;0|32|40|48|56|64|80|96|112|128|160|192|224|256|320;0|32|48|56|64|80|96|112|128|144|160|176|192|224|256;0|8|16|24|32|40|48|56|64|80|96|112|128|144|160"
	Local $sST = "44100|48000|32000;22050|24000|16000;11025|12000|8000"
	If $m1 Then
		$tb = 3 - $l
	Else
		$tb = ($l = 3) ? 3 : 4
	EndIf
	$a = StringSplit($sBT, ";", 2)
	$a = StringSplit($a[$tb], "|", 2)
	$br = $a[$bi] * 1000
	$ts = $m1 ? 0 : ($v = 2 ? 1 : 2) ; samplerate table: MPEG1 / MPEG2 / MPEG2.5
	$a = StringSplit($sST, ";", 2)
	$a = StringSplit($a[$ts], "|", 2)
	$sr = $a[$si]
	If $l = 3 Then
		$fl = (Int(12 * $br / $sr) + $pad) * 4
		$spf = 384
	ElseIf $l = 1 And Not $m1 Then
		$fl = Int(72 * $br / $sr) + $pad
		$spf = 576
	Else
		$fl = Int(144 * $br / $sr) + $pad
		$spf = 1152
	EndIf
	$r[0] = $fl
	$r[1] = $br
	$r[2] = $sr
	$r[3] = $spf
	$r[4] = (BitShift($b3, 6) = 3) ? 1 : 2
	$r[5] = $v * 100 + $l * 10 + $si
	Return $r
EndFunc

; ================= MQTT (native TCP, MQTT 3.1.1, QoS 0 - optional: [mqtt] in the ini) =================
; publishes <base>/state (retained JSON) + <base>/availability (retained, last will) and listens on <base>/cmd.
; Home Assistant MQTT discovery (device "BrAiNPlay <PC>") when discovery=1.
Func _MqInit()
	If IniRead($sIni, "mqtt", "enabled", "") = "" Then ; first start: write the defaults so the section is easy to find
		IniWrite($sIni, "mqtt", "enabled", "0")
		IniWrite($sIni, "mqtt", "host", "")
		IniWrite($sIni, "mqtt", "port", "1883")
		IniWrite($sIni, "mqtt", "user", "")
		IniWrite($sIni, "mqtt", "pass", "")
		IniWrite($sIni, "mqtt", "base", @ComputerName)
		IniWrite($sIni, "mqtt", "discovery", "1")
		IniWrite($sIni, "mqtt", "discovery_prefix", "homeassistant")
	EndIf
	$sMqHost = StringStripWS(IniRead($sIni, "mqtt", "host", ""), 3)
	$iMqPort = Int(IniRead($sIni, "mqtt", "port", "1883"))
	$sMqUser = IniRead($sIni, "mqtt", "user", "")
	$sMqPass = _PassRead() ; (stored encrypted with Windows DPAPI)
	$sMqBase = StringRegExpReplace(StringStripWS(IniRead($sIni, "mqtt", "base", @ComputerName), 3), "/+$", "")
	$sMqPre = StringRegExpReplace(StringStripWS(IniRead($sIni, "mqtt", "discovery_prefix", "homeassistant"), 3), "/+$", "")
	$fMqDisc = (IniRead($sIni, "mqtt", "discovery", "1") = "1")
	$sMqId = "brainplay_" & StringRegExpReplace(StringLower(@ComputerName), "[^a-z0-9]", "_")
	$fMq = (IniRead($sIni, "mqtt", "enabled", "0") = "1") And $sMqHost <> "" And $sMqBase <> ""
	If Not $fMq Then Return
	If TCPStartup() Then
		_MqConnect()
	Else
		$fMq = False
		_Log("mqtt: TCPStartup failed")
	EndIf
EndFunc

Func _MqConnect() ; True if connected + subscribed (blocks while connecting - retried only every 30 s)
	$tMqTry = TimerInit()
	_MqClose()
	Local $ip = TCPNameToIP($sMqHost), $t, $r = "", $b, $sb
	If $ip = "" Then
		_Log("mqtt: host not found: " & $sMqHost)
		Return False
	EndIf
	$iMqSock = TCPConnect($ip, $iMqPort)
	If @error Or $iMqSock < 0 Then
		$iMqSock = -1
		_Log("mqtt: connect failed: " & $sMqHost & ":" & $iMqPort)
		Return False
	EndIf

	; --- Paket-Inhalt (Payload) in korrekter Reihenfolge aufbauen ---
	Local $fl = 0x02 ; Clean Session Flag ist immer aktiv
	Local $sPayload = _MqStr($sMqId) ; Client ID kommt immer zuerst

	; Will-Flags setzen (Will + Will Retain) und an Payload anhängen
	$fl += 0x04 + 0x20
	$sPayload &= _MqStr($sMqBase & "/availability") & _MqStr("offline")

	; Username & Passwort prüfen, Bit-Flags setzen und an Payload anhängen
	If $sMqUser <> "" Then
		$fl = BitOR($fl, 0x80) ; Username Flag
		$sPayload &= _MqStr($sMqUser)
		If $sMqPass <> "" Then
			$fl = BitOR($fl, 0x40) ; Password Flag
			$sPayload &= _MqStr($sMqPass)
		EndIf
	EndIf

	; Header mit Protokollname ("MQTT"), Level (4), den Flags und Keepalive (60s) zusammenbauen
	Local $sBody = _MqStr("MQTT") & "04" & Hex($fl, 2) & "003C" & $sPayload

	; CONNECT-Paket (0x10) mit dynamischer Längenberechnung absenden
	TCPSend($iMqSock, Binary("0x10" & _MqLen(Int(StringLen($sBody) / 2)) & $sBody))

	$t = TimerInit()
	While TimerDiff($t) < 3000 And StringLen($r) < 8
		$r &= _MqRecvHex()
		If $iMqSock < 0 Then Return False
		Sleep(20)
	WEnd
	If StringLeft($r, 4) <> "2002" Or StringMid($r, 7, 2) <> "00" Then
		_Log("mqtt: broker refused the connection (CONNACK " & $r & ")")
		_MqClose()
		Return False
	EndIf
	$sMqBuf = StringTrimLeft($r, 8)
	$tMqPing = TimerInit()
	_Log("mqtt: connected to " & $sMqHost & ":" & $iMqPort & ", base " & $sMqBase)

	; Sendet jetzt ein sauberes PUBLISH-Paket dank fixierter _MqPub-Funktion
	_MqPub($sMqBase & "/availability", "online", True)

	; SUBSCRIBE-Paket absenden (ebenfalls mit Int-Fix)
	$sb = "0001" & _MqStr($sMqBase & "/cmd") & "00" ; SUBSCRIBE, packet id 1, QoS 0
	TCPSend($iMqSock, Binary("0x82" & _MqLen(Int(StringLen($sb) / 2)) & $sb))

	If $fMqDisc Then _MqDiscovery()
	$sMqLast = ""
	Return True
EndFunc



Func _MqPoll() ; every 200 ms from the main loop: receive commands, keepalive, publish the state when it changed
	If Not $fMq Then Return
	If $iMqSock < 0 Then
		If TimerDiff($tMqTry) > 30000 Then _MqConnect()
		Return
	EndIf
	$sMqBuf &= _MqRecvHex()
	_MqParse()
	If $iMqSock < 0 Then Return
	If TimerDiff($tMqPing) > 30000 Then
		TCPSend($iMqSock, Binary("0xC000")) ; PINGREQ
		If @error Then _MqClose()
		$tMqPing = TimerInit()
	EndIf
	Local $j = _MqJson()
	If $j <> $sMqLast And TimerDiff($tMqPub) > 300 Then
		$sMqLast = $j
		$tMqPub = TimerInit()
		_MqPub($sMqBase & "/state", $j, True)
	EndIf
EndFunc

Func _MqQuit()
	If $iMqSock >= 0 Then
		_MqPub($sMqBase & "/availability", "offline", True)
		TCPSend($iMqSock, Binary("0xE000")) ; DISCONNECT
		Sleep(50)
	EndIf
	_MqClose()
	If $fMq Then TCPShutdown()
EndFunc

Func _MqClose()
	If $iMqSock >= 0 Then TCPCloseSocket($iMqSock)
	$iMqSock = -1
	$sMqBuf = ""
EndFunc

Func _MqRecvHex() ; received bytes as a hex string ("" = nothing); closes the socket when the connection is gone
	If $iMqSock < 0 Then Return ""
	Local $r = TCPRecv($iMqSock, 8192, 1)
	If @error Then
		_Log("mqtt: connection lost")
		_MqClose()
		Return ""
	EndIf
	Return StringTrimLeft($r, 2)
EndFunc

Func _MqPub($t, $p, $ret = False) ; PUBLISH, QoS 0
	If $iMqSock < 0 Then Return
	Local $b = _MqStr($t) & StringTrimLeft(StringToBinary($p, 4), 2) ; topic + UTF-8 payload
	; FIX: Hier fehlte das Int() bei der Längenberechnung!
	TCPSend($iMqSock, Binary("0x" & ($ret ? "31" : "30") & _MqLen(Int(StringLen($b) / 2)) & $b))
	If @error Then _MqClose()
EndFunc

Func _MqStr($s) ; UTF-8 string with 2-byte length, as hex
	Local $b = StringToBinary($s, 4)
	Return Hex(BinaryLen($b), 4) & StringTrimLeft($b, 2)
EndFunc

Func _MqLen($n) ; MQTT "remaining length" (1-4 bytes), as hex
	Local $h = "", $d
	Do
		$d = Mod($n, 128)
		$n = Int($n / 128)
		If $n > 0 Then $d += 128
		$h &= Hex($d, 2)
	Until $n = 0
	Return $h
EndFunc

Func _MqParse() ; handle all complete packets in $sMqBuf (hex string); only PUBLISH on <base>/cmd matters
	Local $len, $mul, $i, $b, $total, $pk, $hdr, $qos, $tl, $topic, $po, $pl
	While StringLen($sMqBuf) >= 4
		$len = 0
		$mul = 1
		$i = 3
		Do
			If $i + 1 > StringLen($sMqBuf) Then Return ; length bytes not complete yet
			$b = Dec(StringMid($sMqBuf, $i, 2))
			$len += BitAND($b, 127) * $mul
			$mul *= 128
			$i += 2
		Until BitAND($b, 128) = 0 Or $mul > 2097152
		$total = ($i - 1) + $len * 2
		If StringLen($sMqBuf) < $total Then Return ; wait for the rest
		$pk = StringLeft($sMqBuf, $total)
		$sMqBuf = StringTrimLeft($sMqBuf, $total)
		$hdr = Dec(StringLeft($pk, 2))
		If BitShift($hdr, 4) = 3 Then ; PUBLISH
			$qos = BitAND(BitShift($hdr, 1), 3)
			$tl = Dec(StringMid($pk, $i, 4))
			$topic = BinaryToString("0x" & StringMid($pk, $i + 4, $tl * 2), 4)
			$po = $i + 4 + $tl * 2 + ($qos > 0 ? 4 : 0)
			$pl = BinaryToString("0x" & StringMid($pk, $po), 4)
			If $topic = $sMqBase & "/cmd" Then _MqCmd($pl)
		EndIf
	WEnd
EndFunc

Func _MqJson() ; the player state as JSON (published when it changes)
	Local $st = $fPlay ? ($fPause ? "paused" : "playing") : "stopped", $f = ($fPlay And $iCur >= 0 And $iCur < UBound($aPl)) ? _Name($aPl[$iCur]) : ""
	Return '{"state":"' & $st & '","name":"' & _Js($fPlay ? $sNow : "") & '","title":"' & _Js($fPlay ? $sTagT : "") & '","artist":"' & _Js($fPlay ? $sTagA : "") & '","album":"' & _Js($fPlay ? $sTagAl : "") & '","file":"' & _Js($f) & '","track":' & ($fPlay ? $iCur + 1 : 0) & ',"tracks":' & UBound($aPl) & ',"length":' & ($fPlay ? Int($iLen) : 0) & ',"volume":' & $iVol & ',"balance":' & $iBal & ',"muted":' & ($iVol = 0 ? "true" : "false") & ',"shuffle":' & ($fShuf ? "true" : "false") & ',"loop":' & ($fLoop ? "true" : "false") & ',"video":' & (($fPlay And $fVid) ? "true" : "false") & '}'
EndFunc

Func _Js($s) ; JSON string escape
	$s = StringReplace($s, "\", "\\")
	$s = StringReplace($s, '"', '\"')
	$s = StringReplace($s, @CRLF, " ")
	$s = StringReplace($s, @CR, " ")
	$s = StringReplace($s, @LF, " ")
	Return StringReplace($s, @TAB, " ")
EndFunc

Func _MqCmd($p) ; command from <base>/cmd, e.g. "next", "volume 40", "seek -10", "shuffle on"
	$p = StringLower(StringStripWS($p, 3))
	Local $a = StringSplit($p, " ", 2), $v = UBound($a) > 1 ? $a[1] : ""
	_Log("mqtt cmd: " & $p)
	Switch $a[0]
		Case "playpause", "play_pause", "toggle"
			_PlayPause()
		Case "play"
			If Not $fPlay Or $fPause Then _PlayPause()
		Case "pause"
			If $fPlay And Not $fPause Then _PlayPause()
		Case "stop"
			_Stop()
		Case "next"
			_Next(1)
		Case "prev", "previous"
			_Next(-1)
		Case "vol_up", "volume_up"
			_Vol(5)
		Case "vol_down", "volume_down"
			_Vol(-5)
		Case "mute"
			_Mute()
		Case "volume"
			$iVol = Int(_Min(_Max(Number($v), 0), 100))
			_Apply()
		Case "balance"
			$iBal = Int(_Min(_Max(Number($v), -100), 100))
			_Apply()
		Case "seek"
			_Skip(Number($v))
		Case "shuffle"
			$fShuf = ($v = "toggle" Or $v = "") ? Not $fShuf : ($v = "on")
			GUICtrlSetColor($bShuf, $fShuf ? $ACC : $OFF)
		Case "loop"
			$fLoop = ($v = "toggle" Or $v = "") ? Not $fLoop : ($v = "on")
			GUICtrlSetColor($bLoop, $fLoop ? $ACC : $OFF)
		Case "video", "tv"
			If $fPlay And $fVid Then
				$fVidOn = ($v = "toggle" Or $v = "") ? Not $fVidOn : ($v = "on")
				_VidApply()
			EndIf
		Case "fullscreen"
			_VidKey("f")
		Case Else
			If StringRegExp($a[0], "^\d+$") Then ; a bare number = volume
				$iVol = Int(_Min(_Max(Number($a[0]), 0), 100))
				_Apply()
			EndIf
	EndSwitch
EndFunc

Func _MqCfg($name, $obj, $extra) ; one Home Assistant discovery config
	Local $j = '{"name":"' & _Js($name) & '","unique_id":"%ID%_' & $obj & '",' & $extra & ',"availability_topic":"%BASE%/availability","device":{"identifiers":["%ID%"],"name":"BrAiNPlay ' & _Js(@ComputerName) & '","manufacturer":"BrAiNee","model":"BrAiNPlay"}}'
	$j = StringReplace($j, "%BASE%", $sMqBase)
	Return StringReplace($j, "%ID%", $sMqId)
EndFunc

Func _MqDiscovery() ; entities: Now Playing + State (sensors), Volume (number), Play/Pause, Next, Previous, Stop, Mute (buttons), Shuffle + Loop (switches)
	Local $i, $e, $bt = StringSplit("playpause|Play/Pause|mdi:play-pause;next|Next|mdi:skip-next;prev|Previous|mdi:skip-previous;stop|Stop|mdi:stop;mute|Mute|mdi:volume-mute", ";", 2), $x
	_MqPub($sMqPre & "/sensor/" & $sMqId & "/now/config", _MqCfg("Now Playing", "now", '"icon":"mdi:music","state_topic":"%BASE%/state","value_template":"{{ value_json.name or ''stopped'' }}","json_attributes_topic":"%BASE%/state"'), True)
	_MqPub($sMqPre & "/sensor/" & $sMqId & "/state/config", _MqCfg("State", "state", '"icon":"mdi:play-circle","state_topic":"%BASE%/state","value_template":"{{ value_json.state }}"'), True)
	_MqPub($sMqPre & "/number/" & $sMqId & "/volume/config", _MqCfg("Volume", "volume", '"icon":"mdi:volume-high","command_topic":"%BASE%/cmd","command_template":"volume {{ value | int }}","state_topic":"%BASE%/state","value_template":"{{ value_json.volume }}","min":0,"max":100,"step":5,"mode":"slider"'), True)
	For $i = 0 To UBound($bt) - 1
		$e = StringSplit($bt[$i], "|", 2)
		$x = '"icon":"%ICON%","command_topic":"%BASE%/cmd","payload_press":"%PAYLOAD%"'
		$x = StringReplace(StringReplace($x, "%ICON%", $e[2]), "%PAYLOAD%", $e[0])
		_MqPub($sMqPre & "/button/" & $sMqId & "/" & $e[0] & "/config", _MqCfg($e[1], $e[0], $x), True)
	Next
	_MqPub($sMqPre & "/switch/" & $sMqId & "/shuffle/config", _MqCfg("Shuffle", "shuffle", '"icon":"mdi:shuffle","command_topic":"%BASE%/cmd","payload_on":"shuffle on","payload_off":"shuffle off","state_topic":"%BASE%/state","value_template":"{{ ''ON'' if value_json.shuffle else ''OFF'' }}","state_on":"ON","state_off":"OFF"'), True)
	_MqPub($sMqPre & "/switch/" & $sMqId & "/loop/config", _MqCfg("Loop", "loop", '"icon":"mdi:repeat","command_topic":"%BASE%/cmd","payload_on":"loop on","payload_off":"loop off","state_topic":"%BASE%/state","value_template":"{{ ''ON'' if value_json.loop else ''OFF'' }}","state_on":"ON","state_off":"OFF"'), True)
EndFunc

; ================= options window =================
Func _MediaKeys($on) ; global multimedia keys on/off (off = other programs, e.g. a browser, keep them)
	Local $k = StringSplit("{MEDIA_PLAY_PAUSE}|{MEDIA_NEXT}|{MEDIA_PREV}|{MEDIA_STOP}", "|", 2), $f = StringSplit("_MkPlay|_MkNext|_MkPrev|_MkStop", "|", 2)
	For $i = 0 To 3
		If $on Then
			HotKeySet($k[$i], $f[$i])
		Else
			HotKeySet($k[$i])
		EndIf
	Next
EndFunc

Func _TogAdd($t, $x, $y, $on) ; toggle: caption + ON/OFF pill (both clickable)
	Local $c = GUICtrlCreateLabel($t, $x, $y, 240, 24, $SS_CENTERIMAGE), $p = GUICtrlCreateLabel("", $x + 250, $y, 56, 24, BitOR($SS_CENTER, $SS_CENTERIMAGE))
	GUICtrlSetColor($c, $TXT)
	GUICtrlSetFont($p, 9, 700)
	_ArrayAdd($aTc, $c)
	_ArrayAdd($aTp, $p)
	_ArrayAdd($aTs, $on ? 1 : 0)
	_TogDraw(UBound($aTs) - 1)
EndFunc

Func _TogDraw($i)
	GUICtrlSetData($aTp[$i], $aTs[$i] ? "ON" : "OFF")
	GUICtrlSetBkColor($aTp[$i], $aTs[$i] ? $ACC : $DIM)
	GUICtrlSetColor($aTp[$i], $aTs[$i] ? $BG : $OFF)
EndFunc

Func _OptInp($t, $x, $y, $w, $pw = False)
	Local $id = GUICtrlCreateInput($t, $x, $y, $w, 24, BitOR($ES_AUTOHSCROLL, $pw ? $ES_PASSWORD : 0), $WS_EX_TRANSPARENT)
	GUICtrlSetBkColor($id, $PNL)
	GUICtrlSetColor($id, $TXT)
	Return $id
EndFunc

Func _OptLbl($t, $x, $y, $w, $c = $OFF)
	Local $id = GUICtrlCreateLabel($t, $x, $y, $w, 24, $SS_CENTERIMAGE)
	GUICtrlSetColor($id, $c)
	Return $id
EndFunc

Func _Options() ; settings window (general, video, MQTT); the player keeps running while it is open
	If $fOpt Then Return
	$fOpt = True
	ReDim $aTp[0]
	ReDim $aTc[0]
	ReDim $aTs[0]
	Local $r = _MonitorRect($hMain), $w = 720, $h = 452
	Local $hOpt = GUICreate("BrAiNPlay Options", $w, $h, $r[0] + Int(($r[2] - $w) / 2), $r[1] + Int(($r[3] - $h) / 2), $WS_POPUP, $WS_EX_TOOLWINDOW, $hMain)
	GUISetBkColor($BG, $hOpt)
	GUISetFont(10, 400, 0, "Segoe UI", $hOpt)
	GUICtrlCreateLabel("O P T I O N S", 20, 14, 600, 24, -1, $GUI_WS_EX_PARENTDRAG)
	GUICtrlSetColor(-1, $ACC)
	GUICtrlSetFont(-1, 11, 700)
	Local $bX2 = _X(ChrW(215), 666)
	; --- left: general + video + log ---
	_OptLbl("GENERAL", 20, 56, 300, $ACC)
	_TogAdd("Log file (brainplay.log)", 20, 84, $fLog)
	_TogAdd("Global media keys", 20, 118, $fMKeys)
	_TogAdd("Keep screen awake during video", 20, 152, $fKeepAw)
	_TogAdd("Remember the playlist", 20, 186, $fSavePL)
	_OptLbl("VIDEO", 20, 234, 300, $ACC)
	_TogAdd("Click on video: fullscreen / window", 20, 262, $fClick)
	_OptLbl("FFPLAY", 20, 300, 300, $ACC)
	_TogAdd("Use external ffplay components", 20, 326, $fFF)
	Local $lFF = _OptLbl("", 20, 356, 330)
	Local $bLog = _B("OPEN LOG", 20, 402, 100, 36, $TXT, 9), $bDir = _B("OPEN FOLDER", 126, 402, 110, 36, $TXT, 9), $bUpd = _B("UPDATE FFPLAY", 242, 402, 108, 36, $TXT, 9)
	; --- right: MQTT ---
	_OptLbl("MQTT  (Home Assistant & co.)", 370, 56, 330, $ACC)
	_TogAdd("Enabled", 370, 84, IniRead($sIni, "mqtt", "enabled", "0") = "1")
	_OptLbl("Host", 370, 122, 80)
	Local $eHost = _OptInp($sMqHost, 460, 122, 240)
	_OptLbl("Port", 370, 156, 80)
	Local $ePort = _OptInp($iMqPort, 460, 156, 240)
	_OptLbl("User", 370, 190, 80)
	Local $eUser = _OptInp($sMqUser, 460, 190, 240)
	_OptLbl("Password", 370, 224, 80)
	Local $ePass = _OptInp($sMqPass, 460, 224, 240, True)
	_OptLbl("Base topic", 370, 258, 80)
	Local $eBase = _OptInp($sMqBase, 460, 258, 240)
	_TogAdd("Home Assistant discovery", 370, 296, $fMqDisc)
	_OptLbl("HA prefix", 370, 330, 90)
	Local $ePre = _OptInp($sMqPre, 460, 330, 240)
	Local $lSt = _OptLbl("", 370, 364, 330)
	Local $bApply = _B("SAVE", 370, 402, 160, 36, $ACC, 10), $bClose2 = _B("CANCEL", 540, 402, 160, 36, $TXT, 10)
	Local $kEsc2 = GUICtrlCreateDummy(), $aE[1][2] = [["{ESC}", $kEsc2]]
	GUISetAccelerators($aE, $hOpt)
	GUISetState(@SW_SHOW, $hOpt)
	WinSetOnTop($hOpt, "", 1)
	Local $m, $tT = TimerInit(), $done = False, $i, $pt
	While Not $done
		$m = GUIGetMsg(1)
		If $m[1] = $hOpt Then
			Switch $m[0]
				Case $GUI_EVENT_CLOSE, $bX2, $bClose2, $kEsc2
					$done = True
				Case $bLog
					ShellExecute("notepad.exe", '"' & $sApp & '\brainplay.log"')
				Case $bDir
					ShellExecute($sApp)
				Case $bUpd
					_FFDownload()
				Case $bApply
					$fLog = ($aTs[0] = 1)
					$fMKeys = ($aTs[1] = 1)
					$fKeepAw = ($aTs[2] = 1)
					$fSavePL = ($aTs[3] = 1)
					$fClick = ($aTs[4] = 1)
					IniWrite($sIni, "general", "log", $fLog ? "1" : "0")
					IniWrite($sIni, "general", "mediakeys", $fMKeys ? "1" : "0")
					IniWrite($sIni, "general", "keepawake", $fKeepAw ? "1" : "0")
					IniWrite($sIni, "general", "saveplaylist", $fSavePL ? "1" : "0")
					IniWrite($sIni, "video", "clickmode", $fClick ? "1" : "0")
					$fFF = ($aTs[5] = 1)
					IniWrite($sIni, "ffplay", "enabled", $fFF ? "1" : "0")
					_FFAuto() ; switched on: download now if ffplay is missing / old
					_MediaKeys($fMKeys)
					If Not $fKeepAw Then _KeepAwake(False)
					$pt = Int(GUICtrlRead($ePort))
					If $pt < 1 Or $pt > 65535 Then $pt = 1883
					IniWrite($sIni, "mqtt", "enabled", $aTs[6] = 1 ? "1" : "0")
					IniWrite($sIni, "mqtt", "host", StringStripWS(GUICtrlRead($eHost), 3))
					IniWrite($sIni, "mqtt", "port", $pt)
					IniWrite($sIni, "mqtt", "user", GUICtrlRead($eUser))
					_PassWrite(GUICtrlRead($ePass))
					IniWrite($sIni, "mqtt", "base", StringStripWS(GUICtrlRead($eBase), 3))
					IniWrite($sIni, "mqtt", "discovery", $aTs[7] = 1 ? "1" : "0")
					IniWrite($sIni, "mqtt", "discovery_prefix", StringStripWS(GUICtrlRead($ePre), 3))
					_MqQuit() ; reconnect with the new settings
					$fMq = False
					_MqInit()
					GUICtrlSetData($ePort, $iMqPort)
					_Log("options applied")
					$done = True ; SAVE saves everything and closes the window
				Case Else
					For $i = 0 To UBound($aTs) - 1
						If $m[0] = $aTp[$i] Or $m[0] = $aTc[$i] Then
							$aTs[$i] = 1 - $aTs[$i]
							_TogDraw($i)
						EndIf
					Next
			EndSwitch
		EndIf
		If TimerDiff($tT) > 200 Then ; keep the player alive while the window is open
			$tT = TimerInit()
			_Tick()
			_MqPoll()
			_FFDlPoll()
			GUICtrlSetData($lFF, _FFStatText())
			If $fVidShown Then _VidPoll()
			GUICtrlSetData($lSt, "MQTT: " & ($fMq ? ($iMqSock >= 0 ? "connected to " & $sMqHost & ":" & $iMqPort : "not connected (retry every 30 s)") : "disabled"))
		EndIf
	WEnd
	GUIDelete($hOpt)
	GUISwitch($hMain)
	$fOpt = False
EndFunc

; ================= password in the ini: Windows DPAPI (encrypted for this Windows user on this PC) =================
Func _PassRead() ; "dpapi:<hex>" = encrypted; plain text (old ini) is encrypted on the spot
	Local $v = IniRead($sIni, "mqtt", "pass", ""), $p
	If $v = "" Then Return ""
	If StringLeft($v, 6) = "dpapi:" Then
		$p = _DpapiDec($v)
		If $p = "" Then _Log("mqtt: cannot decrypt the password (other Windows user / PC?) - enter it again in the options")
		Return $p
	EndIf
	_PassWrite($v)
	Return $v
EndFunc

Func _PassWrite($p)
	Local $e = _DpapiEnc($p)
	IniWrite($sIni, "mqtt", "pass", $e <> "" ? $e : $p) ; plain text only if encryption is not possible
EndFunc

Func _DpapiEnc($s) ; text -> "dpapi:" & hex ("" for empty input or on failure)
	If $s = "" Then Return ""
	Local $b = StringToBinary($s, 4), $n2 = BinaryLen($b)
	Local $tD = DllStructCreate("byte[" & $n2 & "]"), $tIn = DllStructCreate("dword;ptr"), $tOut = DllStructCreate("dword;ptr")
	DllStructSetData($tD, 1, $b)
	DllStructSetData($tIn, 1, $n2)
	DllStructSetData($tIn, 2, DllStructGetPtr($tD))
	Local $r = DllCall("crypt32.dll", "bool", "CryptProtectData", "struct*", $tIn, "wstr", "BrAiNPlay", "ptr", 0, "ptr", 0, "ptr", 0, "dword", 1, "struct*", $tOut) ; flag 1 = no UI
	If @error Or Not IsArray($r) Then Return ""
	If Not $r[0] Then Return ""
	Local $cb = DllStructGetData($tOut, 1), $pb = DllStructGetData($tOut, 2)
	Local $o = DllStructGetData(DllStructCreate("byte[" & $cb & "]", $pb), 1)
	DllCall("kernel32.dll", "ptr", "LocalFree", "ptr", $pb)
	Return "dpapi:" & StringTrimLeft($o, 2)
EndFunc

Func _DpapiDec($h) ; "dpapi:<hex>" -> text ("" on failure); anything else is returned unchanged
	If StringLeft($h, 6) <> "dpapi:" Then Return $h
	Local $b = Binary("0x" & StringTrimLeft($h, 6)), $n2 = BinaryLen($b)
	If $n2 = 0 Then Return ""
	Local $tD = DllStructCreate("byte[" & $n2 & "]"), $tIn = DllStructCreate("dword;ptr"), $tOut = DllStructCreate("dword;ptr")
	DllStructSetData($tD, 1, $b)
	DllStructSetData($tIn, 1, $n2)
	DllStructSetData($tIn, 2, DllStructGetPtr($tD))
	Local $r = DllCall("crypt32.dll", "bool", "CryptUnprotectData", "struct*", $tIn, "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "dword", 1, "struct*", $tOut)
	If @error Or Not IsArray($r) Then Return ""
	If Not $r[0] Then Return ""
	Local $cb = DllStructGetData($tOut, 1), $pb = DllStructGetData($tOut, 2)
	Local $o = DllStructGetData(DllStructCreate("byte[" & $cb & "]", $pb), 1)
	DllCall("kernel32.dll", "ptr", "LocalFree", "ptr", $pb)
	Return BinaryToString($o, 4)
EndFunc

; ================= file info via Explorer columns =================
; "Artist - Title" from the tags, else the file name
Func _Tags($f) ; "Artist - Title" (also sets $sTagA / $sTagT / $sTagAl), else the file name. Shell columns first, own ID3v2 reader for mp3 without the Shell
	$sTagA = ""
	$sTagT = _Name($f)
	$sTagAl = ""
	Local $oS = 0, $p, $oF, $oI, $ti = "", $ar = "", $al = "", $a
	If Not $fNoShell Then
		$oS = ObjCreate("Shell.Application")
		If Not IsObj($oS) Then
			$fNoShell = True
			_Log("no Shell.Application (Wine / Linux?) - native fallbacks for length and tags")
		EndIf
	EndIf
	If IsObj($oS) Then
		$p = StringInStr($f, "\", 0, -1)
		$oF = $oS.Namespace(StringLeft($f, $p - 1))
		If IsObj($oF) Then
			$oI = $oF.ParseName(StringMid($f, $p + 1))
			If IsObj($oI) Then
				$ti = _Cl($oF.GetDetailsOf($oI, 21)) ; 21 = Title
				$ar = _Cl($oF.GetDetailsOf($oI, 13)) ; 13 = Contributing artists
				$al = _Cl($oF.GetDetailsOf($oI, 14)) ; 14 = Album
			EndIf
		EndIf
	EndIf
	If $ti = "" And StringRight($f, 4) = ".mp3" Then
		$a = _Id3Tags($f)
		$ti = $a[0]
		$ar = $a[1]
		$al = $a[2]
	EndIf
	If $ti = "" Then Return _Name($f)
	$sTagT = $ti
	$sTagA = $ar
	$sTagAl = $al
	Return $ar <> "" ? $ar & " " & ChrW(8211) & " " & $ti : $ti
EndFunc

Func _Cl($s) ; strip hidden unicode direction marks
	Return StringStripWS(StringRegExpReplace($s, "[\x{200E}\x{200F}\x{202A}-\x{202E}]", ""), 3)
EndFunc

; works for mp3 / wav / wma - whatever Explorer shows in the "Length" column
Func _MP3_GetLengthSec($sFile) ; length in seconds: Explorer's "Length" column first (any format), without the Shell (Wine / Linux) native readers
	If Not FileExists($sFile) Then Return 0
	Local $l = _LenShell($sFile)
	If $l > 0 Then Return $l
	Return _LenNative($sFile)
EndFunc

Func _LenShell($sFile) ; works for mp3 / wav / wma - whatever Explorer shows in the "Length" column
	If $fNoShell Then Return 0
	Local $oShell = ObjCreate("Shell.Application")
	If Not IsObj($oShell) Then
		$fNoShell = True
		_Log("no Shell.Application (Wine / Linux?) - native fallbacks for length and tags")
		Return 0
	EndIf
	Local $iSl = StringInStr($sFile, "\", 0, -1)
	If $iSl < 2 Then Return 0
	Local $sDir = StringLeft($sFile, $iSl - 1), $sName = StringTrimLeft($sFile, $iSl), $oFolder = $oShell.Namespace($sDir)
	If Not IsObj($oFolder) Then Return 0
	Local $oFile = $oFolder.ParseName($sName)
	If Not IsObj($oFile) Then Return 0
	Local $sTime = StringRegExpReplace($oFolder.GetDetailsOf($oFile, 27), "[^\d:]", "") ; strip hidden unicode marks
	If $sTime = "" Then Return 0
	Local $a = StringSplit($sTime, ":")
	Return ($a[0] = 2) ? ($a[1] * 60 + $a[2]) : (($a[0] = 3) ? ($a[1] * 3600 + $a[2] * 60 + $a[3]) : 0)
EndFunc

Func _LenNative($f) ; length without the Shell: mp3 (Xing/Info frame count, else CBR estimate), wav, mp4/m4v/mov (mvhd), avi (avih); audio else via MCI
	Local $e = StringLower(StringRegExpReplace($f, "^.*\.", "")), $l = 0
	Switch $e
		Case "mp3"
			$l = _LenMp3($f)
		Case "wav"
			$l = _LenWav($f)
		Case "mp4", "m4v", "mov"
			$l = _LenMp4($f)
		Case "avi"
			$l = _LenAvi($f)
	EndSwitch
	If $l <= 0 And ($e = "mp3" Or $e = "wav" Or $e = "wma") Then $l = _LenMci($f)
	Return $l
EndFunc

Func _BE32($t, $o) ; big-endian dword at byte offset $o of a byte[] struct
	Return DllStructGetData($t, 1, $o + 1) * 16777216 + DllStructGetData($t, 1, $o + 2) * 65536 + DllStructGetData($t, 1, $o + 3) * 256 + DllStructGetData($t, 1, $o + 4)
EndFunc

Func _LenMp3($f)
	Local $h = FileOpen($f, 16)
	If $h = -1 Then Return 0
	Local $sz = FileGetSize($f), $t = DllStructCreate("byte[4096]"), $lo = 0, $pos, $a, $v, $xo, $id, $fr
	DllStructSetData($t, 1, FileRead($h, 10))
	If DllStructGetData(DllStructCreate("char[3]", DllStructGetPtr($t)), 1) = "ID3" Then ; skip the ID3v2 block
		$lo = 10 + BitShift(DllStructGetData($t, 1, 7), -21) + BitShift(DllStructGetData($t, 1, 8), -14) + BitShift(DllStructGetData($t, 1, 9), -7) + DllStructGetData($t, 1, 10)
		If BitAND(DllStructGetData($t, 1, 6), 0x10) Then $lo += 10
	EndIf
	$pos = _FindStream($h, $lo, $sz)
	If $pos < 0 Then
		FileClose($h)
		Return 0
	EndIf
	FileSetPos($h, $pos, 0)
	DllStructSetData($t, 1, FileRead($h, 4096))
	FileClose($h)
	$a = _MpegHdr($t, 0)
	If $a[1] = 0 Then Return 0
	$v = BitAND(BitShift(DllStructGetData($t, 1, 2), 3), 3)
	$xo = 4 + (BitAND(DllStructGetData($t, 1, 2), 1) ? 0 : 2) + (($v = 3) ? ($a[4] = 1 ? 17 : 32) : ($a[4] = 1 ? 9 : 17)) ; header (+ CRC) + side info
	$id = DllStructGetData(DllStructCreate("char[4]", DllStructGetPtr($t) + $xo), 1)
	If ($id = "Xing" Or $id = "Info") And BitAND(DllStructGetData($t, 1, $xo + 8), 1) Then ; flag "frame count present"
		$fr = _BE32($t, $xo + 8)
		If $fr > 0 Then Return $fr * $a[3] / $a[2]
	EndIf
	Return ($sz - $pos) * 8 / $a[1] ; CBR estimate
EndFunc

Func _LenWav($f)
	Local $h = FileOpen($f, 16)
	If $h = -1 Then Return 0
	Local $t = DllStructCreate("byte[4096]"), $p = 12, $br = 0, $dl = 0, $id, $sz, $ptr = DllStructGetPtr($t), $fs = FileGetSize($f)
	DllStructSetData($t, 1, FileRead($h, 4096))
	FileClose($h)
	While $p < 4000
		$id = DllStructGetData(DllStructCreate("char[4]", $ptr + $p), 1)
		$sz = DllStructGetData(DllStructCreate("dword", $ptr + $p + 4), 1)
		If $id = "fmt " Then $br = DllStructGetData(DllStructCreate("dword", $ptr + $p + 16), 1)
		If $id = "data" Then
			$dl = $sz
			If $dl = 0 Or $dl > $fs Then $dl = $fs - $p - 8
			ExitLoop
		EndIf
		$p += 8 + $sz + BitAND($sz, 1)
	WEnd
	Return $br > 0 ? $dl / $br : 0
EndFunc

Func _LenMp4($f) ; walks the top-level boxes to "moov", its first child "mvhd" holds timescale + duration
	Local $h = FileOpen($f, 16)
	If $h = -1 Then Return 0
	Local $size = FileGetSize($f), $pos = 0, $t = DllStructCreate("byte[64]"), $bs, $hl, $typ, $ts, $du, $k, $b
	For $k = 1 To 64
		FileSetPos($h, $pos, 0)
		$b = FileRead($h, 16)
		If @error Or BinaryLen($b) < 16 Then ExitLoop
		DllStructSetData($t, 1, $b)
		$bs = _BE32($t, 0)
		$typ = DllStructGetData(DllStructCreate("char[4]", DllStructGetPtr($t) + 4), 1)
		$hl = 8
		If $bs = 1 Then ; 64-bit box size
			$bs = _BE32($t, 8) * 4294967296 + _BE32($t, 12)
			$hl = 16
		EndIf
		If $typ = "moov" Then
			FileSetPos($h, $pos + $hl, 0)
			DllStructSetData($t, 1, FileRead($h, 64))
			FileClose($h)
			If DllStructGetData(DllStructCreate("char[4]", DllStructGetPtr($t) + 4), 1) <> "mvhd" Then Return 0
			If DllStructGetData($t, 1, 9) = 1 Then ; version 1: 64-bit duration
				$ts = _BE32($t, 28)
				$du = _BE32($t, 32) * 4294967296 + _BE32($t, 36)
			Else
				$ts = _BE32($t, 20)
				$du = _BE32($t, 24)
			EndIf
			Return $ts > 0 ? $du / $ts : 0
		EndIf
		If $bs < 8 Then ExitLoop
		$pos += $bs
		If $pos >= $size Then ExitLoop
	Next
	FileClose($h)
	Return 0
EndFunc

Func _LenAvi($f) ; "avih": microseconds per frame x total frames
	Local $h = FileOpen($f, 16)
	If $h = -1 Then Return 0
	Local $t = DllStructCreate("byte[64]"), $p = DllStructGetPtr($t)
	DllStructSetData($t, 1, FileRead($h, 64))
	FileClose($h)
	If DllStructGetData(DllStructCreate("char[4]", $p), 1) <> "RIFF" Then Return 0
	If DllStructGetData(DllStructCreate("char[4]", $p + 8), 1) <> "AVI " Then Return 0
	If DllStructGetData(DllStructCreate("char[4]", $p + 24), 1) <> "avih" Then Return 0
	Return DllStructGetData(DllStructCreate("dword", $p + 48), 1) * DllStructGetData(DllStructCreate("dword", $p + 32), 1) / 1000000
EndFunc

Func _LenMci($f) ; last resort for audio: let MCI open the file just to ask for its length
	_Mci("close bplen")
	_Mci('open "' & $f & '" alias bplen')
	If $iErr Then Return 0
	_Mci("set bplen time format milliseconds")
	Local $l = Number(_Mci("status bplen length")) / 1000
	_Mci("close bplen")
	Return $l
EndFunc

Func _Id3Tags($f) ; [title, artist, album] from an ID3v2.3 / 2.4 tag (mp3), without the Shell
	Local $r[3] = ["", "", ""], $h = FileOpen($f, 16)
	If $h = -1 Then Return $r
	Local $t = DllStructCreate("byte[10]"), $ver, $tag, $b, $ln, $p = 0, $fid, $sz, $tb, $ptr
	DllStructSetData($t, 1, FileRead($h, 10))
	$ver = DllStructGetData($t, 1, 4)
	If DllStructGetData(DllStructCreate("char[3]", DllStructGetPtr($t)), 1) <> "ID3" Or ($ver <> 3 And $ver <> 4) Then
		FileClose($h)
		Return $r
	EndIf
	$tag = BitShift(DllStructGetData($t, 1, 7), -21) + BitShift(DllStructGetData($t, 1, 8), -14) + BitShift(DllStructGetData($t, 1, 9), -7) + DllStructGetData($t, 1, 10)
	$b = FileRead($h, _Min($tag, 262144))
	FileClose($h)
	$ln = BinaryLen($b)
	If $ln < 11 Then Return $r
	$tb = DllStructCreate("byte[" & $ln & "]")
	DllStructSetData($tb, 1, $b)
	$ptr = DllStructGetPtr($tb)
	While $p + 10 <= $ln
		If DllStructGetData($tb, 1, $p + 1) = 0 Then ExitLoop ; padding
		$fid = DllStructGetData(DllStructCreate("char[4]", $ptr + $p), 1)
		If $ver = 4 Then ; syncsafe frame size
			$sz = BitShift(DllStructGetData($tb, 1, $p + 5), -21) + BitShift(DllStructGetData($tb, 1, $p + 6), -14) + BitShift(DllStructGetData($tb, 1, $p + 7), -7) + DllStructGetData($tb, 1, $p + 8)
		Else
			$sz = _BE32($tb, $p + 4)
		EndIf
		If $sz <= 0 Or $p + 10 + $sz > $ln Then ExitLoop
		If $fid = "TIT2" Then $r[0] = _Id3Dec($tb, $p + 10, $sz)
		If $fid = "TPE1" Then $r[1] = _Id3Dec($tb, $p + 10, $sz)
		If $fid = "TALB" Then $r[2] = _Id3Dec($tb, $p + 10, $sz)
		$p += 10 + $sz
	WEnd
	Return $r
EndFunc

Func _Id3Dec($t, $off, $sz) ; text frame: 1 encoding byte + text (0 = ANSI, 1 = UTF-16 + BOM, 2 = UTF-16BE, 3 = UTF-8)
	If $sz < 2 Then Return ""
	Local $e = DllStructGetData($t, 1, $off + 1), $x = DllStructGetData(DllStructCreate("byte[" & ($sz - 1) & "]", DllStructGetPtr($t) + $off + 1), 1), $r, $bom
	Switch $e
		Case 0
			$r = BinaryToString($x, 1)
		Case 1
			$bom = Hex(BinaryMid($x, 1, 2))
			If $bom = "FEFF" Then
				$r = BinaryToString(BinaryMid($x, 3), 3)
			Else
				$r = BinaryToString($bom = "FFFE" ? BinaryMid($x, 3) : $x, 2)
			EndIf
		Case 2
			$r = BinaryToString($x, 3)
		Case Else
			$r = BinaryToString($x, 4)
	EndSwitch
	Return StringStripWS(StringReplace($r, Chr(0), ""), 3)
EndFunc   ;==>_MP3_GetLengthSec
