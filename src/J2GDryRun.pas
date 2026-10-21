(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GDryRun.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - -dryrun: metadata only, prints the commit plan (no blobs). STUB of PT0: implemented in PT1.

-----------------------------------------------------------------------------*)

unit J2GDryRun;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  J2GModel, J2GOptions, J2GSession, J2GReport;

// returns the exit code (0 ok)
function J2GRunDryRun(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  const AProjects: TArray<TJ2GProjectInfo>; AReport: TJ2GReport): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, System.DateUtils, System.Generics.Collections,
  J2GFetch, J2GPaths, J2GGrouping, J2GAuthors;

type
  TPlanPrinter = class
  private
    FEnabled: Boolean;
  public
    constructor Create(AEnabled: Boolean);
    procedure Line(const S: string); overload;
    procedure Line(const AFmt: string; const Args: array of const); overload;
  end;

constructor TPlanPrinter.Create(AEnabled: Boolean);
begin
  inherited Create;
  FEnabled := AEnabled;
end;

procedure TPlanPrinter.Line(const S: string);
begin
  // with -json the stdout carries only the JSON line
  if FEnabled then
    Writeln(S);
end;

procedure TPlanPrinter.Line(const AFmt: string; const Args: array of const);
begin
  Line(Format(AFmt, Args));
end;

function IsoUtc(ADate: TDateTime): string;
begin
  if ADate = 0 then
    Result := '(no date)'
  else
    Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', ADate);
end;

function FirstLine(const AComment: string): string;
var
  P: Integer;
begin
  Result := AComment;
  P := Pos(#13, Result);
  if (P = 0) or ((Pos(#10, Result) > 0) and (Pos(#10, Result) < P)) then
    P := Pos(#10, Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  Result := Trim(Result);
  if Result = '' then
    Result := '(no comment)';
end;

function ModuleText(AModule: TJ2GModule): string;
begin
  if AModule = nil then
    Result := '?'
  else if AModule.DisplayName <> '' then
    Result := AModule.DisplayName
  else
    Result := AModule.Name;
end;

// target commit of each label: the commit with the most recent labeled
// revision; Approximate when a labeled revision was replaced by a newer
// revision of the same module up to that commit. Returns the number of tags.
function PlanTags(AProject: TJ2GProject; ACommitOf: TDictionary<Integer, Integer>;
  AReport: TJ2GReport): Integer;
var
  L: TJ2GLabel;
  R, R2: TJ2GRevision;
  RevID, Idx, Idx2, Target: Integer;
begin
  Result := 0;
  for L in AProject.Labels do
  begin
    Target := -1;
    L.TargetRevisionID := 0;
    L.Approximate := False;
    for RevID in L.RevisionIDs do
      if ACommitOf.TryGetValue(RevID, Idx) and (Idx > Target) then
      begin
        Target := Idx;
        L.TargetRevisionID := RevID;
      end;
    if Target < 0 then
    begin
      AReport.Warn(Format('%s: label ''%s'' has no revision in any commit: no tag', [AProject.Name, L.Name]));
      Continue;
    end;
    Inc(Result);
    for RevID in L.RevisionIDs do
    begin
      R := AProject.FindRevision(RevID);
      if not Assigned(R) or not Assigned(R.Module) then
        Continue;
      if not ACommitOf.TryGetValue(RevID, Idx) then
      begin
        L.Approximate := True;
        Continue;
      end;
      for R2 in R.Module.Revisions do
        if (R2.RevisionID <> RevID) and ACommitOf.TryGetValue(R2.RevisionID, Idx2) and
          (Idx2 > Idx) and (Idx2 <= Target) then
        begin
          L.Approximate := True;
          Break;
        end;
    end;
  end;
end;

procedure PrintPlan(P: TPlanPrinter; AProject: TJ2GProject; const AOptions: TJ2GOptions;
  ACommitOf: TDictionary<Integer, Integer>; ATags: Integer);
var
  I, J, Idx: Integer;
  C: TJ2GCommit;
  R: TJ2GRevision;
  L: TJ2GLabel;
  Paths, Flags: string;
begin
  P.Line('Project %s (ID %d)%s', [AProject.Name, AProject.ProjectID, IfThen(AProject.Deleted, ' [deleted]', '')]);
  P.Line('  root: %s', [AProject.Root]);
  P.Line('  repository: %s', [AProject.RepoName]);
  P.Line('  modules: %d, revisions: %d, commits: %d, tags: %d',
    [AProject.Modules.Count, AProject.Revisions.Count, AProject.Commits.Count, ATags]);
  P.Line('');
  for I := 0 to Pred(AProject.Commits.Count) do
  begin
    C := AProject.Commits[I];
    Flags := IfThen(C.DateFromLog, 'log', 'file');
    if C.CommitterDate <> C.AuthorDate then
      Flags := Flags + ', committer ' + IsoUtc(C.CommitterDate);
    P.Line('commit %d/%d  %s  %s  [%s]', [I + 1, AProject.Commits.Count, IsoUtc(C.AuthorDate), C.UserName, Flags]);
    P.Line('    %s', [FirstLine(C.Comment)]);
    for R in C.Revisions do
    begin
      Paths := '';
      for J := 0 to High(R.Members) do
      begin
        if Paths <> '' then
          Paths := Paths + ', ';
        if R.Members[J].Path <> '' then
          Paths := Paths + R.Members[J].Path
        else
          Paths := Paths + R.Members[J].Ext;
      end;
      Flags := '';
      if R.DateSubstituted then
        Flags := Format(' [date substituted, original %s]', [R.OriginalDateText]);
      P.Line('    %s %s (rev %d): %s%s', [ModuleText(R.Module), R.VersionText, R.RevisionID, Paths, Flags]);
    end;
  end;
  if (AOptions.Labels = lmTag) and (AProject.Labels.Count > 0) then
  begin
    P.Line('');
    P.Line('tags:');
    for L in AProject.Labels do
      if (L.TargetRevisionID <> 0) and ACommitOf.TryGetValue(L.TargetRevisionID, Idx) then
        P.Line('  label ''%s'' -> tag %s at commit %d%s',
          [L.Name, L.TagName, Idx + 1, IfThen(L.Approximate, ' (approximate)', '')])
      else
        P.Line('  label ''%s'' -> no tag (no commit)', [L.Name]);
  end;
  for R in AProject.Revisions do
    if not ACommitOf.ContainsKey(R.RevisionID) then
      P.Line('  not in any commit: %s %s (rev %d) %s',
        [ModuleText(R.Module), R.VersionText, R.RevisionID, J2GStatusReason(R.Status)]);
  P.Line('');
end;


function J2GRunDryRun(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  const AProjects: TArray<TJ2GProjectInfo>; AReport: TJ2GReport): Integer;
var
  Printer: TPlanPrinter;
  Authors: TJ2GAuthorMap;
  AuthorsFile, S: string;
  AuthorsExisted: Boolean;
  Warns: TStringList;
  Logins: TStringList;
  Info: TJ2GProjectInfo;
  PR: TJ2GProjectReport;
  Project: TJ2GProject;
  M: TJ2GModule;
  R: TJ2GRevision;
  U: TJ2GUser;
  CommitOf: TDictionary<Integer, Integer>;
  NowUtc: TDateTime;
  I, GroupMinutes, NOk, NFail, FailCode, NLog, NFile: Integer;
begin
  J2GFetchClearCache;
  NowUtc := TTimeZone.Local.ToUniversalTime(Now);
  NOk := 0;
  NFail := 0;
  FailCode := J2G_EXIT_OK;
  Printer := TPlanPrinter.Create(not AOptions.Json);
  Logins := TStringList.Create;
  Logins.Sorted := True;
  Logins.Duplicates := dupIgnore;
  Logins.CaseSensitive := False;
  Authors := TJ2GAuthorMap.Create(AOptions.EmailDomain);
  CommitOf := TDictionary<Integer, Integer>.Create;
  try
    AuthorsFile := AOptions.EffectiveAuthorsFile;
    AuthorsExisted := (AuthorsFile <> '') and FileExists(AuthorsFile);
    if AuthorsExisted then
    begin
      Warns := TStringList.Create;
      try
        Authors.LoadFromFile(AuthorsFile, Warns);
        for S in Warns do
          AReport.Warn(S);
      finally
        Warns.Free;
      end;
    end;

    for Info in AProjects do
    begin
      PR := AReport.BeginProject(Info.ProjectID, Info.Name);
      Project := TJ2GProject.Create;
      try
        try
          J2GFetchProject(ASession, AOptions, Info, Project, AReport);
          for U in Project.Users do
            if U.Login <> '' then
              Logins.Add(U.Login);
          for R in Project.Revisions do
            if R.UserName <> '' then
              Logins.Add(R.UserName);

          Project.RepoName := J2GRepoFolderName(Project.Name);
          if AOptions.OutDir <> '' then
            PR.Repo := IncludeTrailingPathDelimiter(ExpandFileName(AOptions.OutDir)) + Project.RepoName
          else
            PR.Repo := Project.RepoName;
          J2GChooseRoot(Project, AOptions.Root);
          for M in Project.Modules do
            J2GChooseDisplayName(M, '');
          if not J2GAssignPaths(Project, AReport, AOptions.StrictCase) then
          begin
            PR.ExitCode := J2G_EXIT_PARTIAL;
            AReport.Error(Format('%s: paths that differ only by case (-strictcase)', [Project.Name]));
          end;
          J2GAssignDates(Project, NowUtc, AReport);
          if AOptions.NoGroup then
            GroupMinutes := 0
          else
            GroupMinutes := AOptions.GroupMinutes;
          J2GGroupCommits(Project, GroupMinutes, AOptions.GroupMaxSpanHours, AOptions.CommitterDate, AReport);
          if AOptions.Labels = lmTag then
            J2GAssignTagNames(Project);

          CommitOf.Clear;
          for I := 0 to Pred(Project.Commits.Count) do
            for R in Project.Commits[I].Revisions do
              CommitOf.AddOrSetValue(R.RevisionID, I);
          PR.Commits := Project.Commits.Count;
          if AOptions.Labels = lmTag then
            PR.Tags := PlanTags(Project, CommitOf, AReport)
          else
            PR.Tags := 0;
          PrintPlan(Printer, Project, AOptions, CommitOf, PR.Tags);

          NLog := 0;
          NFile := 0;
          for R in Project.Revisions do
            if R.Status <> rsNoMembers then
              if R.LogTime > 0 then
                Inc(NLog)
              else
                Inc(NFile);
          AReport.Info(Format('%s: %d revisions dated by the server log, %d by file time; %d commits, %d tags',
            [Project.Name, NLog, NFile, PR.Commits, PR.Tags]));
        except
          on E: EJ2GError do
          begin
            PR.ExitCode := E.ExitCode;
            AReport.Error(Format('%s: %s', [Info.Name, E.Message]));
          end;
          on E: Exception do
          begin
            PR.ExitCode := J2G_EXIT_SERVER;
            AReport.Error(Format('%s: %s: %s', [Info.Name, E.ClassName, E.Message]));
          end;
        end;
        if PR.ExitCode = J2G_EXIT_OK then
          Inc(NOk)
        else
        begin
          Inc(NFail);
          if FailCode = J2G_EXIT_OK then
            FailCode := PR.ExitCode;
        end;
      finally
        Project.Free;
        AReport.EndProject;
      end;
    end;

    // authors map (plan 10.25): written before the real export so the admin can fill it
    Authors.EnsureLogins(Logins.ToStringArray);
    if AuthorsFile <> '' then
    begin
      if not AuthorsExisted then
        try
          ForceDirectories(ExtractFileDir(AuthorsFile));
          Authors.SaveToFile(AuthorsFile);
          AReport.Info('authors file written: ' + AuthorsFile);
        except
          on E: Exception do
            AReport.Warn(Format('cannot write the authors file %s: %s', [AuthorsFile, E.Message]));
        end;
      AReport.AuthorsFile := AuthorsFile;
    end;
    for S in Authors.Unmapped do
      AReport.AddUnmappedAuthor(S);
    if Length(Authors.Unmapped) > 0 then
      AReport.Info(Format('%d login(s) with the default author identity', [Length(Authors.Unmapped)]));
  finally
    CommitOf.Free;
    Authors.Free;
    Logins.Free;
    Printer.Free;
  end;

  if NFail = 0 then
    Result := J2G_EXIT_OK
  else if NOk > 0 then
    Result := J2G_EXIT_PARTIAL
  else
    Result := FailCode;
end;

end.
