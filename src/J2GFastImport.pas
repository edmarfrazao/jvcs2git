(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GFastImport.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - writer of the git fast-import stream (a file; blobs are never all
kept in memory). Text (paths, idents, messages) is written in UTF-8; 'data'
counts bytes. The first line is 'feature done' and 'done' is written only by
Close(True), so a truncated stream is rejected by git fast-import.
Dates are never negative (assert + fallback to now). Interface frozen in PT0;
implemented in PT3.

-----------------------------------------------------------------------------*)

unit J2GFastImport;

{$I jedi.inc}
{$I compopt.inc}

interface

uses
  System.SysUtils, System.Classes;

type
  TJ2GFastImportWriter = class
  private
    FStream: TStream;
    FFileName: string;
    FNextMark: Integer;
    FBytes: Int64;
    FInCommit: Boolean;
    procedure WriteBytes(const ABytes: TBytes);
    procedure WriteText(const S: string);
    procedure WriteData(const ABytes: TBytes);
    procedure CheckOpen;
  public
    // creates/overwrites AFileName and writes 'feature done'
    constructor Create(const AFileName: string);
    destructor Destroy; override;   // closes without 'done' if Close was not called
    // writes 'done' when ASuccess, then closes the file
    procedure Close(ASuccess: Boolean);
    // next free mark (1, 2, 3...)
    function NewMark: Integer;
    // 'commit <ARef>' + 'mark :<AMark>' + author/committer + message + 'from'
    // (AFromMark = 0 -> no 'from', first commit). AAuthor/ACommitter =
    // 'Name <email>'. Dates in UTC; AOffsetMinutes is the zone written after the
    // seconds ('+0000' when 0). AMessage is normalized: CRLF/CR -> LF, control
    // chars < #32 removed except LF/TAB, ends with LF.
    procedure BeginCommit(const ARef: string; AMark: Integer;
      const AAuthor: string; AAuthorDate: TDateTime; AAuthorOffset: Integer;
      const ACommitter: string; ACommitterDate: TDateTime; ACommitterOffset: Integer;
      const AMessage: string; AFromMark: Integer);
    // 'M 100644 inline <path>' + 'data <n>' + bytes (path quoted by J2GQuotePath)
    procedure FileModify(const APath: string; const AData: TBytes);
    // 'D <path>'
    procedure FileDelete(const APath: string);
    procedure EndCommit;
    // annotated tag: 'tag <AName>' 'from :<AFromMark>' 'tagger ...' 'data ...'
    procedure Tag(const AName: string; AFromMark: Integer; const ATagger: string;
      ADate: TDateTime; AOffset: Integer; const AMessage: string);
    function BytesWritten: Int64;
    function FileName: string;
  end;

// seconds since 1970-01-01 UTC: Round((ADate - UnixDateDelta) * SecsPerDay)
function J2GUnixTime(ADateUtc: TDateTime): Int64;
// '<seconds> +hhmm' / '-hhmm'
function J2GGitDate(ADateUtc: TDateTime; AOffsetMinutes: Integer): string;
// local UTC offset in minutes at ADateUtc (for -localtime)
function J2GLocalOffsetMinutes(ADateUtc: TDateTime): Integer;
// commit message normalization used by BeginCommit/Tag
function J2GNormalizeMessage(const AMessage: string): string;

implementation

uses
  System.DateUtils, J2GPaths;

const
  LF = #10;

// 'Name <email>' as one line: control chars removed
function CleanIdent(const S: string): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(S));
  try
    for C in S do
      if Ord(C) >= 32 then
        SB.Append(C);
    Result := Trim(SB.ToString);
  finally
    SB.Free;
  end;
end;

function NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

function J2GUnixTime(ADateUtc: TDateTime): Int64;
begin
  Result := Round((ADateUtc - UnixDateDelta) * SecsPerDay);
end;

function J2GGitDate(ADateUtc: TDateTime; AOffsetMinutes: Integer): string;
var
  Secs: Int64;
  Sign: Char;
  M: Integer;
begin
  Secs := J2GUnixTime(ADateUtc);
  // git fast-import reads the seconds with strtoul, which accepts a '-': a
  // negative date would be stored (fsck badDate). Never write one (the export
  // validates the dates before; this is the last fallback).
  if Secs < 0 then
    Secs := J2GUnixTime(NowUtc);
  if AOffsetMinutes < 0 then
    Sign := '-'
  else
    Sign := '+';
  M := Abs(AOffsetMinutes);
  Result := Format('%d %s%.2d%.2d', [Secs, Sign, M div 60, M mod 60]);
end;

function J2GLocalOffsetMinutes(ADateUtc: TDateTime): Integer;
var
  LocalDT: TDateTime;
begin
  try
    LocalDT := TTimeZone.Local.ToLocalTime(ADateUtc);
    Result := Round(TTimeZone.Local.GetUtcOffset(LocalDT).TotalMinutes);
  except
    Result := 0;
  end;
end;

function J2GNormalizeMessage(const AMessage: string): string;
var
  SB: TStringBuilder;
  I, L: Integer;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(AMessage) + 1);
  try
    I := 1;
    L := Length(AMessage);
    while I <= L do
    begin
      C := AMessage[I];
      if C = #13 then
      begin
        SB.Append(LF);
        if (I < L) and (AMessage[I + 1] = #10) then
          Inc(I);
      end
      else if (C = #10) or (C = #9) or (Ord(C) >= 32) then
        SB.Append(C);
      Inc(I);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
  // exactly one LF at the end (an empty message stays empty)
  L := Length(Result);
  while (L > 0) and (Result[L] = LF) do
    Dec(L);
  SetLength(Result, L);
  if Result <> '' then
    Result := Result + LF;
end;

{ TJ2GFastImportWriter }

constructor TJ2GFastImportWriter.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FNextMark := 1;
  FStream := TBufferedFileStream.Create(AFileName, fmCreate, 1024 * 1024);
  WriteText('feature done' + LF);
end;

destructor TJ2GFastImportWriter.Destroy;
begin
  try
    Close(False);
  except
    // never raise from the destructor (disk full while flushing...)
  end;
  inherited Destroy;
end;

procedure TJ2GFastImportWriter.CheckOpen;
begin
  if not Assigned(FStream) then
    raise EInOutError.CreateFmt('fast-import stream %s is closed', [FFileName]);
end;

procedure TJ2GFastImportWriter.WriteBytes(const ABytes: TBytes);
begin
  CheckOpen;
  if Length(ABytes) > 0 then
  begin
    FStream.WriteBuffer(ABytes[0], Length(ABytes));
    Inc(FBytes, Length(ABytes));
  end;
end;

procedure TJ2GFastImportWriter.WriteText(const S: string);
begin
  WriteBytes(TEncoding.UTF8.GetBytes(S));
end;

procedure TJ2GFastImportWriter.WriteData(const ABytes: TBytes);
begin
  // 'data <n>' counts bytes; the LF after the data is optional (readability)
  WriteText('data ' + IntToStr(Length(ABytes)) + LF);
  WriteBytes(ABytes);
  WriteText(LF);
end;

procedure TJ2GFastImportWriter.Close(ASuccess: Boolean);
var
  S: TStream;
begin
  if not Assigned(FStream) then
    Exit;
  try
    if ASuccess then
    begin
      if FInCommit then
        EndCommit;
      WriteText('done' + LF);
    end;
  finally
    S := FStream;
    FStream := nil;
    S.Free;   // flushes the buffer
  end;
end;

function TJ2GFastImportWriter.NewMark: Integer;
begin
  Result := FNextMark;
  Inc(FNextMark);
end;

procedure TJ2GFastImportWriter.BeginCommit(const ARef: string; AMark: Integer;
  const AAuthor: string; AAuthorDate: TDateTime; AAuthorOffset: Integer;
  const ACommitter: string; ACommitterDate: TDateTime; ACommitterOffset: Integer;
  const AMessage: string; AFromMark: Integer);
begin
  if FInCommit then
    EndCommit;
  WriteText('commit ' + ARef + LF);
  if AMark > 0 then
  begin
    WriteText('mark :' + IntToStr(AMark) + LF);
    if AMark >= FNextMark then
      FNextMark := AMark + 1;
  end;
  WriteText('author ' + CleanIdent(AAuthor) + ' ' + J2GGitDate(AAuthorDate, AAuthorOffset) + LF);
  WriteText('committer ' + CleanIdent(ACommitter) + ' ' + J2GGitDate(ACommitterDate, ACommitterOffset) + LF);
  WriteData(TEncoding.UTF8.GetBytes(J2GNormalizeMessage(AMessage)));
  if AFromMark > 0 then
    WriteText('from :' + IntToStr(AFromMark) + LF);
  FInCommit := True;
end;

procedure TJ2GFastImportWriter.FileModify(const APath: string; const AData: TBytes);
begin
  WriteText('M 100644 inline ' + J2GQuotePath(APath) + LF);
  WriteData(AData);
end;

procedure TJ2GFastImportWriter.FileDelete(const APath: string);
begin
  WriteText('D ' + J2GQuotePath(APath) + LF);
end;

procedure TJ2GFastImportWriter.EndCommit;
begin
  WriteText(LF);
  FInCommit := False;
end;

procedure TJ2GFastImportWriter.Tag(const AName: string; AFromMark: Integer; const ATagger: string;
  ADate: TDateTime; AOffset: Integer; const AMessage: string);
begin
  if FInCommit then
    EndCommit;
  WriteText('tag ' + AName + LF);
  WriteText('from :' + IntToStr(AFromMark) + LF);
  WriteText('tagger ' + CleanIdent(ATagger) + ' ' + J2GGitDate(ADate, AOffset) + LF);
  WriteData(TEncoding.UTF8.GetBytes(J2GNormalizeMessage(AMessage)));
end;

function TJ2GFastImportWriter.BytesWritten: Int64;
begin
  Result := FBytes;
end;

function TJ2GFastImportWriter.FileName: string;
begin
  Result := FFileName;
end;

end.
