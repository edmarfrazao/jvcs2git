(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: J2GCli.pas

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git - console front end (jvcs2git-cli.exe): command line, password,
exit codes and JSON.

Two forms:
 (a) jvcs2git-cli -identity <name> [<host[:port]>] [-user <u>] ...
     host, port, user and password come from the saved identity; a host/user
     given on the line override it (warning). stdin is NEVER read for the
     password. Missing/incomplete identity or no saved password -> 4.
 (b) jvcs2git-cli <host[:port]> -user <u> ...
     password = first line of stdin when redirected (EOF/empty -> 4, no login);
     interactive console -> prompt without echo.
Precedence: -identity > redirected stdin > prompt. There is no -password.

-----------------------------------------------------------------------------*)

unit J2GCli;

{$I jedi.inc}
{$I compopt.inc}
{$WARN SYMBOL_PLATFORM OFF}

interface

// runs the console tool and returns the exit code
function J2GCliMain: Integer;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  RFormat,
  J2GModel, J2GOptions, J2GIdentity, J2GSession, J2GReport,
  J2GGit, J2GDryRun, J2GSelfTestPaths, J2GSelfTestBlob, J2GExport;

type
  EJ2GUsage = class(Exception);

var
  StdInRedirected: Boolean;

procedure ShowBanner;
begin
  Writeln(J2G_PRODUCT, ' console ', J2G_VERSION, ' - JEDI VCS to Git exporter');
  Writeln(J2G_MIDWARE_NOTICE);
  Writeln('Source: ', J2G_URL, ' (MPL 1.1)');
  Writeln;
end;

procedure ShowUsage(var F: Text);
begin
  Writeln(F, 'Usage:');
  Writeln(F, '  jvcs2git-cli -identity <name> [<host[:port]>] [-user <u>] -out <folder> (-project <name|id> ... | -all) [options]');
  Writeln(F, '  jvcs2git-cli <host[:port]> -user <u> -out <folder> (-project <name|id> ... | -all) [options]');
  Writeln(F, '  jvcs2git-cli ... -list [-include-deleted] [-json]      list the projects and exit');
  Writeln(F, '  jvcs2git-cli ... -dryrun (-project ... | -all)        metadata only: print the commit plan');
  Writeln(F, '  jvcs2git-cli -selftest paths|blob [-json]               offline self tests');
  Writeln(F, '');
  Writeln(F, 'Password: -identity (saved by the JEDI VCS client) > first line of a redirected stdin > prompt.');
  Writeln(F, 'There is no -password option.');
  Writeln(F, '');
  Writeln(F, 'Options:');
  Writeln(F, '  -branch <jvcs branch>    JEDI VCS branch (default HEAD)');
  Writeln(F, '  -branch-name <name>      git branch (default main)');
  Writeln(F, '  -group <minutes>         group check-ins of the same user+comment (default 10)');
  Writeln(F, '  -nogroup                 one commit per revision');
  Writeln(F, '  -group-maxspan <hours>   max span of a group dated by file time (default 168)');
  Writeln(F, '  -localtime               commit dates with the local UTC offset (default +0000)');
  Writeln(F, '  -committer-date original committer date = author date (default: monotonic)');
  Writeln(F, '  -root <folder>           server folder used as repository root');
  Writeln(F, '  -nodfmtext               keep binary .dfm as is (default: convert to text)');
  Writeln(F, '  -encodekey-file <file>   Blowfish key (Base64, 1st line); default: client registry');
  Writeln(F, '  -encodekey-stdin         Blowfish key on stdin (line after the password)');
  Writeln(F, '  -noencodekey             ignore the key saved by the client');
  Writeln(F, '  -authors <file>          author map (default <out>\autores.txt)');
  Writeln(F, '  -email-domain <domain>   default e-mail domain (default jedivcs.local)');
  Writeln(F, '  -labels tag|none         JEDI VCS labels as git tags (default tag)');
  Writeln(F, '  -include-deleted         also deleted (not purged) projects');
  Writeln(F, '  -skiphidden              skip hidden modules');
  Writeln(F, '  -nolog                   do not read the server log (dates by file time)');
  Writeln(F, '  -noattributes            no initial .gitattributes commit');
  Writeln(F, '  -nogit                   only write <out>\<repo>.fast-import');
  Writeln(F, '  -keepcache               keep <out>\.jvcs2git-cache');
  Writeln(F, '  -force                   recreate <out>\<repo> if it was made by jvcs2git');
  Writeln(F, '  -ignorecrc               export blobs with CRC mismatch');
  Writeln(F, '  -strictcase              abort a project on case collisions');
  Writeln(F, '  -blobtimeout <ms>        timeout of blob/log requests (default 120000)');
  Writeln(F, '  -log <file>              log file (default <out>\jvcs2git.log)');
  Writeln(F, '  -json                    one JSON line on stdout; messages go to stderr');
  Writeln(F, '  -quiet                   no messages on the screen');
  Writeln(F, '');
  Writeln(F, 'Exit codes: 0 ok; 2 usage; 4 credential; 5 project not found; 9 server/connection;');
  Writeln(F, '            11 partial (skipped revisions or failed project); 12 environment.');
end;

function IsSwitch(const S: string): Boolean;
begin
  Result := (Length(S) > 1) and CharInSet(S[1], ['-', '/']) and not CharInSet(S[2], ['0'..'9']);
end;

procedure ParseCommandLine(var O: TJ2GOptions);
var
  I: Integer;
  A, Sw: string;
  Positional: TStringList;

  function NextValue: string;
  begin
    if I >= ParamCount then
      raise EJ2GUsage.CreateFmt('missing value for %s', [A]);
    Inc(I);
    Result := ParamStr(I);
  end;

  function NextInt: Integer;
  var
    V: string;
  begin
    V := NextValue;
    if not TryStrToInt(V, Result) or (Result < 0) then
      raise EJ2GUsage.CreateFmt('invalid number for %s: %s', [A, V]);
  end;

  procedure AddProject(const V: string);
  var
    Parts: TArray<string>;
    P: string;
  begin
    Parts := V.Split([',']);
    for P in Parts do
      if Trim(P) <> '' then
      begin
        SetLength(O.Projects, Length(O.Projects) + 1);
        O.Projects[High(O.Projects)] := Trim(P);
      end;
  end;

var
  GroupGiven: Boolean;
begin
  GroupGiven := False;
  Positional := TStringList.Create;
  try
    I := 1;
    while I <= ParamCount do
    begin
      A := ParamStr(I);
      if IsSwitch(A) then
      begin
        Sw := LowerCase(Copy(A, 2, MaxInt));
        if (Sw = '?') or (Sw = 'h') or (Sw = 'help') or (Sw = '-help') then
          O.Command := jcHelp
        else if (Sw = 'password') or (Sw = 'pw') then
          raise EJ2GUsage.Create('-password is not supported: use -identity, a redirected stdin or the prompt')
        else if Sw = 'encodekey' then
          raise EJ2GUsage.Create('-encodekey is not supported (the key would be visible): use -encodekey-file, -encodekey-stdin or the client registry')
        else if Sw = 'identity' then
          O.Identity := NextValue
        else if Sw = 'user' then
          O.User := NextValue
        else if Sw = 'out' then
          O.OutDir := NextValue
        else if Sw = 'project' then
        begin
          // repeat -project or use a comma separated list
          AddProject(NextValue);
        end
        else if Sw = 'all' then
          O.AllProjects := True
        else if Sw = 'list' then
          O.Command := jcList
        else if Sw = 'dryrun' then
          O.Command := jcDryRun
        else if Sw = 'selftest' then
        begin
          O.Command := jcSelfTest;
          O.SelfTestName := LowerCase(NextValue);
          if (O.SelfTestName <> 'paths') and (O.SelfTestName <> 'blob') then
            raise EJ2GUsage.CreateFmt('unknown self test ''%s'' (use paths or blob)', [O.SelfTestName]);
        end
        else if Sw = 'branch' then
          O.JvcsBranch := NextValue
        else if Sw = 'branch-name' then
          O.BranchName := NextValue
        else if Sw = 'group' then
        begin
          O.GroupMinutes := NextInt;
          GroupGiven := True;
        end
        else if Sw = 'nogroup' then
          O.NoGroup := True
        else if Sw = 'group-maxspan' then
          O.GroupMaxSpanHours := NextInt
        else if Sw = 'localtime' then
          O.LocalTime := True
        else if Sw = 'committer-date' then
        begin
          Sw := LowerCase(NextValue);
          if Sw = 'original' then
            O.CommitterDate := cdOriginal
          else if Sw = 'monotonic' then
            O.CommitterDate := cdMonotonic
          else
            raise EJ2GUsage.Create('-committer-date must be original or monotonic');
        end
        else if Sw = 'root' then
          O.Root := NextValue
        else if Sw = 'nodfmtext' then
          O.NoDfmText := True
        else if Sw = 'dfmtext' then
          O.NoDfmText := False
        else if Sw = 'encodekey-file' then
          O.EncodeKeyFile := NextValue
        else if Sw = 'encodekey-stdin' then
          O.EncodeKeyStdin := True
        else if Sw = 'noencodekey' then
          O.NoEncodeKey := True
        else if Sw = 'authors' then
          O.AuthorsFile := NextValue
        else if Sw = 'email-domain' then
          O.EmailDomain := NextValue
        else if Sw = 'labels' then
        begin
          Sw := LowerCase(NextValue);
          if Sw = 'tag' then
            O.Labels := lmTag
          else if Sw = 'none' then
            O.Labels := lmNone
          else
            raise EJ2GUsage.Create('-labels must be tag or none');
        end
        else if Sw = 'include-deleted' then
          O.IncludeDeleted := True
        else if Sw = 'skiphidden' then
          O.SkipHidden := True
        else if Sw = 'nolog' then
          O.NoLog := True
        else if Sw = 'noattributes' then
          O.NoAttributes := True
        else if Sw = 'nogit' then
          O.NoGit := True
        else if Sw = 'keepcache' then
          O.KeepCache := True
        else if Sw = 'force' then
          O.Force := True
        else if Sw = 'ignorecrc' then
          O.IgnoreCrc := True
        else if Sw = 'strictcase' then
          O.StrictCase := True
        else if Sw = 'blobtimeout' then
          O.BlobTimeout := Cardinal(NextInt)
        else if Sw = 'log' then
          O.LogFile := NextValue
        else if Sw = 'json' then
          O.Json := True
        else if Sw = 'quiet' then
          O.Quiet := True
        else
          raise EJ2GUsage.CreateFmt('unknown option: %s', [A]);
      end
      else
        Positional.Add(A);
      Inc(I);
    end;
    if Positional.Count > 1 then
      raise EJ2GUsage.CreateFmt('unexpected argument: %s', [Positional[1]]);
    if Positional.Count = 1 then
      J2GSplitHostPort(Positional[0], O.Host, O.Port);
    if O.NoGroup then
    begin
      if GroupGiven then
        raise EJ2GUsage.Create('-group and -nogroup are mutually exclusive');
      O.GroupMinutes := 0;
    end;
    if O.EncodeKeyFile <> '' then
      O.KeySource := ksFile
    else if O.EncodeKeyStdin then
      O.KeySource := ksStdin
    else if not O.NoEncodeKey then
      O.KeySource := ksRegistry;
  finally
    Positional.Free;
  end;
end;

// one line of the redirected stdin as raw bytes (ANSI), without CR/LF.
// False on EOF without data.
function ReadStdInLineBytes(out ABytes: TBytes): Boolean;
var
  H: THandle;
  B: Byte;
  N: DWORD;
  Got: Boolean;
begin
  ABytes := nil;
  Got := False;
  H := GetStdHandle(STD_INPUT_HANDLE);
  while ReadFile(H, B, 1, N, nil) and (N = 1) do
  begin
    Got := True;
    if B = 10 then
      Break;
    if B <> 13 then
    begin
      SetLength(ABytes, Length(ABytes) + 1);
      ABytes[High(ABytes)] := B;
    end;
  end;
  Result := Got;
end;

// prompt without echo (copy of ReadPassword, jvcs.dpr:8359-8406), as bytes
function ReadPasswordPrompt: TBytes;
var
  StdIn, StdOut: THandle;
  ConsoleMode: Cardinal;
  C: Char;
  CharsRead, CharsWritten: Cardinal;
  S: string;
  Enc: TEncoding;
begin
  S := '';
  Write('Password: ');
  StdIn := GetStdHandle(STD_INPUT_HANDLE);
  StdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  Win32Check(GetConsoleMode(StdIn, ConsoleMode));
  Win32Check(SetConsoleMode(StdIn, ConsoleMode and not ENABLE_ECHO_INPUT and not ENABLE_LINE_INPUT));
  try
    while ReadConsole(StdIn, @C, 1, CharsRead, nil) and (CharsRead = 1) do
    begin
      case C of
        #8:
          if Length(S) > 0 then
            Delete(S, Length(S), 1);
        #10, #13:
          begin
            Writeln;
            Break;
          end;
      else
        begin
          S := S + C;
          C := '*';
          WriteConsole(StdOut, @C, 1, CharsWritten, nil);
        end;
      end;
    end;
  finally
    SetConsoleMode(StdIn, ConsoleMode);
  end;
  Enc := TEncoding.GetEncoding(MWCodePage);
  try
    Result := Enc.GetBytes(S);
  finally
    Enc.Free;
  end;
  if S <> '' then
    FillChar(PChar(S)^, Length(S) * SizeOf(Char), 0);
end;

// resolves host/user/password; raises EJ2GError (2 or 4)
procedure ResolveCredentials(var O: TJ2GOptions; out APassword: TBytes; out AIdentityName: string);
var
  Ident: TJ2GIdentity;
  Err: string;
begin
  APassword := nil;
  AIdentityName := '';
  if O.Identity <> '' then
  begin
    if not J2GLoadIdentity(O.Identity, Ident, Err) then
      raise EJ2GError.Create(J2G_EXIT_CREDENTIAL, Err);
    AIdentityName := Ident.Name;
    if (O.Host <> '') and not SameText(O.Host, Ident.HostName) then
      O.AddWarning(Format('host of the command line overrides identity %s', [Ident.Name]));
    if (O.User <> '') and not SameText(O.User, Ident.User) then
      O.AddWarning(Format('user of the command line overrides identity %s', [Ident.Name]));
    if O.Host = '' then
    begin
      O.Host := Ident.HostName;
      if O.Port = '' then
        O.Port := Ident.Port;
    end;
    if O.User = '' then
      O.User := Ident.User;
    if not Ident.HasPassword then
      raise EJ2GError.CreateFmt(J2G_EXIT_CREDENTIAL,
        'identity ''%s'' has no saved password (check "Store Password with identity" in the JEDI VCS client)', [Ident.Name]);
    APassword := J2GIdentityPasswordBytes(Ident);
  end
  else
  begin
    if O.Host = '' then
      raise EJ2GUsage.Create('missing <host[:port]> or -identity <name>');
    if O.User = '' then
      raise EJ2GUsage.Create('missing -user <name> (or use -identity)');
    if StdInRedirected then
    begin
      if not ReadStdInLineBytes(APassword) or (Length(APassword) = 0) then
        raise EJ2GError.Create(J2G_EXIT_CREDENTIAL, 'password not given on stdin');
    end
    else
      APassword := ReadPasswordPrompt;
  end;
  if O.Port = '' then
    O.Port := '2106';
end;

// Blowfish key per KeySource; never logged
procedure ResolveKey(var O: TJ2GOptions; AReport: TJ2GReport);
var
  L: TStringList;
  Raw: TBytes;
  Line: string;
begin
  O.ClearKey;
  case O.KeySource of
    ksRegistry:
      O.EncodeKey := J2GRegistryEncodeKey;
    ksFile:
      begin
        if not FileExists(O.EncodeKeyFile) then
          raise EJ2GError.CreateFmt(J2G_EXIT_USAGE, '-encodekey-file not found: %s', [O.EncodeKeyFile]);
        L := TStringList.Create;
        try
          L.LoadFromFile(O.EncodeKeyFile, TEncoding.ANSI);
          if L.Count > 0 then
            Line := L[0]
          else
            Line := '';
          O.EncodeKey := J2GDecodeBase64(Line);
        finally
          L.Free;
        end;
      end;
    ksStdin:
      if ReadStdInLineBytes(Raw) then
      begin
        O.EncodeKey := J2GDecodeBase64(TEncoding.ANSI.GetString(Raw));
        J2GWipe(Raw);
      end;
  end;
  if (O.KeySource in [ksFile, ksStdin]) and (Length(O.EncodeKey) = 0) then
    AReport.Warn('invalid Blowfish key (not Base64): encrypted revisions will be skipped')
  else if (Length(O.EncodeKey) > 0) and ((Length(O.EncodeKey) < 8) or (Length(O.EncodeKey) > 65)) then
  begin
    AReport.Warn('invalid Blowfish key (length must be 8..65 bytes): encrypted revisions will be skipped');
    O.ClearKey;
  end;
end;

function ProjectsJson(const AList: TArray<TJ2GProjectInfo>): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to High(AList) do
    begin
      if I > 0 then
        SB.Append(',');
      SB.Append('{"id":').Append(AList[I].ProjectID)
        .Append(',"name":').Append(J2GJsonStr(AList[I].Name))
        .Append(',"deleted":').Append(J2GJsonBool(AList[I].Deleted)).Append('}');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function DoList(Session: TJ2GSession; const O: TJ2GOptions; Report: TJ2GReport): Integer;
var
  List, Shown: TArray<TJ2GProjectInfo>;
  P: TJ2GProjectInfo;
begin
  List := Session.GetProjects;
  Shown := nil;
  for P in List do
    if O.IncludeDeleted or not P.Deleted then
    begin
      SetLength(Shown, Length(Shown) + 1);
      Shown[High(Shown)] := P;
    end;
  Report.RawProjectsJson := ProjectsJson(Shown);
  Report.Message := Format('%d project(s)', [Length(Shown)]);
  if not O.Json then
  begin
    Writeln(Format('%6s  %s', ['ID', 'Project']));
    for P in Shown do
      if P.Deleted then
        Writeln(Format('%6d  %s  [deleted]', [P.ProjectID, P.Name]))
      else
        Writeln(Format('%6d  %s', [P.ProjectID, P.Name]));
    Writeln(Report.Message);
  end;
  Result := J2G_EXIT_OK;
end;

function J2GCliMain: Integer;
var
  O: TJ2GOptions;
  Report: TJ2GReport;
  Session: TJ2GSession;
  Password: TBytes;
  IdentityName, Msg, W: string;
  ConsoleMode: Cardinal;
  All, Selected: TArray<TJ2GProjectInfo>;
  I: Integer;
begin
  Result := J2G_EXIT_OK;
  DefaultSystemCodePage := MWCodePage;
  StdInRedirected := not GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), ConsoleMode);
  O.SetDefaults;
  // -json/-quiet must hold even when the parse stops before reaching them
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), '-json') or SameText(ParamStr(I), '/json') then
      O.Json := True
    else if SameText(ParamStr(I), '-quiet') or SameText(ParamStr(I), '/quiet') then
      O.Quiet := True;
  Report := TJ2GReport.Create;
  try
    try
      try
        ParseCommandLine(O);
      finally
        // JSON/quiet must be known even when the parse fails
        Report.JsonMode := O.Json;
        Report.Quiet := O.Quiet;
        Report.Command := J2GCommandName(O.Command);
      end;
      if not O.Json and not O.Quiet then
        ShowBanner;
      if O.Command = jcHelp then
      begin
        ShowUsage(Output);
        Exit(J2G_EXIT_OK);
      end;
      if not O.Validate(Msg) then
        raise EJ2GUsage.Create(Msg);
      if (O.Command in [jcExport, jcDryRun]) and J2GGitVersion(W) and
        not J2GGitCheckRefFormat(O.BranchName, True) then
        raise EJ2GUsage.CreateFmt('invalid -branch-name: %s', [O.BranchName]);

      if O.Command = jcSelfTest then
      begin
        if O.SelfTestName = 'paths' then
          Result := J2GRunSelfTestPaths(Report)
        else
          Result := J2GRunSelfTestBlob(Report);
        if Report.Message = '' then
          if Result = 0 then
            Report.Message := 'self test ' + O.SelfTestName + ' passed'
          else
            Report.Message := 'self test ' + O.SelfTestName + ' failed';
        Exit;
      end;

      if O.OutDir <> '' then
      begin
        try
          ForceDirectories(ExpandFileName(O.OutDir));
        except
          on E: Exception do
            raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'cannot create the output folder %s: %s', [O.OutDir, E.Message]);
        end;
        if not DirectoryExists(ExpandFileName(O.OutDir)) then
          raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'cannot create the output folder %s', [O.OutDir]);
      end;
      if O.EffectiveLogFile <> '' then
        try
          Report.OpenLog(O.EffectiveLogFile);
        except
          on E: Exception do
            raise EJ2GError.CreateFmt(J2G_EXIT_ENVIRONMENT, 'cannot write the log %s: %s', [O.EffectiveLogFile, E.Message]);
        end;

      ResolveCredentials(O, Password, IdentityName);
      for W in O.ParseWarnings do
        Report.Warn(W);
      if O.Command in [jcExport, jcDryRun] then
        ResolveKey(O, Report);

      Session := TJ2GSession.Create(Report);
      try
        try
          Session.Connect(O.Host, O.Port, O.User, Password, IdentityName);
        finally
          J2GWipe(Password);
        end;
        Session.SelectBranch(O.JvcsBranch);
        if O.Command = jcList then
          Result := DoList(Session, O, Report)
        else
        begin
          All := Session.GetProjects;
          if not J2GResolveProjects(All, O.Projects, O.AllProjects, O.IncludeDeleted, Selected, Msg) then
            raise EJ2GError.CreateFmt(J2G_EXIT_NOTFOUND, 'project not found: %s (use -list)', [Msg]);
          if Length(Selected) = 0 then
            raise EJ2GError.Create(J2G_EXIT_NOTFOUND, 'no project to export');
          if O.Command = jcDryRun then
            Result := J2GRunDryRun(Session, O, Selected, Report)
          else
            Result := J2GRunExport(Session, O, Selected, Report, nil, nil);
        end;
      finally
        Session.Free;
      end;
    except
      on E: EJ2GUsage do
      begin
        Result := J2G_EXIT_USAGE;
        Report.Message := E.Message;
        Writeln(ErrOutput, 'Error: ', E.Message);
        Writeln(ErrOutput);
        ShowUsage(ErrOutput);
      end;
      on E: EJ2GError do
      begin
        Result := E.ExitCode;
        Report.Message := E.Message;
        Report.Error(E.Message);
      end;
      on E: Exception do
      begin
        Result := J2G_EXIT_SERVER;
        Report.Message := E.ClassName + ': ' + E.Message;
        Report.Error(Report.Message);
      end;
    end;
  finally
    O.ClearKey;
    Report.ExitCode := Result;
    if Report.Message = '' then
      if Result = J2G_EXIT_OK then
        Report.Message := 'ok'
      else
        Report.Message := Report.Summary;
    if O.Command <> jcHelp then
      Report.Info(Format('exit code %d - %s', [Result, Report.Message]));
    if O.Json then
      Writeln(Report.ToJson);
    Report.Free;
  end;
end;

end.
