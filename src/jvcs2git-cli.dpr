(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: jvcs2git-cli.dpr

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git-cli.exe - console of the JEDI VCS to Git exporter (scripts, AI).
The JEDI VCS units come from the search path (external\JEDI_VCS or JVCS_ROOT,
see tools\compilar.bat and tools\msbuild\jvcs2git.props).

-----------------------------------------------------------------------------*)

program jvcs2git_cli;

{$I jedi.inc}
{$I compopt.inc}
{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  J2GModel in 'J2GModel.pas',
  J2GOptions in 'J2GOptions.pas',
  J2GIdentity in 'J2GIdentity.pas',
  J2GReport in 'J2GReport.pas',
  J2GSession in 'J2GSession.pas',
  J2GFetch in 'J2GFetch.pas',
  J2GPaths in 'J2GPaths.pas',
  J2GGrouping in 'J2GGrouping.pas',
  J2GAuthors in 'J2GAuthors.pas',
  J2GBlob in 'J2GBlob.pas',
  J2GFastImport in 'J2GFastImport.pas',
  J2GGit in 'J2GGit.pas',
  J2GExport in 'J2GExport.pas',
  J2GDryRun in 'J2GDryRun.pas',
  J2GSelfTestPaths in 'J2GSelfTestPaths.pas',
  J2GSelfTestBlob in 'J2GSelfTestBlob.pas',
  J2GCli in 'J2GCli.pas';

{$R jvcs2git-cli.res}

begin
  ExitCode := J2GCliMain;
end.
