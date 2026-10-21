(*-----------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License
Version 1.1 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/MPL-1.1.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either expressed or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: jvcs2git.dpr

The Initial Developer of the Original Code is Edmar Frazao.
Portions created by Edmar Frazao are Copyright (C) 2026 Edmar Frazao.
All Rights Reserved.
-----------------------------------------------------------------------------

jvcs2git.exe - window of the JEDI VCS to Git exporter (Archive Admin).
Same engine units as jvcs2git-cli.exe.

-----------------------------------------------------------------------------*)

program jvcs2git;

{$I jedi.inc}
{$I compopt.inc}

uses
  System.SysUtils,
  Vcl.Forms,
  RFormat,
  JVCSUIScale,
  JVCSUITheme,
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
  J2GMain in 'J2GMain.pas' {J2GMainForm};

{$R jvcs2git.res}

begin
  // records of the protocol use ShortString: align with the protocol code page
  DefaultSystemCodePage := MWCodePage;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  JVCSUIInitialize;           // font/scale of the JEDI VCS client (JVCSUIScale)
  JVCSUIThemeInitialize;      // light/dark theme of the client (JVCSUITheme)
  JVCSUIStartFollowingSystem; // follows the Windows theme change
  Application.Title := 'jvcs2git';
  Application.CreateForm(TJ2GMainForm, J2GMainForm);
  Application.Run;
end.
