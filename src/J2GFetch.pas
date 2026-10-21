(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GFetch.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - metadata of a project read from the server: modules, revisions,
members (module history), labels, users and check-in times from the server
log. No blob is read here. Interface frozen in PT0; implemented in PT1.

-----------------------------------------------------------------------------*)

unit J2GFetch;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes,
  J2GModel, J2GOptions, J2GSession, J2GReport;

// Fills AProject (ProjectID/Name/Deleted/Description from AInfo):
//  Modules   GET_PROJECT_MODULE_LIST(ExcludeHiddenModules = AOptions.SkipHidden)
//  Revisions GET_REVISION_LIST: ONLY ModuleID, RevisionID, Version, Revision,
//            Hidden (+ ModuleTimestamp from the 1st row of each module; name,
//            path, user and timestamp of the other rows are ignored, plan 10.1)
//  Members   GET_MODULE_HISTORY per module, grouped by RevisionID: UserName and
//            Comment from the 1st row; one member {Ext, Size, OrigTime} per
//            row; Rev.OrigTime = max(member OrigTime) (plan 10.5); revision
//            without rows -> Status rsNoMembers (reported with Skip)
//  Labels    GET_LABELS + GET_LABELS_BY_PROJECT (labels with revisions of the
//            project; Rev.LabelIDs too)
//  Users     GET_USERS
//  LogTime   unless AOptions.NoLog or the server log is off: GET_LOG_ENTRIES
//            (all 0, 'i;', timeout AOptions.BlobTimeout) filtered by the
//            project's ModuleIDs, GET_LOG_COMMENT per entry (cache by LogID),
//            heuristic match user+comment from the newest to the oldest
//            (jvcs.dpr:4433-4450). Unmatched revisions keep LogTime = 0.
// Revisions are sorted by RevisionID (AProject.SortRevisions).
// A metadata failure raises (EJ2GError 9 for the connection; the caller marks
// the project as failed).
procedure J2GFetchProject(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  const AInfo: TJ2GProjectInfo; AProject: TJ2GProject; AReport: TJ2GReport);

// GET_USERS
function J2GFetchUsers(ASession: TJ2GSession): TArray<TJ2GUser>;

// forgets the server log read by the previous projects (call at the start of
// each run: the log is read once per run and shared by the projects)
procedure J2GFetchClearCache;

implementation

uses
  System.StrUtils, System.Generics.Collections, System.Generics.Defaults,
  JVCSTypes, JVCSClientObjBase, JVCSClientObj;

type
  // one revision of GET_MODULE_HISTORY (used by the log heuristic)
  THistRev = record
    RevisionID: Integer;
    UserName: string;
    Comment: string;
  end;

  // one check-in entry of the server log for a module of the project
  TLogRow = record
    LogID: Integer;
    ModuleID: Integer;
    Stamp: TDateTime;   // GMT
    UserName: string;
    Comment: string;
    Linked: Boolean;    // GET_LOG_COMMENT <> 'blank'
  end;

  THistMap = TDictionary<Integer, TArray<THistRev>>;

  // server log entry kept for the whole run (-all reads the log only once)
  TLogEntry = record
    LogID: Integer;
    ModuleID: Integer;
    Stamp: TDateTime;
    UserName: string;
  end;

var
  GLogLoaded: Boolean;
  GLogEntries: TArray<TLogEntry>;
  GLogComments: TDictionary<Integer, string>; // LogID -> comment ('blank' = not linked)

procedure J2GFetchClearCache;
begin
  GLogLoaded := False;
  GLogEntries := nil;
  FreeAndNil(GLogComments);
end;

function NormalizeExt(const AExt: string): string;
begin
  Result := LowerCase(Trim(AExt));
  if (Result <> '') and (Result[1] <> '.') then
    Result := '.' + Result;
end;

function J2GFetchUsers(ASession: TJ2GSession): TArray<TJ2GUser>;
var
  GetUsers: TJVCSGetUsers;
  I: Integer;
begin
  Result := nil;
  GetUsers := TJVCSGetUsers.Create(nil);
  try
    ASession.Send(GetUsers);
    SetLength(Result, GetUsers.OutputItemCount);
    for I := 0 to Pred(GetUsers.OutputItemCount) do
    begin
      Result[I].UserID := GetUsers.OutputItems[I].UserID;
      Result[I].Login := string(GetUsers.OutputItems[I].UserName);
      Result[I].Deleted := GetUsers.OutputItems[I].UserDeleted;
    end;
  finally
    GetUsers.Free;
  end;
end;

// GET_PROJECT_MODULE_LIST: name and path of every module (plan 10.1)
procedure FetchModules(ASession: TJ2GSession; const AOptions: TJ2GOptions; AProject: TJ2GProject);
var
  GetModuleList: TJVCSGetProjectModuleList;
  I: Integer;
  M: TJ2GModule;
begin
  GetModuleList := TJVCSGetProjectModuleList.Create(nil);
  try
    GetModuleList.ProjectID := AProject.ProjectID;
    GetModuleList.ExcludeHiddenModules := AOptions.SkipHidden;
    ASession.Send(GetModuleList);
    for I := 0 to Pred(GetModuleList.OutputItemCount) do
    begin
      if Assigned(AProject.FindModule(GetModuleList.OutputItems[I].ModuleID)) then
        Continue;
      M := TJ2GModule.Create;
      M.ModuleID := GetModuleList.OutputItems[I].ModuleID;
      M.Name := string(GetModuleList.OutputItems[I].ModuleName);
      M.Path := string(GetModuleList.OutputItems[I].ModulePath);
      AProject.AddModule(M);
    end;
  finally
    GetModuleList.Free;
  end;
end;

// GET_REVISION_LIST: only ModuleID, RevisionID, Version, Revision, Hidden;
// the timestamp of the 1st row of a module is modules.tstamp (0 in the others)
procedure FetchRevisions(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  AProject: TJ2GProject; AReport: TJ2GReport);
var
  GetRevisionList: TJVCSGetRevisionList;
  I, Unknown: Integer;
  Item: TGetRevisionListOutputItem;
  M: TJ2GModule;
  R: TJ2GRevision;
begin
  Unknown := 0;
  GetRevisionList := TJVCSGetRevisionList.Create(nil);
  try
    GetRevisionList.ProjectID := AProject.ProjectID;
    GetRevisionList.ExcludeHiddenModules := AOptions.SkipHidden;
    ASession.Send(GetRevisionList);
    for I := 0 to Pred(GetRevisionList.OutputItemCount) do
    begin
      Item := GetRevisionList.OutputItems[I];
      M := AProject.FindModule(Item.ModuleID);
      if not Assigned(M) then
      begin
        Inc(Unknown);
        Continue;
      end;
      if Item.Timestamp > M.ModuleTimestamp then
        M.ModuleTimestamp := Item.Timestamp;
      M.Hidden := Item.Hidden;
      if Assigned(AProject.FindRevision(Item.RevisionID)) then
        Continue;
      R := TJ2GRevision.Create;
      R.RevisionID := Item.RevisionID;
      R.ModuleID := Item.ModuleID;
      R.Module := M;
      R.Version := Item.Version;
      R.Revision := Item.Revision;
      R.Hidden := Item.Hidden;
      R.Status := rsPending;
      AProject.AddRevision(R);
    end;
  finally
    GetRevisionList.Free;
  end;
  if Unknown > 0 then
    AReport.Warn(Format('%s: %d revision row(s) of modules missing from the module list were ignored',
      [AProject.Name, Unknown]));
end;

// GET_MODULE_HISTORY per module: one row per member; user and comment only in
// the 1st row of each RevisionID; OrigTime(rev) = max of the members (plan 10.5)
procedure FetchHistory(ASession: TJ2GSession; AProject: TJ2GProject; AReport: TJ2GReport;
  AHist: THistMap);
var
  GetModuleHistory: TJVCSGetModuleHistory;
  Item: TGetModuleHistoryOutputItem;
  M: TJ2GModule;
  R: TJ2GRevision;
  HistRevs: TList<THistRev>;
  Index: TDictionary<Integer, Integer>;
  H: THistRev;
  Mb: TJ2GMember;
  I, K: Integer;
  IsFirst: Boolean;
begin
  HistRevs := TList<THistRev>.Create;
  Index := TDictionary<Integer, Integer>.Create;
  try
    for M in AProject.Modules do
    begin
      if M.Revisions.Count = 0 then
        Continue;
      HistRevs.Clear;
      Index.Clear;
      GetModuleHistory := TJVCSGetModuleHistory.Create(nil);
      try
        GetModuleHistory.ModuleID := M.ModuleID;
        ASession.Send(GetModuleHistory);
        for I := 0 to Pred(GetModuleHistory.OutputItemCount) do
        begin
          Item := GetModuleHistory.OutputItems[I];
          IsFirst := not Index.TryGetValue(Item.RevisionID, K);
          if IsFirst then
          begin
            H.RevisionID := Item.RevisionID;
            H.UserName := string(Item.UserName);
            H.Comment := Item.CheckinComment;
            K := HistRevs.Add(H);
            Index.Add(Item.RevisionID, K);
          end;
          R := AProject.FindRevision(Item.RevisionID);
          if not Assigned(R) or (R.ModuleID <> M.ModuleID) then
            Continue;
          if IsFirst then
          begin
            R.UserName := string(Item.UserName);
            R.Comment := Item.CheckinComment;
          end;
          Mb := Default(TJ2GMember);
          Mb.Ext := NormalizeExt(string(Item.Extension));
          Mb.Size := Item.Size;
          Mb.OrigTime := Item.Timestamp;
          Mb.Status := rsPending;
          if R.MemberIndex(Mb.Ext) >= 0 then
          begin
            AReport.Debug(Format('rev %d %s: duplicated member %s ignored', [R.RevisionID, M.Name, Mb.Ext]));
            Continue;
          end;
          if (Length(R.Members) = 0) or (Mb.OrigTime > R.OrigTime) then
            R.OrigTime := Mb.OrigTime;
          R.Members := R.Members + [Mb];
        end;
      finally
        GetModuleHistory.Free;
      end;
      AHist.AddOrSetValue(M.ModuleID, HistRevs.ToArray);
    end;
  finally
    Index.Free;
    HistRevs.Free;
  end;
  for R in AProject.Revisions do
    if Length(R.Members) = 0 then
    begin
      R.Status := rsNoMembers;
      AReport.Skip(R.RevisionID, R.Module.Name, '', J2G_REASON_NOMEMBERS,
        'revision without rows in the module history');
    end;
end;

// GET_LABELS_BY_PROJECT + GET_LABELS: labels with revisions of the project
procedure FetchLabels(ASession: TJ2GSession; AProject: TJ2GProject);
var
  GetLabelsByProject: TJVCSGetLabelsByProject;
  GetLabels: TJVCSGetLabels;
  Map: TDictionary<Integer, TJ2GLabel>;
  Item: TGetLabelsByProjectOutputItem;
  L: TJ2GLabel;
  R: TJ2GRevision;
  I: Integer;
  Pending: TList<TJ2GLabel>;
begin
  Map := TDictionary<Integer, TJ2GLabel>.Create;
  Pending := TList<TJ2GLabel>.Create;
  try
    try
      GetLabelsByProject := TJVCSGetLabelsByProject.Create(nil);
      try
        GetLabelsByProject.ProjectID := AProject.ProjectID;
        ASession.Send(GetLabelsByProject);
        for I := 0 to Pred(GetLabelsByProject.OutputItemCount) do
        begin
          Item := GetLabelsByProject.OutputItems[I];
          R := AProject.FindRevision(Item.RevisionID);
          if not Assigned(R) then
            Continue;
          if not Map.TryGetValue(Item.LabelID, L) then
          begin
            L := TJ2GLabel.Create;
            L.LabelID := Item.LabelID;
            Map.Add(L.LabelID, L);
            Pending.Add(L);
          end;
          if not L.RevisionIDs.Contains(R.RevisionID) then
            L.RevisionIDs.Add(R.RevisionID);
          if not R.LabelIDs.Contains(L.LabelID) then
            R.LabelIDs.Add(L.LabelID);
        end;
      finally
        GetLabelsByProject.Free;
      end;
      if Map.Count > 0 then
      begin
        GetLabels := TJVCSGetLabels.Create(nil);
        try
          GetLabels.IncludeDescription := True;
          ASession.Send(GetLabels);
          for I := 0 to Pred(GetLabels.OutputItemCount) do
            if Map.TryGetValue(GetLabels.OutputItems[I].LabelID, L) then
            begin
              L.Name := string(GetLabels.OutputItems[I].LabelName);
              L.Description := GetLabels.OutputItems[I].Description;
            end;
        finally
          GetLabels.Free;
        end;
      end;
      Pending.Sort(TComparer<TJ2GLabel>.Construct(
        function(const A, B: TJ2GLabel): Integer
        begin
          Result := A.LabelID - B.LabelID;
        end));
      for L in Pending do
      begin
        L.RevisionIDs.Sort;
        AProject.Labels.Add(L);
      end;
      Pending.Clear;
    except
      for L in Pending do
        L.Free;
      raise;
    end;
  finally
    Pending.Free;
    Map.Free;
  end;
end;

function CompareLogRows(const A, B: TLogRow): Integer;
begin
  if A.Stamp < B.Stamp then
    Result := -1
  else if A.Stamp > B.Stamp then
    Result := 1
  else
    Result := A.LogID - B.LogID;
end;

function CompareHistRevsDesc(const A, B: THistRev): Integer;
begin
  Result := B.RevisionID - A.RevisionID;
end;

// server log: check-in time by the user+comment heuristic of jvcs.dpr
// (command log): per module, from the newest log entry to the oldest, each
// entry takes the next older revision of the same user with the same comment
procedure FetchLog(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  AProject: TJ2GProject; AReport: TJ2GReport; AHist: THistMap);
var
  State: TJ2GServerLogState;
  GetLogEntries: TJVCSGetLogEntries;
  GetLogComment: TJVCSGetLogComment;
  Rows: TObjectDictionary<Integer, TList<TLogRow>>;
  List: TList<TLogRow>;
  Row: TLogRow;
  Revs: TArray<THistRev>;
  M: TJ2GModule;
  R: TJ2GRevision;
  I, J, K, RevPtr, NEntries, NMatched, NWithMembers: Integer;
begin
  if AOptions.NoLog then
  begin
    AReport.Info(AProject.Name + ': server log not read (-nolog): dates by file time');
    Exit;
  end;
  State := ASession.ServerLogState;
  if State = slOff then
  begin
    AReport.Info(AProject.Name + ': the server does not write the log (WriteVCSLog off): dates by file time');
    Exit;
  end;

  NEntries := 0;
  NMatched := 0;
  Rows := TObjectDictionary<Integer, TList<TLogRow>>.Create([doOwnsValues]);
  try
    if not GLogLoaded then
    begin
      GetLogEntries := TJVCSGetLogEntries.Create(nil);
      try
        GetLogEntries.ProjectID := 0; // all: a shared module may get check-ins from another project
        GetLogEntries.ModuleID := 0;
        GetLogEntries.UserID := 0;
        GetLogEntries.StartDate := 0;
        GetLogEntries.EndDate := 0;
        GetLogEntries.EntryType := 'i;'; // server format: one char and ';' per type
        try
          ASession.Send(GetLogEntries, AOptions.BlobTimeout);
        except
          on E: EJVCSClientRequestError do
          begin
            AReport.Warn(Format('%s: server log not available (%s): dates by file time', [AProject.Name, E.Message]));
            Exit;
          end;
        end;
        SetLength(GLogEntries, GetLogEntries.OutputItemCount);
        for I := 0 to Pred(GetLogEntries.OutputItemCount) do
        begin
          GLogEntries[I].LogID := GetLogEntries.OutputItems[I].LogID;
          GLogEntries[I].ModuleID := GetLogEntries.OutputItems[I].ModuleID;
          GLogEntries[I].Stamp := GetLogEntries.OutputItems[I].Timestamp;
          GLogEntries[I].UserName := string(GetLogEntries.OutputItems[I].UserName);
        end;
        GLogLoaded := True;
        if not Assigned(GLogComments) then
          GLogComments := TDictionary<Integer, string>.Create;
      finally
        GetLogEntries.Free;
      end;
    end;
    for I := 0 to High(GLogEntries) do
    begin
      M := AProject.FindModule(GLogEntries[I].ModuleID);
      if not Assigned(M) or (M.Revisions.Count = 0) then
        Continue;
      Row.LogID := GLogEntries[I].LogID;
      Row.ModuleID := M.ModuleID;
      Row.Stamp := GLogEntries[I].Stamp;
      Row.UserName := GLogEntries[I].UserName;
      Row.Comment := '';
      Row.Linked := False;
      if not Rows.TryGetValue(M.ModuleID, List) then
      begin
        List := TList<TLogRow>.Create;
        Rows.Add(M.ModuleID, List);
      end;
      List.Add(Row);
      Inc(NEntries);
    end;

    // comments: one request per entry (LogID is unique), cached for the run
    // (a module shared by several projects is asked only once)
    for List in Rows.Values do
      for I := 0 to Pred(List.Count) do
      begin
        Row := List[I];
        if not GLogComments.TryGetValue(Row.LogID, Row.Comment) then
        begin
          GetLogComment := TJVCSGetLogComment.Create(nil);
          try
            GetLogComment.LogID := Row.LogID;
            ASession.Send(GetLogComment, AOptions.BlobTimeout);
            Row.Comment := GetLogComment.CheckinComment;
            GLogComments.Add(Row.LogID, Row.Comment);
          finally
            GetLogComment.Free;
          end;
        end;
        // without a linked revision (logcomm) the server answers the literal word 'blank'
        Row.Linked := Row.Comment <> 'blank';
        if not Row.Linked then
          Row.Comment := '';
        List[I] := Row;
      end;

    for M in AProject.Modules do
    begin
      if not Rows.TryGetValue(M.ModuleID, List) or not AHist.TryGetValue(M.ModuleID, Revs) then
        Continue;
      // oldest first (the server sorts by date; LogID breaks ties)
      List.Sort(TComparer<TLogRow>.Construct(CompareLogRows));
      // revisions newest first (RevisionID comes from a generator)
      Revs := Copy(Revs);
      TArray.Sort<THistRev>(Revs, TComparer<THistRev>.Construct(CompareHistRevsDesc));
      RevPtr := 0;
      for J := Pred(List.Count) downto 0 do
      begin
        Row := List[J];
        if not Row.Linked then
          Continue;
        for K := RevPtr to High(Revs) do
          if (AnsiCompareText(Revs[K].UserName, Row.UserName) = 0) and
            (Revs[K].Comment = Row.Comment) then
          begin
            R := AProject.FindRevision(Revs[K].RevisionID);
            if Assigned(R) and (R.ModuleID = M.ModuleID) then
            begin
              R.LogTime := Row.Stamp;
              Inc(NMatched);
            end;
            RevPtr := K + 1;
            Break;
          end;
      end;
    end;
  finally
    Rows.Free;
  end;

  NWithMembers := 0;
  for R in AProject.Revisions do
    if R.Status <> rsNoMembers then
      Inc(NWithMembers);
  AReport.Info(Format('%s: server log %s: %d check-in entries, %d of %d revisions dated by the log',
    [AProject.Name, IfThen(State = slOn, 'on', 'unknown'), NEntries, NMatched, NWithMembers]));
end;

procedure J2GFetchProject(ASession: TJ2GSession; const AOptions: TJ2GOptions;
  const AInfo: TJ2GProjectInfo; AProject: TJ2GProject; AReport: TJ2GReport);
var
  Hist: THistMap;
  Users: TArray<TJ2GUser>;
begin
  AProject.ProjectID := AInfo.ProjectID;
  AProject.Name := AInfo.Name;
  AProject.Deleted := AInfo.Deleted;
  AProject.Description := AInfo.Description;

  FetchModules(ASession, AOptions, AProject);
  FetchRevisions(ASession, AOptions, AProject, AReport);
  Hist := THistMap.Create;
  try
    FetchHistory(ASession, AProject, AReport, Hist);
    FetchLabels(ASession, AProject);
    try
      Users := J2GFetchUsers(ASession);
      AProject.Users.AddRange(Users);
    except
      on E: EJVCSClientRequestError do
        AReport.Warn(Format('%s: user list not available (%s)', [AProject.Name, E.Message]));
    end;
    FetchLog(ASession, AOptions, AProject, AReport, Hist);
  finally
    Hist.Free;
  end;
  AProject.SortRevisions;

  if Assigned(AReport.Current) then
  begin
    AReport.Current.Modules := AProject.Modules.Count;
    AReport.Current.Revisions := AProject.Revisions.Count;
  end;
  AReport.Info(Format('%s: %d modules, %d revisions, %d labels',
    [AProject.Name, AProject.Modules.Count, AProject.Revisions.Count, AProject.Labels.Count]));
end;

initialization

finalization
  J2GFetchClearCache;

end.
