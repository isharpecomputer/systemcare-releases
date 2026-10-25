; iSharpe SystemCare + PC Armor: one installer for a customer who has both (Inno Setup 6).
; Build with tools\build-combined.ps1, which downloads the published SystemCare MSI and PC Armor setup and passes:
;   ISCC.exe /DSystemCareVersion=1.7.101 /DPcArmorVersion=1.4.3 /DSystemCareMsi=... /DPcArmorSetup=... SystemCareAndPcArmor.iss
;
; It installs nothing of its own and leaves nothing behind: each product installs, updates and uninstalls exactly as it does on its
; own. It asks the two questions both products need once - the customer's email, and how PC Armor protects the internet - then
; installs SystemCare and PC Armor silently and opens SystemCare's setup page with the email filled in. That page is still where the
; customer reads the agreement and presses Connect.
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
; Opens SystemCare's setup page with the customer's email filled in. SystemCare asks Windows for its own rights.
Filename: "{commonpf64}\iSharpe SystemCare\iSharpe.SystemCare.exe"; Parameters: "{code:SystemCareArgs}"; Description: "Open SystemCare to finish setting up (recommended)"; Flags: nowait postinstall skipifsilent

[Code]
var
  ProtectPage: TInputOptionWizardPage;
  EmailPage: TInputQueryWizardPage;
  Failure: String;

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
  Result := (Pos('@', S) > 1) and (Pos('.', S) > Pos('@', S) + 1) and (Pos(' ', S) = 0) and (Pos('"', S) = 0);
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

function SystemCareArgs(Param: String): String;
begin
  Result := '';
  if Email <> '' then
    Result := '--customer-email=' + Email;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  RC: Integer;
begin
  if CurStep <> ssPostInstall then
    Exit;

  // SystemCare first, then PC Armor: when PC Armor is there and licensed, SystemCare hands it the scanning by itself.
  WizardForm.StatusLabel.Caption := 'Installing iSharpe SystemCare...';
  if not Exec(ExpandConstant('{sys}\msiexec.exe'), '/i "' + ExpandConstant('{tmp}\SystemCare.msi') + '" /qn /norestart',
              '', SW_HIDE, ewWaitUntilTerminated, RC) or ((RC <> 0) and (RC <> 3010)) then
    Failure := Failure + #13#10 + 'SystemCare did not install (Windows Installer code ' + IntToStr(RC) + ').';

  WizardForm.StatusLabel.Caption := 'Installing PC Armor (this can take a minute)...';
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
