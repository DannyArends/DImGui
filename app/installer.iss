; app/installer.iss  -  build CalderaD installer straight from compile output.
; Compile from a vcvars64 shell (so VCToolsRedistDir is set), from the repo root:
;     iscc app/installer.iss   ->   dist\CalderaD-Setup.exe
;
; SourceDir=.. anchors every relative path at the repo root (one level above app\),
; so the invoking directory does not matter, only this script's location does.
;
; Expected layout after a Windows build (relative to repo root):
;   bin\DImGui.exe                dub output (targetName = DImGui)
;   bin\*.dll                     dependency DLLs (dub copyFiles-windows)
;   app\src\main\assets\data\     runtime assets
; The exe is installed and registered as CalderaD.exe.

#define AppName        "CalderaD"
#define AppVersion     "0.1.0"
#define AppPublisher   "Danny Arends"
#define AppExeName     "CalderaD.exe"
#define BuiltExe       "DImGui.exe"

; --- VC++ runtime redist folder, root from the environment (set by vcvars64) ---
#define VCRT GetEnv("VCToolsRedistDir")
#if VCRT == ""
  #error VCToolsRedistDir is not set. Run iscc from a vcvars64 shell.
#endif
#define VCCRT VCRT + "x64\Microsoft.VC142.CRT\"
#if FileExists(VCCRT + "VCRUNTIME140.dll") == 0
  #error VC runtime not found at VCCRT. Check the Microsoft.VCxxx.CRT folder name.
#endif

[Setup]
AppId={{7C2D9E14-3B6A-4F58-9D21-CA1DE1A00001}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
SourceDir=..
OutputDir=bin
OutputBaseFilename={#AppName}-Setup
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Built exe, renamed to CalderaD.exe on install
Source: "bin\{#BuiltExe}"; DestDir: "{app}"; DestName: "{#AppExeName}"; Flags: ignoreversion
; Every DLL dub placed in bin\ (SDL3, cimgui, assimp, shaderc, spirv-cross, glslang, ...).
; Never bundle the Vulkan loader; it must come from the GPU driver.
Source: "bin\*.dll"; DestDir: "{app}"; Excludes: "vulkan-1.dll"; Flags: ignoreversion
; VC++ runtime trio, app-local, resolved from the environment at compile time
Source: "{#VCCRT}VCRUNTIME140.dll";   DestDir: "{app}"; Flags: ignoreversion
Source: "{#VCCRT}VCRUNTIME140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VCCRT}MSVCP140.dll";        DestDir: "{app}"; Flags: ignoreversion
; Runtime assets, recursively, preserving subfolders -> {app}\data\...
Source: "app\src\main\assets\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";           Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";     Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent