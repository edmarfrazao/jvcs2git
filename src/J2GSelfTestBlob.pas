(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GSelfTestBlob.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - -selftest blob: ZIP sample, .dfm conversion, minimal stream imported by git fast-import. Implemented in PT3.

Offline: ZIP made with the client's own JVCSCompressFile (Abbrevia) and
extracted back with ExtractBlobToStream, Blowfish round trip, CRC, binary
forms ('TPF0' and $FF resource) converted to text, dates and messages of the
fast-import writer. With git on the PATH: a minimal stream is imported into a
temporary repository (deleted at the end); without git those cases are skipped
with a warning.

-----------------------------------------------------------------------------*)

unit J2GSelfTestBlob;

{$I jedi.inc}
{$I compopt.inc}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  J2GReport;

// returns 0 when every case passes
function J2GRunSelfTestBlob(AReport: TJ2GReport): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows,
  J2GModel, J2GBlob, J2GFastImport, J2GGit,
  JVCSTypes, JVCSClientObjBase, JVCSClientObj, BFCrypt, Checksum,
  AbUtils, AbArcTyp, AbZipTyp;

type
  TBlobTest = class
  private
    FReport: TJ2GReport;
    FFailures: Integer;
    FTempDir: string;
    procedure Check(ACondition: Boolean; const ACase, AFailDetail: string);
    function TempFile(const AName: string): string;
    procedure TestZip;
    procedure TestBlowfish;
    procedure TestDfm;
    procedure TestDates;
    procedure TestGit;
  public
    constructor Create(AReport: TJ2GReport);
    function Run: Integer;
  end;

const
  LF = #10;
  CRLF = #13#10;

function BytesOf(const S: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(S);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function StartsWithText(const B: TBytes; const S: string): Boolean;
var
  P: TBytes;
begin
  P := TEncoding.ASCII.GetBytes(S);
  Result := (Length(B) >= Length(P)) and CompareMem(@B[0], @P[0], Length(P));
end;

function BytesCrc(const B: TBytes): Cardinal;
var
  Dummy: Byte;
begin
  if Length(B) = 0 then
    Result := CRC32OfBuffer(Dummy, 0)
  else
    Result := CRC32OfBuffer(B[0], Length(B));
end;

// sample content with every byte value and CRLF (content must not change)
function SampleContent: TBytes;
var
  I: Integer;
  Head: TBytes;
begin
  Head := BytesOf('unit Unit1;' + CRLF + CRLF + 'interface' + CRLF + 'end.' + CRLF);
  SetLength(Result, Length(Head) + 512);
  Move(Head[0], Result[0], Length(Head));
  for I := 0 to 511 do
    Result[Length(Head) + I] := Byte(I mod 256);
end;

// deletes a folder tree, also read-only files (git objects are read-only)
procedure DeleteTree(const ADir: string);
var
  F, D: string;
begin
  if not DirectoryExists(ADir) then
    Exit;
  for F in TDirectory.GetFiles(ADir, '*', TSearchOption.soAllDirectories) do
  begin
    FileSetAttr(F, faNormal);
    System.SysUtils.DeleteFile(F);
  end;
  for D in TDirectory.GetDirectories(ADir, '*', TSearchOption.soTopDirectoryOnly) do
    DeleteTree(D);
  RemoveDir(ADir);
end;

// unzip as J2GBlob does: ExtractBlobToStream of the client + name of item 0
function Unzip(ASource: TStream; out AContent: TBytes; out AName: string): Boolean;
var
  Obj: TJVCSGetSingleBlob;
  Dest: TBytesStream;
  Archive: TAbZipArchive;
begin
  AName := '';
  AContent := nil;
  Obj := TJVCSGetSingleBlob.Create(nil);
  Dest := TBytesStream.Create;
  try
    ASource.Position := 0;
    Result := Obj.ExtractBlobToStream(ASource, Dest);
    if Result then
    begin
      AContent := Copy(Dest.Bytes, 0, Dest.Size);
      ASource.Position := 0;
      Archive := TAbZipArchive.CreateFromStream(ASource, 'AbArchive');
      try
        Archive.Load;
        if Archive.ItemList.Count > 0 then
          AName := Archive.Items[0].FileName;
      finally
        Archive.Free;
      end;
    end;
  finally
    Dest.Free;
    Obj.Free;
  end;
end;

{ TBlobTest }

constructor TBlobTest.Create(AReport: TJ2GReport);
begin
  inherited Create;
  FReport := AReport;
end;

procedure TBlobTest.Check(ACondition: Boolean; const ACase, AFailDetail: string);
begin
  if ACondition then
    FReport.Info('ok   ' + ACase)
  else
  begin
    Inc(FFailures);
    FReport.Error('FAIL ' + ACase + ': ' + AFailDetail);
  end;
end;

function TBlobTest.TempFile(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TBlobTest.TestZip;
var
  Src, ZipFile, Name, CacheFile: string;
  Content, Back, Loaded: TBytes;
  FS: TFileStream;
  WasBin, Failed: Boolean;
begin
  // a ZIP made exactly as the client makes it on check-in (JVCSCompressFile:
  // Abbrevia, soStripPath, item named after the workstation file)
  ForceDirectories(TempFile('ws'));
  Src := TPath.Combine(TempFile('ws'), 'Unit1.pas');
  Content := SampleContent;
  TFile.WriteAllBytes(Src, Content);
  ZipFile := '';
  Check(JVCSCompressFile(Src, ZipFile), 'zip: JVCSCompressFile creates the sample ZIP', 'JVCSCompressFile returned False');
  if (ZipFile = '') or not FileExists(ZipFile) then
    Exit;
  try
    FS := TFileStream.Create(ZipFile, fmOpenRead or fmShareDenyWrite);
    try
      Check(Unzip(FS, Back, Name), 'zip: ExtractBlobToStream recognizes the ZIP', 'not recognized as ZIP');
    finally
      FS.Free;
    end;
    Check(SameBytes(Back, Content), 'zip: extracted bytes equal the original',
      Format('%d bytes, expected %d', [Length(Back), Length(Content)]));
    Check(Name = 'Unit1.pas', 'zip: item name keeps the original spelling (Unit1.pas)', 'item name ' + Name);
    Check(BytesCrc(Back) = Cardinal(Integer(BytesCrc(Content))), 'zip: CRC32OfBuffer of the extracted bytes matches',
      Format('$%.8x <> $%.8x', [BytesCrc(Back), BytesCrc(Content)]));
    // a well known CRC-32 value (IEEE): '123456789' -> $CBF43926
    Check(BytesCrc(BytesOf('123456789')) = $CBF43926, 'crc: CRC-32 check value of ''123456789''',
      Format('$%.8x', [BytesCrc(BytesOf('123456789'))]));
    // a cached non-form member is returned unchanged
    CacheFile := TempFile('42.pas');
    TFile.WriteAllBytes(CacheFile, Back);
    Loaded := J2GLoadMemberContent(CacheFile, '.pas', True, WasBin, Failed);
    Check(SameBytes(Loaded, Content) and not WasBin and not Failed,
      'cache: J2GLoadMemberContent returns the raw bytes of a .pas', 'content changed');
  finally
    System.SysUtils.DeleteFile(ZipFile);
  end;
end;

procedure TBlobTest.TestBlowfish;
var
  Src, ZipFile, EncFile, DecFile, Name: string;
  Key: TBytes;
  Content, Back: TBytes;
  FS: TFileStream;
  I: Integer;
begin
  // test key (not a real one): 16 bytes
  SetLength(Key, 16);
  for I := 0 to High(Key) do
    Key[I] := Byte(I * 7 + 3);
  Src := TPath.Combine(TempFile('ws'), 'Crypt1.pas');
  Content := SampleContent;
  TFile.WriteAllBytes(Src, Content);
  ZipFile := '';
  if not JVCSCompressFile(Src, ZipFile) then
  begin
    Check(False, 'blowfish: sample ZIP', 'JVCSCompressFile returned False');
    Exit;
  end;
  EncFile := TempFile('crypt.bf');
  DecFile := TempFile('crypt.zip');
  try
    Check(BlowFishEncode(nil, Key, ZipFile, EncFile), 'blowfish: encode the ZIP', 'BlowFishEncode returned False');
    FS := TFileStream.Create(EncFile, fmOpenRead or fmShareDenyWrite);
    try
      Check(not Unzip(FS, Back, Name), 'blowfish: encrypted blob is not a ZIP (-> encrypted without key)',
        'encrypted blob recognized as ZIP');
    finally
      FS.Free;
    end;
    Check(BlowFishDecode(nil, Key, EncFile, DecFile), 'blowfish: decode', 'BlowFishDecode returned False');
    TrimZipPadding(DecFile);
    FS := TFileStream.Create(DecFile, fmOpenRead or fmShareDenyWrite);
    try
      Check(Unzip(FS, Back, Name) and SameBytes(Back, Content) and (Name = 'Crypt1.pas'),
        'blowfish: decoded + TrimZipPadding is the original ZIP', 'content or name differs');
    finally
      FS.Free;
    end;
  finally
    FillChar(Key[0], Length(Key), 0);
    System.SysUtils.DeleteFile(ZipFile);
    System.SysUtils.DeleteFile(EncFile);
    System.SysUtils.DeleteFile(DecFile);
  end;
end;

procedure TBlobTest.TestDfm;
var
  DfmText, S: string;
  Input: TStringStream;
  Output: TBytesStream;
  Bin, Res, Txt, Plain, Loaded, Bad: TBytes;
  Err, CacheFile: string;
  Ok, WasBin, Failed: Boolean;
begin
  // text form with an accented string (#225 = a acute), as the IDE writes it
  DfmText := 'object Form1: TForm1' + CRLF +
    '  Left = 10' + CRLF +
    '  Caption = ''Ol''#225'' mundo''' + CRLF +
    '  object Button1: TButton' + CRLF +
    '    Caption = ''A''#231#227''o''' + CRLF +
    '  end' + CRLF +
    'end' + CRLF;
  Input := TStringStream.Create(DfmText, TEncoding.ASCII);
  Output := TBytesStream.Create;
  try
    ObjectTextToBinary(Input, Output);
    Bin := Copy(Output.Bytes, 0, Output.Size);
  finally
    Output.Free;
    Input.Free;
  end;
  Check(StartsWithText(Bin, 'TPF0'), 'dfm: ObjectTextToBinary produced a TPF0 form', 'no TPF0 signature');
  try
    Ok := J2GConvertDfmBytes(Bin, Txt, Err);
    S := TEncoding.ASCII.GetString(Txt);
    Check(Ok and StartsWithText(Txt, 'object ') and (Pos('#225', S) > 0),
      'dfm: TPF0 -> text starts with ''object '' and keeps the accent (#225)', 'result: ' + Err + ' ' + Copy(S, 1, 40));
  except
    on E: Exception do
      Check(False, 'dfm: TPF0 -> text', 'exception ' + E.ClassName + ': ' + E.Message);
  end;

  // Delphi 1 resource format: first byte $FF
  Input := TStringStream.Create(DfmText, TEncoding.ASCII);
  Output := TBytesStream.Create;
  try
    ObjectTextToResource(Input, Output);
    Res := Copy(Output.Bytes, 0, Output.Size);
  finally
    Output.Free;
    Input.Free;
  end;
  Check((Length(Res) > 0) and (Res[0] = $FF), 'dfm: ObjectTextToResource produced a $FF resource', 'first byte not $FF');
  try
    Ok := J2GConvertDfmBytes(Res, Txt, Err);
    Check(Ok and StartsWithText(Txt, 'object '), 'dfm: $FF resource -> text starts with ''object ''', 'result: ' + Err);
  except
    on E: Exception do
      Check(False, 'dfm: $FF resource -> text', 'exception ' + E.ClassName + ': ' + E.Message);
  end;

  // text form: not converted, bytes unchanged
  Plain := BytesOf(DfmText);
  Ok := J2GConvertDfmBytes(Plain, Txt, Err);
  Check(not Ok and SameBytes(Txt, Plain) and (Err = ''), 'dfm: text form is not converted (bytes unchanged)', 'changed or error ' + Err);

  // corrupted binary form: no exception, raw bytes back and an error text
  Bad := BytesOf('TPF0'#7'garbage');
  try
    Ok := J2GConvertDfmBytes(Bad, Txt, Err);
    Check(not Ok and SameBytes(Txt, Bad) and (Err <> ''), 'dfm: corrupted TPF0 -> raw bytes + error, no exception',
      'unexpected result');
  except
    on E: Exception do
      Check(False, 'dfm: corrupted TPF0', 'exception ' + E.ClassName + ': ' + E.Message);
  end;

  // through the cache: J2GLoadMemberContent with and without -nodfmtext
  CacheFile := TempFile('43.dfm');
  TFile.WriteAllBytes(CacheFile, Bin);
  Loaded := J2GLoadMemberContent(CacheFile, '.dfm', True, WasBin, Failed);
  Check(WasBin and not Failed and StartsWithText(Loaded, 'object '), 'cache: .dfm binary loaded as text', 'not converted');
  Loaded := J2GLoadMemberContent(CacheFile, '.dfm', False, WasBin, Failed);
  Check(WasBin and not Failed and SameBytes(Loaded, Bin), 'cache: -nodfmtext keeps the binary bytes', 'changed');
  TFile.WriteAllBytes(CacheFile, Bad);
  Loaded := J2GLoadMemberContent(CacheFile, '.dfm', True, WasBin, Failed);
  Check(WasBin and Failed and SameBytes(Loaded, Bad), 'cache: corrupted .dfm -> AFailed and raw bytes', 'unexpected');
end;

procedure TBlobTest.TestDates;
var
  D: TDateTime;
  S: string;
  Secs: Int64;
begin
  D := EncodeDate(2001, 9, 9) + EncodeTime(1, 46, 40, 0);
  Check(J2GUnixTime(D) = 1000000000, 'date: J2GUnixTime(2001-09-09 01:46:40) = 1000000000', IntToStr(J2GUnixTime(D)));
  Check(J2GGitDate(D, 0) = '1000000000 +0000', 'date: J2GGitDate UTC', J2GGitDate(D, 0));
  Check(J2GGitDate(D, -180) = '1000000000 -0300', 'date: J2GGitDate -0300', J2GGitDate(D, -180));
  Check(J2GGitDate(D, 330) = '1000000000 +0530', 'date: J2GGitDate +0530', J2GGitDate(D, 330));
  S := J2GGitDate(0, 0);   // TDateTime 0 = 1899: never negative
  Secs := StrToInt64Def(Copy(S, 1, Pos(' ', S) - 1), -1);
  Check(Secs > 0, 'date: 1899 (TDateTime 0) is never written negative', S);
  Check(Abs(J2GLocalOffsetMinutes(D)) <= 14 * 60, 'date: J2GLocalOffsetMinutes in range',
    IntToStr(J2GLocalOffsetMinutes(D)));
  Check(J2GNormalizeMessage('a'#13#10'b'#13'c'#1#9'd'#10#10) = 'a'#10'b'#10'c'#9'd'#10,
    'message: CRLF/CR -> LF, control chars removed, one final LF', J2GNormalizeMessage('a'#13#10'b'#13'c'#1#9'd'#10#10));
  Check(J2GNormalizeMessage('') = '', 'message: empty stays empty', 'not empty');
end;

procedure TBlobTest.TestGit;
const
  Ref = 'refs/heads/main';
var
  Version, Stream, Trunc, Repo, Repo2, Output, SpacePath, Line: string;
  W: TJ2GFastImportWriter;
  D: TDateTime;
  M1, M2, Code: Integer;
  Lines: TStringList;
  AllPositive: Boolean;
  PasV2: TBytes;
  Rejected: Boolean;
begin
  if not J2GGitVersion(Version) then
  begin
    FReport.Warn('git not found on the PATH: git fast-import cases skipped');
    Exit;
  end;
  FReport.Info('git: ' + Version);
  Stream := TempFile('test.fast-import');
  Repo := TempFile('repo');
  // path with a space and accents (c cedilla, a tilde)
  SpacePath := 'docs/meu arquivo a' + #231#227 + 'o.txt';
  PasV2 := BytesOf('unit unit;' + CRLF + '// v2' + CRLF + 'end.' + CRLF);
  D := EncodeDate(2001, 9, 9) + EncodeTime(1, 46, 40, 0);
  W := TJ2GFastImportWriter.Create(Stream);
  try
    M1 := W.NewMark;
    M2 := W.NewMark;
    Check((M1 = 1) and (M2 = 2), 'stream: marks 1, 2', Format('%d, %d', [M1, M2]));
    // committer date 0 (1899): must be written as a positive date
    W.BeginCommit(Ref, M1, 'Jo' + #227 + 'o Silva <joao@jedivcs.local>', D, -180,
      'Jo' + #227 + 'o Silva <joao@jedivcs.local>', 0, 0,
      'Primeira vers' + #227 + 'o'#13#10'linha 2'#1, 0);
    W.FileModify('src/unit.pas', BytesOf('unit unit;' + CRLF + 'end.' + CRLF));
    W.FileModify('src/unit.dfm', BytesOf('object Form1: TForm1' + CRLF + 'end' + CRLF));
    W.FileModify('_externos/c/lib/x.pas', BytesOf('unit x;' + CRLF));
    W.FileModify('_externos/unc/srv/share/x.pas', BytesOf('unit x;' + CRLF));
    W.FileModify(SpacePath, BytesOf('texto' + CRLF));
    W.EndCommit;
    W.BeginCommit(Ref, M2, 'Maria <maria@jedivcs.local>', D + 1, 0,
      'Maria <maria@jedivcs.local>', D + 1, 0, 'unit.dfm removido', M1);
    W.FileModify('src/unit.pas', PasV2);
    W.FileDelete('src/unit.dfm');
    W.EndCommit;
    W.Tag('v1.0', M2, 'Maria <maria@jedivcs.local>', D + 1, 0, 'Release 1.0' + CRLF + 'unit.pas 1.1');
    W.Close(True);
    Check(W.BytesWritten = TFile.GetSize(Stream), 'stream: BytesWritten equals the file size',
      Format('%d <> %d', [W.BytesWritten, TFile.GetSize(Stream)]));
  finally
    W.Free;
  end;

  try
    J2GGitInitRepo(Repo, 'main');
    J2GGitFastImport(Repo, Stream);
    J2GGitCheckout(Repo, 'main');
    Check(True, 'git: init + fast-import + checkout (exit 0)', '');
  except
    on E: Exception do
    begin
      Check(False, 'git: init + fast-import + checkout', E.Message);
      Exit;
    end;
  end;

  Lines := TStringList.Create;
  try
    Code := J2GRunGit(['-c', 'core.quotepath=off', 'ls-tree', '-r', '--name-only', 'HEAD'], Repo, Output);
    Lines.Text := Output;
    Check((Code = 0) and (Lines.IndexOf('src/unit.pas') >= 0) and (Lines.IndexOf('src/unit.dfm') < 0),
      'git: ls-tree HEAD has src/unit.pas and not src/unit.dfm (D)', Output);
    Check((Lines.IndexOf('_externos/c/lib/x.pas') >= 0) and (Lines.IndexOf('_externos/unc/srv/share/x.pas') >= 0),
      'git: _externos/c/... and _externos/unc/... imported', Output);
    Check(Lines.IndexOf(SpacePath) >= 0, 'git: path with space and accents imported (UTF-8)', Output);
    Check(FileExists(TPath.Combine(Repo, StringReplace(SpacePath, '/', '\', [rfReplaceAll]))) and
      FileExists(TPath.Combine(Repo, '_externos\c\lib\x.pas')) and not FileExists(TPath.Combine(Repo, 'src\unit.dfm')),
      'git: checkout wrote the files on disk', 'missing file in the work tree');

    Code := J2GRunGit(['symbolic-ref', 'HEAD'], Repo, Output);
    Check((Code = 0) and (Output = 'refs/heads/main'), 'git: symbolic-ref HEAD = refs/heads/main', Output);

    Code := J2GRunGit(['fsck', '--strict'], Repo, Output);
    Check((Code = 0) and (Pos('error', LowerCase(Output)) = 0) and (Pos('baddate', LowerCase(Output)) = 0),
      'git: fsck --strict without errors', Output);

    Code := J2GRunGit(['log', '--format=%at%n%ct'], Repo, Output);
    Lines.Text := Output;
    AllPositive := (Code = 0) and (Lines.Count = 4);
    for Line in Lines do
      if StrToInt64Def(Trim(Line), -1) <= 0 then
        AllPositive := False;
    Check(AllPositive, 'git: log %at/%ct all positive (2 commits)', Output);

    Code := J2GRunGit(['log', '-1', '--skip=1', '--format=%an|%s'], Repo, Output);
    Check((Code = 0) and (Output = 'Jo' + #227 + 'o Silva|Primeira vers' + #227 + 'o linha 2'),
      'git: author and message in UTF-8, control chars removed', Output);

    Code := J2GRunGit(['cat-file', '-t', 'v1.0'], Repo, Output);
    Check((Code = 0) and (Output = 'tag'), 'git: v1.0 is an annotated tag', Output);

    Code := J2GRunGit(['show', 'HEAD:src/unit.pas'], Repo, Output);
    Check((Code = 0) and (Pos('// v2', Output) > 0), 'git: src/unit.pas has the content of commit 2', Output);
  finally
    Lines.Free;
  end;

  // truncated stream (no 'done'): must be rejected
  Trunc := TempFile('trunc.fast-import');
  Repo2 := TempFile('repo2');
  W := TJ2GFastImportWriter.Create(Trunc);
  try
    W.BeginCommit(Ref, W.NewMark, 'A <a@b>', D, 0, 'A <a@b>', D, 0, 'x', 0);
    W.FileModify('a.txt', BytesOf('a'));
    W.EndCommit;
    W.Close(False);
  finally
    W.Free;
  end;
  Rejected := False;
  try
    J2GGitInitRepo(Repo2, 'main');
    J2GGitFastImport(Repo2, Trunc);
  except
    on E: EJ2GError do
      Rejected := True;
  end;
  Check(Rejected, 'git: truncated stream (no ''done'') rejected by fast-import', 'fast-import accepted it');
end;

function TBlobTest.Run: Integer;

  procedure Step(AProc: TProc; const AName: string);
  begin
    try
      AProc();
    except
      on E: Exception do
        Check(False, AName, 'exception ' + E.ClassName + ': ' + E.Message);
    end;
  end;

begin
  FTempDir := TPath.Combine(TPath.GetTempPath, Format('jvcs2git-selftest-%d-%d', [GetCurrentProcessId, GetTickCount]));
  ForceDirectories(FTempDir);
  try
    Step(TestZip, 'zip');
    Step(TestBlowfish, 'blowfish');
    Step(TestDfm, 'dfm');
    Step(TestDates, 'dates');
    Step(TestGit, 'git');
  finally
    try
      DeleteTree(FTempDir);
    except
      on E: Exception do
        FReport.Warn('cannot delete ' + FTempDir + ': ' + E.Message);
    end;
    if DirectoryExists(FTempDir) then
      FReport.Warn('temporary folder not deleted: ' + FTempDir);
  end;
  if FFailures = 0 then
  begin
    FReport.Info('self test blob: all cases passed');
    Result := J2G_EXIT_OK;
  end
  else
  begin
    FReport.Message := Format('self test blob: %d case(s) failed', [FFailures]);
    Result := 1;
  end;
end;

function J2GRunSelfTestBlob(AReport: TJ2GReport): Integer;
var
  T: TBlobTest;
begin
  T := TBlobTest.Create(AReport);
  try
    Result := T.Run;
  finally
    T.Free;
  end;
end;

end.
