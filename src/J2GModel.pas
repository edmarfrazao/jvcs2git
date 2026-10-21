(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GModel.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - data model shared by every unit (CLI, GUI, fetch, grouping,
fast-import). Frozen after PT0: new fields only with notice to the main
session. All dates are GMT/UTC (as the JEDI VCS server stores them).

-----------------------------------------------------------------------------*)

unit J2GModel;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

const
  // exit codes (aligned with the JEDI VCS AI wrapper, tools\ai\LEIAME.md 3)
  J2G_EXIT_OK          = 0;
  J2G_EXIT_USAGE       = 2;
  J2G_EXIT_CREDENTIAL  = 4;
  J2G_EXIT_NOTFOUND    = 5;
  J2G_EXIT_SERVER      = 9;
  J2G_EXIT_PARTIAL     = 11;
  J2G_EXIT_ENVIRONMENT = 12;

  // skipped reasons (JSON "reason", report)
  J2G_REASON_ENCRYPTED  = 'encrypted';
  J2G_REASON_NOBLOB     = 'noBlob';
  J2G_REASON_CRC        = 'crcMismatch';
  J2G_REASON_ERROR      = 'error';
  J2G_REASON_NOMEMBERS  = 'noMembers';
  J2G_REASON_NOCOMMIT   = 'noCommit';     // tag without any emitted commit
  J2G_REASON_DFMFAILED  = 'dfmNotConverted';

  J2G_PRODUCT = 'jvcs2git';
  J2G_VERSION = '0.1.1';    // keep equal to src\jvcs2git-ver.rh
  J2G_URL = 'https://github.com/edmarfrazao/jvcs2git';
  J2G_MIDWARE_NOTICE = 'This product is based on MidWare. Freeware source code is available at http://www.overbyte.be.';

type
  // error with the exit code the CLI must return
  EJ2GError = class(Exception)
  private
    FExitCode: Integer;
  public
    constructor Create(AExitCode: Integer; const AMsg: string);
    constructor CreateFmt(AExitCode: Integer; const AMsg: string; const Args: array of const);
    property ExitCode: Integer read FExitCode;
  end;

  // status of a revision or of one member (blob) of a revision
  TJ2GRevStatus = (rsPending, rsOk, rsEncrypted, rsNoBlob, rsCrcMismatch,
    rsError, rsNoMembers);

  // where the effective date of a revision came from
  TJ2GDateSource = (dsNone, dsLog, dsFile, dsModule, dsPrevious, dsNow);

  TJ2GModule = class;

  // one member (blob) of a revision: the module file or a family member (.dfm...)
  TJ2GMember = record
    Ext: string;            // lower case with dot: '.pas', '.dfm'
    Size: Integer;          // original size from GET_MODULE_HISTORY
    OrigTime: TDateTime;    // origtime of this blob (GMT; file time on the workstation)
    Status: TJ2GRevStatus;
    Path: string;           // final repository path ('src/Unit1.pas'), set before the stream
    CacheFile: string;      // cached raw bytes (after unzip/decrypt, before .dfm conversion)
    ZipName: string;        // file name found inside the ZIP (original spelling), '' if none
  end;

  TJ2GRevision = class
  public
    RevisionID: Integer;
    ModuleID: Integer;
    Module: TJ2GModule;     // not owned
    Version: Integer;
    Revision: Integer;
    Hidden: Boolean;
    UserName: string;       // login (from GET_MODULE_HISTORY, 1st row)
    Comment: string;        // check-in comment (1st row)
    OrigTime: TDateTime;    // max(origtime of all members)
    LogTime: TDateTime;     // check-in time from the server log (0 = not matched)
    Date: TDateTime;        // effective date (GMT) after validation/substitution
    DateSource: TJ2GDateSource;
    DateSubstituted: Boolean;
    OriginalDateText: string; // original value when DateSubstituted
    Members: TArray<TJ2GMember>;
    Status: TJ2GRevStatus;  // aggregate
    Mark: Integer;          // fast-import mark of the commit that contains it (0 = none)
    LabelIDs: TList<Integer>;
    constructor Create;
    destructor Destroy; override;
    function VersionText: string; // '1.3'
    function MemberIndex(const AExt: string): Integer;
  end;

  TJ2GModule = class
  public
    ModuleID: Integer;
    Name: string;           // name as stored on the server (lower case)
    Path: string;           // folder as stored on the server (lower case, may end with '\')
    Hidden: Boolean;
    RelPath: string;        // repository folder, '/' separated, '' = root, ends with '/' when not empty
    DisplayName: string;    // ONE spelling per module (latest readable ZIP name or server name)
    ModuleTimestamp: TDateTime; // modules.tstamp (1st row of GET_REVISION_LIST), 0 = unknown
    Revisions: TList<TJ2GRevision>;  // not owned, sorted by RevisionID
    LastPaths: TStringList; // paths emitted by the last exported revision (sorted, no dups)
    constructor Create;
    destructor Destroy; override;
    function FullServerName: string; // Path + Name (rule of jvcs.dpr:4316)
  end;

  TJ2GLabel = class
  public
    LabelID: Integer;
    Name: string;
    Description: string;
    TagName: string;        // sanitized git tag name
    RevisionIDs: TList<Integer>; // labeled revisions of this project
    TargetMark: Integer;    // commit mark the tag points to (0 = no tag)
    TargetRevisionID: Integer;
    Approximate: Boolean;   // not all labeled revisions are in the target commit state
    constructor Create;
    destructor Destroy; override;
  end;

  TJ2GCommit = class
  public
    Mark: Integer;
    Revisions: TList<TJ2GRevision>; // not owned, in RevisionID order
    UserName: string;
    Comment: string;
    AuthorDate: TDateTime;    // GMT
    CommitterDate: TDateTime; // GMT, monotonic unless -committer-date original
    DateFromLog: Boolean;     // all revisions dated by the server log
    constructor Create;
    destructor Destroy; override;
    function HasModule(AModuleID: Integer): Boolean;
  end;

  TJ2GUser = record
    UserID: Integer;
    Login: string;
    Deleted: Boolean;
  end;

  // entry of GET_PROJECT_LIST
  TJ2GProjectInfo = record
    ProjectID: Integer;
    Name: string;
    Deleted: Boolean;
    Description: string;
  end;

  TJ2GProject = class
  private
    FModuleIndex: TDictionary<Integer, TJ2GModule>;
    FRevisionIndex: TDictionary<Integer, TJ2GRevision>;
  public
    ProjectID: Integer;
    Name: string;           // 'exemplo01.dpr'
    Deleted: Boolean;
    Description: string;
    RepoName: string;       // repository folder name (sanitized, without extension)
    Root: string;           // server folder used as repository root (lower case, ends with '\')
    Modules: TObjectList<TJ2GModule>;      // owned
    Revisions: TObjectList<TJ2GRevision>;  // owned, sorted by RevisionID
    Labels: TObjectList<TJ2GLabel>;        // owned
    Commits: TObjectList<TJ2GCommit>;      // owned
    Users: TList<TJ2GUser>;
    constructor Create;
    destructor Destroy; override;
    function AddModule(AModule: TJ2GModule): TJ2GModule;
    function AddRevision(ARevision: TJ2GRevision): TJ2GRevision;
    function FindModule(AModuleID: Integer): TJ2GModule;
    function FindRevision(ARevisionID: Integer): TJ2GRevision;
    procedure SortRevisions; // by RevisionID; also each module's list
  end;

function J2GStatusReason(AStatus: TJ2GRevStatus): string;

implementation

uses
  System.Generics.Defaults;

{ EJ2GError }

constructor EJ2GError.Create(AExitCode: Integer; const AMsg: string);
begin
  inherited Create(AMsg);
  FExitCode := AExitCode;
end;

constructor EJ2GError.CreateFmt(AExitCode: Integer; const AMsg: string; const Args: array of const);
begin
  inherited CreateFmt(AMsg, Args);
  FExitCode := AExitCode;
end;

function J2GStatusReason(AStatus: TJ2GRevStatus): string;
begin
  case AStatus of
    rsEncrypted:   Result := J2G_REASON_ENCRYPTED;
    rsNoBlob:      Result := J2G_REASON_NOBLOB;
    rsCrcMismatch: Result := J2G_REASON_CRC;
    rsNoMembers:   Result := J2G_REASON_NOMEMBERS;
    rsError:       Result := J2G_REASON_ERROR;
  else
    Result := '';
  end;
end;

{ TJ2GRevision }

constructor TJ2GRevision.Create;
begin
  inherited Create;
  LabelIDs := TList<Integer>.Create;
end;

destructor TJ2GRevision.Destroy;
begin
  LabelIDs.Free;
  inherited Destroy;
end;

function TJ2GRevision.MemberIndex(const AExt: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Members) do
    if SameText(Members[I].Ext, AExt) then
      Exit(I);
  Result := -1;
end;

function TJ2GRevision.VersionText: string;
begin
  Result := Format('%d.%d', [Version, Revision]);
end;

{ TJ2GModule }

constructor TJ2GModule.Create;
begin
  inherited Create;
  Revisions := TList<TJ2GRevision>.Create;
  LastPaths := TStringList.Create;
  LastPaths.Sorted := True;
  LastPaths.Duplicates := dupIgnore;
  LastPaths.CaseSensitive := True;
end;

destructor TJ2GModule.Destroy;
begin
  LastPaths.Free;
  Revisions.Free;
  inherited Destroy;
end;

function TJ2GModule.FullServerName: string;
begin
  if (Pos('\', Name) = 0) and (Path <> '') then
    Result := IncludeTrailingPathDelimiter(Path) + Name
  else
    Result := Name;
end;

{ TJ2GLabel }

constructor TJ2GLabel.Create;
begin
  inherited Create;
  RevisionIDs := TList<Integer>.Create;
end;

destructor TJ2GLabel.Destroy;
begin
  RevisionIDs.Free;
  inherited Destroy;
end;

{ TJ2GCommit }

constructor TJ2GCommit.Create;
begin
  inherited Create;
  Revisions := TList<TJ2GRevision>.Create;
end;

destructor TJ2GCommit.Destroy;
begin
  Revisions.Free;
  inherited Destroy;
end;

function TJ2GCommit.HasModule(AModuleID: Integer): Boolean;
var
  R: TJ2GRevision;
begin
  for R in Revisions do
    if R.ModuleID = AModuleID then
      Exit(True);
  Result := False;
end;

{ TJ2GProject }

constructor TJ2GProject.Create;
begin
  inherited Create;
  Modules := TObjectList<TJ2GModule>.Create(True);
  Revisions := TObjectList<TJ2GRevision>.Create(True);
  Labels := TObjectList<TJ2GLabel>.Create(True);
  Commits := TObjectList<TJ2GCommit>.Create(True);
  Users := TList<TJ2GUser>.Create;
  FModuleIndex := TDictionary<Integer, TJ2GModule>.Create;
  FRevisionIndex := TDictionary<Integer, TJ2GRevision>.Create;
end;

destructor TJ2GProject.Destroy;
begin
  FRevisionIndex.Free;
  FModuleIndex.Free;
  Users.Free;
  Commits.Free;
  Labels.Free;
  Revisions.Free;
  Modules.Free;
  inherited Destroy;
end;

function TJ2GProject.AddModule(AModule: TJ2GModule): TJ2GModule;
begin
  Modules.Add(AModule);
  FModuleIndex.AddOrSetValue(AModule.ModuleID, AModule);
  Result := AModule;
end;

function TJ2GProject.AddRevision(ARevision: TJ2GRevision): TJ2GRevision;
begin
  Revisions.Add(ARevision);
  FRevisionIndex.AddOrSetValue(ARevision.RevisionID, ARevision);
  if (ARevision.Module = nil) then
    ARevision.Module := FindModule(ARevision.ModuleID);
  if Assigned(ARevision.Module) then
    ARevision.Module.Revisions.Add(ARevision);
  Result := ARevision;
end;

function TJ2GProject.FindModule(AModuleID: Integer): TJ2GModule;
begin
  if not FModuleIndex.TryGetValue(AModuleID, Result) then
    Result := nil;
end;

function TJ2GProject.FindRevision(ARevisionID: Integer): TJ2GRevision;
begin
  if not FRevisionIndex.TryGetValue(ARevisionID, Result) then
    Result := nil;
end;

procedure TJ2GProject.SortRevisions;
var
  Cmp: IComparer<TJ2GRevision>;
  M: TJ2GModule;
begin
  Cmp := TComparer<TJ2GRevision>.Construct(
    function(const A, B: TJ2GRevision): Integer
    begin
      if A.RevisionID < B.RevisionID then
        Result := -1
      else if A.RevisionID > B.RevisionID then
        Result := 1
      else
        Result := 0;
    end);
  Revisions.Sort(Cmp);
  for M in Modules do
    M.Revisions.Sort(Cmp);
end;

end.
