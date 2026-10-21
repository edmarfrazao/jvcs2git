(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GBlob.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - content of a revision member: GET_SINGLE_BLOB (never
GET_CHECKOUT_MODULE, which writes to the server log) -> ZIP or Blowfish ->
raw bytes, CRC check, original file name of the ZIP item, disk cache, and the
binary .dfm -> text conversion applied when the content is written.

Cache (plan 10.9): <cache dir>\<RevisionID><ext> holds the RAW bytes (after
unzip/decrypt, before any .dfm conversion); written as '.tmp' and renamed only
after the CRC check. A cached file is reused only if it exists without '.tmp'
and its size equals Member.Size; otherwise it is deleted and downloaded again.
Interface frozen in PT0; implemented in PT3.

-----------------------------------------------------------------------------*)

unit J2GBlob;

{$I jedi.inc}
{$I compopt.inc}
{$WARN SYMBOL_PLATFORM OFF}

interface

uses
  System.SysUtils, System.Classes,
  J2GModel, J2GSession, J2GReport;

type
  TJ2GBlobFetcher = class
  private
    FSession: TJ2GSession;
    FCacheDir: string;
    FKey: TBytes;
    FTimeout: Cardinal;
    FIgnoreCrc: Boolean;
    FReport: TJ2GReport;
    FTempSeq: Integer;
    function TempFileName(const ASuffix: string): string;
    function Decrypt(ASource, ADest: TStream; out ADetail: string): Boolean;
  public
    // AKey: Blowfish key bytes (may be empty); ATimeout: ms for GET_SINGLE_BLOB
    constructor Create(ASession: TJ2GSession; const ACacheDir: string; const AKey: TBytes;
      ATimeout: Cardinal; AIgnoreCrc: Boolean; AReport: TJ2GReport);
    destructor Destroy; override;
    // Gets the raw bytes of ARev.Members[AMemberIndex] into the cache.
    // Sets Member.Status (rsOk, rsEncrypted, rsNoBlob, rsCrcMismatch, rsError),
    // Member.CacheFile and Member.ZipName; returns the status. ADetail = text
    // for the report when not rsOk. Updates AReport.Current.BlobsDownloaded,
    // BlobsFromCache and BytesDownloaded. Never raises for a per-member
    // problem; raises EJ2GError(9) only when the connection is lost.
    // Size = 0 -> rsNoBlob; not a ZIP and no (valid) key -> rsEncrypted;
    // CRC mismatch -> rsCrcMismatch (kept in the cache and rsOk with
    // AIgnoreCrc, plus a warning).
    function Fetch(ARev: TJ2GRevision; AMemberIndex: Integer; out ADetail: string): TJ2GRevStatus;
    // deletes the cache folder
    procedure ClearCache;
    function CacheDir: string;
  end;

// Bytes to write in the repository for a cached member: the raw bytes, or,
// when AConvertDfm and AExt is '.dfm'/'.fmx'/'.xfm'/'.lfm' and the content is
// binary ('TPF0' -> ObjectBinaryToText; first byte $FF -> ObjectResourceToText),
// the text form. AWasBinary = the content was a binary form; AFailed = the
// conversion raised (raw bytes returned).
function J2GLoadMemberContent(const ACacheFile, AExt: string; AConvertDfm: Boolean;
  out AWasBinary, AFailed: Boolean): TBytes;

// binary form (TPF0 or $FF resource) -> text; False + raw input when not binary
// or on error (AError)
function J2GConvertDfmBytes(const ABytes: TBytes; out AText: TBytes; out AError: string): Boolean;

implementation

uses
  System.IOUtils, Winapi.Windows,
  JVCSTypes, JVCSClientObjBase, JVCSClientObj, BFCrypt, Checksum,
  AbUtils, AbArcTyp, AbZipTyp;

const
  FILER_SIGNATURE = $30465054;  // 'TPF0' (System.Classes FilerSignature)
  // sidecar with the name of the ZIP item, so a cached blob keeps it
  ZIPNAME_SUFFIX = '.zipname';

function IsFormExt(const AExt: string): Boolean;
begin
  Result := SameText(AExt, '.dfm') or SameText(AExt, '.fmx') or SameText(AExt, '.xfm') or
    SameText(AExt, '.lfm');
end;

// 0 = not binary, 1 = 'TPF0', 2 = 16-bit resource ($FF)
function BinaryFormKind(const ABytes: TBytes): Integer;
begin
  if (Length(ABytes) >= 4) and (PCardinal(@ABytes[0])^ = FILER_SIGNATURE) then
    Result := 1
  else if (Length(ABytes) > 0) and (ABytes[0] = $FF) then
    Result := 2
  else
    Result := 0;
end;

function J2GConvertDfmBytes(const ABytes: TBytes; out AText: TBytes; out AError: string): Boolean;
var
  Kind: Integer;
  Input, Output: TBytesStream;
begin
  AError := '';
  AText := ABytes;
  Kind := BinaryFormKind(ABytes);
  if Kind = 0 then
    Exit(False);
  Result := False;
  try
    Input := TBytesStream.Create(ABytes);
    Output := TBytesStream.Create;
    try
      // 'TPF0' is FilerSignature: ObjectBinaryToText. ObjectResourceToText
      // requires a resource header and raises EInvalidImage on 'TPF0' (10.2).
      if Kind = 1 then
        ObjectBinaryToText(Input, Output)
      else
        ObjectResourceToText(Input, Output);
      AText := Copy(Output.Bytes, 0, Output.Size);
      Result := True;
    finally
      Output.Free;
      Input.Free;
    end;
  except
    on E: Exception do
    begin
      AText := ABytes;
      AError := E.ClassName + ': ' + E.Message;
      Result := False;
    end;
  end;
end;

function J2GLoadMemberContent(const ACacheFile, AExt: string; AConvertDfm: Boolean;
  out AWasBinary, AFailed: Boolean): TBytes;
var
  Text: TBytes;
  Err: string;
begin
  AWasBinary := False;
  AFailed := False;
  Result := TFile.ReadAllBytes(ACacheFile);
  if not IsFormExt(AExt) then
    Exit;
  AWasBinary := BinaryFormKind(Result) <> 0;
  if AWasBinary and AConvertDfm then
  begin
    if J2GConvertDfmBytes(Result, Text, Err) then
      Result := Text
    else
      AFailed := True;
  end;
end;

// name of the first item of a ZIP (original spelling on the workstation), '' if none
function ZipItemName(AStream: TStream): string;
var
  Archive: TAbZipArchive;
begin
  Result := '';
  AStream.Position := 0;
  if VerifyZip(AStream) <> atZip then
    Exit;
  AStream.Position := 0;
  Archive := TAbZipArchive.CreateFromStream(AStream, 'AbArchive');
  try
    Archive.Load;
    if Archive.ItemList.Count > 0 then
      Result := ExtractFileName(StringReplace(Archive.Items[0].FileName, '/', '\', [rfReplaceAll]));
  finally
    Archive.Free;
  end;
end;

// ExtractBlobToStream of the client (False = not a ZIP); AName = item name
function UnzipBlob(AObject: TJVCSClientObject; ASource, ADest: TStream; out AName: string): Boolean;
begin
  AName := '';
  ADest.Size := 0;
  ASource.Position := 0;
  Result := AObject.ExtractBlobToStream(ASource, ADest);
  if Result then
    AName := ZipItemName(ASource);
  ASource.Position := 0;
end;

function StreamCrc(AStream: TMemoryStream): Cardinal;
var
  Dummy: Byte;
begin
  if AStream.Size = 0 then
    Result := CRC32OfBuffer(Dummy, 0)
  else
    Result := CRC32OfBuffer(AStream.Memory^, AStream.Size);
end;

procedure DeleteIfExists(const AFileName: string);
begin
  if FileExists(AFileName) then
  begin
    FileSetAttr(AFileName, faNormal);
    System.SysUtils.DeleteFile(AFileName);
  end;
end;

{ TJ2GBlobFetcher }

constructor TJ2GBlobFetcher.Create(ASession: TJ2GSession; const ACacheDir: string; const AKey: TBytes;
  ATimeout: Cardinal; AIgnoreCrc: Boolean; AReport: TJ2GReport);
begin
  inherited Create;
  FSession := ASession;
  FCacheDir := ExcludeTrailingPathDelimiter(ACacheDir);
  FKey := Copy(AKey);
  FTimeout := ATimeout;
  FIgnoreCrc := AIgnoreCrc;
  FReport := AReport;
end;

destructor TJ2GBlobFetcher.Destroy;
begin
  if Length(FKey) > 0 then
    FillChar(FKey[0], Length(FKey), 0);
  FKey := nil;
  inherited Destroy;
end;

function TJ2GBlobFetcher.CacheDir: string;
begin
  Result := FCacheDir;
end;

procedure TJ2GBlobFetcher.ClearCache;
var
  F: string;
begin
  if (FCacheDir = '') or not DirectoryExists(FCacheDir) then
    Exit;
  try
    for F in TDirectory.GetFiles(FCacheDir) do
      DeleteIfExists(F);
    TDirectory.Delete(FCacheDir, True);
  except
    on E: Exception do
      if Assigned(FReport) then
        FReport.Warn(Format('cannot delete the blob cache %s: %s', [FCacheDir, E.Message]));
  end;
end;

function TJ2GBlobFetcher.TempFileName(const ASuffix: string): string;
begin
  Inc(FTempSeq);
  Result := TPath.Combine(TPath.GetTempPath, Format('jvcs2git-%d-%d-%d%s',
    [GetCurrentProcessId, GetTickCount, FTempSeq, ASuffix]));
end;

// Blowfish (as HandleBlob.pas: file in, file out, then the zero padding after
// the end of the ZIP is trimmed); temporary files in %TEMP%, always deleted
function TJ2GBlobFetcher.Decrypt(ASource, ADest: TStream; out ADetail: string): Boolean;
var
  InFile, OutFile: string;
  FS: TFileStream;
begin
  Result := False;
  ADetail := '';
  InFile := TempFileName('.bf');
  OutFile := TempFileName('.zip');
  try
    FS := TFileStream.Create(InFile, fmCreate);
    try
      ASource.Position := 0;
      FS.CopyFrom(ASource, ASource.Size);
    finally
      FS.Free;
    end;
    if not BlowFishDecode(nil, FKey, InFile, OutFile) then
    begin
      ADetail := 'Blowfish decoding failed';
      Exit;
    end;
    TrimZipPadding(OutFile);
    FS := TFileStream.Create(OutFile, fmOpenRead or fmShareDenyWrite);
    try
      ADest.Size := 0;
      ADest.CopyFrom(FS, FS.Size);
      ADest.Position := 0;
    finally
      FS.Free;
    end;
    Result := True;
  finally
    DeleteIfExists(InFile);
    DeleteIfExists(OutFile);
  end;
end;

function TJ2GBlobFetcher.Fetch(ARev: TJ2GRevision; AMemberIndex: Integer; out ADetail: string): TJ2GRevStatus;
var
  Ext, CacheName, TmpName, ZipName, Detail: string;
  Obj: TJVCSGetSingleBlob;
  Raw, Plain: TMemoryStream;
  Crc, OrigCrc: Cardinal;
  Rep: TJ2GProjectReport;

  procedure SetMember(AStatus: TJ2GRevStatus; const ACache, AZip: string);
  begin
    ARev.Members[AMemberIndex].Status := AStatus;
    ARev.Members[AMemberIndex].CacheFile := ACache;
    ARev.Members[AMemberIndex].ZipName := AZip;
  end;

  function Done(AStatus: TJ2GRevStatus; const ADetailText: string): TJ2GRevStatus;
  begin
    ADetail := ADetailText;
    if AStatus <> rsOk then
      SetMember(AStatus, '', ZipName);
    Result := AStatus;
  end;

begin
  ADetail := '';
  ZipName := '';
  if (AMemberIndex < 0) or (AMemberIndex > High(ARev.Members)) then
    Exit(rsError);
  Rep := nil;
  if Assigned(FReport) then
    Rep := FReport.Current;
  Ext := LowerCase(ARev.Members[AMemberIndex].Ext);
  if ARev.Members[AMemberIndex].Size = 0 then
    Exit(Done(rsNoBlob, 'size 0 in the module history'));

  ForceDirectories(FCacheDir);
  CacheName := IncludeTrailingPathDelimiter(FCacheDir) + IntToStr(ARev.RevisionID) + Ext;
  TmpName := CacheName + '.tmp';
  DeleteIfExists(TmpName);

  // cache from a previous run: only a complete file with the expected size
  if FileExists(CacheName) then
  begin
    try
      if TFile.GetSize(CacheName) = ARev.Members[AMemberIndex].Size then
      begin
        if FileExists(CacheName + ZIPNAME_SUFFIX) then
          ZipName := Trim(TFile.ReadAllText(CacheName + ZIPNAME_SUFFIX, TEncoding.UTF8));
        // accepted only when it names the same file (plan 10.3); else the server name is used
        if (ZipName <> '') and Assigned(ARev.Module) and
          not SameText(ChangeFileExt(ExtractFileName(ZipName), ''), ChangeFileExt(ExtractFileName(ARev.Module.Name), '')) then
          ZipName := '';
        SetMember(rsOk, CacheName, ZipName);
        if Assigned(Rep) then
          Inc(Rep.BlobsFromCache);
        Exit(rsOk);
      end;
    except
      // unreadable: download again
    end;
    DeleteIfExists(CacheName);
    DeleteIfExists(CacheName + ZIPNAME_SUFFIX);
  end;

  Obj := TJVCSGetSingleBlob.Create(nil);
  Plain := TMemoryStream.Create;
  try
    Obj.RevisionID := ARev.RevisionID;
    Obj.Extension := JVCSString20(AnsiString(Ext));
    try
      FSession.Send(Obj, FTimeout);
    except
      on E: EJ2GError do
        raise;   // connection lost (code 9)
      on E: Exception do
        Exit(Done(rsError, 'GET_SINGLE_BLOB: ' + E.Message));
    end;
    Raw := Obj.ModuleBinary;
    if Assigned(Rep) then
    begin
      Inc(Rep.BlobsDownloaded);
      Inc(Rep.BytesDownloaded, Raw.Size);
    end;
    if Raw.Size = 0 then
      Exit(Done(rsNoBlob, 'the server returned no blob'));

    try
      if not UnzipBlob(Obj, Raw, Plain, ZipName) then
      begin
        // not a ZIP: Blowfish encrypted
        if (Length(FKey) < 8) or (Length(FKey) > 65) then
          Exit(Done(rsEncrypted, 'blob is encrypted (Blowfish) and no valid key was given'));
        Plain.Size := 0;
        if not Decrypt(Raw, Plain, Detail) then
          Exit(Done(rsEncrypted, Detail));
        Raw.Size := 0;
        Raw.CopyFrom(Plain, 0);
        if not UnzipBlob(Obj, Raw, Plain, ZipName) then
          Exit(Done(rsEncrypted, 'blob is not a ZIP after decryption (wrong key?)'));
      end;
    except
      on E: Exception do
        Exit(Done(rsError, 'cannot extract the blob: ' + E.Message));
    end;

    // CRC of the raw content, before any conversion
    Crc := StreamCrc(Plain);
    OrigCrc := Cardinal(Obj.ModuleOriginalCRC);
    try
      Plain.SaveToFile(TmpName);
      if (Crc <> OrigCrc) and not FIgnoreCrc then
      begin
        DeleteIfExists(TmpName);
        Exit(Done(rsCrcMismatch, Format('CRC $%.8x, expected $%.8x', [Crc, OrigCrc])));
      end;
      if ZipName <> '' then
        TFile.WriteAllText(CacheName + ZIPNAME_SUFFIX, ZipName, TEncoding.UTF8)
      else
        DeleteIfExists(CacheName + ZIPNAME_SUFFIX);
      DeleteIfExists(CacheName);
      if not RenameFile(TmpName, CacheName) then
        RaiseLastOSError;
    except
      on E: Exception do
      begin
        DeleteIfExists(TmpName);
        Exit(Done(rsError, Format('cannot write the cache file %s: %s', [CacheName, E.Message])));
      end;
    end;
    SetMember(rsOk, CacheName, ZipName);
    Result := rsOk;
    if Crc <> OrigCrc then
    begin
      ADetail := Format('CRC $%.8x, expected $%.8x (kept: -ignorecrc)', [Crc, OrigCrc]);
      if Assigned(FReport) then
        FReport.Warn(Format('rev %d %s: %s', [ARev.RevisionID, Ext, ADetail]));
    end;
  finally
    Plain.Free;
    Obj.Free;
  end;
end;

end.
