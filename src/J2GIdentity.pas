(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GIdentity.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - identities saved by the JEDI VCS client in
HKCU\Software\JEDI\JEDIVCS\Identities\<name> (HostName, Port, User,
Password = Base64 of the ANSI bytes) and the Blowfish key of the client
(HKCU\Software\JEDI\JEDIVCS\Options\EncodeKey, Base64).
The password and the key are only returned as bytes: never shown, logged or
converted to text here. Callers must zero them after use.

-----------------------------------------------------------------------------*)

unit J2GIdentity;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes;

const
  J2G_REG_BASE = 'Software\JEDI\JEDIVCS';
  J2G_REG_IDENTITIES = J2G_REG_BASE + '\Identities';
  J2G_REG_OPTIONS = J2G_REG_BASE + '\Options';

type
  TJ2GIdentity = record
    Name: string;        // name as stored in the registry (case preserved)
    HostName: string;
    Port: string;
    User: string;
    HasPassword: Boolean;
  end;

// names of the saved identities (sorted); the last used first when known
function J2GListIdentities: TArray<string>;
// loads an identity (case-insensitive name). False + AError when missing/incomplete.
function J2GLoadIdentity(const AName: string; out AIdent: TJ2GIdentity; out AError: string): Boolean;
// password bytes (ANSI) of the identity; raises EJ2GError(4) when absent/corrupt
function J2GIdentityPasswordBytes(const AIdent: TJ2GIdentity): TBytes;
// Blowfish key saved by the client (Options\EncodeKey); nil when absent/invalid
function J2GRegistryEncodeKey: TBytes;
// decodes Base64 text to bytes; nil when invalid
function J2GDecodeBase64(const AText: string): TBytes;
// zeroes and frees a byte array
procedure J2GWipe(var ABytes: TBytes);

implementation

uses
  System.Win.Registry, Winapi.Windows, System.NetEncoding, J2GModel;

procedure J2GWipe(var ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    FillChar(ABytes[0], Length(ABytes), 0);
  ABytes := nil;
end;

function J2GDecodeBase64(const AText: string): TBytes;
var
  S: string;
  I: Integer;
begin
  Result := nil;
  S := Trim(AText);
  if S = '' then
    Exit;
  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['A'..'Z', 'a'..'z', '0'..'9', '+', '/', '=', #13, #10]) then
      Exit;
  try
    Result := TNetEncoding.Base64.DecodeStringToBytes(S);
  except
    Result := nil;
  end;
end;

function OpenRead(Reg: TRegistry; const AKey: string): Boolean;
begin
  Reg.RootKey := HKEY_CURRENT_USER;
  Result := Reg.OpenKeyReadOnly(AKey);
end;

function J2GListIdentities: TArray<string>;
var
  Reg: TRegistry;
  Names: TStringList;
  LastName: string;
  I: Integer;
begin
  Result := nil;
  Reg := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.CaseSensitive := False;
    LastName := '';
    if OpenRead(Reg, J2G_REG_IDENTITIES) then
    begin
      Reg.GetKeyNames(Names);
      if Reg.ValueExists('LastUsedID') then
      begin
        I := -1;
        try
          case Reg.GetDataType('LastUsedID') of
            rdInteger: I := Reg.ReadInteger('LastUsedID');
            rdString, rdExpandString: I := StrToIntDef(Reg.ReadString('LastUsedID'), -1);
          end;
        except
          I := -1;
        end;
        if (I >= 0) and Reg.ValueExists('ID' + IntToStr(I)) then
          try
            LastName := Reg.ReadString('ID' + IntToStr(I));
          except
            LastName := '';
          end;
      end;
      Reg.CloseKey;
    end;
  except
    // a broken registry entry must not stop the tool: treat as empty
  end;
  try
    if (LastName <> '') and (Names.IndexOf(LastName) >= 0) then
    begin
      Names.Sorted := False;
      I := Names.IndexOf(LastName);
      if I > 0 then
      begin
        Names.Delete(I);
        Names.Insert(0, LastName);
      end;
    end;
    SetLength(Result, Names.Count);
    for I := 0 to Names.Count - 1 do
      Result[I] := Names[I];
  finally
    Names.Free;
    Reg.Free;
  end;
end;

function ReadStr(Reg: TRegistry; const AName: string): string;
begin
  Result := '';
  if not Reg.ValueExists(AName) then
    Exit;
  case Reg.GetDataType(AName) of
    rdString, rdExpandString: Result := Reg.ReadString(AName);
    rdInteger: Result := IntToStr(Reg.ReadInteger(AName));
  end;
end;

function J2GLoadIdentity(const AName: string; out AIdent: TJ2GIdentity; out AError: string): Boolean;
var
  Reg: TRegistry;
  Names: TStringList;
  I: Integer;
begin
  AIdent := Default(TJ2GIdentity);
  AError := '';
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    if not OpenRead(Reg, J2G_REG_IDENTITIES) then
    begin
      AError := 'no saved identities (HKCU\' + J2G_REG_IDENTITIES + ')';
      Exit;
    end;
    Reg.GetKeyNames(Names);
    Reg.CloseKey;
    for I := 0 to Names.Count - 1 do
      if SameText(Names[I], AName) then
      begin
        AIdent.Name := Names[I];
        Break;
      end;
    if AIdent.Name = '' then
    begin
      AError := Format('identity ''%s'' not found', [AName]);
      Exit;
    end;
    if not OpenRead(Reg, J2G_REG_IDENTITIES + '\' + AIdent.Name) then
    begin
      AError := Format('identity ''%s'' cannot be read', [AIdent.Name]);
      Exit;
    end;
    AIdent.HostName := Trim(ReadStr(Reg, 'HostName'));
    AIdent.Port := Trim(ReadStr(Reg, 'Port'));
    AIdent.User := Trim(ReadStr(Reg, 'User'));
    // only checks that a value exists: the content is read by J2GIdentityPasswordBytes
    AIdent.HasPassword := Reg.ValueExists('Password') and (Reg.GetDataSize('Password') > 2);
    Reg.CloseKey;
    if AIdent.Port = '' then
      AIdent.Port := '2106';
    if (AIdent.HostName = '') or (AIdent.User = '') then
    begin
      AError := Format('identity ''%s'' is incomplete (HostName/User)', [AIdent.Name]);
      Exit;
    end;
    Result := True;
  finally
    Names.Free;
    Reg.Free;
  end;
end;

function J2GIdentityPasswordBytes(const AIdent: TJ2GIdentity): TBytes;
var
  Reg: TRegistry;
  S: string;
begin
  Result := nil;
  Reg := TRegistry.Create(KEY_READ);
  try
    if not OpenRead(Reg, J2G_REG_IDENTITIES + '\' + AIdent.Name) then
      raise EJ2GError.CreateFmt(J2G_EXIT_CREDENTIAL, 'identity ''%s'' cannot be read', [AIdent.Name]);
    S := ReadStr(Reg, 'Password');
    Reg.CloseKey;
    if S = '' then
      raise EJ2GError.CreateFmt(J2G_EXIT_CREDENTIAL,
        'identity ''%s'' has no saved password (check "Store Password with identity" in the JEDI VCS client)', [AIdent.Name]);
    Result := J2GDecodeBase64(S);
    // the text form is not needed any more
    if S <> '' then
      FillChar(PChar(S)^, Length(S) * SizeOf(Char), 0);
    if Length(Result) = 0 then
      raise EJ2GError.CreateFmt(J2G_EXIT_CREDENTIAL, 'saved password of identity ''%s'' is corrupt (invalid Base64)', [AIdent.Name]);
  finally
    Reg.Free;
  end;
end;

function J2GRegistryEncodeKey: TBytes;
var
  Reg: TRegistry;
  S: string;
begin
  Result := nil;
  Reg := TRegistry.Create(KEY_READ);
  try
    if OpenRead(Reg, J2G_REG_OPTIONS) then
    begin
      S := ReadStr(Reg, 'EncodeKey');
      Reg.CloseKey;
      if S <> '' then
      begin
        Result := J2GDecodeBase64(S);
        FillChar(PChar(S)^, Length(S) * SizeOf(Char), 0);
      end;
    end;
  finally
    Reg.Free;
  end;
end;

end.
