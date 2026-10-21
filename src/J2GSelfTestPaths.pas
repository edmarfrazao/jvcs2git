(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GSelfTestPaths.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - -selftest paths: fixed cases of J2GPaths, J2GGrouping and
J2GAuthors (root, _externos, sanitizing, quoting, tag names, case
collisions, dates, grouping, author map). Everything is built in memory (no
server); the author map uses a temporary file in %TEMP%, deleted at the end.
When git is in the PATH every sanitized tag name is also checked with
'git check-ref-format'.

-----------------------------------------------------------------------------*)

unit J2GSelfTestPaths;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  J2GReport;

// returns 0 when every case passes (1 otherwise)
function J2GRunSelfTestPaths(AReport: TJ2GReport): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  J2GModel, J2GOptions, J2GPaths, J2GGrouping, J2GAuthors, J2GGit;

type
  TSelfTest = class
  private
    FReport: TJ2GReport;
    FCases: Integer;
    FFailures: Integer;
    FGitOk: Boolean;
    procedure Check(ACond: Boolean; const AName: string; const ADetail: string = '');
    procedure CheckEq(const AName, AExpected, AActual: string);
    procedure CheckInt(const AName: string; AExpected, AActual: Integer);
    function NewSilentReport: TJ2GReport;
    function AddModule(P: TJ2GProject; AID: Integer; const AName, APath: string): TJ2GModule;
    function AddRevision(P: TJ2GProject; ARevID, AModID: Integer; const AUser, AComment: string;
      AOrigTime: TDateTime; ALogTime: TDateTime; const AExts: array of string): TJ2GRevision;
    procedure TestRoot;
    procedure TestRelativeAndSanitize;
    procedure TestAssignPaths;
    procedure TestQuote;
    procedure TestTags;
    procedure TestDates;
    procedure TestGrouping;
    procedure TestAuthors;
  public
    constructor Create(AReport: TJ2GReport);
    function Run: Integer;
  end;

const
  // fixed "now" so that the cases do not depend on the clock
  NowUtcY = 2026; NowUtcM = 10; NowUtcD = 20;

function FixedNow: TDateTime;
begin
  Result := EncodeDate(NowUtcY, NowUtcM, NowUtcD) + EncodeTime(12, 0, 0, 0);
end;

function Dt(Y, M, D, H, N: Word): TDateTime;
begin
  Result := EncodeDate(Y, M, D) + EncodeTime(H, N, 0, 0);
end;

function Visible(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
    if (Ord(C) < 32) or (Ord(C) > 126) then
      Result := Result + '#' + IntToStr(Ord(C))
    else
      Result := Result + C;
end;

{ TSelfTest }

constructor TSelfTest.Create(AReport: TJ2GReport);
begin
  inherited Create;
  FReport := AReport;
end;

procedure TSelfTest.Check(ACond: Boolean; const AName, ADetail: string);
begin
  Inc(FCases);
  if ACond then
    FReport.Info('ok: ' + AName)
  else
  begin
    Inc(FFailures);
    if ADetail <> '' then
      FReport.Error('FAILED: ' + AName + ' - ' + ADetail)
    else
      FReport.Error('FAILED: ' + AName);
  end;
end;

procedure TSelfTest.CheckEq(const AName, AExpected, AActual: string);
begin
  Check(AExpected = AActual, AName + ' = ' + Visible(AExpected),
    'got ' + Visible(AActual));
end;

procedure TSelfTest.CheckInt(const AName: string; AExpected, AActual: Integer);
begin
  Check(AExpected = AActual, Format('%s = %d', [AName, AExpected]),
    Format('got %d', [AActual]));
end;

function TSelfTest.NewSilentReport: TJ2GReport;
begin
  // receives the warnings of the code under test; prints nothing
  Result := TJ2GReport.Create;
  Result.JsonMode := True;
  Result.Quiet := True;
  Result.BeginProject(1, 'selftest.dpr');
end;

function TSelfTest.AddModule(P: TJ2GProject; AID: Integer; const AName, APath: string): TJ2GModule;
begin
  Result := TJ2GModule.Create;
  Result.ModuleID := AID;
  Result.Name := AName;
  Result.Path := APath;
  P.AddModule(Result);
end;

function TSelfTest.AddRevision(P: TJ2GProject; ARevID, AModID: Integer; const AUser, AComment: string;
  AOrigTime: TDateTime; ALogTime: TDateTime; const AExts: array of string): TJ2GRevision;
var
  I: Integer;
begin
  Result := TJ2GRevision.Create;
  Result.RevisionID := ARevID;
  Result.ModuleID := AModID;
  Result.Version := 1;
  Result.Revision := ARevID;
  Result.UserName := AUser;
  Result.Comment := AComment;
  Result.OrigTime := AOrigTime;
  Result.LogTime := ALogTime;
  Result.Status := rsPending;
  SetLength(Result.Members, Length(AExts));
  for I := 0 to High(AExts) do
  begin
    Result.Members[I].Ext := AExts[I];
    Result.Members[I].OrigTime := AOrigTime;
  end;
  P.AddRevision(Result);
end;

procedure TSelfTest.TestRoot;
var
  P: TJ2GProject;
begin
  // folder of the module named like the project
  P := TJ2GProject.Create;
  try
    P.Name := 'exemplo01.dpr';
    AddModule(P, 1, 'unit1.pas', 'c:\proj\exemplo01\src\');
    AddModule(P, 2, 'exemplo01.dpr', 'c:\proj\exemplo01\');
    AddModule(P, 3, 'x.pas', 'c:\lib\');
    CheckEq('root: folder of the .dpr', 'c:\proj\exemplo01\', J2GChooseRoot(P, ''));
    CheckEq('root: AProject.Root set', 'c:\proj\exemplo01\', P.Root);
    CheckEq('root: -root normalized', 'c:\outra\pasta\', J2GChooseRoot(P, 'C:/Outra/Pasta'));
  finally
    P.Free;
  end;
  // longest common prefix by component (not by character)
  P := TJ2GProject.Create;
  try
    P.Name := 'grupo.bpg';
    AddModule(P, 1, 'a.pas', 'c:\proj\abc\src\');
    AddModule(P, 2, 'b.pas', 'c:\proj\abcdef\');
    AddModule(P, 3, 'c.pas', 'C:\Proj\abc\');
    CheckEq('root: common prefix by component', 'c:\proj\', J2GChooseRoot(P, ''));
  finally
    P.Free;
  end;
  P := TJ2GProject.Create;
  try
    P.Name := 'x.dpr';
    AddModule(P, 1, 'a.pas', 'c:\proj\');
    AddModule(P, 2, 'b.pas', 'd:\proj\');
    CheckEq('root: different drives -> none', '', J2GChooseRoot(P, ''));
  finally
    P.Free;
  end;
  P := TJ2GProject.Create;
  try
    P.Name := 'x.dpr';
    AddModule(P, 1, 'a.pas', '\\srv\share\p\a\');
    AddModule(P, 2, 'b.pas', '\\srv\share\p\b\');
    CheckEq('root: UNC common prefix', '\\srv\share\p\', J2GChooseRoot(P, ''));
  finally
    P.Free;
  end;
end;

procedure TSelfTest.TestRelativeAndSanitize;
var
  Changed: Boolean;
begin
  CheckEq('relative: inside the root', 'src/sub/', J2GRelativeFolder('c:\proj\src\sub\', 'c:\proj\', Changed));
  Check(not Changed, 'relative: inside the root not changed');
  CheckEq('relative: the root itself', '', J2GRelativeFolder('c:\proj\', 'c:\proj\', Changed));
  CheckEq('relative: c:\lib -> _externos/c/lib/', '_externos/c/lib/', J2GRelativeFolder('c:\lib\', 'c:\proj\', Changed));
  Check(not Changed, 'relative: drive letter is not a sanitizing change');
  CheckEq('relative: \\srv\share\lib -> _externos/unc/srv/share/lib/', '_externos/unc/srv/share/lib/',
    J2GRelativeFolder('\\srv\share\lib\', 'c:\proj\', Changed));
  CheckEq('relative: trailing dot of a folder', 'sub/', J2GRelativeFolder('c:\proj\sub.\', 'c:\proj\', Changed));
  Check(Changed, 'relative: trailing dot reported as changed');
  CheckEq('relative: no root -> _externos', '_externos/d/x/', J2GRelativeFolder('D:\X\', '', Changed));

  CheckEq('sanitize: nul.pas', '_nul.pas',J2GSanitizeComponent('nul.pas'));
  CheckEq('sanitize: COM1', '_COM1', J2GSanitizeComponent('COM1'));
  CheckEq('sanitize: lpt9.txt', '_lpt9.txt', J2GSanitizeComponent('lpt9.txt'));
  CheckEq('sanitize: com10 is not reserved', 'com10', J2GSanitizeComponent('com10'));
  CheckEq('sanitize: console.pas is not reserved', 'console.pas', J2GSanitizeComponent('console.pas'));
  CheckEq('sanitize: ":" in the name', 'a_b.pas', J2GSanitizeComponent('a:b.pas'));
  CheckEq('sanitize: forbidden chars', 'x_y_z___.txt', J2GSanitizeComponent('x<y>z|?*.txt'));
  CheckEq('sanitize: trailing dot and space', 'a', J2GSanitizeComponent('a. . '));
  CheckEq('sanitize: only dots', '_', J2GSanitizeComponent('...'));
  CheckEq('sanitize: empty', '_', J2GSanitizeComponent(''));
  CheckEq('sanitize: control char', 'a_b', J2GSanitizeComponent('a'#9'b'));
  CheckEq('sanitize: .git', '_.Git', J2GSanitizeComponent('.Git'));
  CheckEq('repo folder: exemplo01.dpr', 'exemplo01', J2GRepoFolderName('exemplo01.dpr'));
  CheckEq('repo folder: aux.dpr', '_aux', J2GRepoFolderName('aux.dpr'));
  CheckEq('repo folder: never empty', '_', J2GRepoFolderName(' .dpr '));
end;

procedure TSelfTest.TestAssignPaths;
var
  P: TJ2GProject;
  M1, M2, M3, M4, M5: TJ2GModule;
  R1, R2, R3, R4, R5: TJ2GRevision;
  Rep: TJ2GReport;
begin
  P := TJ2GProject.Create;
  Rep := NewSilentReport;
  try
    P.Name := 'proj.dpr';
    M1 := AddModule(P, 10, 'unit1.pas', 'c:\proj\sub\');
    M2 := AddModule(P, 11, 'unit1.pas', 'c:\proj\sub.\');   // same path after sanitizing
    M3 := AddModule(P, 12, 'x.pas', 'c:\lib\');
    M4 := AddModule(P, 13, 'x.pas', '\\srv\share\lib\');
    M5 := AddModule(P, 14, 'nul.pas', 'c:\proj\sub.\');
    AddModule(P, 15, 'proj.dpr', 'c:\proj\');
    R1 := AddRevision(P, 1, 10, 'u', 'c', Dt(2001, 1, 1, 0, 0), 0, ['.pas', '.dfm']);
    R2 := AddRevision(P, 2, 11, 'u', 'c', Dt(2001, 1, 1, 0, 0), 0, ['.pas', '.dfm']);
    R3 := AddRevision(P, 3, 12, 'u', 'c', Dt(2001, 1, 1, 0, 0), 0, ['.pas']);
    R4 := AddRevision(P, 4, 13, 'u', 'c', Dt(2001, 1, 1, 0, 0), 0, ['.pas']);
    R5 := AddRevision(P, 5, 14, 'u', 'c', Dt(2001, 1, 1, 0, 0), 0, ['.pas']);
    J2GChooseRoot(P, '');
    J2GChooseDisplayName(M1, 'Unit1.pas');
    CheckEq('display name: ZIP spelling accepted', 'Unit1.pas', M1.DisplayName);
    J2GChooseDisplayName(M2, 'outro.pas');
    CheckEq('display name: different ZIP name ignored', 'unit1.pas', M2.DisplayName);
    Check(J2GAssignPaths(P, Rep, False), 'assign paths: returns True without -strictcase');
    CheckEq('paths: module spelling', 'sub/Unit1.pas', R1.Members[0].Path);
    CheckEq('paths: member gets base spelling + lower ext', 'sub/Unit1.dfm', R1.Members[1].Path);
    CheckEq('paths: case collision -> -<ModuleID>', 'sub/unit1-11.pas', R2.Members[0].Path);
    CheckEq('paths: case collision member', 'sub/unit1-11.dfm', R2.Members[1].Path);
    CheckEq('paths: c:\lib\x.pas', '_externos/c/lib/x.pas', R3.Members[0].Path);
    CheckEq('paths: \\srv\share\lib\x.pas', '_externos/unc/srv/share/lib/x.pas', R4.Members[0].Path);
    CheckEq('paths: c:\proj\sub.\nul.pas', 'sub/_nul.pas', R5.Members[0].Path);
    CheckEq('paths: RelPath', 'sub/', M5.RelPath);
    Check(Rep.Current.Warnings.Count >= 2, 'paths: collision and sanitizing reported as warnings',
      Format('%d warnings', [Rep.Current.Warnings.Count]));
    M2.DisplayName := 'unit1.pas';  // spelling as before the first run
    Check(not J2GAssignPaths(P, Rep, True),'assign paths: -strictcase returns False on collision');
    CheckEq('paths: second run keeps the paths', 'sub/unit1-11.pas', R2.Members[0].Path);
  finally
    Rep.Free;
    P.Free;
  end;
end;

procedure TSelfTest.TestQuote;
begin
  CheckEq('quote: plain path unchanged', 'src/Unit1.pas', J2GQuotePath('src/Unit1.pas'));
  CheckEq('quote: space', '"src/My Unit.pas"', J2GQuotePath('src/My Unit.pas'));
  CheckEq('quote: double quote', '"a\"b.pas"', J2GQuotePath('a"b.pas'));
  CheckEq('quote: backslash', '"a\\b.pas"', J2GQuotePath('a\b.pas'));
  CheckEq('quote: LF', '"a\nb.pas"', J2GQuotePath('a'#10'b.pas'));
  CheckEq('quote: control char octal', '"a\001b"', J2GQuotePath('a'#1'b'));
  CheckEq('quote: accent unchanged (UTF-8 by the writer)', 'src/a' + #$00E7 + #$00E3 + 'o.pas',
    J2GQuotePath('src/a' + #$00E7 + #$00E3 + 'o.pas'));
end;

procedure TSelfTest.TestTags;
const
  Names: array[0..13] of string = ('.NET 4', 'v1.0.', 'beta/', 'a//b', '@', ' ~^:?*[\ ',
    'x.lock', 'a..b', 'a@{b', '/lead/trail/', 'ver 1.0 (final)', 'a/.b/c.', 'tab'#9'x', 'nul');
  Expected: array[0..13] of string = ('NET-4', 'v1.0', 'beta', 'a/b', 'label-4', 'label-5',
    'x', 'a-b', 'a-b', 'lead/trail', 'ver-1.0-(final)', 'a/b/c', 'tab-x', 'nul_');
var
  I: Integer;
  S: string;
  P: TJ2GProject;
  L: TJ2GLabel;

  function AddLabel(AID: Integer; const AName: string): TJ2GLabel;
  begin
    Result := TJ2GLabel.Create;
    Result.LabelID := AID;
    Result.Name := AName;
    P.Labels.Add(Result);
  end;

  procedure GitCheck(const ATag: string);
  begin
    if FGitOk then
      Check(J2GGitCheckRefFormat(ATag, False), 'git check-ref-format refs/tags/' + Visible(ATag));
  end;

begin
  for I := 0 to High(Names) do
  begin
    S := J2GSanitizeTagName(Names[I], I);
    CheckEq('tag: ' + Visible(Names[I]), Expected[I], S);
    GitCheck(S);
  end;
  P := TJ2GProject.Create;
  try
    AddLabel(1, 'Release');
    AddLabel(2, 'release');
    AddLabel(3, 'a');
    AddLabel(4, 'A/b');
    AddLabel(5, '???');
    J2GAssignTagNames(P);
    CheckEq('tags: first keeps its name', 'Release', P.Labels[0].TagName);
    CheckEq('tags: case collision -> -<LabelID>', 'release-2', P.Labels[1].TagName);
    CheckEq('tags: a', 'a', P.Labels[2].TagName);
    CheckEq('tags: a vs A/b (file x folder) -> -<LabelID>', 'A-b-4', P.Labels[3].TagName);
    CheckEq('tags: only invalid chars', 'label-5', P.Labels[4].TagName);
    for L in P.Labels do
      GitCheck(L.TagName);
  finally
    P.Free;
  end;
end;

procedure TSelfTest.TestDates;
var
  P: TJ2GProject;
  R1, R2, R3, R4, R5: TJ2GRevision;
  M: TJ2GModule;
  Rep: TJ2GReport;
  NowUtc: TDateTime;
  I: Integer;
begin
  NowUtc := FixedNow;
  Check(not J2GDateIsValid(0, NowUtc), 'date: 0 invalid');
  Check(not J2GDateIsValid(-1, NowUtc), 'date: -1 invalid');
  Check(not J2GDateIsValid(EncodeDate(1979, 12, 31), NowUtc), 'date: 1979-12-31 invalid');
  Check(J2GDateIsValid(EncodeDate(1980, 1, 1), NowUtc), 'date: 1980-01-01 valid');
  Check(J2GDateIsValid(NowUtc + 0.5, NowUtc), 'date: now + 12 h valid');
  Check(not J2GDateIsValid(NowUtc + 2, NowUtc), 'date: now + 2 days invalid');

  P := TJ2GProject.Create;
  Rep := NewSilentReport;
  try
    P.Name := 'd.dpr';
    AddModule(P, 1, 'a.pas', 'c:\p\');
    M := AddModule(P, 2, 'b.pas', 'c:\p\');
    M.ModuleTimestamp := Dt(2005, 5, 5, 5, 5);
    R1 := AddRevision(P, 1, 1, 'u', 'one', Dt(2004, 1, 1, 10, 0), 0, ['.pas']);
    R2 := AddRevision(P, 2, 1, 'v', 'two', 0, 0, ['.pas']);
    R3 := AddRevision(P, 3, 1, 'u', 'three', EncodeDate(1899, 12, 31), 0, ['.pas']);
    R4 := AddRevision(P, 4, 2, 'v', 'four', NowUtc + 30, 0, ['.pas']);
    R5 := AddRevision(P, 5, 1, 'u', 'five', 0, Dt(2003, 1, 1, 0, 0), ['.pas']);
    P.SortRevisions;
    J2GAssignDates(P, NowUtc, Rep);
    Check((R1.DateSource = dsFile) and not R1.DateSubstituted, 'dates: valid OrigTime kept (file)');
    Check((R2.DateSource = dsPrevious) and R2.DateSubstituted and
      SameDateTime(R2.Date, IncSecond(R1.Date)), 'dates: OrigTime 0 -> previous + 1 s');
    CheckEq('dates: original text kept', '0', R2.OriginalDateText);
    Check((R3.DateSource = dsPrevious) and R3.DateSubstituted, 'dates: 1899 -> previous + 1 s');
    Check((R4.DateSource = dsModule) and R4.DateSubstituted and
      SameDateTime(R4.Date, M.ModuleTimestamp), 'dates: future, last revision -> module timestamp');
    Check((R5.DateSource = dsLog) and not R5.DateSubstituted, 'dates: log time preferred');
    CheckInt('dates: substituted count', 3, Rep.Current.DatesSubstituted);
    J2GGroupCommits(P, 10, 24, cdMonotonic, Rep);
    Check(P.Commits.Count = 5, 'dates: 5 commits (author/comment differ)');
    for I := 1 to P.Commits.Count - 1 do
      Check(P.Commits[I].CommitterDate >= P.Commits[I - 1].CommitterDate,
        Format('dates: committer monotonic at commit %d', [I + 1]));
    Check(SameDateTime(P.Commits[4].AuthorDate, R5.Date) and (P.Commits[4].CommitterDate > R5.Date),
      'dates: author keeps the old date, committer does not go back');
    J2GGroupCommits(P, 10, 24, cdOriginal, Rep);
    Check(SameDateTime(P.Commits[4].CommitterDate, R5.Date), 'dates: -committer-date original');
  finally
    Rep.Free;
    P.Free;
  end;

  // first revision invalid and nothing before it -> now
  P := TJ2GProject.Create;
  Rep := NewSilentReport;
  try
    AddModule(P, 1, 'a.pas', 'c:\p\');
    AddModule(P, 2, 'b.pas', 'c:\p\');
    R1 := AddRevision(P, 1, 1, 'u', 'x', 0, 0, ['.pas']);
    AddRevision(P, 2, 1, 'u', 'x', Dt(2001, 1, 1, 0, 0), 0, ['.pas']);
    J2GAssignDates(P, NowUtc, Rep);
    Check((R1.DateSource = dsNow) and SameDateTime(R1.Date, NowUtc), 'dates: no previous -> now');
  finally
    Rep.Free;
    P.Free;
  end;
end;

procedure TSelfTest.TestGrouping;
var
  P: TJ2GProject;
  Rep: TJ2GReport;
  D: TDateTime;

  procedure NewProject;
  var
    J: Integer;
  begin
    FreeAndNil(P);
    P := TJ2GProject.Create;
    P.Name := 'g.dpr';
    for J := 1 to 6 do
      AddModule(P, J, Format('m%d.pas', [J]), 'c:\g\');
  end;

  procedure Prepare;
  begin
    P.SortRevisions;
    J2GAssignDates(P, FixedNow, Rep);
  end;

begin
  P := nil;
  Rep := NewSilentReport;
  try
    D := Dt(2002, 3, 1, 9, 0);
    // 3 revisions, same user and comment, file dates days apart, no log
    NewProject;
    AddRevision(P, 101, 1, 'joao', 'fix', D, 0, ['.pas']);
    AddRevision(P, 105, 2, 'joao', ' fix ', D + 3, 0, ['.pas']);
    AddRevision(P, 109, 3, 'JOAO', 'fix', D - 2, 0, ['.pas']);
    Prepare;
    J2GGroupCommits(P, 10, 24 * 30, cdMonotonic, Rep);
    CheckInt('group: 3 revisions days apart without log -> commits', 1, P.Commits.Count);
    if P.Commits.Count = 1 then
      Check(SameDateTime(P.Commits[0].AuthorDate, D + 3), 'group: commit date = max of the group');
    CheckInt('group: commits dated by file', 1, Rep.Current.CommitsDateFromFile);
    // the span limit (-group-maxspan) still splits
    J2GGroupCommits(P, 10, 24, cdMonotonic, Rep);
    CheckInt('group: span over -group-maxspan 24 h splits', 3, P.Commits.Count);
    // -nogroup
    J2GGroupCommits(P, 0, 24 * 30, cdMonotonic, Rep);
    CheckInt('group: -nogroup -> one commit per revision', 3, P.Commits.Count);

    // a revision of another user in the middle
    NewProject;
    AddRevision(P, 101, 1, 'joao', 'fix', D, 0, ['.pas']);
    AddRevision(P, 102, 2, 'joao', 'fix', D + 1, 0, ['.pas']);
    AddRevision(P, 103, 4, 'maria', 'fix', D + 1, 0, ['.pas']);
    AddRevision(P, 104, 3, 'joao', 'fix', D + 2, 0, ['.pas']);
    Prepare;
    J2GGroupCommits(P, 10, 24 * 30, cdMonotonic, Rep);
    CheckInt('group: other user in the middle -> commits', 3, P.Commits.Count);
    if P.Commits.Count = 3 then
    begin
      CheckInt('group: joao before maria', 2, P.Commits[0].Revisions.Count);
      CheckInt('group: joao after maria', 1, P.Commits[2].Revisions.Count);
    end;

    // same module twice and different comment
    NewProject;
    AddRevision(P, 1, 1, 'joao', 'a', D, 0, ['.pas']);
    AddRevision(P, 2, 1, 'joao', 'a', D, 0, ['.pas']);
    AddRevision(P, 3, 2, 'joao', 'b', D, 0, ['.pas']);
    Prepare;
    J2GGroupCommits(P, 10, 24, cdMonotonic, Rep);
    CheckInt('group: module repeated or other comment -> commits', 3, P.Commits.Count);

    // dated by the server log: window of N minutes over the last date
    NewProject;
    AddRevision(P, 1, 1, 'ana', 'log', D, D, ['.pas']);
    AddRevision(P, 2, 2, 'ana', 'log', D, D + 8 / MinsPerDay, ['.pas']);
    AddRevision(P, 3, 3, 'ana', 'log', D, D + 16 / MinsPerDay, ['.pas']);
    AddRevision(P, 4, 4, 'ana', 'log', D, D + 40 / MinsPerDay, ['.pas']);
    Prepare;
    J2GGroupCommits(P, 10, 24, cdMonotonic, Rep);
    CheckInt('group: log dates within 10 min chained, 24 min gap splits', 2, P.Commits.Count);
    if P.Commits.Count = 2 then
      Check(P.Commits[0].DateFromLog and (P.Commits[0].Revisions.Count = 3), 'group: log commit flagged');
    CheckInt('group: commits dated by log', 2, Rep.Current.CommitsDateFromLog);

    // revisions without members are not grouped
    NewProject;
    AddRevision(P, 1, 1, 'ana', 'x', D, 0, ['.pas']);
    AddRevision(P, 2, 2, '', '', 0, 0, []).Status := rsNoMembers;
    AddRevision(P, 3, 3, 'ana', 'x', D, 0, ['.pas']);
    Prepare;
    J2GGroupCommits(P, 10, 24, cdMonotonic, Rep);
    CheckInt('group: revision without members ignored', 1, P.Commits.Count);
  finally
    P.Free;
    Rep.Free;
  end;
end;

procedure TSelfTest.TestAuthors;
var
  FileName, FileName2: string;
  Map, Map2: TJ2GAuthorMap;
  Warnings: TStringList;
  Bytes: TBytes;
  U: TArray<string>;
  Joao: string;
  Ansi: TEncoding;
begin
  Joao := 'Jo' + #$00E3 + 'o Silva';
  FileName := TPath.Combine(TPath.GetTempPath, 'jvcs2git-selftest-' + IntToStr(TThread.CurrentThread.ThreadID) + '-autores.txt');
  FileName2 := ChangeFileExt(FileName, '.ansi.txt');
  Map := nil;
  Map2 := nil;
  Warnings := TStringList.Create;
  try
    // UTF-8 without BOM, LF, comments, a bad line and a line without e-mail
    TFile.WriteAllBytes(FileName, TEncoding.UTF8.GetBytes('# comment'#10'joao=' + Joao + ' <joao@empresa.com>'#10 +
      #10' maria = Maria <maria@x.com> '#10'bad line'#10'pedro=Pedro sem email'#10));
    Map := TJ2GAuthorMap.Create('jedivcs.local');
    Map.LoadFromFile(FileName, Warnings);
    CheckInt('authors: entries read', 2, Map.Count);
    CheckInt('authors: invalid lines reported', 2, Warnings.Count);
    CheckEq('authors: Ident with accent, case-insensitive login', Joao + ' <joao@empresa.com>', Map.Ident('JOAO'));
    Check(not Map.IsDefault('maria'), 'authors: mapped login is not default');
    Map.EnsureLogins(['joao', 'carlos', 'Ana', '']);
    CheckInt('authors: EnsureLogins adds the missing ones', 4, Map.Count);
    CheckEq('authors: default identity', 'carlos <carlos@jedivcs.local>', Map.Ident('carlos'));
    CheckEq('authors: unknown login, < > removed', 'xy <x_y_@jedivcs.local>', Map.Ident('x<y>'));
    U := Map.Unmapped;
    CheckEq('authors: Unmapped', 'Ana,carlos', string.Join(',', U));
    Map.SaveToFile(FileName);
    Bytes := TFile.ReadAllBytes(FileName);
    Check((Length(Bytes) > 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF),
      'authors: written with UTF-8 BOM');
    Check(Pos(#13#10, TEncoding.UTF8.GetString(Bytes)) > 0, 'authors: written with CRLF');
    Map2 := TJ2GAuthorMap.Create('jedivcs.local');
    Warnings.Clear;
    Map2.LoadFromFile(FileName, Warnings);
    CheckInt('authors: reload count', 4, Map2.Count);
    CheckInt('authors: reload without warnings', 0, Warnings.Count);
    CheckEq('authors: reload keeps the accent', Joao + ' <joao@empresa.com>', Map2.Ident('joao'));
    CheckEq('authors: reload Unmapped', 'Ana,carlos', string.Join(',', Map2.Unmapped));
    FreeAndNil(Map2);
    // file saved as ANSI by an editor
    Ansi := TEncoding.GetEncoding(1252);
    try
      TFile.WriteAllBytes(FileName2, Ansi.GetBytes('joao=' + Joao + ' <j@e.com>'#13#10));
    finally
      Ansi.Free;
    end;
    Map2 := TJ2GAuthorMap.Create('jedivcs.local');
    Warnings.Clear;
    Map2.LoadFromFile(FileName2, Warnings);
    CheckEq('authors: ANSI file read', Joao + ' <j@e.com>', Map2.Ident('joao'));
    CheckInt('authors: ANSI file warned', 1, Warnings.Count);
    FreeAndNil(Map2);
    Map2 := TJ2GAuthorMap.Create('x.org');
    Map2.LoadFromFile(TPath.Combine(TPath.GetTempPath, 'jvcs2git-selftest-missing.txt'), Warnings);
    CheckInt('authors: missing file = empty map', 0, Map2.Count);
  finally
    Map2.Free;
    Map.Free;
    Warnings.Free;
    if FileExists(FileName) then
      DeleteFile(FileName);
    if FileExists(FileName2) then
      DeleteFile(FileName2);
  end;
  Check(not FileExists(FileName) and not FileExists(FileName2), 'authors: temporary files deleted');
end;

function TSelfTest.Run: Integer;
var
  GitVersion: string;

  procedure Section(const AName: string; AProc: TProc);
  begin
    try
      AProc();
    except
      on E: Exception do
      begin
        Inc(FCases);
        Inc(FFailures);
        FReport.Error(Format('FAILED: %s raised %s: %s', [AName, E.ClassName, E.Message]));
      end;
    end;
  end;

begin
  FGitOk := J2GGitVersion(GitVersion);
  if FGitOk then
    FReport.Info('git found (' + Trim(GitVersion) + '): tag names checked with git check-ref-format')
  else
    FReport.Info('git not found: tag names not checked with git check-ref-format');
  Section('root', TestRoot);
  Section('relative/sanitize', TestRelativeAndSanitize);
  Section('assign paths', TestAssignPaths);
  Section('quote', TestQuote);
  Section('tags', TestTags);
  Section('dates', TestDates);
  Section('grouping', TestGrouping);
  Section('authors', TestAuthors);
  FReport.Info(Format('self test paths: %d cases, %d failed', [FCases, FFailures]));
  if FFailures = 0 then
    Result := J2G_EXIT_OK
  else
  begin
    FReport.Message := Format('self test paths failed: %d of %d cases', [FFailures, FCases]);
    Result := 1;
  end;
end;

function J2GRunSelfTestPaths(AReport: TJ2GReport): Integer;
var
  T: TSelfTest;
begin
  T := TSelfTest.Create(AReport);
  try
    Result := T.Run;
  finally
    T.Free;
  end;
end;

end.
