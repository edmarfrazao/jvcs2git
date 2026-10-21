(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GSession.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - connection to the JEDI VCS server (TJVCSConnection of the JEDI VCS
client, reference sequence jvcs.dpr:8636-8724): login, branch selection,
Send with timeout and one retry after reconnecting, server log state and the
project list.

With an identity, the named mutex of the AI wrapper (jvcs-ai.ps1 Enter-JaLock)
is held while connected, so the wrapper and its hooks wait instead of logging
in with the same user and dropping this session.

The password is kept only as bytes, for the reconnection, and zeroed on
Disconnect/Destroy. It is never logged.

-----------------------------------------------------------------------------*)

unit J2GSession;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  JVCSClientObjBase, JVCSConnect,
  J2GModel, J2GIdentity, J2GReport;

type
  TJ2GServerLogState = (slUnknown, slOff, slOn);

  TJ2GSession = class
  private
    FConnection: TJVCSConnection;
    FReport: TJ2GReport;
    FHost: string;
    FPort: string;
    FUser: string;
    FPassword: TBytes;
    FBranchName: string;
    FBranchID: Integer;
    FMutex: THandle;
    FMutexName: string;
    FIdentityName: string;
    FReconnects: Integer;
    procedure DoLogin;
    procedure DoSelectBranch;
    function PasswordText: string;
  public
    constructor Create(AReport: TJ2GReport);
    destructor Destroy; override;
    // connects; AIdentityName <> '' acquires the wrapper mutex first
    procedure Connect(const AHost, APort, AUser: string; const APassword: TBytes;
      const AIdentityName: string = ''; AMutexWaitSec: Integer = 30);
    procedure Disconnect;
    function Connected: Boolean;
    // JEDI VCS branch by name ('' or 'HEAD' = default)
    procedure SelectBranch(const ABranchName: string);
    // sends a request; ATimeout = 0 keeps the object's timeout. One retry after
    // reconnecting when the request fails for transport reasons (not for an
    // answer of the server such as 403).
    procedure Send(AObject: TJVCSClientObject; ATimeout: Cardinal = 0);
    function ServerLogState: TJ2GServerLogState;
    function GetProjects: TArray<TJ2GProjectInfo>;
    function ServerDescription: string;
    property Connection: TJVCSConnection read FConnection;
    property Host: string read FHost;
    property Port: string read FPort;
    property User: string read FUser;
    property Reconnects: Integer read FReconnects;
  end;

// fvcscrypt.dll next to the exe (needed for the login); raises EJ2GError(12)
procedure J2GCheckRequiredLibs;
// resolves -project values (name or ID, case-insensitive) against the list
function J2GResolveProjects(const AList: TArray<TJ2GProjectInfo>; const ASpecs: TArray<string>;
  AAll, AIncludeDeleted: Boolean; out ASelected: TArray<TJ2GProjectInfo>; out AMissing: string): Boolean;
// name of the wrapper mutex for an identity (same sanitizing as jvcs-ai.ps1)
function J2GWrapperMutexName(const AIdentity, AUser, AHost, APort: string): string;

implementation

uses
  RFormat, JVCSTypes, JVCSClientObj, JVCSBranchClientObj;

procedure J2GCheckRequiredLibs;
var
  Lib: HMODULE;
  FileName: string;
begin
  FileName := ExtractFilePath(ParamStr(0)) + 'fvcscrypt.dll';
  if not FileExists(FileName) then
    raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'fvcscrypt.dll not found next to the program (%s)', [FileName]);
  Lib := LoadLibrary(PChar(FileName));
  if Lib = 0 then
    raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'fvcscrypt.dll cannot be loaded (%s)', [SysErrorMessage(GetLastError)]);
  FreeLibrary(Lib);
end;

function J2GWrapperMutexName(const AIdentity, AUser, AHost, APort: string): string;
var
  Key: string;
  I: Integer;
begin
  Key := AIdentity + '.' + AUser + '@' + AHost + '_' + APort;
  for I := 1 to Length(Key) do
    if not CharInSet(Key[I], ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '@', '-']) then
      Key[I] := '_';
  Result := 'Local\JEDI.JVCS.AI.' + Key;
end;

function J2GResolveProjects(const AList: TArray<TJ2GProjectInfo>; const ASpecs: TArray<string>;
  AAll, AIncludeDeleted: Boolean; out ASelected: TArray<TJ2GProjectInfo>; out AMissing: string): Boolean;
var
  Spec: string;
  P: TJ2GProjectInfo;
  ID, I: Integer;
  Found, Dup: Boolean;

  procedure AddSel(const AP: TJ2GProjectInfo);
  var
    J: Integer;
  begin
    for J := 0 to High(ASelected) do
      if ASelected[J].ProjectID = AP.ProjectID then
        Exit;
    SetLength(ASelected, Length(ASelected) + 1);
    ASelected[High(ASelected)] := AP;
  end;

begin
  ASelected := nil;
  AMissing := '';
  if AAll then
  begin
    for P in AList do
      if AIncludeDeleted or not P.Deleted then
        AddSel(P);
    Exit(True);
  end;
  for Spec in ASpecs do
  begin
    Found := False;
    ID := StrToIntDef(Trim(Spec), -1);
    for I := 0 to High(AList) do
    begin
      P := AList[I];
      if ((ID > 0) and (P.ProjectID = ID)) or SameText(P.Name, Trim(Spec)) or
        SameText(ChangeFileExt(P.Name, ''), Trim(Spec)) then
      begin
        // a deleted project is found only with -include-deleted
        Dup := P.Deleted and not AIncludeDeleted;
        if not Dup then
        begin
          AddSel(P);
          Found := True;
          Break;
        end;
      end;
    end;
    if not Found then
    begin
      if AMissing <> '' then
        AMissing := AMissing + ', ';
      AMissing := AMissing + Spec;
    end;
  end;
  Result := AMissing = '';
end;

{ TJ2GSession }

constructor TJ2GSession.Create(AReport: TJ2GReport);
begin
  inherited Create;
  FReport := AReport;
  FMutex := 0;
end;

destructor TJ2GSession.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

function TJ2GSession.PasswordText: string;
var
  Enc: TEncoding;
begin
  // the password travels as ANSI bytes of the protocol code page
  Enc := TEncoding.GetEncoding(MWCodePage);
  try
    Result := Enc.GetString(FPassword);
  finally
    Enc.Free;
  end;
end;

procedure TJ2GSession.DoLogin;
var
  Pw: string;
begin
  FreeAndNil(FConnection);
  try
    FConnection := TJVCSConnection.Create(nil);
  except
    on E: Exception do
      raise EJ2GError.Create(J2G_EXIT_ENVIRONMENT, E.Message);
  end;
  FConnection.Server := FHost;
  FConnection.Port := FPort;
  FConnection.UserName := FUser;
  Pw := PasswordText;
  try
    FConnection.UserPassword := Pw;
    try
      FConnection.Active := True;
    except
      on E: EJVCSClientRequestError do
        raise EJ2GError.CreateFmt(J2G_EXIT_SERVER, 'server %s:%s: %s', [FHost, FPort, E.Message]);
      on E: EJ2GError do
        raise;
      on E: Exception do
      begin
        // transport errors come as "Request 'X' failed/timed out"; anything else
        // raised during LOGIN is the server refusing the credentials
        if (Pos('Request ''', E.Message) = 1) or not (E is EJVCSClient) then
          raise EJ2GError.CreateFmt(J2G_EXIT_SERVER, 'cannot connect to %s:%s: %s', [FHost, FPort, E.Message])
        else
          raise EJ2GError.CreateFmt(J2G_EXIT_CREDENTIAL, 'login refused for user ''%s'': %s', [FUser, E.Message]);
      end;
    end;
  finally
    if Pw <> '' then
      FillChar(PChar(Pw)^, Length(Pw) * SizeOf(Char), 0);
    // the connection keeps its own copy for its lifetime (TJVCSConnection)
  end;
  if not FConnection.Active then
    raise EJ2GError.CreateFmt(J2G_EXIT_CREDENTIAL, 'login refused for user ''%s''', [FUser]);
end;

procedure TJ2GSession.Connect(const AHost, APort, AUser: string; const APassword: TBytes;
  const AIdentityName: string; AMutexWaitSec: Integer);
var
  W: DWORD;
begin
  Disconnect;
  // records of the protocol use ShortString: align with the protocol code page
  DefaultSystemCodePage := MWCodePage;
  J2GCheckRequiredLibs;
  FHost := AHost;
  FPort := APort;
  if FPort = '' then
    FPort := '2106';
  FUser := AUser;
  FIdentityName := AIdentityName;
  FPassword := Copy(APassword);
  if FIdentityName <> '' then
  begin
    FMutexName := J2GWrapperMutexName(FIdentityName, FUser, FHost, FPort);
    FMutex := CreateMutex(nil, False, PChar(FMutexName));
    if FMutex = 0 then
      raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'cannot create mutex %s', [FMutexName]);
    W := WaitForSingleObject(FMutex, Cardinal(AMutexWaitSec) * 1000);
    if W = WAIT_ABANDONED then
      FReport.Warn('the previous jvcs-ai call ended without releasing the mutex (abandoned); continuing')
    else if W <> WAIT_OBJECT_0 then
    begin
      CloseHandle(FMutex);
      FMutex := 0;
      raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT,
        'another jvcs-ai call with identity ''%s'' is running for more than %d s (mutex %s)',
        [FIdentityName, AMutexWaitSec, FMutexName]);
    end;
  end;
  FReport.Info(Format('connecting to %s:%s as %s', [FHost, FPort, FUser]));
  DoLogin;
  FReport.Info('connected: ' + ServerDescription);
end;

procedure TJ2GSession.Disconnect;
begin
  if Assigned(FConnection) then
  begin
    try
      if FConnection.Active then
        FConnection.Active := False;
    except
      // the server may have dropped the session already
    end;
    FreeAndNil(FConnection);
  end;
  J2GWipe(FPassword);
  if FMutex <> 0 then
  begin
    ReleaseMutex(FMutex);
    CloseHandle(FMutex);
    FMutex := 0;
  end;
end;

function TJ2GSession.Connected: Boolean;
begin
  Result := Assigned(FConnection) and FConnection.Active;
end;

function TJ2GSession.ServerDescription: string;
begin
  if Assigned(FConnection) then
    Result := Format('%s v.%d', [FConnection.ServerType, FConnection.ServerVersion])
  else
    Result := '';
end;

procedure TJ2GSession.DoSelectBranch;
var
  GetBranchList: TJVCSGetBranchList;
  SelectBranch: TJVCSSelectBranch;
  I: Integer;
begin
  if (FBranchName = '') or SameText(FBranchName, 'HEAD') then
    Exit;
  if FBranchID = 0 then
  begin
    GetBranchList := TJVCSGetBranchList.Create(nil);
    try
      GetBranchList.IncludeDetails := False;
      FConnection.SendRequest(GetBranchList);
      for I := 0 to Pred(GetBranchList.OutputItemCount) do
        if SameText(GetBranchList.OutputItems[I].Name, FBranchName) then
        begin
          FBranchID := GetBranchList.OutputItems[I].BranchID;
          Break;
        end;
    finally
      GetBranchList.Free;
    end;
    if FBranchID = 0 then
      raise EJ2GError.CreateFmt(J2G_EXIT_NOTFOUND, 'JEDI VCS branch ''%s'' not found', [FBranchName]);
  end;
  SelectBranch := TJVCSSelectBranch.Create(nil);
  try
    SelectBranch.BranchID := FBranchID;
    FConnection.SendRequest(SelectBranch);
    if not SelectBranch.BranchFound then
      raise EJ2GError.CreateFmt(J2G_EXIT_NOTFOUND, 'JEDI VCS branch ''%s'' not found', [FBranchName]);
  finally
    SelectBranch.Free;
  end;
end;

procedure TJ2GSession.SelectBranch(const ABranchName: string);
begin
  FBranchName := ABranchName;
  FBranchID := 0;
  DoSelectBranch;
  if (FBranchName = '') or SameText(FBranchName, 'HEAD') then
    FReport.Info('JEDI VCS branch: HEAD')
  else
    FReport.Info('JEDI VCS branch: ' + FBranchName);
end;

procedure TJ2GSession.Send(AObject: TJVCSClientObject; ATimeout: Cardinal);
begin
  if not Assigned(FConnection) then
    raise EJ2GError.Create(J2G_EXIT_SERVER, 'not connected');
  if ATimeout > 0 then
    AObject.RequestTimeout := ATimeout;
  try
    FConnection.SendRequest(AObject);
  except
    on E: EJVCSClientRequestError do
      raise;
    on E: Exception do
    begin
      // transport failure or dropped session: reconnect once and repeat
      FReport.Warn(Format('request %s failed (%s); reconnecting', [AObject.ClassName, E.Message]));
      Inc(FReconnects);
      try
        DoLogin;
        DoSelectBranch;
      except
        on E2: EJ2GError do
          raise EJ2GError.CreateFmt(J2G_EXIT_SERVER, 'connection lost and reconnection failed: %s', [E2.Message]);
      end;
      if ATimeout > 0 then
        AObject.RequestTimeout := ATimeout;
      try
        FConnection.SendRequest(AObject);
      except
        on E3: EJVCSClientRequestError do
          raise;
        on E3: Exception do
          raise EJ2GError.CreateFmt(J2G_EXIT_SERVER, 'request %s failed after reconnecting: %s', [AObject.ClassName, E3.Message]);
      end;
    end;
  end;
end;

function TJ2GSession.ServerLogState: TJ2GServerLogState;
var
  GetServerOptions: TJVCSGetServerOptions;
begin
  Result := slUnknown;
  GetServerOptions := TJVCSGetServerOptions.Create(nil);
  try
    try
      Send(GetServerOptions);
      if GetServerOptions.WriteVCSLog then
        Result := slOn
      else
        Result := slOff;
    except
      on E: EJVCSClientRequestError do
        if E.StatusCode = 403 then
          Result := slUnknown
        else
          raise;
    end;
  finally
    GetServerOptions.Free;
  end;
end;

function TJ2GSession.GetProjects: TArray<TJ2GProjectInfo>;
var
  GetProjectList: TJVCSGetProjectList;
  I: Integer;
begin
  Result := nil;
  GetProjectList := TJVCSGetProjectList.Create(nil);
  try
    GetProjectList.Purpose := '';
    GetProjectList.IncludeDetails := False;
    Send(GetProjectList);
    SetLength(Result, GetProjectList.OutputItemCount);
    for I := 0 to Pred(GetProjectList.OutputItemCount) do
    begin
      Result[I].ProjectID := GetProjectList.OutputItems[I].ProjectID;
      Result[I].Name := string(GetProjectList.OutputItems[I].ProjectName);
      Result[I].Deleted := GetProjectList.OutputItems[I].ProjectDeleted;
      Result[I].Description := GetProjectList.OutputItems[I].Description;
    end;
  finally
    GetProjectList.Free;
  end;
end;

end.
