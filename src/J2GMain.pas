(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GMain.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - main window (Archive Admin).

- Connection: host:port, user and password, or a saved identity of the JEDI
  VCS client (the saved password is used as bytes and never shown).
- "List projects" logs in (connection test), lists the projects and the users
  of the server and loads/creates the author map (autores.txt) of the output
  folder in an editable grid.
- "Export" writes the grid to autores.txt and runs J2GRunExport in a worker
  thread. The TJVCSConnection (ICS sockets) is created, used and destroyed in
  the worker thread; the window only receives messages and progress through
  TThread.Queue. Cancel = Boolean flag polled by the engine.
- The Blowfish key is only chosen by source (registry / file / none) and is
  never displayed.

-----------------------------------------------------------------------------*)

unit J2GMain;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils, System.Classes, System.Types,
  System.UITypes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Grids, Vcl.ValEdit, Vcl.Samples.Spin,
  J2GModel, J2GOptions, J2GReport;

type
  TJ2GMainForm = class(TForm)
    pnlEnv: TPanel;
    lblEnv: TLabel;
    lnkGit: TLinkLabel;
    btnRecheck: TButton;
    grpConnection: TGroupBox;
    lblIdentity: TLabel;
    cbIdentity: TComboBox;
    lblBranch: TLabel;
    edBranch: TEdit;
    lblServer: TLabel;
    edServer: TEdit;
    lblUser: TLabel;
    edUser: TEdit;
    lblPassword: TLabel;
    edPassword: TEdit;
    btnList: TButton;
    grpOutput: TGroupBox;
    lblOutDir: TLabel;
    edOutDir: TEdit;
    btnBrowse: TButton;
    pnlBottom: TPanel;
    pbProgress: TProgressBar;
    lblStatus: TLabel;
    btnExport: TButton;
    btnCancel: TButton;
    btnOpenFolder: TButton;
    btnOpenReport: TButton;
    pcMain: TPageControl;
    tsProjects: TTabSheet;
    pnlProjTop: TPanel;
    chkShowDeleted: TCheckBox;
    btnCheckAll: TButton;
    btnUncheckAll: TButton;
    lvProjects: TListView;
    tsAuthors: TTabSheet;
    lblAuthors: TLabel;
    vleAuthors: TValueListEditor;
    tsOptions: TTabSheet;
    sbOptions: TScrollBox;
    grpHistory: TGroupBox;
    rbGroup: TRadioButton;
    seGroup: TSpinEdit;
    lblMinutes: TLabel;
    rbNoGroup: TRadioButton;
    chkLocalTime: TCheckBox;
    chkLabels: TCheckBox;
    chkDfmText: TCheckBox;
    chkSkipHidden: TCheckBox;
    grpGit: TGroupBox;
    lblGitBranch: TLabel;
    edGitBranch: TEdit;
    chkNoGit: TCheckBox;
    chkKeepCache: TCheckBox;
    chkForce: TCheckBox;
    grpKey: TGroupBox;
    rbKeyRegistry: TRadioButton;
    rbKeyFile: TRadioButton;
    edKeyFile: TEdit;
    btnKeyFile: TButton;
    rbKeyNone: TRadioButton;
    tsLog: TTabSheet;
    memLog: TMemo;
    tsAbout: TTabSheet;
    memAbout: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure cbIdentityChange(Sender: TObject);
    procedure btnListClick(Sender: TObject);
    procedure btnBrowseClick(Sender: TObject);
    procedure edOutDirExit(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnOpenFolderClick(Sender: TObject);
    procedure btnOpenReportClick(Sender: TObject);
    procedure chkShowDeletedClick(Sender: TObject);
    procedure btnCheckAllClick(Sender: TObject);
    procedure btnUncheckAllClick(Sender: TObject);
    procedure chkNoGitClick(Sender: TObject);
    procedure btnRecheckClick(Sender: TObject);
    procedure lnkGitLinkClick(Sender: TObject; const Link: string; LinkType: TSysLinkType);
    procedure btnKeyFileClick(Sender: TObject);
    procedure OptionChanged(Sender: TObject);
  private
    FWorker: TThread;            // TJ2GWorker; nil when idle (FreeOnTerminate)
    FWorkerIsExport: Boolean;
    FCloseRequested: Boolean;
    FAskingClose: Boolean;       // "cancel and close?" question open
    FEnvOk: Boolean;
    FProjects: TArray<TJ2GProjectInfo>;
    FLogins: TArray<string>;
    FAuthorsDomain: string;
    FLastOutDir: string;         // output folder of the last export
    procedure CheckEnvironment;
    procedure UpdateControls;
    procedure FillProjectList;
    procedure LoadAuthorsGrid(AKeepWhenNoFile: Boolean);
    function SaveAuthorsGrid(const AFileName, ADomain: string): Boolean;
    function BuildOptions(ACommand: TJ2GCommand; out AOptions: TJ2GOptions): Boolean;
    function CheckedProjects: TArray<TJ2GProjectInfo>;
    function IdentityName: string;
    function PasswordBytes: TBytes;
    function OutDir: string;
    function ReportFile: string;
    procedure StartWorker(AExport: Boolean; const AOptions: TJ2GOptions;
      const ASelected: TArray<TJ2GProjectInfo>);
    procedure WorkerDone(Sender: TObject);
    procedure ShellOpen(const ATarget: string);
  public
    procedure AddLog(ALevel: TJ2GLogLevel; const AMsg: string);
    procedure SetProgress(const AProject: string; ADone, ATotal: Integer; const AStage: string);
  end;

var
  J2GMainForm: TJ2GMainForm;

implementation

uses
  System.IOUtils, System.Math, System.Generics.Collections, RFormat, JVCSUIScale, JVCSUITheme,
  J2GIdentity, J2GSession, J2GFetch, J2GExport, J2GAuthors, J2GGit;

{$R *.dfm}

const
  GIT_DOWNLOAD_URL = 'https://git-scm.com/download/win';
  NO_IDENTITY = '(none - type server, user and password)';

type
  TJ2GWorker = class(TThread)
  private
    FForm: TJ2GMainForm;
    FIsExport: Boolean;
    FOptions: TJ2GOptions;
    FPassword: TBytes;          // typed password (no identity); zeroed after Connect
    FSelected: TArray<TJ2GProjectInfo>;
    procedure DoMessage(ALevel: TJ2GLogLevel; const AMsg: string);
    procedure DoProgress(const AProject: string; ADone, ATotal: Integer; const AStage: string);
    procedure ResolveKey(AReport: TJ2GReport);
    procedure Connect(ASession: TJ2GSession);
  protected
    procedure Execute; override;
  public
    Cancel: Boolean;            // set by the window; polled by J2GRunExport
    ExitCode: Integer;
    ErrorText: string;
    Summary: string;
    Projects: TArray<TJ2GProjectInfo>;
    Users: TArray<TJ2GUser>;
    Lines: TArray<string>;      // one result line per exported project
    constructor Create(AForm: TJ2GMainForm; AIsExport: Boolean; const AOptions: TJ2GOptions;
      const APassword: TBytes; const ASelected: TArray<TJ2GProjectInfo>);
    destructor Destroy; override;
  end;

{ TJ2GWorker }

constructor TJ2GWorker.Create(AForm: TJ2GMainForm; AIsExport: Boolean; const AOptions: TJ2GOptions;
  const APassword: TBytes; const ASelected: TArray<TJ2GProjectInfo>);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FForm := AForm;
  FIsExport := AIsExport;
  FOptions := AOptions;
  FPassword := Copy(APassword);
  FSelected := Copy(ASelected);
end;

destructor TJ2GWorker.Destroy;
begin
  J2GWipe(FPassword);
  FOptions.ClearKey;
  inherited Destroy;
end;

procedure TJ2GWorker.DoMessage(ALevel: TJ2GLogLevel; const AMsg: string);
var
  S: string;
  F: TJ2GMainForm;
begin
  if ALevel = llDebug then
    Exit;
  S := AMsg;
  F := FForm;
  Queue(
    procedure
    begin
      F.AddLog(ALevel, S);
    end);
end;

procedure TJ2GWorker.DoProgress(const AProject: string; ADone, ATotal: Integer; const AStage: string);
var
  P, St: string;
  F: TJ2GMainForm;
begin
  P := AProject;
  St := AStage;
  F := FForm;
  Queue(
    procedure
    begin
      F.SetProgress(P, ADone, ATotal, St);
    end);
end;

// Blowfish key per KeySource (same rules as the console); never logged
procedure TJ2GWorker.ResolveKey(AReport: TJ2GReport);
var
  L: TStringList;
  Line: string;
begin
  FOptions.ClearKey;
  case FOptions.KeySource of
    ksRegistry:
      FOptions.EncodeKey := J2GRegistryEncodeKey;
    ksFile:
      begin
        if not FileExists(FOptions.EncodeKeyFile) then
          raise EJ2GError.CreateFmt(J2G_EXIT_USAGE, 'key file not found: %s', [FOptions.EncodeKeyFile]);
        L := TStringList.Create;
        try
          L.LoadFromFile(FOptions.EncodeKeyFile, TEncoding.ANSI);
          if L.Count > 0 then
            Line := L[0]
          else
            Line := '';
          FOptions.EncodeKey := J2GDecodeBase64(Line);
        finally
          L.Free;
        end;
      end;
  end;
  if (FOptions.KeySource = ksFile) and (Length(FOptions.EncodeKey) = 0) then
    AReport.Warn('invalid Blowfish key (not Base64): encrypted revisions will be skipped')
  else if (Length(FOptions.EncodeKey) > 0) and ((Length(FOptions.EncodeKey) < 8) or (Length(FOptions.EncodeKey) > 65)) then
  begin
    AReport.Warn('invalid Blowfish key (length must be 8..65 bytes): encrypted revisions will be skipped');
    FOptions.ClearKey;
  end
  else if (FOptions.KeySource = ksRegistry) and (Length(FOptions.EncodeKey) = 0) then
    AReport.Info('no Blowfish key saved by the JEDI VCS client: encrypted revisions will be skipped');
end;

// login inside this thread (the ICS sockets belong to the thread that creates them)
procedure TJ2GWorker.Connect(ASession: TJ2GSession);
var
  Ident: TJ2GIdentity;
  Err, Host, Port, User: string;
  Pwd: TBytes;
begin
  Pwd := nil;
  try
    if FOptions.Identity <> '' then
    begin
      if not J2GLoadIdentity(FOptions.Identity, Ident, Err) then
        raise EJ2GError.Create(J2G_EXIT_CREDENTIAL, Err);
      if not Ident.HasPassword then
        raise EJ2GError.CreateFmt(J2G_EXIT_CREDENTIAL,
          'identity ''%s'' has no saved password (check "Store Password with identity" in the JEDI VCS client)',
          [Ident.Name]);
      Host := Ident.HostName;
      Port := Ident.Port;
      User := Ident.User;
      Pwd := J2GIdentityPasswordBytes(Ident);
      ASession.Connect(Host, Port, User, Pwd, Ident.Name);
    end
    else
      ASession.Connect(FOptions.Host, FOptions.Port, FOptions.User, FPassword, '');
  finally
    J2GWipe(Pwd);
    J2GWipe(FPassword);
  end;
end;

procedure TJ2GWorker.Execute;
var
  Report: TJ2GReport;
  Session: TJ2GSession;
  P: TJ2GProjectReport;
  S: string;
begin
  ExitCode := J2G_EXIT_OK;
  Report := TJ2GReport.Create;
  try
    Report.OnMessage := DoMessage;
    if FIsExport then
      Report.Command := 'export'
    else
      Report.Command := 'list';
    try
      if FIsExport then
      begin
        try
          ForceDirectories(ExpandFileName(FOptions.OutDir));
          Report.OpenLog(FOptions.EffectiveLogFile);
        except
          on E: Exception do
            raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'cannot write in the output folder %s: %s',
              [FOptions.OutDir, E.Message]);
        end;
        Report.Info(J2G_PRODUCT + ' ' + J2G_VERSION + ' (window)');
        ResolveKey(Report);
      end;
      Session := TJ2GSession.Create(Report);
      try
        Connect(Session);
        Session.SelectBranch(FOptions.JvcsBranch);
        if FIsExport then
          ExitCode := J2GRunExport(Session, FOptions, FSelected, Report, DoProgress, @Cancel)
        else
        begin
          Projects := Session.GetProjects;
          Users := J2GFetchUsers(Session);
          Report.Info(Format('%d project(s), %d user(s)', [Length(Projects), Length(Users)]));
        end;
      finally
        Session.Free;
      end;
    except
      on E: EJ2GError do
      begin
        ExitCode := E.ExitCode;
        ErrorText := E.Message;
        Report.Error(E.Message);
      end;
      on E: Exception do
      begin
        ExitCode := J2G_EXIT_SERVER;
        ErrorText := E.ClassName + ': ' + E.Message;
        Report.Error(ErrorText);
      end;
    end;
    if FIsExport then
    begin
      Report.ExitCode := ExitCode;
      for P in Report.Projects do
      begin
        S := Format('%s: exit code %d, %d commit(s), %d tag(s), %d skipped member(s), %.0f s',
          [P.Name, P.ExitCode, P.Commits, P.Tags, P.Skipped.Count, P.Seconds]);
        if P.Repo <> '' then
          S := S + ' -> ' + P.Repo;
        Lines := Lines + [S];
      end;
      if Report.Projects.Count > 0 then
        Summary := Report.Summary
      else
        Summary := ErrorText;
      if Cancel then
        Summary := 'cancelled - ' + Summary;
      Report.Info(Format('exit code %d - %s', [ExitCode, Summary]));
    end;
  finally
    Report.Free;
  end;
end;

{ TJ2GMainForm }

procedure TJ2GMainForm.FormCreate(Sender: TObject);
var
  Names: TArray<string>;
  N: string;
begin
  JVCSUIApplyToForm(Self, True);
  JVCSUIApplyThemeToForm(Self);
  Caption := J2G_PRODUCT + ' ' + J2G_VERSION + ' - JEDI VCS to Git exporter';
  memAbout.Lines.Text :=
    J2G_PRODUCT + ' ' + J2G_VERSION + ' - JEDI VCS to Git exporter' + sLineBreak +
    sLineBreak +
    J2G_MIDWARE_NOTICE + sLineBreak +
    'Source: ' + J2G_URL + ' (MPL 1.1)' + sLineBreak +
    sLineBreak +
    'Exports the history of JEDI VCS 2.5 projects (modules, revisions, check-in' + sLineBreak +
    'comments, labels) to Git repositories. The JEDI VCS server is only read.' + sLineBreak +
    'The password and the Blowfish key are never shown or written to the log.';
  lnkGit.Caption := 'Download <a href="' + GIT_DOWNLOAD_URL + '">Git for Windows</a>';
  FAuthorsDomain := 'jedivcs.local';

  cbIdentity.Items.Clear;
  cbIdentity.Items.Add(NO_IDENTITY);
  Names := J2GListIdentities;
  for N in Names do
    cbIdentity.Items.Add(N);
  // the last used identity comes first
  if Length(Names) > 0 then
    cbIdentity.ItemIndex := 1
  else
    cbIdentity.ItemIndex := 0;
  cbIdentityChange(nil);

  pcMain.ActivePage := tsProjects;
  CheckEnvironment;
  UpdateControls;
end;

procedure TJ2GMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
  Answer: Integer;
begin
  if not Assigned(FWorker) then
    Exit;
  CanClose := False;
  if FCloseRequested then
    Exit;
  if FWorkerIsExport then
  begin
    // the worker may end while the question is open (WorkerDone runs in the modal loop)
    FAskingClose := True;
    try
      Answer := MessageDlg('An export is running. Cancel it and close the window?',
        mtConfirmation, [mbYes, mbNo], 0, mbNo);
    finally
      FAskingClose := False;
    end;
    if Answer <> mrYes then
      Exit;
    if not Assigned(FWorker) then
    begin
      CanClose := True;
      Exit;
    end;
    TJ2GWorker(FWorker).Cancel := True;
    lblStatus.Caption := 'Cancelling... the window closes when the engine stops.';
  end
  else
    lblStatus.Caption := 'Waiting for the server... the window closes when it answers.';
  // the worker owns the connection: close only after it ends (WorkerDone)
  FCloseRequested := True;
  UpdateControls;
end;

procedure TJ2GMainForm.CheckEnvironment;
var
  Msg, V: string;
  GitMissing: Boolean;
begin
  Msg := '';
  GitMissing := False;
  try
    J2GCheckRequiredLibs;
  except
    on E: Exception do
      Msg := E.Message;
  end;
  if not chkNoGit.Checked and not J2GGitVersion(V) then
  begin
    GitMissing := True;
    if Msg <> '' then
      Msg := Msg + sLineBreak;
    Msg := Msg + 'Git was not found on the PATH: install Git for Windows and click "Check again" ' +
      '(or check "Only write the fast-import stream" in Options).';
  end;
  FEnvOk := Msg = '';
  lblEnv.Caption := Msg;
  lnkGit.Visible := GitMissing;
  if not FEnvOk then
    pnlEnv.Top := 0;
  pnlEnv.Visible := not FEnvOk;
  if FEnvOk and (V <> '') then
    AddLog(llInfo, V);
end;

procedure TJ2GMainForm.UpdateControls;
var
  Busy, Ident: Boolean;
begin
  Busy := Assigned(FWorker);
  Ident := cbIdentity.ItemIndex > 0;
  grpConnection.Enabled := not Busy;
  grpOutput.Enabled := not Busy;
  pnlProjTop.Enabled := not Busy;
  lvProjects.Enabled := not Busy;
  vleAuthors.Enabled := not Busy;
  sbOptions.Enabled := not Busy;
  edServer.ReadOnly := Ident;
  edUser.ReadOnly := Ident;
  edPassword.ReadOnly := Ident;  // read-only (not disabled) so the hint stays visible
  seGroup.Enabled := rbGroup.Checked;
  edKeyFile.Enabled := rbKeyFile.Checked;
  btnKeyFile.Enabled := rbKeyFile.Checked;
  btnList.Enabled := not Busy;
  btnExport.Enabled := not Busy and FEnvOk and (lvProjects.Items.Count > 0);
  btnCancel.Enabled := Busy and FWorkerIsExport and not TJ2GWorker(FWorker).Cancel;
  btnOpenFolder.Enabled := (OutDir <> '') and DirectoryExists(OutDir);
  btnOpenReport.Enabled := FileExists(ReportFile);
end;

procedure TJ2GMainForm.OptionChanged(Sender: TObject);
begin
  UpdateControls;
end;

function TJ2GMainForm.IdentityName: string;
begin
  if cbIdentity.ItemIndex > 0 then
    Result := cbIdentity.Items[cbIdentity.ItemIndex]
  else
    Result := '';
end;

function TJ2GMainForm.OutDir: string;
begin
  Result := Trim(edOutDir.Text);
  if Result <> '' then
    Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
end;

function TJ2GMainForm.ReportFile: string;
var
  D: string;
begin
  D := FLastOutDir;
  if D = '' then
    D := OutDir;
  if D = '' then
    Result := ''
  else
    Result := IncludeTrailingPathDelimiter(D) + J2G_REPORT_FILE;
end;

procedure TJ2GMainForm.cbIdentityChange(Sender: TObject);
var
  Ident: TJ2GIdentity;
  Err: string;
begin
  if cbIdentity.ItemIndex > 0 then
  begin
    edPassword.Text := '';
    if J2GLoadIdentity(IdentityName, Ident, Err) then
    begin
      if Ident.Port <> '' then
        edServer.Text := Ident.HostName + ':' + Ident.Port
      else
        edServer.Text := Ident.HostName;
      edUser.Text := Ident.User;
      if Ident.HasPassword then
        edPassword.TextHint := '(saved with the identity)'
      else
        edPassword.TextHint := '(no saved password)';
    end
    else
    begin
      edPassword.TextHint := '';
      AddLog(llWarn, Err);
    end;
  end
  else
    edPassword.TextHint := '';
  UpdateControls;
end;

// typed password as bytes in the protocol code page (as the console prompt)
function TJ2GMainForm.PasswordBytes: TBytes;
var
  Enc: TEncoding;
begin
  Enc := TEncoding.GetEncoding(MWCodePage);
  try
    Result := Enc.GetBytes(edPassword.Text);
  finally
    Enc.Free;
  end;
end;

function TJ2GMainForm.BuildOptions(ACommand: TJ2GCommand; out AOptions: TJ2GOptions): Boolean;
var
  Msg: string;
  I: Integer;
  Sel: TArray<TJ2GProjectInfo>;
begin
  Result := False;
  AOptions.SetDefaults;
  AOptions.Command := ACommand;
  AOptions.Identity := IdentityName;
  J2GSplitHostPort(edServer.Text, AOptions.Host, AOptions.Port);
  if AOptions.Port = '' then
    AOptions.Port := '2106';
  AOptions.User := Trim(edUser.Text);
  AOptions.JvcsBranch := Trim(edBranch.Text);
  if SameText(AOptions.JvcsBranch, 'HEAD') then
    AOptions.JvcsBranch := '';
  AOptions.IncludeDeleted := chkShowDeleted.Checked;
  AOptions.OutDir := OutDir;
  AOptions.BranchName := Trim(edGitBranch.Text);
  AOptions.Force := chkForce.Checked;
  AOptions.NoGit := chkNoGit.Checked;
  AOptions.KeepCache := chkKeepCache.Checked;
  AOptions.NoGroup := rbNoGroup.Checked;
  if AOptions.NoGroup then
    AOptions.GroupMinutes := 0
  else
    AOptions.GroupMinutes := seGroup.Value;
  AOptions.LocalTime := chkLocalTime.Checked;
  AOptions.NoDfmText := not chkDfmText.Checked;
  if chkLabels.Checked then
    AOptions.Labels := lmTag
  else
    AOptions.Labels := lmNone;
  AOptions.SkipHidden := chkSkipHidden.Checked;
  if rbKeyFile.Checked then
  begin
    AOptions.KeySource := ksFile;
    AOptions.EncodeKeyFile := Trim(edKeyFile.Text);
  end
  else if rbKeyNone.Checked then
  begin
    AOptions.KeySource := ksNone;
    AOptions.NoEncodeKey := True;
  end
  else
    AOptions.KeySource := ksRegistry;

  if (AOptions.Identity = '') and ((AOptions.Host = '') or (AOptions.User = '')) then
  begin
    MessageDlg('Choose a saved identity or type the server (host:port) and the user.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if (AOptions.Identity = '') and (edPassword.Text = '') then
  begin
    MessageDlg('Type the password of the JEDI VCS user.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if ACommand = jcExport then
  begin
    Sel := CheckedProjects;
    for I := 0 to High(Sel) do
      AOptions.Projects := AOptions.Projects + [IntToStr(Sel[I].ProjectID)];
    if Length(Sel) = 0 then
    begin
      MessageDlg('Check at least one project in the Projects page.', mtWarning, [mbOK], 0);
      Exit;
    end;
    if AOptions.OutDir = '' then
    begin
      MessageDlg('Choose the output folder.', mtWarning, [mbOK], 0);
      Exit;
    end;
    if (AOptions.KeySource = ksFile) and not FileExists(AOptions.EncodeKeyFile) then
    begin
      MessageDlg('Key file not found: ' + AOptions.EncodeKeyFile, mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  if not AOptions.Validate(Msg) then
  begin
    MessageDlg(Msg, mtWarning, [mbOK], 0);
    Exit;
  end;
  Result := True;
end;

function TJ2GMainForm.CheckedProjects: TArray<TJ2GProjectInfo>;
var
  I, Idx: Integer;
begin
  Result := nil;
  for I := 0 to lvProjects.Items.Count - 1 do
    if lvProjects.Items[I].Checked then
    begin
      Idx := NativeInt(lvProjects.Items[I].Data);
      if (Idx >= 0) and (Idx <= High(FProjects)) then
        Result := Result + [FProjects[Idx]];
    end;
end;

procedure TJ2GMainForm.FillProjectList;
var
  Checked: TList;
  I: Integer;
  It: TListItem;
begin
  Checked := TList.Create;
  lvProjects.Items.BeginUpdate;
  try
    for I := 0 to lvProjects.Items.Count - 1 do
      if lvProjects.Items[I].Checked then
        Checked.Add(Pointer(NativeInt(FProjects[NativeInt(lvProjects.Items[I].Data)].ProjectID)));
    lvProjects.Items.Clear;
    for I := 0 to High(FProjects) do
      if chkShowDeleted.Checked or not FProjects[I].Deleted then
      begin
        It := lvProjects.Items.Add;
        It.Caption := FProjects[I].Name;
        It.SubItems.Add(IntToStr(FProjects[I].ProjectID));
        if FProjects[I].Deleted then
          It.SubItems.Add('yes')
        else
          It.SubItems.Add('');
        It.Data := Pointer(NativeInt(I));
        It.Checked := Checked.IndexOf(Pointer(NativeInt(FProjects[I].ProjectID))) >= 0;
      end;
  finally
    lvProjects.Items.EndUpdate;
    Checked.Free;
  end;
end;

// authors grid = logins of the server, with the identity of autores.txt (or the default)
procedure TJ2GMainForm.LoadAuthorsGrid(AKeepWhenNoFile: Boolean);
var
  Map: TJ2GAuthorMap;
  Warn: TStringList;
  FileName, L, W: string;
begin
  if Length(FLogins) = 0 then
    Exit;
  FileName := '';
  if OutDir <> '' then
    FileName := IncludeTrailingPathDelimiter(OutDir) + 'autores.txt';
  if AKeepWhenNoFile and ((FileName = '') or not FileExists(FileName)) then
    Exit;
  Map := TJ2GAuthorMap.Create(FAuthorsDomain);
  Warn := TStringList.Create;
  try
    if (FileName <> '') and FileExists(FileName) then
    begin
      Map.LoadFromFile(FileName, Warn);
      for W in Warn do
        AddLog(llWarn, W);
      AddLog(llInfo, 'authors loaded from ' + FileName);
    end;
    Map.EnsureLogins(FLogins);
    vleAuthors.Strings.BeginUpdate;
    try
      vleAuthors.Strings.Clear;
      for L in FLogins do
        vleAuthors.Strings.Add(L + '=' + Map.Ident(L));
    finally
      vleAuthors.Strings.EndUpdate;
    end;
  finally
    Warn.Free;
    Map.Free;
  end;
end;

// writes the grid into AFileName (keeping logins of the file that are not on
// the grid) through the public TJ2GAuthorMap API; False on an invalid line
function TJ2GMainForm.SaveAuthorsGrid(const AFileName, ADomain: string): Boolean;
var
  Map: TJ2GAuthorMap;
  Warn, Grid: TStringList;
  Tmp, Login, Value, Bad, U: string;
  I, LT, GT: Integer;
  Unmapped: TArray<string>;
begin
  Result := True;
  if vleAuthors.Strings.Count = 0 then
    Exit;
  Bad := '';
  Grid := TStringList.Create;
  try
    for I := 0 to vleAuthors.Strings.Count - 1 do
    begin
      Login := Trim(vleAuthors.Strings.Names[I]);
      Value := Trim(vleAuthors.Strings.ValueFromIndex[I]);
      LT := Pos('<', Value);
      GT := LastDelimiter('>', Value);
      if (Login = '') then
        Continue;
      if (LT < 1) or (GT <> Length(Value)) or (GT < LT + 2) or
        (Pos('<', Copy(Value, LT + 1, MaxInt)) > 0) or (Pos('>', Copy(Value, 1, GT - 1)) > 0) then
        Bad := Bad + sLineBreak + '  ' + Login + ' = ' + Value
      else
        Grid.Add(Login + '=' + Value);
    end;
    if Bad <> '' then
    begin
      pcMain.ActivePage := tsAuthors;
      MessageDlg('Invalid author (expected Full Name <e-mail>):' + Bad, mtError, [mbOK], 0);
      Exit(False);
    end;
    Tmp := TPath.GetTempFileName;
    Map := TJ2GAuthorMap.Create(ADomain);
    Warn := TStringList.Create;
    try
      TFile.WriteAllText(Tmp, Grid.Text, TEncoding.UTF8);
      if FileExists(AFileName) then
        Map.LoadFromFile(AFileName, Warn);
      Warn.Clear;
      Map.LoadFromFile(Tmp, Warn);  // the grid wins (last line wins)
      Map.SaveToFile(AFileName);
      AddLog(llInfo, Format('authors saved to %s (%d login(s))', [AFileName, Map.Count]));
      Unmapped := Map.Unmapped;
      if Length(Unmapped) > 0 then
      begin
        U := string.Join(', ', Unmapped);
        AddLog(llWarn, Format('%d login(s) still with the default name/e-mail (fill them in the Authors page; ' +
          'Git cannot change the authors later): %s', [Length(Unmapped), U]));
      end;
    finally
      Warn.Free;
      Map.Free;
      if FileExists(Tmp) then
        System.SysUtils.DeleteFile(Tmp);
    end;
  finally
    Grid.Free;
  end;
end;

procedure TJ2GMainForm.StartWorker(AExport: Boolean; const AOptions: TJ2GOptions;
  const ASelected: TArray<TJ2GProjectInfo>);
var
  Pwd: TBytes;
  W: TJ2GWorker;
begin
  Pwd := nil;
  if AOptions.Identity = '' then
    Pwd := PasswordBytes;
  try
    W := TJ2GWorker.Create(Self, AExport, AOptions, Pwd, ASelected);
  finally
    J2GWipe(Pwd);
  end;
  W.OnTerminate := WorkerDone;
  FWorker := W;
  FWorkerIsExport := AExport;
  pbProgress.Position := 0;
  pbProgress.Style := pbstMarquee;
  UpdateControls;
  Screen.Cursor := crAppStart;
  W.Start;
end;

procedure TJ2GMainForm.WorkerDone(Sender: TObject);
var
  W: TJ2GWorker;
  S: string;
  Kind: TMsgDlgType;
begin
  W := TJ2GWorker(Sender);
  FWorker := nil;
  Screen.Cursor := crDefault;
  pbProgress.Style := pbstNormal;
  if not FWorkerIsExport then
  begin
    pbProgress.Position := 0;
    if W.ExitCode = J2G_EXIT_OK then
    begin
      FProjects := W.Projects;
      FLogins := nil;
      for var U in W.Users do
        if Trim(U.Login) <> '' then
          FLogins := FLogins + [U.Login];
      TArray.Sort<string>(FLogins);
      FillProjectList;
      LoadAuthorsGrid(False);
      lblStatus.Caption := Format('Connected: %d project(s) listed, %d user(s).',
        [lvProjects.Items.Count, Length(FLogins)]);
    end
    else
    begin
      lblStatus.Caption := 'Connection failed: ' + W.ErrorText;
      if not FCloseRequested and not FAskingClose then
        MessageDlg('Cannot list the projects:' + sLineBreak + W.ErrorText, mtError, [mbOK], 0);
    end;
  end
  else
  begin
    for S in W.Lines do
      AddLog(llInfo, S);
    lblStatus.Caption := Format('Exit code %d - %s', [W.ExitCode, W.Summary]);
    pbProgress.Position := IfThen(W.ExitCode = J2G_EXIT_OK, pbProgress.Max, pbProgress.Position);
    if not FCloseRequested and not FAskingClose then
    begin
      if W.ExitCode = J2G_EXIT_OK then
        Kind := mtInformation
      else
        Kind := mtWarning;
      S := Format('Export finished with exit code %d.', [W.ExitCode]) + sLineBreak + W.Summary;
      if Length(W.Lines) > 0 then
        S := S + sLineBreak + sLineBreak + string.Join(sLineBreak, W.Lines);
      if (W.ExitCode <> J2G_EXIT_OK) and (W.ErrorText <> '') then
        S := S + sLineBreak + sLineBreak + W.ErrorText;
      S := S + sLineBreak + sLineBreak + 'See the Log page and ' + J2G_REPORT_FILE + '.';
      MessageDlg(S, Kind, [mbOK], 0);
    end;
  end;
  UpdateControls;
  if FCloseRequested then
    TThread.ForceQueue(nil,
      procedure
      begin
        Close;
      end);
end;

procedure TJ2GMainForm.AddLog(ALevel: TJ2GLogLevel; const AMsg: string);
const
  Prefix: array[TJ2GLogLevel] of string = ('[debug] ', '', '[warning] ', '[error] ');
begin
  memLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' ' + Prefix[ALevel] + AMsg);
end;

procedure TJ2GMainForm.SetProgress(const AProject: string; ADone, ATotal: Integer; const AStage: string);
begin
  if ATotal > 0 then
  begin
    pbProgress.Style := pbstNormal;
    pbProgress.Max := ATotal;
    pbProgress.Position := Min(ADone, ATotal);
    lblStatus.Caption := Format('%s - %s %d/%d', [AProject, AStage, ADone, ATotal]);
  end
  else
  begin
    pbProgress.Style := pbstMarquee;
    lblStatus.Caption := Format('%s - %s', [AProject, AStage]);
  end;
end;

procedure TJ2GMainForm.btnListClick(Sender: TObject);
var
  O: TJ2GOptions;
begin
  if Assigned(FWorker) or not BuildOptions(jcList, O) then
    Exit;
  AddLog(llInfo, '---- List projects ----');
  lblStatus.Caption := 'Connecting...';
  StartWorker(False, O, nil);
end;

procedure TJ2GMainForm.btnExportClick(Sender: TObject);
var
  O: TJ2GOptions;
  V: string;
begin
  if Assigned(FWorker) or not BuildOptions(jcExport, O) then
    Exit;
  CheckEnvironment;
  if not FEnvOk then
  begin
    UpdateControls;
    Exit;
  end;
  if J2GGitVersion(V) and not J2GGitCheckRefFormat(O.BranchName, True) then
  begin
    pcMain.ActivePage := tsOptions;
    MessageDlg('Invalid Git branch name: ' + O.BranchName, mtWarning, [mbOK], 0);
    Exit;
  end;
  if O.Force and (MessageDlg('The repository folder of each selected project will be DELETED and created ' +
    'again (only folders made by jvcs2git). Continue?', mtConfirmation, [mbYes, mbNo], 0, mbNo) <> mrYes) then
    Exit;
  try
    ForceDirectories(O.OutDir);
  except
    on E: Exception do
    begin
      MessageDlg('Cannot create the output folder: ' + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  if not SaveAuthorsGrid(O.EffectiveAuthorsFile, O.EmailDomain) then
    Exit;
  FLastOutDir := O.OutDir;
  pcMain.ActivePage := tsLog;
  AddLog(llInfo, '---- Export to ' + O.OutDir + ' ----');
  lblStatus.Caption := 'Exporting...';
  StartWorker(True, O, CheckedProjects);
end;

procedure TJ2GMainForm.btnCancelClick(Sender: TObject);
begin
  if Assigned(FWorker) and FWorkerIsExport then
  begin
    TJ2GWorker(FWorker).Cancel := True;
    lblStatus.Caption := 'Cancelling...';
    AddLog(llWarn, 'cancel requested');
    UpdateControls;
  end;
end;

procedure TJ2GMainForm.btnBrowseClick(Sender: TObject);
var
  Dlg: TFileOpenDialog;
begin
  Dlg := TFileOpenDialog.Create(Self);
  try
    Dlg.Title := 'Output folder (one Git repository per project)';
    Dlg.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    if OutDir <> '' then
      Dlg.DefaultFolder := OutDir;
    if Dlg.Execute then
    begin
      edOutDir.Text := Dlg.FileName;
      edOutDirExit(nil);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TJ2GMainForm.edOutDirExit(Sender: TObject);
begin
  // another folder with its own autores.txt: show it; otherwise keep the edits
  LoadAuthorsGrid(True);
  FLastOutDir := '';
  UpdateControls;
end;

procedure TJ2GMainForm.btnKeyFileClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'File with the Blowfish key (Base64, first line)';
    Dlg.Filter := 'All files (*.*)|*.*';
    Dlg.Options := [ofFileMustExist, ofEnableSizing];
    if Dlg.Execute then
      edKeyFile.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TJ2GMainForm.ShellOpen(const ATarget: string);
begin
  if ShellExecute(Handle, 'open', PChar(ATarget), nil, nil, SW_SHOWNORMAL) <= 32 then
    ShellExecute(Handle, 'open', 'notepad.exe', PChar('"' + ATarget + '"'), nil, SW_SHOWNORMAL);
end;

procedure TJ2GMainForm.btnOpenFolderClick(Sender: TObject);
begin
  if FLastOutDir <> '' then
    ShellOpen(FLastOutDir)
  else if OutDir <> '' then
    ShellOpen(OutDir);
end;

procedure TJ2GMainForm.btnOpenReportClick(Sender: TObject);
begin
  if FileExists(ReportFile) then
    ShellOpen(ReportFile);
end;

procedure TJ2GMainForm.chkShowDeletedClick(Sender: TObject);
begin
  FillProjectList;
  UpdateControls;
end;

procedure TJ2GMainForm.btnCheckAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to lvProjects.Items.Count - 1 do
    lvProjects.Items[I].Checked := True;
end;

procedure TJ2GMainForm.btnUncheckAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to lvProjects.Items.Count - 1 do
    lvProjects.Items[I].Checked := False;
end;

procedure TJ2GMainForm.chkNoGitClick(Sender: TObject);
begin
  CheckEnvironment;
  UpdateControls;
end;

procedure TJ2GMainForm.btnRecheckClick(Sender: TObject);
begin
  CheckEnvironment;
  UpdateControls;
end;

procedure TJ2GMainForm.lnkGitLinkClick(Sender: TObject; const Link: string; LinkType: TSysLinkType);
begin
  ShellExecute(Handle, 'open', PChar(Link), nil, nil, SW_SHOWNORMAL);
end;

end.
