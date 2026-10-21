(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GAuthors.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - author map (autores.txt). One line per login:
    login=Full Name <e-mail>
'#' starts a comment; blank lines ignored; logins compared case-insensitive.
Default for a login not in the file: 'login <login@<domain>>' (unmapped).
File in UTF-8 (BOM accepted when reading; written with BOM and CRLF so that
Notepad keeps accents). Interface frozen in PT0; implemented in PT2.

-----------------------------------------------------------------------------*)

unit J2GAuthors;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TJ2GAuthorEntry = record
    Login: string;   // spelling of the file (or of the server)
    Name: string;
    Email: string;
  end;

  TJ2GAuthorMap = class
  private
    FDomain: string;
    FEntries: TDictionary<string, TJ2GAuthorEntry>; // key: lower case login
    function DefaultEmail(const ALogin: string): string;
    function DefaultEntry(const ALogin: string): TJ2GAuthorEntry;
    function EntryIsDefault(const AEntry: TJ2GAuthorEntry): Boolean;
    class function Key(const ALogin: string): string; static;
  public
    constructor Create(const AEmailDomain: string);
    destructor Destroy; override;
    // loads the file (missing file = empty map); invalid lines -> AWarnings
    procedure LoadFromFile(const AFileName: string; AWarnings: TStrings = nil);
    // adds default entries for logins not in the map yet
    procedure EnsureLogins(const ALogins: array of string);
    // writes every entry (header with instructions, sorted by login)
    procedure SaveToFile(const AFileName: string);
    // 'Full Name <e-mail>' for the git author/committer/tagger lines; logins
    // not in the map get the default identity. Never empty; '<' '>' and
    // control chars removed from the name part.
    function Ident(const ALogin: string): string;
    // True when ALogin still has the default identity (not filled by the admin)
    function IsDefault(const ALogin: string): Boolean;
    // logins with the default identity, sorted
    function Unmapped: TArray<string>;
    function Count: Integer;
  end;

implementation

uses
  Winapi.Windows, System.IOUtils;

const
  // header of the generated file (ASCII; English and Portuguese)
  HeaderLines: array[0..13] of string = (
    '# jvcs2git - author map / mapa de autores',
    '#',
    '# One line per JEDI VCS login:      login=Full Name <e-mail>',
    '# Uma linha por login do JEDI VCS:  login=Nome Completo <e-mail>',
    '#',
    '# Fill in the real names and e-mails BEFORE the export: Git cannot change',
    '# the authors later without rewriting the whole history.',
    '# Preencha os nomes e e-mails reais ANTES da exportacao: o Git nao permite',
    '# corrigir os autores depois sem reescrever todo o historico.',
    '#',
    '# Logins still with "login <login@domain>" are reported as unmapped.',
    '# Logins ainda com "login <login@dominio>" sao listados como nao mapeados.',
    '# Lines starting with # are comments / Linhas com # sao comentarios.',
    '');

// removes '<', '>' and control chars; trims
function CleanIdentPart(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
    if (Ord(C) >= 32) and (Ord(C) <> 127) and (C <> '<') and (C <> '>') then
      Result := Result + C;
  Result := Trim(Result);
end;

{ TJ2GAuthorMap }

constructor TJ2GAuthorMap.Create(const AEmailDomain: string);
begin
  inherited Create;
  FDomain := Trim(AEmailDomain);
  if FDomain = '' then
    FDomain := 'jedivcs.local';
  FEntries := TDictionary<string, TJ2GAuthorEntry>.Create;
end;

destructor TJ2GAuthorMap.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

class function TJ2GAuthorMap.Key(const ALogin: string): string;
begin
  Result := LowerCase(Trim(ALogin));
end;

function TJ2GAuthorMap.DefaultEmail(const ALogin: string): string;
var
  C: Char;
  Local: string;
begin
  // local part: lower case login, only [a-z0-9._+-]
  Local := '';
  for C in LowerCase(Trim(ALogin)) do
    if CharInSet(C, ['a'..'z', '0'..'9', '.', '_', '+', '-']) then
      Local := Local + C
    else
      Local := Local + '_';
  if Local = '' then
    Local := 'unknown';
  Result := Local + '@' + FDomain;
end;

function TJ2GAuthorMap.DefaultEntry(const ALogin: string): TJ2GAuthorEntry;
begin
  Result.Login := Trim(ALogin);
  Result.Name := Result.Login;
  Result.Email := DefaultEmail(ALogin);
end;

function TJ2GAuthorMap.EntryIsDefault(const AEntry: TJ2GAuthorEntry): Boolean;
begin
  Result := SameText(Trim(AEntry.Name), Trim(AEntry.Login)) and
    SameText(AEntry.Email, DefaultEmail(AEntry.Login));
end;

procedure TJ2GAuthorMap.LoadFromFile(const AFileName: string; AWarnings: TStrings);
var
  Bytes: TBytes;
  Text, Line, Login, Value: string;
  Lines: TStringList;
  Utf8Strict: TEncoding;
  Start, I, P, LT, GT: Integer;
  E: TJ2GAuthorEntry;

  procedure AddWarning(const AMsg: string);
  begin
    if Assigned(AWarnings) then
      AWarnings.Add(Format('%s line %d: %s', [ExtractFileName(AFileName), I + 1, AMsg]));
  end;

begin
  if (AFileName = '') or not FileExists(AFileName) then
    Exit;
  Bytes := TFile.ReadAllBytes(AFileName);
  Start := 0;
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Start := 3;
  // strict UTF-8 first; a file saved as ANSI by an editor is read as ANSI
  Utf8Strict := TMBCSEncoding.Create(CP_UTF8, MB_ERR_INVALID_CHARS, 0);
  try
    try
      Text := Utf8Strict.GetString(Bytes, Start, Length(Bytes) - Start);
    except
      on EEncodingError do
      begin
        Text := TEncoding.ANSI.GetString(Bytes, Start, Length(Bytes) - Start);
        if Assigned(AWarnings) then
          AWarnings.Add(Format('%s is not UTF-8; read as ANSI', [ExtractFileName(AFileName)]));
      end;
    end;
  finally
    Utf8Strict.Free;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] = '#') then
        Continue;
      P := Pos('=', Line);
      Login := Trim(Copy(Line, 1, P - 1));
      Value := Trim(Copy(Line, P + 1, MaxInt));
      LT := Pos('<', Value);
      GT := LastDelimiter('>', Value);
      if (P < 2) or (Login = '') then
      begin
        AddWarning('expected login=Full Name <e-mail>');
        Continue;
      end;
      if (LT = 0) or (GT < LT) or (GT <> Length(Value)) or
        (Pos('<', Copy(Value, LT + 1, MaxInt)) > 0) or (Pos('>', Copy(Value, 1, GT - 1)) > 0) then
      begin
        AddWarning(Format('invalid identity for %s (expected Full Name <e-mail>)', [Login]));
        Continue;
      end;
      E.Login := Login;
      E.Name := CleanIdentPart(Copy(Value, 1, LT - 1));
      if E.Name = '' then
        E.Name := Login;
      E.Email := CleanIdentPart(Copy(Value, LT + 1, GT - LT - 1));
      if FEntries.ContainsKey(Key(Login)) then
        AddWarning(Format('login %s repeated; the last line wins', [Login]));
      FEntries.AddOrSetValue(Key(Login), E);
    end;
  finally
    Lines.Free;
  end;
end;

procedure TJ2GAuthorMap.EnsureLogins(const ALogins: array of string);
var
  L: string;
begin
  for L in ALogins do
    if (Trim(L) <> '') and not FEntries.ContainsKey(Key(L)) then
      FEntries.Add(Key(L), DefaultEntry(L));
end;

procedure TJ2GAuthorMap.SaveToFile(const AFileName: string);
var
  Keys: TArray<string>;
  K, Dir: string;
  SL: TStringList;
  E: TJ2GAuthorEntry;
begin
  SL := TStringList.Create;
  try
    SL.LineBreak := #13#10;
    SL.WriteBOM := True;
    for K in HeaderLines do
      SL.Add(K);
    Keys := FEntries.Keys.ToArray;
    TArray.Sort<string>(Keys);
    for K in Keys do
    begin
      E := FEntries[K];
      SL.Add(Format('%s=%s <%s>', [E.Login, E.Name, E.Email]));
    end;
    Dir := ExtractFileDir(ExpandFileName(AFileName));
    if Dir <> '' then
      ForceDirectories(Dir);
    SL.SaveToFile(AFileName, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

function TJ2GAuthorMap.Ident(const ALogin: string): string;
var
  E: TJ2GAuthorEntry;
  Name, Email: string;
begin
  if not FEntries.TryGetValue(Key(ALogin), E) then
    E := DefaultEntry(ALogin);
  Name := CleanIdentPart(E.Name);
  if Name = '' then
    Name := CleanIdentPart(ALogin);
  if Name = '' then
    Name := 'unknown';
  Email := CleanIdentPart(E.Email);
  Result := Name + ' <' + Email + '>';
end;

function TJ2GAuthorMap.IsDefault(const ALogin: string): Boolean;
var
  E: TJ2GAuthorEntry;
begin
  if FEntries.TryGetValue(Key(ALogin), E) then
    Result := EntryIsDefault(E)
  else
    Result := True;
end;

function TJ2GAuthorMap.Unmapped: TArray<string>;
var
  L: TStringList;
  E: TJ2GAuthorEntry;
begin
  L := TStringList.Create;
  try
    for E in FEntries.Values do
      if EntryIsDefault(E) then
        L.Add(E.Login);
    L.Sort;
    Result := L.ToStringArray;
  finally
    L.Free;
  end;
end;

function TJ2GAuthorMap.Count: Integer;
begin
  Result := FEntries.Count;
end;

end.
