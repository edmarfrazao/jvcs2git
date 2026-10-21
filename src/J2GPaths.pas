(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GPaths.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - repository root, relative paths, _externos, path sanitizing,
fast-import quoting, tag names and repository folder name.
Pure functions (no server, no disk). Interface frozen in PT0; implemented in
PT2.

-----------------------------------------------------------------------------*)

unit J2GPaths;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes,
  J2GModel, J2GReport;

// Repository root (server folder, lower case, ends with '\'):
// AOptionRoot (-root) if given; else the folder of the module whose name equals
// the project name (the .dpr); else the longest common folder prefix of all
// modules. Sets and returns AProject.Root.
function J2GChooseRoot(AProject: TJ2GProject; const AOptionRoot: string): string;

// Repository folder ('/' separated, '' = root, ends with '/' when not empty) of
// a server folder. Inside the root: the rest of the path. Outside:
// '_externos/<drive letter>/<rest>' for 'X:\...' (no ':'), and
// '_externos/unc/<server>/<share>/<rest>' for '\\server\share\...'.
// Every component is sanitized (J2GSanitizeComponent). AChanged = True when
// any component was altered by the sanitizing.
function J2GRelativeFolder(const AServerFolder, ARoot: string; out AChanged: Boolean): string;

// One path component valid for Git for Windows / NTFS: trailing '.' and ' '
// removed; < > : " | ? * and chars < #32 -> '_'; reserved names (con, prn,
// aux, nul, com1-9, lpt1-9, with or without extension) prefixed with '_';
// empty -> '_'.
function J2GSanitizeComponent(const S: string): string;

// ONE spelling per module: AZipName (name found inside the ZIP of the most
// recent readable revision) when SameText with the server name, otherwise
// the server name. Sets AModule.DisplayName.
procedure J2GChooseDisplayName(AModule: TJ2GModule; const AZipName: string);

// Sets Module.RelPath (from AProject.Root) and Members[].Path of every revision:
// member with the module extension -> RelPath + DisplayName; other members ->
// RelPath + ChangeFileExt(DisplayName, lower case ext). Modules without
// DisplayName use Name. Case-insensitive collisions between different modules
// (full paths of all members): the first keeps its spelling, the next gets
// '-<ModuleID>' before the extension, with a warning in AReport. Altered
// (sanitized) paths are reported as warnings too.
// Returns False when there was a collision and AStrictCase is True.
function J2GAssignPaths(AProject: TJ2GProject; AReport: TJ2GReport; AStrictCase: Boolean): Boolean;

// Path for a fast-import 'M'/'D' line: unchanged when it has no special
// char; otherwise in double quotes with C-style escapes (\" \\ \n \t ...).
// The writer encodes the result in UTF-8.
function J2GQuotePath(const APath: string): string;

// Tag name valid for 'git check-ref-format refs/tags/<name>' (full rule set,
// see plan 10.8); empty or '@' -> 'label-<LabelID>'.
function J2GSanitizeTagName(const AName: string; ALabelID: Integer): string;

// Sets TagName of every label of the project; collisions compared
// case-insensitive (loose refs on Windows) get '-<LabelID>'.
procedure J2GAssignTagNames(AProject: TJ2GProject);

// Repository folder name from the project name: without extension, sanitized
// for the file system (J2GSanitizeComponent); never empty.
function J2GRepoFolderName(const AProjectName: string): string;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults;

const
  // tag names longer than this are cut (loose refs are files: MAX_PATH)
  TagMaxLength = 120;

// server folder: '/' -> '\', lower case, ends with '\' ('' stays '')
function NormalizeFolder(const AFolder: string): string;
begin
  Result := LowerCase(Trim(StringReplace(AFolder, '/', '\', [rfReplaceAll])));
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result);
end;

// server folder of a module (Name may carry the folder, jvcs.dpr:4316)
function ModuleFolder(AModule: TJ2GModule): string;
begin
  if Pos('\', AModule.Name) > 0 then
    Result := NormalizeFolder(ExtractFilePath(AModule.Name))
  else
    Result := NormalizeFolder(AModule.Path);
end;

function ModuleFileName(AModule: TJ2GModule): string;
begin
  Result := ExtractFileName(AModule.Name);
end;

// 'c:\a\b\' -> ['c:', 'a', 'b']; '\\srv\share\x\' -> ['', '', 'srv', 'share', 'x']
function SplitFolder(const AFolder: string): TArray<string>;
var
  S: string;
begin
  S := AFolder;
  if (S <> '') and (S[Length(S)] = '\') then
    Delete(S, Length(S), 1);
  if S = '' then
    Result := nil
  else
    Result := S.Split(['\']);
end;

// minimum number of components of a usable root: 'c:' (1) or '\\srv\share' (4)
function RootIsUsable(const AParts: TArray<string>; ACount: Integer): Boolean;
begin
  if ACount <= 0 then
    Exit(False);
  if AParts[0] = '' then
    Result := (ACount >= 4) and (Length(AParts) >= 4) and (AParts[1] = '') and
      (AParts[2] <> '') and (AParts[3] <> '')
  else
    Result := True;
end;

function J2GChooseRoot(AProject: TJ2GProject; const AOptionRoot: string): string;
var
  M: TJ2GModule;
  Common, Parts: TArray<string>;
  Count, I: Integer;
  Folder: string;
  First: Boolean;
begin
  Result := '';
  if Trim(AOptionRoot) <> '' then
    Result := NormalizeFolder(AOptionRoot)
  else
  begin
    // 1) folder of the module named like the project (the .dpr)
    for M in AProject.Modules do
      if SameText(ModuleFileName(M), ExtractFileName(AProject.Name)) then
      begin
        Folder := ModuleFolder(M);
        if Folder <> '' then
        begin
          Result := Folder;
          Break;
        end;
      end;
    // 2) longest common folder prefix, compared by component
    if Result = '' then
    begin
      First := True;
      Count := 0;
      for M in AProject.Modules do
      begin
        Folder := ModuleFolder(M);
        if Folder = '' then
          Continue;
        Parts := SplitFolder(Folder);
        if First then
        begin
          Common := Parts;
          Count := Length(Parts);
          First := False;
        end
        else
        begin
          if Length(Parts) < Count then
            Count := Length(Parts);
          for I := 0 to Count - 1 do
            if Parts[I] <> Common[I] then
            begin
              Count := I;
              Break;
            end;
        end;
      end;
      if not First and RootIsUsable(Common, Count) then
      begin
        for I := 0 to Count - 1 do
          Result := Result + Common[I] + '\';
      end;
    end;
  end;
  AProject.Root := Result;
end;

function IsReservedBase(const ABase: string): Boolean;
var
  B: string;
begin
  B := LowerCase(TrimRight(ABase));
  Result := (B = 'con') or (B = 'prn') or (B = 'aux') or (B = 'nul') or
    (B = 'conin$') or (B = 'conout$') or
    ((Length(B) = 4) and ((Copy(B, 1, 3) = 'com') or (Copy(B, 1, 3) = 'lpt')) and
     CharInSet(B[4], ['1'..'9']));
end;

function J2GSanitizeComponent(const S: string): string;
var
  I, P: Integer;
  C: Char;
begin
  Result := S;
  for I := 1 to Length(Result) do
  begin
    C := Result[I];
    if (Ord(C) < 32) or CharInSet(C, ['<', '>', ':', '"', '|', '?', '*', '/', '\']) then
      Result[I] := '_';
  end;
  // trailing dots and spaces are dropped by Windows ('sub.' == 'sub')
  while (Result <> '') and CharInSet(Result[Length(Result)], ['.', ' ']) do
    Delete(Result, Length(Result), 1);
  if Result = '' then
    Exit('_');
  // reserved device names, with or without extension ('nul.pas')
  P := Pos('.', Result);
  if P > 0 then
  begin
    if IsReservedBase(Copy(Result, 1, P - 1)) then
      Result := '_' + Result;
  end
  else if IsReservedBase(Result) then
    Result := '_' + Result;
  // never a '.git' component (git refuses it; 'git~1' is its NTFS short name)
  if SameText(Result, '.git') or SameText(Result, 'git~1') then
    Result := '_' + Result;
end;

function J2GRelativeFolder(const AServerFolder, ARoot: string; out AChanged: Boolean): string;
var
  Folder, Root, Rest, Prefix, Part, Clean: string;
  Parts: TArray<string>;
begin
  AChanged := False;
  Folder := NormalizeFolder(AServerFolder);
  Root := NormalizeFolder(ARoot);
  Prefix := '';
  if Folder = '' then
    Exit('');
  if (Root <> '') and SameText(Copy(Folder, 1, Length(Root)), Root) then
    Rest := Copy(Folder, Length(Root) + 1, MaxInt)
  else if (Length(Folder) >= 2) and (Folder[2] = ':') and CharInSet(Folder[1], ['a'..'z', 'A'..'Z']) then
  begin
    // 'c:\lib\' -> '_externos/c/lib/' (no ':' from ExtractFileDrive)
    Prefix := '_externos/' + LowerCase(Folder[1]) + '/';
    Rest := Copy(Folder, 3, MaxInt);
  end
  else if Copy(Folder, 1, 2) = '\\' then
  begin
    // '\\srv\share\lib\' -> '_externos/unc/srv/share/lib/'
    Prefix := '_externos/unc/';
    Rest := Copy(Folder, 3, MaxInt);
  end
  else
    Rest := Folder;   // relative folder: taken as inside the root
  Result := Prefix;
  Parts := Rest.Split(['\']);
  for Part in Parts do
  begin
    if Part = '' then
      Continue;       // 'a\\b', leading/trailing separators
    Clean := J2GSanitizeComponent(Part);
    if Clean <> Part then
      AChanged := True;
    Result := Result + Clean + '/';
  end;
end;

procedure J2GChooseDisplayName(AModule: TJ2GModule; const AZipName: string);
var
  ServerName, ZipName: string;
begin
  ServerName := ModuleFileName(AModule);
  ZipName := ExtractFileName(StringReplace(AZipName, '/', '\', [rfReplaceAll]));
  if (ZipName <> '') and SameText(ZipName, ServerName) then
    AModule.DisplayName := ZipName
  else
    AModule.DisplayName := ServerName;
end;

// file name of a member: the module extension keeps the display name,
// other members get the base name with their (lower case) extension
function MemberFileName(const AName, AModuleExt, AMemberExt: string): string;
begin
  if SameText(AMemberExt, AModuleExt) then
    Result := AName
  else
    Result := ChangeFileExt(AName, LowerCase(AMemberExt));
end;

function J2GAssignPaths(AProject: TJ2GProject; AReport: TJ2GReport; AStrictCase: Boolean): Boolean;
var
  Owners: TDictionary<string, Integer>; // lower case full path -> ModuleID
  Sorted: TList<TJ2GModule>;
  Exts: TStringList;
  M: TJ2GModule;
  R: TJ2GRevision;
  I: Integer;
  Changed, Collided, AnyCollision: Boolean;
  BaseName, CleanName, ModuleExt, Key: string;
  OwnerID: Integer;

  function Collides(const AName: string; out AOwnerID: Integer): Boolean;
  var
    J: Integer;
  begin
    for J := 0 to Exts.Count - 1 do
      if Owners.TryGetValue(LowerCase(M.RelPath + MemberFileName(AName, ModuleExt, Exts[J])), AOwnerID) and
        (AOwnerID <> M.ModuleID) then
        Exit(True);
    AOwnerID := 0;
    Result := False;
  end;

begin
  AnyCollision := False;
  Owners := TDictionary<string, Integer>.Create;
  Sorted := TList<TJ2GModule>.Create;
  Exts := TStringList.Create;
  try
    Exts.Sorted := True;
    Exts.Duplicates := dupIgnore;
    Exts.CaseSensitive := False;
    // deterministic: the module with the lowest ModuleID keeps its spelling
    Sorted.AddRange(AProject.Modules);
    Sorted.Sort(TComparer<TJ2GModule>.Construct(
      function(const A, B: TJ2GModule): Integer
      begin
        Result := A.ModuleID - B.ModuleID;
      end));
    for M in Sorted do
    begin
      M.RelPath := J2GRelativeFolder(ModuleFolder(M), AProject.Root, Changed);
      if M.DisplayName <> '' then
        BaseName := M.DisplayName
      else
        BaseName := ModuleFileName(M);
      CleanName := J2GSanitizeComponent(BaseName);
      if CleanName <> BaseName then
        Changed := True;
      ModuleExt := LowerCase(ExtractFileExt(BaseName));
      // every extension the module ever had
      Exts.Clear;
      Exts.Add(ModuleExt);
      for R in M.Revisions do
        for I := 0 to High(R.Members) do
          Exts.Add(LowerCase(R.Members[I].Ext));
      // case-insensitive collision with another module
      Collided := Collides(CleanName, OwnerID);
      if Collided then
      begin
        CleanName := ChangeFileExt(CleanName, '') + '-' + IntToStr(M.ModuleID) + ExtractFileExt(CleanName);
        AnyCollision := True;
        if Assigned(AReport) then
          AReport.Warn(Format('case collision: %s (module %d) collides with module %d; written as %s',
            [M.FullServerName, M.ModuleID, OwnerID, M.RelPath + CleanName]));
        if Collides(CleanName, OwnerID) and Assigned(AReport) then
          AReport.Warn(Format('path still collides after renaming: %s', [M.RelPath + CleanName]));
      end
      else if Changed and Assigned(AReport) then
        AReport.Warn(Format('path altered for Git for Windows: %s -> %s',
          [M.FullServerName, M.RelPath + CleanName]));
      // the final spelling is what the stream writes (RelPath + DisplayName)
      M.DisplayName := CleanName;
      for I := 0 to Exts.Count - 1 do
      begin
        Key := LowerCase(M.RelPath + MemberFileName(CleanName, ModuleExt, Exts[I]));
        if not Owners.ContainsKey(Key) then
          Owners.Add(Key, M.ModuleID);
      end;
      for R in M.Revisions do
        for I := 0 to High(R.Members) do
          R.Members[I].Path := M.RelPath + MemberFileName(CleanName, ModuleExt, R.Members[I].Ext);
    end;
  finally
    Exts.Free;
    Sorted.Free;
    Owners.Free;
  end;
  Result := not (AnyCollision and AStrictCase);
end;

function J2GQuotePath(const APath: string): string;
var
  C: Char;
  Need: Boolean;
begin
  // implemented in PT0 (used by J2GFastImport); quoted when it has a space,
  // a quote, a backslash or a control char, or starts with '"'
  Need := APath = '';
  for C in APath do
    if (C = '"') or (C = '\') or (C = ' ') or (Ord(C) < 32) or (Ord(C) = 127) then
    begin
      Need := True;
      Break;
    end;
  if not Need then
    Exit(APath);
  Result := '"';
  for C in APath do
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #7: Result := Result + '\a';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #11: Result := Result + '\v';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if (Ord(C) < 32) or (Ord(C) = 127) then
        Result := Result + '\' + IntToStr(Ord(C) div 64) + IntToStr((Ord(C) div 8) mod 8) + IntToStr(Ord(C) mod 8)
      else
        Result := Result + C;
    end;
  Result := Result + '"';
end;

// one component of a tag name: no leading '.', no trailing '.' or '.lock',
// no '-' at the ends (cosmetic); repeated until stable
function CleanTagComponent(const S: string): string;
var
  Old: string;
begin
  Result := S;
  repeat
    Old := Result;
    while (Result <> '') and (Result[1] = '-') do
      Delete(Result, 1, 1);
    while (Result <> '') and (Result[Length(Result)] = '-') do
      Delete(Result, Length(Result), 1);
    while (Result <> '') and (Result[1] = '.') do
      Delete(Result, 1, 1);
    while (Result <> '') and (Result[Length(Result)] = '.') do
      Delete(Result, Length(Result), 1);
    if (Length(Result) >= 5) and SameText(Copy(Result, Length(Result) - 4, 5), '.lock') then
      Delete(Result, Length(Result) - 4, 5);
  until Result = Old;
  // loose refs are files on Windows: no device names
  if (Result <> '') and IsReservedBase(Copy(Result, 1, Pos('.', Result + '.') - 1)) then
    Result := Result + '_';
end;

function J2GSanitizeTagName(const AName: string; ALabelID: Integer): string;
var
  S, Part, Joined: string;
  I: Integer;
  C: Char;
  Parts: TArray<string>;
begin
  S := Trim(AName);
  // git check-ref-format: no control chars, DEL, space ~ ^ : ? * [ \ ; also
  // < > | " (invalid in Windows file names, loose refs are files)
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (Ord(C) < 32) or (Ord(C) = 127) or
      CharInSet(C, [' ', '~', '^', ':', '?', '*', '[', '\', '<', '>', '|', '"']) then
      S[I] := '-';
  end;
  while Pos('..', S) > 0 do
    S := StringReplace(S, '..', '-', [rfReplaceAll]);
  while Pos('@{', S) > 0 do
    S := StringReplace(S, '@{', '-', [rfReplaceAll]);
  while Pos('--', S) > 0 do
    S := StringReplace(S, '--', '-', [rfReplaceAll]);
  if Length(S) > TagMaxLength then
    S := Copy(S, 1, TagMaxLength);
  // per component; empty components dropped ('//', leading/trailing '/')
  Joined := '';
  Parts := S.Split(['/']);
  for Part in Parts do
  begin
    S := CleanTagComponent(Part);
    if S = '' then
      Continue;
    if Joined <> '' then
      Joined := Joined + '/';
    Joined := Joined + S;
  end;
  if (Joined = '') or (Joined = '@') then
    Joined := 'label-' + IntToStr(ALabelID);
  Result := Joined;
end;

// True when two tag names cannot coexist as loose refs on Windows: equal
// ignoring case, or one is a "folder" of the other ('a' and 'a/b')
function TagNamesConflict(const A, B: string): Boolean;
var
  LA, LB: string;
begin
  LA := LowerCase(A);
  LB := LowerCase(B);
  Result := (LA = LB) or (Copy(LA, 1, Length(LB) + 1) = LB + '/') or
    (Copy(LB, 1, Length(LA) + 1) = LA + '/');
end;

procedure J2GAssignTagNames(AProject: TJ2GProject);
var
  Sorted: TList<TJ2GLabel>;
  Used: TStringList;
  L: TJ2GLabel;
  Name: string;

  function Conflicts(const AName: string): Boolean;
  var
    J: Integer;
  begin
    for J := 0 to Used.Count - 1 do
      if TagNamesConflict(AName, Used[J]) then
        Exit(True);
    Result := False;
  end;

begin
  Sorted := TList<TJ2GLabel>.Create;
  Used := TStringList.Create;
  try
    Sorted.AddRange(AProject.Labels);
    Sorted.Sort(TComparer<TJ2GLabel>.Construct(
      function(const A, B: TJ2GLabel): Integer
      begin
        Result := A.LabelID - B.LabelID;
      end));
    for L in Sorted do
    begin
      Name := J2GSanitizeTagName(L.Name, L.LabelID);
      if Conflicts(Name) then
      begin
        Name := Name + '-' + IntToStr(L.LabelID);
        // 'a' x 'a/b': a suffix does not help while the name keeps the
        // folder of another tag, so the name is flattened
        if Conflicts(Name) then
          Name := StringReplace(Name, '/', '-', [rfReplaceAll]);
        while Conflicts(Name) do
          Name := Name + '-' + IntToStr(L.LabelID);
      end;
      L.TagName := Name;
      Used.Add(Name);
    end;
  finally
    Used.Free;
    Sorted.Free;
  end;
end;

function J2GRepoFolderName(const AProjectName: string): string;
var
  S: string;
begin
  S := Trim(StringReplace(AProjectName, '/', '\', [rfReplaceAll]));
  S := ExtractFileName(S);
  S := ChangeFileExt(S, '');
  Result := J2GSanitizeComponent(Trim(S));
end;

end.
