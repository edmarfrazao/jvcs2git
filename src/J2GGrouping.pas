(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GGrouping.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - effective dates of the revisions and grouping of revisions into
commits. Revisions are ordered by RevisionID (monotonic generator), NEVER by
date. Pure functions. Interface frozen in PT0; implemented in PT2.

-----------------------------------------------------------------------------*)

unit J2GGrouping;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes,
  J2GModel, J2GOptions, J2GReport;

// valid date: >= 1980-01-01 and <= ANowUtc + 1 day
function J2GDateIsValid(ADate, ANowUtc: TDateTime): Boolean;

// Sets Date/DateSource/DateSubstituted/OriginalDateText of every revision of
// AProject (already sorted by RevisionID), first valid of:
//   LogTime (dsLog), OrigTime (dsFile), Module.ModuleTimestamp only for the
//   last revision of the module (dsModule), date of the previous revision
//   + 1 s (dsPrevious), ANowUtc (dsNow).
// OrigTime discarded (0, -1, 1899, future...) -> DateSubstituted = True,
// OriginalDateText = original value, counted in AReport.Current.DatesSubstituted
// and listed as a warning.
procedure J2GAssignDates(AProject: TJ2GProject; ANowUtc: TDateTime; AReport: TJ2GReport);

// Builds AProject.Commits (marks are NOT assigned here) from the revisions in
// RevisionID order (plan 10.5):
//  - AGroupMinutes = 0 (-nogroup): one commit per revision;
//  - both revisions dated by log: same UserName, same Trim(Comment),
//    |Date - last date of the group| <= AGroupMinutes;
//  - any of them dated otherwise: same UserName, same Trim(Comment) and
//    adjacency in the RevisionID list, span (max-min Date) <= AMaxSpanHours;
//  - in both cases the module must not be in the group yet.
// AuthorDate = max(Date of the group revisions); CommitterDate =
// max(AuthorDate, previous CommitterDate) with cdMonotonic, = AuthorDate with
// cdOriginal. DateFromLog = all revisions dated by log. Updates
// AReport.Current.CommitsDateFromLog/CommitsDateFromFile.
procedure J2GGroupCommits(AProject: TJ2GProject; AGroupMinutes, AMaxSpanHours: Integer;
  ACommitterDate: TJ2GCommitterDate; AReport: TJ2GReport);

implementation

const
  OneSecond = 1 / SecsPerDay;

function J2GDateIsValid(ADate, ANowUtc: TDateTime): Boolean;
begin
  Result := (ADate >= EncodeDate(1980, 1, 1)) and (ADate <= ANowUtc + 1);
end;

function DateText(ADate: TDateTime): string;
begin
  if ADate = 0 then
    Result := '0'
  else if (ADate < -657434) or (ADate > 2958465) then  // outside 0001..9999
    Result := FloatToStr(ADate, TFormatSettings.Invariant)
  else
    Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', ADate);
end;

function RevModuleName(R: TJ2GRevision): string;
begin
  if Assigned(R.Module) then
    Result := R.Module.Name
  else
    Result := 'module ' + IntToStr(R.ModuleID);
end;

function IsLastOfModule(R: TJ2GRevision): Boolean;
begin
  Result := Assigned(R.Module) and (R.Module.Revisions.Count > 0) and
    (R.Module.Revisions.Last = R);
end;

procedure J2GAssignDates(AProject: TJ2GProject; ANowUtc: TDateTime; AReport: TJ2GReport);
var
  R: TJ2GRevision;
  Prev: TDateTime;
  Substituted: Integer;
begin
  Prev := 0;
  Substituted := 0;
  for R in AProject.Revisions do
  begin
    R.DateSubstituted := False;
    R.OriginalDateText := '';
    if (R.LogTime > 0) and J2GDateIsValid(R.LogTime, ANowUtc) then
    begin
      R.Date := R.LogTime;
      R.DateSource := dsLog;
    end
    else if J2GDateIsValid(R.OrigTime, ANowUtc) then
    begin
      R.Date := R.OrigTime;
      R.DateSource := dsFile;
    end
    else
    begin
      // file time discarded (0, -1 of FileGetUTCDateTime, 1899, future...)
      R.DateSubstituted := True;
      R.OriginalDateText := DateText(R.OrigTime);
      if IsLastOfModule(R) and J2GDateIsValid(R.Module.ModuleTimestamp, ANowUtc) then
      begin
        R.Date := R.Module.ModuleTimestamp;
        R.DateSource := dsModule;
      end
      else if Prev > 0 then
      begin
        R.Date := Prev + OneSecond;
        R.DateSource := dsPrevious;
      end
      else
      begin
        R.Date := ANowUtc;
        R.DateSource := dsNow;
      end;
      Inc(Substituted);
      if Assigned(AReport) then
        AReport.Warn(Format('rev %d (%s %s): invalid date %s substituted by %s',
          [R.RevisionID, RevModuleName(R), R.VersionText, R.OriginalDateText,
           FormatDateTime('yyyy-mm-dd hh:nn:ss', R.Date)]));
    end;
    Prev := R.Date;
  end;
  if Assigned(AReport) and Assigned(AReport.Current) then
    AReport.Current.DatesSubstituted := Substituted;
end;

function SameAuthorAndComment(A, B: TJ2GRevision): Boolean;
begin
  Result := SameText(A.UserName, B.UserName) and (Trim(A.Comment) = Trim(B.Comment));
end;

// can R join the commit C (whose last revision is the previous revision of
// the project in RevisionID order, so adjacency holds by construction)?
function CanJoin(C: TJ2GCommit; R: TJ2GRevision; AGroupMinutes, AMaxSpanHours: Integer): Boolean;
var
  Last, X: TJ2GRevision;
  MinD, MaxD: TDateTime;
begin
  Last := C.Revisions.Last;
  if not SameAuthorAndComment(Last, R) or C.HasModule(R.ModuleID) then
    Exit(False);
  if (Last.DateSource = dsLog) and (R.DateSource = dsLog) then
    // both by the server log: time window over the last date of the group
    Result := Abs(R.Date - Last.Date) <= AGroupMinutes / MinsPerDay + OneSecond / 2
  else
  begin
    // dated by file time: adjacency, with a span limit (<= 0 = no limit)
    if AMaxSpanHours <= 0 then
      Exit(True);
    MinD := R.Date;
    MaxD := R.Date;
    for X in C.Revisions do
    begin
      if X.Date < MinD then
        MinD := X.Date;
      if X.Date > MaxD then
        MaxD := X.Date;
    end;
    Result := MaxD - MinD <= AMaxSpanHours / HoursPerDay + OneSecond / 2;
  end;
end;

procedure J2GGroupCommits(AProject: TJ2GProject; AGroupMinutes, AMaxSpanHours: Integer;
  ACommitterDate: TJ2GCommitterDate; AReport: TJ2GReport);
var
  R: TJ2GRevision;
  C: TJ2GCommit;
  PrevCommitter: TDateTime;
  FromLog, FromFile: Integer;
begin
  AProject.Commits.Clear;
  C := nil;
  for R in AProject.Revisions do
  begin
    // revisions without history rows have no author/comment/blob: they
    // never become part of a commit (J2GExport reports them)
    if R.Status = rsNoMembers then
      Continue;
    if Assigned(C) and (AGroupMinutes > 0) and CanJoin(C, R, AGroupMinutes, AMaxSpanHours) then
      C.Revisions.Add(R)
    else
    begin
      C := TJ2GCommit.Create;
      AProject.Commits.Add(C);
      C.Revisions.Add(R);
      C.UserName := R.UserName;
      C.Comment := R.Comment;
    end;
  end;

  PrevCommitter := 0;
  FromLog := 0;
  FromFile := 0;
  for C in AProject.Commits do
  begin
    C.AuthorDate := 0;
    C.DateFromLog := True;
    for R in C.Revisions do
    begin
      if R.Date > C.AuthorDate then
        C.AuthorDate := R.Date;
      if R.DateSource <> dsLog then
        C.DateFromLog := False;
    end;
    if (ACommitterDate = cdMonotonic) and (PrevCommitter > C.AuthorDate) then
      C.CommitterDate := PrevCommitter
    else
      C.CommitterDate := C.AuthorDate;
    if C.CommitterDate > PrevCommitter then
      PrevCommitter := C.CommitterDate;
    if C.DateFromLog then
      Inc(FromLog)
    else
      Inc(FromFile);
  end;
  if Assigned(AReport) and Assigned(AReport.Current) then
  begin
    AReport.Current.CommitsDateFromLog := FromLog;
    AReport.Current.CommitsDateFromFile := FromFile;
  end;
end;

end.
