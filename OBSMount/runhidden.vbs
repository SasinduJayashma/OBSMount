;--------------------------------------------------------
[Setup]
AppName=OBS Drive Mount
AppVersion=2.0
DefaultDirName={autopf}\OBSDrive
DefaultGroupName=OBS Drive
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=dist
OutputBaseFilename=OBSDrive-Setup
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
SetupIconFile=files\obsMount.ico
LicenseFile=files\LICENSE.txt
InfoAfterFile=files\POSTINSTALL.txt
AppContact=Call 0712245012 or Email sasindujayashmaavmu@gmail.com
AppCopyright=Copyright (C) 2025 Sasindu Jayashma.
ShowComponentSizes=yes

;--------------------------------------------------------
[Files]
Source: "files\winfsp-2.0.23075.msi"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "files\rclone.exe";          DestDir: "{app}"
Source: "files\mount.cmd";           DestDir: "{app}"
Source: "files\unmount.cmd";         DestDir: "{app}"
Source: "files\runhidden.vbs";       DestDir: "{app}"

;--------------------------------------------------------
[Run]
Filename: "msiexec.exe"; \
  Parameters: "/i ""{tmp}\winfsp-2.0.23075.msi"" /qn INSTALLLEVEL=1000"; \
  StatusMsg: "Installing WinFsp driver..."; \
  Flags: waituntilterminated runascurrentuser
  
; The old line to run runhidden.vbs is removed.
; We will run it dynamically from [Code] for the just-configured instance.
; Filename: "{app}\runhidden.vbs"; Flags: shellexec nowait postinstall skipifsilent

; Removed static [Icons] entry for startup. It will be created dynamically in [Code].
; [Icons]
; Name: "{userstartup}\OBS Drive Mount"; Filename: "{app}\runhidden.vbs"

;--------------------------------------------------------
[UninstallDelete]
Type: files; Name: "{userstartup}\OBS Drive Mount (*).lnk"
Type: files; Name: "{app}\obs-config-*.ini"
Type: files; Name: "{app}\rclone-*.conf"
Type: files; Name: "{localappdata}\rclone\mount-*.log"


;--------------------------------------------------------
;  CUSTOM WIZARD PAGES
[Code]

var
  PgBucket, PgCred: TInputQueryWizardPage;
  CurrentDriveLetter: string; // To store the drive letter for use in ssDone or ssPostInstall

// Function to create a shortcut (from Inno Setup examples, slightly adapted)
procedure CreateShortcutInStartup(const LinkName, TargetPath, Parameters, WorkingDir, IconPath: String; IconIndex, ShowCmd: Integer);
var
  ShellLink: IShellLink;
  PFile: IPersistFile;
  WPath: WideString;
begin
  ShellLink := CreateShellLink;
  try
    ShellLink.SetPath(TargetPath);
    ShellLink.SetArguments(Parameters);
    ShellLink.SetWorkingDirectory(WorkingDir);
    if IconPath <> '' then
      ShellLink.SetIconLocation(IconPath, IconIndex);
    ShellLink.SetShowCmd(ShowCmd);
    //ShellLink.SetDescription(Description); // Description is part of LinkName for .lnk files

    PFile := ShellLink as IPersistFile;
    WPath := LinkName;
    PFile.Save(WPath, False);
    Log(Fmt('Created shortcut: %s -> %s (Params: %s)', [LinkName, TargetPath, Parameters]));
  except
    Log(Fmt('Error creating shortcut %s: %s', [LinkName, GetExceptionMessage]));
  end;
end;

procedure InitializeWizard;
begin
  { ------ Page 1: bucket & region ------ }
  PgBucket := CreateInputQueryPage(
    wpSelectDir, // This should probably be wpWelcome or a later page ID
    'OBS Bucket Details',
    'Enter your Huawei OBS bucket information and click Next.',
    '');
  with PgBucket do
  begin
    Add('Bucket name:', False);
    Add('Region (e.g. ap-southeast-3):', False);
    Add('Endpoint (obs.<region>.myhuaweicloud.com):', False);
  end;

  { ------ Page 2: access keys & drive letter ------ }
  PgCred := CreateInputQueryPage(
    PgBucket.ID,
    'Access Credentials & Drive Letter',
    'Paste the Access Key ID and Secret Key for your OBS IAM user, and choose a drive letter.',
    '');
  with PgCred do
  begin
    Add('Access Key ID:', False);
    Add('Secret Key:', True);      { second param = PasswordChar }
    Add('Drive letter (e.g., Q):', False); // Ensure user enters a single letter
    Values[2] := 'P';              { pre-fill drive letter }
  end;
end;

// Function to generate a somewhat unique port based on drive letter
// This is a simple example, consider a more robust port management for production
function GenerateRcPort(DriveLetter: String): Integer;
var
  UpperDriveLetter: String;
begin
  if Length(DriveLetter) = 1 then
  begin
    UpperDriveLetter := UpCaseString(DriveLetter);
    // Base port 5572. Add offset based on drive letter (A=0, B=1, etc.)
    // This simple scheme might have collisions if other apps use these ports.
    Result := 5572 + (Ord(UpperDriveLetter[1]) - Ord('A'));
    if (Result < 1024) or (Result > 65535) then // Basic port range check
      Result := 5600 + Random(100); // Fallback to a random port in a small range
  end
  else
    Result := 5600 + Random(100); // Fallback for invalid drive letter string
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  IniPath, RcloneCfgPath: String;
  DriveLetter, BucketName, Region, Endpoint, Ak, Sk, RcPortStr: String;
  RcPort: Integer;
  VbsPath, LnkBasePath, LnkName: String;
  ErrorCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    BucketName := Trim(PgBucket.Values[0]);
    Region := Trim(PgBucket.Values[1]);
    Endpoint := Trim(PgBucket.Values[2]);
    Ak := Trim(PgCred.Values[0]);
    Sk := Trim(PgCred.Values[1]);
    DriveLetter := Trim(UpCaseString(PgCred.Values[2])); // Store and use uppercase drive letter

    // Validate drive letter is a single alphabet character
    if (Length(DriveLetter) <> 1) or not (DriveLetter[1] in ['A'..'Z']) then
    begin
      MsgBox('Invalid drive letter: ' + DriveLetter + #13#10 + 'Please use a single alphabet character (A-Z).', mbError, MB_OK);
      // Ideally, prevent moving from wizard page with invalid input.
      // For now, just log and potentially skip creating this profile.
      Log('Invalid drive letter entered: ' + DriveLetter);
      Exit; 
    end;
    
    CurrentDriveLetter := DriveLetter; // Store for potential use in ssDone for immediate run

    IniPath := ExpandConstant('{app}\obs-config-' + DriveLetter + '.ini');
    RcloneCfgPath := ExpandConstant('{app}\rclone-' + DriveLetter + '.conf');
    
    RcPort := GenerateRcPort(DriveLetter);
    RcPortStr := IntToStr(RcPort);

    Log(Fmt('Saving configuration for Profile %s to %s', [DriveLetter, IniPath]));
    Log(Fmt('Bucket: %s, Region: %s, Endpoint: %s, Drive: %s, RC Port: %s', [BucketName, Region, Endpoint, DriveLetter, RcPortStr]));

    SaveStringToFile(IniPath,
      '; OBS Configuration for Drive ' + DriveLetter + #13#10 +
      'bucket='   + BucketName + #13#10 +
      'region='   + Region + #13#10 +
      'endpoint=' + Endpoint + #13#10 +
      'ak='       + Ak + #13#10 +
      'sk='       + Sk + #13#10 +
      'drive='    + DriveLetter + #13#10 +
      'rc_port='  + RcPortStr + #13#10,
      False);

    Log(Fmt('Saving rclone config for Profile %s to %s', [DriveLetter, RcloneCfgPath]));
    SaveStringToFile(RcloneCfgPath,
      '[huaweiOBS]' #13#10 + // Can keep this section name static as file is unique
      'type = s3' #13#10 +
      'provider = Other' #13#10 +
      'access_key_id = '     + Ak + #13#10 +
      'secret_access_key = ' + Sk + #13#10 +
      'endpoint = '          + Endpoint + #13#10 +
      'region = '            + Region + #13#10,
      False);

    // Create Startup Shortcut dynamically
    VbsPath := ExpandConstant('{app}\runhidden.vbs');
    LnkBasePath := ExpandConstant('{userstartup}\OBS Drive Mount ('); // Note the opening parenthesis
    LnkName := LnkBasePath + DriveLetter + ').lnk'; // e.g., OBS Drive Mount (Q).lnk
    
    Log(Fmt('Creating startup shortcut: %s for drive %s', [LnkName, DriveLetter]));
    CreateShortcutInStartup(LnkName, VbsPath, DriveLetter, ExpandConstant('{app}'), '', 0, SW_SHOWNORMAL);

    // Optionally, run the newly configured mount instance immediately
    // This replaces the static [Run] entry for runhidden.vbs
    if MsgBox('OBS Drive for ' + DriveLetter + ': has been configured.'#13#10 +
              'Do you want to start this mount now?' #13#10 +
              '(It will also start automatically on next login).', mbConfirmation, MB_YESNO) = IDYES then
    begin
        Log(Fmt('Attempting to start mount for drive %s post-install.', [DriveLetter]));
        if not Exec(VbsPath, DriveLetter, ExpandConstant('{app}'), SW_HIDE, ewNoWait, ErrorCode) then
        begin
            Log(Fmt('Error starting mount for drive %s post-install. Code: %d', [DriveLetter, ErrorCode]));
        end;
    end;
  end;
end;

// Stops Next if anything is blank (ensure drive letter is also checked for basic format)
function NextButtonClick(CurPageID: Integer): Boolean;
var
  DriveInput: String;
begin
  Result := True;  // assume OK

  // Bucket / Region / Endpoint page
  if CurPageID = PgBucket.ID then
  begin
    if (Trim(PgBucket.Values[0]) = '') or
        (Trim(PgBucket.Values[1]) = '') or
        (Trim(PgBucket.Values[2]) = '') then
    begin
      MsgBox('Please fill in Bucket, Region and Endpoint before continuing.',
              mbError, MB_OK);
      Result := False;
    end;
  end

  // Credentials page
  else if CurPageID = PgCred.ID then
  begin
    DriveInput := Trim(UpCaseString(PgCred.Values[2]));
    if (Trim(PgCred.Values[0]) = '') or  // AK
        (Trim(PgCred.Values[1]) = '') or  // SK
        (DriveInput = '') then           // Drive
    begin
      MsgBox('Access Key, Secret Key and Drive Letter cannot be empty.',
              mbError, MB_OK);
      Result := False;
    end
    else if (Length(DriveInput) <> 1) or not (DriveInput[1] in ['A'..'Z']) then
    begin
        MsgBox('Invalid Drive Letter: "' + PgCred.Values[2] + '". Please enter a single alphabet character (e.g., Q).', mbError, MB_OK);
        Result := False;
    end;
  end;
end;