(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GReport.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - log (screen + file), skipped revisions, warnings, summary, JSON and
the Markdown report. Interface frozen after PT0.

Streams: with -json the stdout gets ONLY the final JSON line; messages go to
stderr (silenced by -quiet) and to the log file. Without -json messages go to
stdout (errors to stderr). In the window (no console) only OnMessage is used.
Never log the password or the Blowfish key.

-----------------------------------------------------------------------------*)

unit J2GReport;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections;

type
  TJ2GLogLevel = (llDebug, llInfo, llWarn, llError);
  TJ2GLogEvent = procedure(ALevel: TJ2GLogLevel; const AMsg: string) of object;

  TJ2GSkip = record
    RevisionID: Integer;
    Module: string;
    Ext: string;
    Reason: string;   // J2G_REASON_* (J2GModel)
    Detail: string;   // free text (report/log only, not in JSON)
  end;

  TJ2GProjectReport = class
  public
    ProjectID: Integer;
    Name: string;
    Repo: string;               // repository folder
    StreamFile: string;         // <out>\<repo>.fast-import
    ExitCode: Integer;          // 0, 5, 9, 11, 12
    Modules: Integer;
    Revisions: Integer;
    Commits: Integer;
    Tags: Integer;
    BlobsDownloaded: Integer;
    BlobsFromCache: Integer;
    BytesDownloaded: Int64;
    Seconds: Double;
    DfmConverted: Integer;
    DfmConvertFailed: Integer;
    DfmBinaryFound: Integer;
    CommitsDateFromLog: Integer;
    CommitsDateFromFile: Integer;
    DatesSubstituted: Integer;
    Skipped: TList<TJ2GSkip>;
    Warnings: TStringList;
    constructor Create;
    destructor Destroy; override;
    function Ok: Boolean;
    function ToJson: string;
  end;

  TJ2GReport = class
  private
    FLock: TCriticalSection;
    FLog: TFileStream;
    FProjects: TObjectList<TJ2GProjectReport>;
    FCurrent: TJ2GProjectReport;
    FWarnings: TStringList;
    FUnmappedAuthors: TStringList;
    FOnMessage: TJ2GLogEvent;
    procedure WriteLogLine(const ALine: string);
    procedure Emit(ALevel: TJ2GLogLevel; const AMsg: string);
  public
    JsonMode: Boolean;
    Quiet: Boolean;
    Command: string;           // export | list | dryrun | selftest
    ExitCode: Integer;
    Message: string;
    LogFile: string;
    ReportFile: string;
    AuthorsFile: string;
    RawProjectsJson: string;   // used instead of Projects in ToJson when not empty (-list)
    ExtraJson: string;         // extra top-level fields, already JSON: '"x":1,"y":"z"'
    constructor Create;
    destructor Destroy; override;
    procedure OpenLog(const AFileName: string);
    procedure CloseLog;
    procedure Debug(const AMsg: string);
    procedure Info(const AMsg: string);
    procedure Warn(const AMsg: string);    // adds to the current project (or global) warnings
    procedure Error(const AMsg: string);   // screen + log, not a warning
    procedure Skip(ARevisionID: Integer; const AModule, AExt, AReason: string; const ADetail: string = '');
    function BeginProject(AProjectID: Integer; const AName: string): TJ2GProjectReport;
    procedure EndProject;
    procedure AddUnmappedAuthor(const ALogin: string);
    function Summary: string;
    function ToJson: string;
    procedure WriteMarkdown(const AFileName: string);
    property Projects: TObjectList<TJ2GProjectReport> read FProjects;
    property Current: TJ2GProjectReport read FCurrent;
    property Warnings: TStringList read FWarnings;
    property UnmappedAuthors: TStringList read FUnmappedAuthors;
    property OnMessage: TJ2GLogEvent read FOnMessage write FOnMessage;
  end;

// JSON string literal, ASCII only (\uXXXX), with quotes
function J2GJsonStr(const S: string): string;
// path for JSON/report: forward slashes
function J2GJsonPath(const S: string): string;
function J2GJsonBool(B: Boolean): string;

implementation

uses
  J2GModel;

function J2GJsonStr(const S: string): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(S) + 2);
  try
    SB.Append('"');
    for C in S do
      case C of
        '"': SB.Append('\"');
        '\': SB.Append('\\');
        #8: SB.Append('\b');
        #9: SB.Append('\t');
        #10: SB.Append('\n');
        #12: SB.Append('\f');
        #13: SB.Append('\r');
      else
        if (Ord(C) < 32) or (Ord(C) > 126) then
          SB.Append('\u' + IntToHex(Ord(C), 4).ToLower)
        else
          SB.Append(C);
      end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function J2GJsonPath(const S: string): string;
begin
  Result := StringReplace(S, '\', '/', [rfReplaceAll]);
end;

function J2GJsonBool(B: Boolean): string;
begin
  if B then
    Result := 'true'
  else
    Result := 'false';
end;

function JsonFloat(const D: Double): string;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Invariant;
  Result := FormatFloat('0.0', D, FS);
end;

function JsonStrArray(L: TStrings): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to L.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + J2GJsonStr(L[I]);
  end;
  Result := Result + ']';
end;

{ TJ2GProjectReport }

constructor TJ2GProjectReport.Create;
begin
  inherited Create;
  Skipped := TList<TJ2GSkip>.Create;
  Warnings := TStringList.Create;
end;

destructor TJ2GProjectReport.Destroy;
begin
  Warnings.Free;
  Skipped.Free;
  inherited Destroy;
end;

function TJ2GProjectReport.Ok: Boolean;
begin
  Result := ExitCode = J2G_EXIT_OK;
end;

function TJ2GProjectReport.ToJson: string;
var
  SB: TStringBuilder;
  I: Integer;
  S: TJ2GSkip;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{"id":').Append(ProjectID)
      .Append(',"name":').Append(J2GJsonStr(Name))
      .Append(',"ok":').Append(J2GJsonBool(Ok))
      .Append(',"exitCode":').Append(ExitCode)
      .Append(',"repo":').Append(J2GJsonStr(J2GJsonPath(Repo)))
      .Append(',"modules":').Append(Modules)
      .Append(',"revisions":').Append(Revisions)
      .Append(',"commits":').Append(Commits)
      .Append(',"tags":').Append(Tags)
      .Append(',"blobsDownloaded":').Append(BlobsDownloaded)
      .Append(',"blobsFromCache":').Append(BlobsFromCache)
      .Append(',"bytesDownloaded":').Append(BytesDownloaded)
      .Append(',"seconds":').Append(JsonFloat(Seconds))
      .Append(',"dfmConverted":').Append(DfmConverted)
      .Append(',"dfmConvertFailed":').Append(DfmConvertFailed)
      .Append(',"commitsDateFromLog":').Append(CommitsDateFromLog)
      .Append(',"commitsDateFromFile":').Append(CommitsDateFromFile)
      .Append(',"datesSubstituted":').Append(DatesSubstituted)
      .Append(',"skipped":[');
    for I := 0 to Skipped.Count - 1 do
    begin
      S := Skipped[I];
      if I > 0 then
        SB.Append(',');
      SB.Append('{"revisionId":').Append(S.RevisionID)
        .Append(',"module":').Append(J2GJsonStr(S.Module))
        .Append(',"ext":').Append(J2GJsonStr(S.Ext))
        .Append(',"reason":').Append(J2GJsonStr(S.Reason)).Append('}');
    end;
    SB.Append('],"warnings":').Append(JsonStrArray(Warnings)).Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TJ2GReport }

constructor TJ2GReport.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FProjects := TObjectList<TJ2GProjectReport>.Create(True);
  FWarnings := TStringList.Create;
  FUnmappedAuthors := TStringList.Create;
  FUnmappedAuthors.Sorted := True;
  FUnmappedAuthors.Duplicates := dupIgnore;
  Command := 'export';
end;

destructor TJ2GReport.Destroy;
begin
  CloseLog;
  FUnmappedAuthors.Free;
  FWarnings.Free;
  FProjects.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TJ2GReport.OpenLog(const AFileName: string);
begin
  CloseLog;
  if AFileName = '' then
    Exit;
  ForceDirectories(ExtractFileDir(ExpandFileName(AFileName)));
  if FileExists(AFileName) then
  begin
    FLog := TFileStream.Create(AFileName, fmOpenReadWrite or fmShareDenyWrite);
    FLog.Seek(0, soEnd);
  end
  else
    FLog := TFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
  LogFile := ExpandFileName(AFileName);
  WriteLogLine('');
  WriteLogLine(Format('==== %s %s - %s ====', [J2G_PRODUCT, Command,
    FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
end;

procedure TJ2GReport.CloseLog;
begin
  FreeAndNil(FLog);
end;

procedure TJ2GReport.WriteLogLine(const ALine: string);
var
  B: TBytes;
begin
  if not Assigned(FLog) then
    Exit;
  B := TEncoding.UTF8.GetBytes(ALine + #13#10);
  if Length(B) > 0 then
    FLog.WriteBuffer(B[0], Length(B));
end;

procedure TJ2GReport.Emit(ALevel: TJ2GLogLevel; const AMsg: string);
const
  Prefix: array[TJ2GLogLevel] of string = ('[debug] ', '', '[warning] ', '[error] ');
var
  Line: string;
begin
  Line := Prefix[ALevel] + AMsg;
  FLock.Enter;
  try
    WriteLogLine(FormatDateTime('hh:nn:ss', Now) + ' ' + Line);
    if IsConsole and (ALevel <> llDebug) then
    begin
      if JsonMode then
      begin
        if not Quiet or (ALevel = llError) then
          Writeln(ErrOutput, Line);
      end
      else if ALevel = llError then
        Writeln(ErrOutput, Line)
      else if not Quiet then
        Writeln(Line);
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(FOnMessage) then
    FOnMessage(ALevel, AMsg);
end;

procedure TJ2GReport.Debug(const AMsg: string);
begin
  Emit(llDebug, AMsg);
end;

procedure TJ2GReport.Info(const AMsg: string);
begin
  Emit(llInfo, AMsg);
end;

procedure TJ2GReport.Warn(const AMsg: string);
begin
  FLock.Enter;
  try
    if Assigned(FCurrent) then
      FCurrent.Warnings.Add(AMsg)
    else
      FWarnings.Add(AMsg);
  finally
    FLock.Leave;
  end;
  Emit(llWarn, AMsg);
end;

procedure TJ2GReport.Error(const AMsg: string);
begin
  Emit(llError, AMsg);
end;

procedure TJ2GReport.Skip(ARevisionID: Integer; const AModule, AExt, AReason, ADetail: string);
var
  S: TJ2GSkip;
  Msg: string;
begin
  S.RevisionID := ARevisionID;
  S.Module := AModule;
  S.Ext := AExt;
  S.Reason := AReason;
  S.Detail := ADetail;
  FLock.Enter;
  try
    if Assigned(FCurrent) then
      FCurrent.Skipped.Add(S);
  finally
    FLock.Leave;
  end;
  Msg := Format('skipped: rev %d %s (%s) %s', [ARevisionID, AModule, AExt, AReason]);
  if ADetail <> '' then
    Msg := Msg + ' - ' + ADetail;
  Emit(llWarn, Msg);
end;

function TJ2GReport.BeginProject(AProjectID: Integer; const AName: string): TJ2GProjectReport;
begin
  Result := TJ2GProjectReport.Create;
  Result.ProjectID := AProjectID;
  Result.Name := AName;
  FLock.Enter;
  try
    FProjects.Add(Result);
    FCurrent := Result;
  finally
    FLock.Leave;
  end;
end;

procedure TJ2GReport.EndProject;
begin
  FLock.Enter;
  try
    FCurrent := nil;
  finally
    FLock.Leave;
  end;
end;

procedure TJ2GReport.AddUnmappedAuthor(const ALogin: string);
begin
  FLock.Enter;
  try
    FUnmappedAuthors.Add(ALogin);
  finally
    FLock.Leave;
  end;
end;

function TJ2GReport.Summary: string;
var
  P: TJ2GProjectReport;
  NSkip, NFail: Integer;
begin
  NSkip := 0;
  NFail := 0;
  for P in FProjects do
  begin
    Inc(NSkip, P.Skipped.Count);
    if not (P.ExitCode in [J2G_EXIT_OK, J2G_EXIT_PARTIAL]) then
      Inc(NFail);
  end;
  Result := Format('%d project(s), %d failed, %d skipped member(s)', [FProjects.Count, NFail, NSkip]);
end;

function TJ2GReport.ToJson: string;
var
  SB: TStringBuilder;
  I: Integer;
  AllWarn: TStringList;
begin
  SB := TStringBuilder.Create;
  AllWarn := TStringList.Create;
  try
    AllWarn.Assign(FWarnings);
    SB.Append('{"ok":').Append(J2GJsonBool(ExitCode = J2G_EXIT_OK))
      .Append(',"command":').Append(J2GJsonStr(Command))
      .Append(',"exitCode":').Append(ExitCode)
      .Append(',"message":').Append(J2GJsonStr(Message));
    if AllWarn.Count > 0 then
      SB.Append(',"warnings":').Append(JsonStrArray(AllWarn));
    if LogFile <> '' then
      SB.Append(',"log":').Append(J2GJsonStr(J2GJsonPath(LogFile)));
    if ReportFile <> '' then
      SB.Append(',"report":').Append(J2GJsonStr(J2GJsonPath(ReportFile)));
    if AuthorsFile <> '' then
    begin
      SB.Append(',"authorsFile":').Append(J2GJsonStr(J2GJsonPath(AuthorsFile)));
      SB.Append(',"unmappedAuthors":').Append(JsonStrArray(FUnmappedAuthors));
    end;
    if ExtraJson <> '' then
      SB.Append(',').Append(ExtraJson);
    SB.Append(',"projects":');
    if RawProjectsJson <> '' then
      SB.Append(RawProjectsJson)
    else
    begin
      SB.Append('[');
      for I := 0 to FProjects.Count - 1 do
      begin
        if I > 0 then
          SB.Append(',');
        SB.Append(FProjects[I].ToJson);
      end;
      SB.Append(']');
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    AllWarn.Free;
    SB.Free;
  end;
end;

procedure TJ2GReport.WriteMarkdown(const AFileName: string);
var
  L: TStringList;
  P: TJ2GProjectReport;
  S: TJ2GSkip;
  W: string;
begin
  L := TStringList.Create;
  try
    L.Add('# jvcs2git - relatorio / report');
    L.Add('');
    L.Add(Format('- Data / date: %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)]));
    L.Add(Format('- Comando / command: `%s` - exit code %d', [Command, ExitCode]));
    L.Add(Format('- Resumo / summary: %s', [Message]));
    if LogFile <> '' then
      L.Add(Format('- Log: `%s`', [LogFile]));
    if AuthorsFile <> '' then
      L.Add(Format('- Autores / authors: `%s`', [AuthorsFile]));
    if FUnmappedAuthors.Count > 0 then
      L.Add('- Logins sem nome/e-mail no mapa / unmapped logins: ' + FUnmappedAuthors.CommaText);
    for W in FWarnings do
      L.Add('- Aviso / warning: ' + W);
    for P in FProjects do
    begin
      L.Add('');
      L.Add(Format('## %s (ID %d) - exit code %d', [P.Name, P.ProjectID, P.ExitCode]));
      L.Add('');
      L.Add('| Item | Valor / value |');
      L.Add('|---|---|');
      L.Add(Format('| Repositorio / repository | `%s` |', [P.Repo]));
      L.Add(Format('| Modulos / modules | %d |', [P.Modules]));
      L.Add(Format('| Revisoes / revisions | %d |', [P.Revisions]));
      L.Add(Format('| Commits | %d |', [P.Commits]));
      L.Add(Format('| Tags | %d |', [P.Tags]));
      L.Add(Format('| Blobs baixados / downloaded | %d (%d bytes) |', [P.BlobsDownloaded, P.BytesDownloaded]));
      L.Add(Format('| Blobs do cache / from cache | %d |', [P.BlobsFromCache]));
      L.Add(Format('| .dfm convertidos / converted | %d (falhas / failed: %d) |', [P.DfmConverted, P.DfmConvertFailed]));
      L.Add(Format('| Commits com data do log / dated by log | %d |', [P.CommitsDateFromLog]));
      L.Add(Format('| Commits com data do arquivo / dated by file | %d |', [P.CommitsDateFromFile]));
      L.Add(Format('| Datas substituidas / substituted dates | %d |', [P.DatesSubstituted]));
      L.Add(Format('| Tempo / time | %.1f s |', [P.Seconds]));
      if P.Skipped.Count > 0 then
      begin
        L.Add('');
        L.Add('### Pulados / skipped');
        L.Add('');
        L.Add('| Rev ID | Modulo / module | Ext | Motivo / reason | Detalhe / detail |');
        L.Add('|---|---|---|---|---|');
        for S in P.Skipped do
          L.Add(Format('| %d | %s | %s | %s | %s |', [S.RevisionID, S.Module, S.Ext, S.Reason, S.Detail]));
      end;
      if P.Warnings.Count > 0 then
      begin
        L.Add('');
        L.Add('### Avisos / warnings');
        L.Add('');
        for W in P.Warnings do
          L.Add('- ' + W);
      end;
    end;
    ForceDirectories(ExtractFileDir(ExpandFileName(AFileName)));
    L.WriteBOM := False;
    L.LineBreak := #13#10;
    L.SaveToFile(AFileName, TEncoding.UTF8);
    ReportFile := ExpandFileName(AFileName);
  finally
    L.Free;
  end;
end;

end.
