(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GExport.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - export engine. Per project:
  metadata (J2GFetch) -> root and ONE spelling per module (ZIP name of the
  latest readable revision) -> paths -> dates and commits (J2GGrouping) ->
  tags -> stream <out>\<repo>.fast-import (J2GFastImport; blobs through the
  cache <out>\.jvcs2git-cache, J2GBlob) -> git init + fast-import + checkout
  (J2GGit) -> report.
A problem with one revision never stops the export (skipped list); a
metadata failure marks the project as failed and -all goes on.

-----------------------------------------------------------------------------*)

unit J2GExport;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes,
  J2GModel, J2GOptions, J2GSession, J2GReport;

type
  // progress of the export (called from the engine thread; the window must Queue)
  TJ2GProgressEvent = procedure(const AProject: string; ADone, ATotal: Integer;
    const AStage: string) of object;

// exports the projects; returns the exit code (0, 11, 9, 12...).
// ACancel: optional flag polled between commits (window).
function J2GRunExport(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  const AProjects: TArray<TJ2GProjectInfo>; AReport: TJ2GReport;
  AOnProgress: TJ2GProgressEvent; ACancel: PBoolean): Integer;

const
  J2G_CACHE_DIR = '.jvcs2git-cache';
  J2G_REPORT_FILE = 'jvcs2git-relatorio.md';

implementation

uses
  System.IOUtils, System.DateUtils, System.Generics.Collections, System.Generics.Defaults,
  J2GFetch, J2GPaths, J2GGrouping, J2GAuthors, J2GBlob, J2GFastImport, J2GGit;

const
  SNoComment = '(sem coment'#$00E1'rio)';
  SToolIdent = 'jvcs2git <jvcs2git@localhost>';

type
  TJ2GProjectExporter = class
  private
    FSession: TJ2GSession;
    FOptions: TJ2GOptions;
    FReport: TJ2GReport;
    FRep: TJ2GProjectReport;
    FAuthors: TJ2GAuthorMap;
    FFetcher: TJ2GBlobFetcher;
    FProject: TJ2GProject;
    FWriter: TJ2GFastImportWriter;
    FOnProgress: TJ2GProgressEvent;
    FCancel: PBoolean;
    FOutDir: string;
    FRepoDir: string;
    FStreamFile: string;
    FRef: string;
    FLastMark: Integer;
    FCommitIdent: TDictionary<Integer, string>; // mark -> author ident
    FCommitDate: TDictionary<Integer, TDateTime>; // mark -> committer date
    function Offset(ADateUtc: TDateTime): Integer;
    procedure Progress(ADone, ATotal: Integer; const AStage: string);
    procedure CheckCancel;
    procedure PrepareRepoFolder;
    procedure ChooseDisplayNames;
    function MemberOfModuleExt(ARev: TJ2GRevision): Integer;
    function FetchMember(ARev: TJ2GRevision; AIndex: Integer): Boolean;
    function BuildMessage(ACommit: TJ2GCommit; const AWritten: TList<TJ2GRevision>): string;
    procedure WriteAttributesCommit;
    procedure WriteCommit(ACommit: TJ2GCommit);
    procedure WriteTags;
  public
    constructor Create(ASession: TJ2GSession; const AOptions: TJ2GOptions; AReport: TJ2GReport;
      AAuthors: TJ2GAuthorMap; AFetcher: TJ2GBlobFetcher; AOnProgress: TJ2GProgressEvent; ACancel: PBoolean);
    destructor Destroy; override;
    procedure Run(const AInfo: TJ2GProjectInfo; ARep: TJ2GProjectReport);
  end;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function IsoUtc(ADate: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', ADate) + ' UTC';
end;

{ TJ2GProjectExporter }

constructor TJ2GProjectExporter.Create(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  AReport: TJ2GReport; AAuthors: TJ2GAuthorMap; AFetcher: TJ2GBlobFetcher;
  AOnProgress: TJ2GProgressEvent; ACancel: PBoolean);
begin
  inherited Create;
  FSession := ASession;
  FOptions := AOptions;
  FReport := AReport;
  FAuthors := AAuthors;
  FFetcher := AFetcher;
  FOnProgress := AOnProgress;
  FCancel := ACancel;
  FOutDir := IncludeTrailingPathDelimiter(ExpandFileName(AOptions.OutDir));
  FRef := 'refs/heads/' + AOptions.BranchName;
  FCommitIdent := TDictionary<Integer, string>.Create;
  FCommitDate := TDictionary<Integer, TDateTime>.Create;
end;

destructor TJ2GProjectExporter.Destroy;
begin
  FWriter.Free;
  FProject.Free;
  FCommitDate.Free;
  FCommitIdent.Free;
  inherited Destroy;
end;

function TJ2GProjectExporter.Offset(ADateUtc: TDateTime): Integer;
begin
  if FOptions.LocalTime then
    Result := J2GLocalOffsetMinutes(ADateUtc)
  else
    Result := 0;
end;

procedure TJ2GProjectExporter.Progress(ADone, ATotal: Integer; const AStage: string);
begin
  if Assigned(FOnProgress) then
    FOnProgress(FProject.Name, ADone, ATotal, AStage);
end;

procedure TJ2GProjectExporter.CheckCancel;
begin
  if Assigned(FCancel) and FCancel^ then
    raise EJ2GError.Create(J2G_EXIT_PARTIAL, 'cancelled by the user (the cache is kept; run again to resume)');
end;

procedure TJ2GProjectExporter.PrepareRepoFolder;
var
  Entries: TArray<string>;
begin
  if FOptions.NoGit or not DirectoryExists(FRepoDir) then
    Exit;
  Entries := TDirectory.GetFileSystemEntries(FRepoDir);
  if Length(Entries) = 0 then
    Exit;
  if not FOptions.Force then
    raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT,
      'folder already exists: %s (delete it, use another -out, or -force if it was made by jvcs2git)', [FRepoDir]);
  if not J2GIsJvcs2GitRepo(FRepoDir) then
    raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT,
      'folder already exists and was not made by jvcs2git (no .git\%s): %s', [J2G_MARKS_FILE, FRepoDir]);
  FReport.Info('-force: deleting ' + FRepoDir);
  try
    TDirectory.Delete(FRepoDir, True);
  except
    on E: Exception do
      raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'cannot delete %s: %s', [FRepoDir, E.Message]);
  end;
end;

function TJ2GProjectExporter.MemberOfModuleExt(ARev: TJ2GRevision): Integer;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(ARev.Module.Name));
  Result := ARev.MemberIndex(Ext);
  if (Result < 0) and (Length(ARev.Members) > 0) then
    Result := 0;
end;

function TJ2GProjectExporter.FetchMember(ARev: TJ2GRevision; AIndex: Integer): Boolean;
var
  Detail: string;
  St: TJ2GRevStatus;
begin
  if ARev.Members[AIndex].Status = rsOk then
    Exit(True);
  if ARev.Members[AIndex].Status <> rsPending then
    Exit(False);
  St := FFetcher.Fetch(ARev, AIndex, Detail);
  Result := St = rsOk;
  if not Result then
    FReport.Skip(ARev.RevisionID, ARev.Module.DisplayName + '', ARev.Members[AIndex].Ext,
      J2GStatusReason(St), Detail);
end;

procedure TJ2GProjectExporter.ChooseDisplayNames;
var
  M: TJ2GModule;
  I, Idx, N: Integer;
  ZipName: string;
  R: TJ2GRevision;
begin
  N := 0;
  for M in FProject.Modules do
  begin
    Inc(N);
    Progress(N, FProject.Modules.Count, 'names');
    CheckCancel;
    ZipName := '';
    // DisplayName is still empty: the skip list must show the server name
    M.DisplayName := M.Name;
    for I := M.Revisions.Count - 1 downto 0 do
    begin
      R := M.Revisions[I];
      Idx := MemberOfModuleExt(R);
      if Idx < 0 then
        Continue;
      if FetchMember(R, Idx) and (R.Members[Idx].ZipName <> '') then
      begin
        ZipName := R.Members[Idx].ZipName;
        Break;
      end;
      // a readable revision without ZIP name (old blob) also ends the search
      if R.Members[Idx].Status = rsOk then
        Break;
    end;
    M.DisplayName := '';
    J2GChooseDisplayName(M, ZipName);
  end;
end;

function TJ2GProjectExporter.BuildMessage(ACommit: TJ2GCommit; const AWritten: TList<TJ2GRevision>): string;
var
  Comment, Trailer: string;
  R: TJ2GRevision;
  First: Boolean;
begin
  Comment := Trim(ACommit.Comment);
  if Comment = '' then
    Comment := SNoComment;
  Trailer := 'JEDI VCS: ' + FProject.Name + ';';
  First := True;
  for R in ACommit.Revisions do
  begin
    if not First then
      Trailer := Trailer + ',';
    First := False;
    Trailer := Trailer + Format(' %s %s (rev %d)', [R.Module.DisplayName, R.VersionText, R.RevisionID]);
    if not AWritten.Contains(R) then
      Trailer := Trailer + ' [skipped]';
    if R.DateSubstituted then
      Trailer := Trailer + Format(' [date substituted, original: %s]', [R.OriginalDateText]);
  end;
  Result := Comment + #10#10 + Trailer + #10;
end;

procedure TJ2GProjectExporter.WriteAttributesCommit;
var
  FirstDate: TDateTime;
  Mark: Integer;
  Data: TBytes;
begin
  if FOptions.NoAttributes or (FProject.Commits.Count = 0) then
    Exit;
  FirstDate := IncSecond(FProject.Commits[0].AuthorDate, -1);
  if FirstDate < EncodeDate(1980, 1, 1) then
    FirstDate := EncodeDate(1980, 1, 1);
  Mark := FWriter.NewMark;
  FWriter.BeginCommit(FRef, Mark, SToolIdent, FirstDate, Offset(FirstDate),
    SToolIdent, FirstDate, Offset(FirstDate),
    'jvcs2git: .gitattributes (* -text: keep the exact bytes of the JEDI VCS archive)', 0);
  Data := TEncoding.ASCII.GetBytes('* -text'#10);
  FWriter.FileModify('.gitattributes', Data);
  FWriter.EndCommit;
  FLastMark := Mark;
  FCommitIdent.AddOrSetValue(Mark, SToolIdent);
  FCommitDate.AddOrSetValue(Mark, FirstDate);
end;

procedure TJ2GProjectExporter.WriteCommit(ACommit: TJ2GCommit);
type
  TOp = record
    Rev: TJ2GRevision;
    Index: Integer;
  end;
var
  R: TJ2GRevision;
  I, Mark: Integer;
  Ops: TList<TOp>;
  Op: TOp;
  Deletes: TStringList;
  NewPaths: TStringList;
  Written: TList<TJ2GRevision>;
  Path, Ident: string;
  Data: TBytes;
  WasBinary, Failed: Boolean;
  P, J: Integer;
begin
  Ops := TList<TOp>.Create;
  Deletes := TStringList.Create;
  Written := TList<TJ2GRevision>.Create;
  try
    // 1) blobs of every member into the cache (status decides what is written)
    for R in ACommit.Revisions do
      for I := 0 to High(R.Members) do
        if FetchMember(R, I) then
        begin
          Op.Rev := R;
          Op.Index := I;
          Ops.Add(Op);
          if not Written.Contains(R) then
            Written.Add(R);
        end;
    if Ops.Count = 0 then
    begin
      FReport.Warn(Format('no file could be written for the check-in of %s at %s (%d revision(s)): commit not emitted',
        [ACommit.UserName, IsoUtc(ACommit.AuthorDate), ACommit.Revisions.Count]));
      Exit;
    end;
    // 2) 'D' for members that disappeared (not for skipped members)
    for R in Written do
    begin
      for I := 0 to R.Module.LastPaths.Count - 1 do
      begin
        Path := R.Module.LastPaths[I];
        P := -1;
        for Op in Ops do
          if (Op.Rev = R) and (R.Members[Op.Index].Path = Path) then
            P := Op.Index;
        if P >= 0 then
          Continue;
        // still a member of this revision (skipped): keep the previous content
        for J := 0 to High(R.Members) do
          if R.Members[J].Path = Path then
            P := J;
        if P < 0 then
          Deletes.Add(Path);
      end;
    end;
    Mark := FWriter.NewMark;
    Ident := FAuthors.Ident(ACommit.UserName);
    FWriter.BeginCommit(FRef, Mark, Ident, ACommit.AuthorDate, Offset(ACommit.AuthorDate),
      Ident, ACommit.CommitterDate, Offset(ACommit.CommitterDate),
      BuildMessage(ACommit, Written), FLastMark);
    for Path in Deletes do
      FWriter.FileDelete(Path);
    for Op in Ops do
    begin
      Data := J2GLoadMemberContent(Op.Rev.Members[Op.Index].CacheFile, Op.Rev.Members[Op.Index].Ext,
        not FOptions.NoDfmText, WasBinary, Failed);
      if WasBinary then
      begin
        Inc(FRep.DfmBinaryFound);
        if Failed then
        begin
          Inc(FRep.DfmConvertFailed);
          FReport.Warn(Format('binary form not converted to text (written as is): %s rev %d',
            [Op.Rev.Members[Op.Index].Path, Op.Rev.RevisionID]));
        end
        else if not FOptions.NoDfmText then
          Inc(FRep.DfmConverted);
      end;
      FWriter.FileModify(Op.Rev.Members[Op.Index].Path, Data);
    end;
    FWriter.EndCommit;
    // 3) state of each module after this commit
    for R in Written do
    begin
      NewPaths := TStringList.Create;
      try
        NewPaths.Sorted := True;
        NewPaths.Duplicates := dupIgnore;
        NewPaths.CaseSensitive := True;
        for I := 0 to High(R.Members) do
          if R.Members[I].Status = rsOk then
            NewPaths.Add(R.Members[I].Path)
          else if R.Module.LastPaths.IndexOf(R.Members[I].Path) >= 0 then
            NewPaths.Add(R.Members[I].Path);
        R.Module.LastPaths.Assign(NewPaths);
      finally
        NewPaths.Free;
      end;
      R.Mark := Mark;
    end;
    FLastMark := Mark;
    FCommitIdent.AddOrSetValue(Mark, Ident);
    FCommitDate.AddOrSetValue(Mark, ACommit.CommitterDate);
    Inc(FRep.Commits);
    if ACommit.DateFromLog then
      Inc(FRep.CommitsDateFromLog)
    else
      Inc(FRep.CommitsDateFromFile);
  finally
    Written.Free;
    Deletes.Free;
    Ops.Free;
  end;
end;

procedure TJ2GProjectExporter.WriteTags;
var
  L: TJ2GLabel;
  RevID, TargetMark, I: Integer;
  Target, R, Later: TJ2GRevision;
  Msg: string;
  Approx: Boolean;
begin
  if FOptions.Labels <> lmTag then
    Exit;
  for L in FProject.Labels do
  begin
    if L.RevisionIDs.Count = 0 then
      Continue;
    // the most recent labeled revision of the project
    Target := nil;
    for RevID in L.RevisionIDs do
    begin
      R := FProject.FindRevision(RevID);
      if Assigned(R) and ((Target = nil) or (R.RevisionID > Target.RevisionID)) then
        Target := R;
    end;
    if Target = nil then
      Continue;
    TargetMark := Target.Mark;
    Approx := False;
    if TargetMark = 0 then
    begin
      // nearest emitted commit before it, in RevisionID order
      Approx := True;
      for I := FProject.Revisions.IndexOf(Target) downto 0 do
        if FProject.Revisions[I].Mark > 0 then
        begin
          TargetMark := FProject.Revisions[I].Mark;
          Break;
        end;
    end;
    if TargetMark = 0 then
    begin
      FReport.Skip(Target.RevisionID, Target.Module.DisplayName, '', J2G_REASON_NOCOMMIT,
        Format('label "%s": no commit to tag', [L.Name]));
      Continue;
    end;
    // every labeled revision must be the state of its module at the target commit
    for RevID in L.RevisionIDs do
    begin
      R := FProject.FindRevision(RevID);
      if not Assigned(R) then
        Continue;
      if (R.Mark = 0) or (R.Mark > TargetMark) then
        Approx := True
      else
        for Later in R.Module.Revisions do
          if (Later.RevisionID > R.RevisionID) and (Later.Mark > 0) and (Later.Mark <= TargetMark) then
          begin
            Approx := True;
            Break;
          end;
    end;
    Msg := Trim(L.Description);
    if Msg <> '' then
      Msg := Msg + #10#10;
    Msg := Msg + 'JEDI VCS label: ' + L.Name + #10;
    for RevID in L.RevisionIDs do
    begin
      R := FProject.FindRevision(RevID);
      if Assigned(R) then
        Msg := Msg + Format('%s %s (rev %d)', [R.Module.DisplayName, R.VersionText, R.RevisionID]) + #10;
    end;
    if Approx then
    begin
      Msg := Msg + #10 + 'jvcs2git: approximate tag (not every labeled revision is in this commit state)' + #10;
      FReport.Warn(Format('approximate tag %s (label "%s")', [L.TagName, L.Name]));
    end;
    FWriter.Tag(L.TagName, TargetMark, FCommitIdent[TargetMark], FCommitDate[TargetMark],
      Offset(FCommitDate[TargetMark]), Msg);
    L.TargetMark := TargetMark;
    L.TargetRevisionID := Target.RevisionID;
    L.Approximate := Approx;
    Inc(FRep.Tags);
  end;
end;

procedure TJ2GProjectExporter.Run(const AInfo: TJ2GProjectInfo; ARep: TJ2GProjectReport);
var
  Logins: TStringList;
  R: TJ2GRevision;
  U: TJ2GUser;
  C: TJ2GCommit;
  N: Integer;
  Ok: Boolean;
begin
  FRep := ARep;
  FProject := TJ2GProject.Create;
  FProject.Name := AInfo.Name;
  Progress(0, 0, 'metadata');
  J2GFetchProject(FSession, FOptions, AInfo, FProject, FReport);
  FRep.Modules := FProject.Modules.Count;
  FRep.Revisions := FProject.Revisions.Count;

  // authors of this project
  Logins := TStringList.Create;
  try
    Logins.Sorted := True;
    Logins.Duplicates := dupIgnore;
    Logins.CaseSensitive := False;
    for U in FProject.Users do
      Logins.Add(U.Login);
    for R in FProject.Revisions do
      if R.UserName <> '' then
        Logins.Add(R.UserName);
    FAuthors.EnsureLogins(Logins.ToStringArray);
  finally
    Logins.Free;
  end;

  FProject.RepoName := J2GRepoFolderName(FProject.Name);
  FRepoDir := FOutDir + FProject.RepoName;
  FStreamFile := FOutDir + FProject.RepoName + '.fast-import';
  FRep.Repo := FRepoDir;
  FRep.StreamFile := FStreamFile;
  PrepareRepoFolder;

  J2GChooseRoot(FProject, FOptions.Root);
  FReport.Info(Format('%s: repository root %s', [FProject.Name, FProject.Root]));
  ChooseDisplayNames;
  Ok := J2GAssignPaths(FProject, FReport, FOptions.StrictCase);
  if not Ok then
    raise EJ2GError.CreateFmt(J2G_EXIT_PARTIAL, '%s: case collisions between modules (-strictcase)', [FProject.Name]);
  J2GAssignDates(FProject, NowUtc, FReport);
  if FOptions.NoGroup then
    J2GGroupCommits(FProject, 0, FOptions.GroupMaxSpanHours, FOptions.CommitterDate, FReport)
  else
    J2GGroupCommits(FProject, FOptions.GroupMinutes, FOptions.GroupMaxSpanHours, FOptions.CommitterDate, FReport);
  // the grouping counts the dates; the writer counts again the emitted commits
  FRep.CommitsDateFromLog := 0;
  FRep.CommitsDateFromFile := 0;
  if FOptions.Labels = lmTag then
    J2GAssignTagNames(FProject);

  // stream
  FWriter := TJ2GFastImportWriter.Create(FStreamFile);
  FLastMark := 0;
  WriteAttributesCommit;
  N := 0;
  for C in FProject.Commits do
  begin
    Inc(N);
    Progress(N, FProject.Commits.Count, 'commits');
    CheckCancel;
    WriteCommit(C);
  end;
  WriteTags;
  FWriter.Close(True);
  FReport.Info(Format('%s: %d commit(s), %d tag(s), stream %s (%d bytes)',
    [FProject.Name, FRep.Commits, FRep.Tags, FStreamFile, FWriter.BytesWritten]));
  if FRep.DfmBinaryFound > 0 then
    if (FRep.DfmConverted = 0) and not FOptions.NoDfmText then
      FReport.Warn(Format('%s: %d binary form(s) found and NONE was converted to text',
        [FProject.Name, FRep.DfmBinaryFound]));

  // git
  if not FOptions.NoGit then
  begin
    Progress(0, 0, 'git');
    J2GGitInitRepo(FRepoDir, FOptions.BranchName);
    J2GGitFastImport(FRepoDir, FStreamFile);
    if FRep.Commits + Ord(not FOptions.NoAttributes) > 0 then
      J2GGitCheckout(FRepoDir, FOptions.BranchName);
    FReport.Info(Format('%s: repository %s', [FProject.Name, FRepoDir]));
  end;
end;

function J2GRunExport(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  const AProjects: TArray<TJ2GProjectInfo>; AReport: TJ2GReport;
  AOnProgress: TJ2GProgressEvent; ACancel: PBoolean): Integer;
var
  OutDir, AuthorsFile, GitVersion, Login: string;
  AuthorsExisted, AllOk, Cancelled: Boolean;
  Authors: TJ2GAuthorMap;
  Fetcher: TJ2GBlobFetcher;
  Info: TJ2GProjectInfo;
  Rep: TJ2GProjectReport;
  Exporter: TJ2GProjectExporter;
  T0: TDateTime;
  Code: Integer;
  Codes: TList<Integer>;
  AuthWarn: TStringList;
begin
  J2GFetchClearCache;
  OutDir := IncludeTrailingPathDelimiter(ExpandFileName(AOptions.OutDir));
  ForceDirectories(OutDir);
  // environment before any download
  if not AOptions.NoGit then
  begin
    if not J2GGitVersion(GitVersion) then
      raise EJ2GError.Create(J2G_EXIT_ENVIRONMENT, 'git not found on the PATH (install Git for Windows, or use -nogit)');
    AReport.Info('git: ' + GitVersion);
  end;

  AuthorsFile := AOptions.EffectiveAuthorsFile;
  AuthorsExisted := FileExists(AuthorsFile);
  Codes := TList<Integer>.Create;
  AuthWarn := TStringList.Create;
  Authors := TJ2GAuthorMap.Create(AOptions.EmailDomain);
  Fetcher := TJ2GBlobFetcher.Create(ASession, OutDir + J2G_CACHE_DIR, AOptions.EncodeKey,
    AOptions.BlobTimeout, AOptions.IgnoreCrc, AReport);
  Cancelled := False;
  try
    if AuthorsExisted then
    begin
      Authors.LoadFromFile(AuthorsFile, AuthWarn);
      for Login in AuthWarn do
        AReport.Warn(Login);
    end;
    for Info in AProjects do
    begin
      Rep := AReport.BeginProject(Info.ProjectID, Info.Name);
      T0 := Now;
      Exporter := TJ2GProjectExporter.Create(ASession, AOptions, AReport, Authors, Fetcher, AOnProgress, ACancel);
      try
        try
          AReport.Info('==== ' + Info.Name + ' ====');
          Exporter.Run(Info, Rep);
          if Rep.Skipped.Count > 0 then
            Rep.ExitCode := J2G_EXIT_PARTIAL
          else
            Rep.ExitCode := J2G_EXIT_OK;
        except
          on E: EJ2GError do
          begin
            Rep.ExitCode := E.ExitCode;
            AReport.Error(Info.Name + ': ' + E.Message);
            if Assigned(ACancel) and ACancel^ then
              Cancelled := True;
          end;
          on E: Exception do
          begin
            Rep.ExitCode := J2G_EXIT_SERVER;
            AReport.Error(Format('%s: %s: %s', [Info.Name, E.ClassName, E.Message]));
          end;
        end;
      finally
        Rep.Seconds := SecondSpan(Now, T0);
        Exporter.Free;
        AReport.EndProject;
      end;
      Codes.Add(Rep.ExitCode);
      if Cancelled then
        Break;
    end;

    // author map: created on the first run; unmapped logins listed
    if (AuthorsFile <> '') then
    begin
      if not AuthorsExisted then
        try
          Authors.SaveToFile(AuthorsFile);
        except
          on E: Exception do
            AReport.Warn('cannot write ' + AuthorsFile + ': ' + E.Message);
        end;
      AReport.AuthorsFile := AuthorsFile;
    end;
    for Login in Authors.Unmapped do
      AReport.AddUnmappedAuthor(Login);
    if Length(Authors.Unmapped) > 0 then
      AReport.Warn(Format('%d login(s) without name/e-mail in %s (default identity used)',
        [Length(Authors.Unmapped), ExtractFileName(AuthorsFile)]));

    AllOk := True;
    for Code in Codes do
      if Code <> J2G_EXIT_OK then
        AllOk := False;
    if AllOk then
      Result := J2G_EXIT_OK
    else if (Codes.Count = 1) then
      Result := Codes[0]
    else
      Result := J2G_EXIT_PARTIAL;

    // the cache stays with -keepcache, -nogit or when something failed
    if AllOk and not AOptions.KeepCache and not AOptions.NoGit then
      try
        Fetcher.ClearCache;
      except
        on E: Exception do
          AReport.Warn('cannot delete the cache: ' + E.Message);
      end;
  finally
    Fetcher.Free;
    Authors.Free;
    AuthWarn.Free;
    Codes.Free;
  end;
  AReport.ExitCode := Result;
  AReport.Message := AReport.Summary;
  try
    AReport.WriteMarkdown(OutDir + J2G_REPORT_FILE);
  except
    on E: Exception do
      AReport.Warn('cannot write the report: ' + E.Message);
  end;
end;

end.
