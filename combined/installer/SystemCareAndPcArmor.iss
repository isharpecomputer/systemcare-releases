; iSharpe SystemCare + PC Armor: one installer for a customer who has both (Inno Setup 6).
; Build with tools\build-combined.ps1, which downloads the published SystemCare MSI and PC Armor setup and passes:
;   ISCC.exe /DSystemCareVersion=1.7.101 /DPcArmorVersion=1.4.3 /DSystemCareMsi=... /DPcArmorSetup=... SystemCareAndPcArmor.iss
;
; It installs nothing of its own and leaves nothing behind: each product installs, updates and uninstalls exactly as it does on its
; own. It asks the two questions both products need once - the customer's email, and how PC Armor protects the internet - then
; installs SystemCare and PC Armor silently and registers SystemCare under the email with SystemCare's own `server-setup`, the same
; way PC Armor's "Install SystemCare" does from the dashboard. Only when that registration fails does the finish page offer SystemCare's
; setup page (email filled in), where it can be connected by hand and the problem is shown.
#ifndef SystemCareVersion
  #define SystemCareVersion "0.0.0"
#endif
#ifndef PcArmorVersion
  #define PcArmorVersion "0.0.0"
#endif

[Setup]
AppId={{6F2B8A41-7C3D-4E59-9A1B-2D8C5E0F7A36}
AppName=iSharpe SystemCare and PC Armor
AppVersion={#SystemCareVersion}+{#PcArmorVersion}
AppVerName=iSharpe SystemCare {#SystemCareVersion} and PC Armor {#PcArmorVersion}
AppPublisher=iSharpe Computer Solutions
AppPublisherURL=https://isharpe.com
AppSupportPhone=336.260.0664
VersionInfoVersion={#SystemCareVersion}
VersionInfoDescription=iSharpe SystemCare and PC Armor setup
OutputDir=..\artifacts\combined
OutputBaseFilename=iSharpe-SystemCare-PCArmor-Setup-{#SystemCareVersion}-{#PcArmorVersion}
SetupIconFile=..\assets\isharpe-systemcare.ico
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
MinVersion=10.0.17763
; Nothing of its own is installed, so there is nothing for it to uninstall: each product has its own entry in Installed apps.
CreateAppDir=no
Uninstallable=no
DisableProgramGroupPage=yes
DisableReadyPage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel2=This installs iSharpe SystemCare, which keeps this computer maintained, and PC Armor, which protects it from threats and dangerous websites.%n%nPC Armor does the security scanning; SystemCare looks after everything else.

[Files]
Source: "{#SystemCareMsi}"; DestDir: "{tmp}"; DestName: "SystemCare.msi"; Flags: deleteafterinstall
Source: "{#PcArmorSetup}"; DestDir: "{tmp}"; DestName: "PCArmor-Setup.exe"; Flags: deleteafterinstall

[Run]
; Only when SystemCare could not be registered here: opens its setup page with the customer's email filled in. SystemCare asks Windows
; for its own rights.
Filename: "{commonpf64}\iSharpe SystemCare\iSharpe.SystemCare.exe"; Parameters: "{code:SystemCareArgs}"; Description: "Open SystemCare to finish setting up (recommended)"; Flags: nowait postinstall skipifsilent; Check: NotRegistered

[Code]
var
  ProtectPage: TInputOptionWizardPage;
  EmailPage: TInputQueryWizardPage;
  Failure: String;
  Registered: Boolean;

const
  DashboardUrl = 'https://fastpc123.com';

procedure InitializeWizard;
begin
  ProtectPage := CreateInputOptionPage(wpWelcome, 'Internet protection',
    'Choose how PC Armor protects this computer''s internet',
    'PC Armor installs the NextDNS firewall, which blocks dangerous websites before they load.',
    True, False);
  ProtectPage.Add('Protection + Ad Blocking (recommended)');
  ProtectPage.Add('Standard Protection (no ad blocking)');
  ProtectPage.Add('Do not install the DNS firewall now');
  ProtectPage.SelectedValueIndex := 0;

  EmailPage := CreateInputQueryPage(ProtectPage.ID, 'Customer',
    'Enter the customer''s email address',
    'Both SystemCare and PC Armor are licensed to this address on the iSharpe dashboard. Add it there for both products first.');
  EmailPage.Add('Email address:', False);
end;

{ Plain sanity check only; the dashboard decides whether the address is licensed. }
function LooksLikeEmail(S: String): Boolean;
begin
  Result := (Pos('@', S) > 1) and (Pos('.', S) > Pos('@', S) + 1) and (Pos(' ', S) = 0) and (Pos('"', S) = 0)
    { It goes on SystemCare's command line, so nothing cmd.exe would act on. }
    and (Pos('&', S) = 0) and (Pos('|', S) = 0) and (Pos('<', S) = 0) and (Pos('>', S) = 0) and (Pos('^', S) = 0) and (Pos('%', S) = 0);
end;

function Email: String;
begin
  Result := Trim(ExpandConstant('{param:EMAIL|}'));
  if (Result = '') and (EmailPage <> nil) and not WizardSilent then
    Result := Trim(EmailPage.Values[0]);
  if not LooksLikeEmail(Result) then
    Result := '';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  { Email, not the page: a silent install gives it as /EMAIL= and leaves the page empty, and checking the page alone stopped
    every silent install with an email on a message box nobody could answer. }
  if (EmailPage <> nil) and (CurPageID = EmailPage.ID) and (Email = '') then
  begin
    MsgBox('Enter the customer''s email address. Both products are licensed to it.', mbError, MB_OK);
    Result := False;
  end;
end;

{ PC Armor's own silent options: the protection chosen, and the email it activates under. }
function PcArmorArgs: String;
var
  Profile: String;
begin
  Result := '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART';
  Profile := ExpandConstant('{param:PROFILE|}');
  if WizardSilent then
  begin
    if ExpandConstant('{param:NODNS|0}') = '1' then Result := Result + ' /NODNS=1'
    else if Profile <> '' then Result := Result + ' /PROFILE=' + Profile
    else Result := Result + ' /PROFILE=adblock';
  end
  else
    case ProtectPage.SelectedValueIndex of
      0: Result := Result + ' /PROFILE=adblock';
      1: Result := Result + ' /PROFILE=standard';
    else
      Result := Result + ' /NODNS=1';
    end;
  if Email <> '' then
    Result := Result + ' /EMAIL=' + Email;
end;

function FileContentsOrEmpty(Path: String): String;
var
  S: AnsiString;
begin
  Result := '';
  if LoadStringFromFile(Path, S) then
    Result := String(S);
end;

function SystemCareArgs(Param: String): String;
begin
  Result := '';
  if Email <> '' then
    Result := '--customer-email=' + Email;
end;

function NotRegistered: Boolean;
begin
  Result := not Registered;
end;

function SystemCareSettings: String;
begin
  Result := ExpandConstant('{commonappdata}\iSharpe SystemCare\config\settings.json');
end;

{ A computer that never had SystemCare has no settings yet: it is given just the dashboard's address, and SystemCare fills in the rest
  with its defaults. Settings already there are left alone (SystemCare set up before keeps its own address, or is connected by hand). }
procedure GiveSystemCareTheDashboard;
begin
  if FileExists(SystemCareSettings) then
    Exit;
  ForceDirectories(ExtractFileDir(SystemCareSettings));
  if not SaveStringToFile(SystemCareSettings, '{' + #13#10 + '  "server": {' + #13#10 + '    "address": "' + DashboardUrl + '"' + #13#10 + '  }' + #13#10 + '}' + #13#10, False) then
    Log('Could not write ' + SystemCareSettings);
end;

{ SystemCare's own registration, as its setup page's Connect button does: the dashboard checks the email is licensed for SystemCare.
  Tried a few times, since a computer that has just installed something can take a moment to reach the internet. }
procedure RegisterSystemCare;
var
  Agent, Output, Said: String;
  RC, Attempt: Integer;
begin
  Agent := ExpandConstant('{commonpf64}\iSharpe SystemCare\iSharpe.SystemCare.Agent.exe');
  if (Email = '') or not FileExists(Agent) then
    Exit;
  WizardForm.StatusLabel.Caption := 'Connecting SystemCare to the iSharpe dashboard...';
  Output := ExpandConstant('{tmp}\systemcare-setup.txt');
  for Attempt := 1 to 3 do
  begin
    if Attempt > 1 then
      Sleep(10000);
    RC := -1;
    if Exec(ExpandConstant('{cmd}'), '/C ""' + Agent + '" server-setup ' + Email + ' > "' + Output + '" 2>&1"', '', SW_HIDE, ewWaitUntilTerminated, RC) and (RC = 0) then
    begin
      Registered := True;
      Log('SystemCare registered under ' + Email);
      Exit;
    end;
    Said := Trim(FileContentsOrEmpty(Output));
    Log('SystemCare server-setup try ' + IntToStr(Attempt) + ' ended with ' + IntToStr(RC) + ':' + #13#10 + Said);
    { 1 = reached or not reached; other codes (no address, no email) will not change by trying again. }
    if RC <> 1 then
      Break;
  end;
  if Length(Said) > 400 then
    Said := Copy(Said, 1, 400) + '...';
  Failure := Failure + #13#10 + 'SystemCare installed but did not connect to the dashboard: ' + Said + #13#10 +
             'Open SystemCare from the next page to connect it.';
end;

{ Windows Installer fails (1603) when the same SystemCare is installed over itself, so a computer that already has this version or a
  newer one keeps it. It still gets connected, which is usually why the installer is run again. }
function SystemCareAlreadyHere: Boolean;
var
  Installed: String;
  Have, Bundled: Int64;
begin
  Result := GetVersionNumbersString(ExpandConstant('{commonpf64}\iSharpe SystemCare\iSharpe.SystemCare.exe'), Installed)
    and StrToVersion(Installed, Have) and StrToVersion('{#SystemCareVersion}', Bundled)
    and (ComparePackedVersion(Have, Bundled) >= 0);
end;

{ A PC Armor already here keeps PCArmor.exe open in its icon next to the clock, and its setup then stops with code 5 (file in use;
  Windows will not close it for an installer in another session). The dashboard's install does the same: close it, and PC Armor's
  own setup step starts the icon again. }
procedure StopPcArmor;
var
  RC: Integer;
begin
  if not FileExists(ExpandConstant('{commonpf64}\PC Armor\PCArmor.exe')) then
    Exit;
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
       '-NoProfile -NonInteractive -Command "Get-Process PCArmor -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq ''' +
       ExpandConstant('{commonpf64}\PC Armor\PCArmor.exe') + ''' } | Stop-Process -Force"', '', SW_HIDE, ewWaitUntilTerminated, RC);
  Log('Closed the running PC Armor before its setup (code ' + IntToStr(RC) + ').');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  RC: Integer;
begin
  if CurStep = ssInstall then
    GiveSystemCareTheDashboard;
  if CurStep <> ssPostInstall then
    Exit;

  // SystemCare first, then PC Armor: when PC Armor is there and licensed, SystemCare hands it the scanning by itself.
  if SystemCareAlreadyHere then
  begin
    Log('SystemCare ' + '{#SystemCareVersion}' + ' or newer is already installed; only connecting it.');
    RegisterSystemCare;
  end
  else
  begin
    WizardForm.StatusLabel.Caption := 'Installing iSharpe SystemCare...';
    if not Exec(ExpandConstant('{sys}\msiexec.exe'), '/i "' + ExpandConstant('{tmp}\SystemCare.msi') + '" /qn /norestart',
                '', SW_HIDE, ewWaitUntilTerminated, RC) or ((RC <> 0) and (RC <> 3010)) then
      Failure := Failure + #13#10 + 'SystemCare did not install (Windows Installer code ' + IntToStr(RC) + ').'
    else
      RegisterSystemCare;
  end;

  WizardForm.StatusLabel.Caption := 'Installing PC Armor (this can take a minute)...';
  StopPcArmor;
  if not Exec(ExpandConstant('{tmp}\PCArmor-Setup.exe'), PcArmorArgs, '', SW_HIDE, ewWaitUntilTerminated, RC) or (RC <> 0) then
    Failure := Failure + #13#10 + 'PC Armor did not install (setup code ' + IntToStr(RC) + ').';

  if Failure <> '' then
  begin
    if not WizardSilent then
      MsgBox('Not everything installed:' + #13#10 + Failure + #13#10 + #13#10 +
             'Run this installer again, or install the one that failed on its own. Call 336.260.0664 for help.', mbError, MB_OK);
    Log('Combined setup problems:' + Failure);
  end;
end;
