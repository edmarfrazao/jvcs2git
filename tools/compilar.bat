@echo off
rem ==========================================================================
rem  compilar.bat - compila o jvcs2git (Delphi 13, Win32, dcc32 direto)
rem
rem  Uso:   compilar.bat [cli|gui|all] [Debug|Release] [/info]
rem         Padrao: all Release
rem
rem  Saidas: bin\Win32\jvcs2git.exe, bin\Win32\jvcs2git-cli.exe, fvcscrypt.dll
rem          DCUs em dcu\Win32\<cfg>\<alvo>; logs em tools\logs
rem
rem  Units do JEDI VCS (conexao, protocolo, ZIP, Blowfish, CRC, UTC):
rem    %JVCS_ROOT% se definido (so para desenvolvimento local; deve estar na
rem    mesma tag fixada pelo submodulo), senao external\JEDI_VCS (submodulo).
rem  O Delphi e as bibliotecas do GetIt (JCL, ICS, Abbrevia) sao achados por
rem  <JVCS>\tools\versao-delphi.bat + versoes.ini (pasta padrao do RAD Studio
rem  ou BDSROOT; JVCS_CATALOG muda o CatalogRepository).
rem  Copia REDUZIDA de JEDI_VCS tools\compilar.bat: sem SynEdit/VTV/JVCL,
rem  sem MSBuild, sem Win64.
rem ==========================================================================
setlocal EnableExtensions DisableDelayedExpansion

set "BLD_CODEPAGE=1252"
set "BLD_MAXERR=5"
set "BLD_NS=Winapi;System.Win;Data.Win;Datasnap.Win;Web.Win;Soap.Win;Xml.Win;System;Data;Datasnap;Web;Soap;Xml;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell"
rem  Defines iguais nos dois exes (JVCSCONSOLECLIENT tambem vem do compopt.inc)
set "BLD_DEFINES=DelphiPersonalEdition;JVCSCONSOLECLIENT;BRANCHING;OVERBYTEV6_UP"

for %%I in ("%~dp0..") do set "BLD_ROOT=%%~fI"
for %%I in ("%~dp0.") do set "BLD_TOOLS=%%~fI"
set "BLD_SRC=%BLD_ROOT%\src"
set "BLD_LOGDIR=%BLD_TOOLS%\logs"

set "PRJ_cli_NAME=jvcs2git-cli"
set "PRJ_gui_NAME=jvcs2git"
set "ALL_PROJECTS=cli gui"

rem ---- Parametros -----------------------------------------------------------
set "BLD_WHAT="
set "BLD_CFG="
set "BLD_INFO=0"
:args
if "%~1"=="" goto :args_done
if "%~1"=="/?" goto :usage
if /i "%~1"=="-h" goto :usage
if /i "%~1"=="/info" (set "BLD_INFO=1") else if not defined BLD_WHAT (set "BLD_WHAT=%~1") else if not defined BLD_CFG (set "BLD_CFG=%~1") else (echo [AVISO] parametro ignorado: %~1)
shift
goto :args
:args_done
if not defined BLD_WHAT set "BLD_WHAT=all"
if not defined BLD_CFG set "BLD_CFG=Release"
set "BLD_TARGETS="
if /i "%BLD_WHAT%"=="all" set "BLD_TARGETS=%ALL_PROJECTS%"
for %%P in (%ALL_PROJECTS%) do if /i "%%P"=="%BLD_WHAT%" set "BLD_TARGETS=%%P"
if not defined BLD_TARGETS goto :bad_what
if /i "%BLD_CFG%"=="Debug" (set "BLD_CFG=Debug") else if /i "%BLD_CFG%"=="Release" (set "BLD_CFG=Release") else goto :bad_cfg

rem ---- Raiz do JEDI VCS -------------------------------------------------------
if defined JVCS_ROOT (
    set "BLD_JVCS=%JVCS_ROOT:"=%"
    set "BLD_JVCSHOW=JVCS_ROOT"
) else (
    set "BLD_JVCS=%BLD_ROOT%\external\JEDI_VCS"
    set "BLD_JVCSHOW=submodulo"
)
if "%BLD_JVCS:~-1%"=="\" set "BLD_JVCS=%BLD_JVCS:~0,-1%"
if not exist "%BLD_JVCS%\tools\msbuild\JediVCS2026.props" goto :no_jvcs
if not exist "%BLD_JVCS%\tools\versao-delphi.bat" goto :no_jvcs
if "%BLD_JVCSHOW%"=="submodulo" for /f "usebackq delims=" %%S in (`git -C "%BLD_JVCS%" rev-parse --short HEAD 2^>nul`) do set "BLD_JVCSHOW=submodulo external\JEDI_VCS @ %%S"

rem ---- Delphi (versao-delphi.bat do JEDI VCS, Delphi 13) ----------------------
call "%BLD_JVCS%\tools\versao-delphi.bat" "13"
if errorlevel 1 goto :bad_ver
set "BLD_BDSDIR=%VD_BDSDIR%"

if /i "%BLD_CFG%"=="Debug" (
    set "BLD_LIBCFG=debug"
    set "BLD_SW=-$O- -$Q+ -$R+ -$C+ -$D+ -$L+ -$Y+ -V -GD -DDEBUG"
) else (
    set "BLD_LIBCFG=release"
    set "BLD_SW=-$O+ -$Q- -$R- -$C- -$D- -$L- -$Y- -DRELEASE"
)
set "BLD_SW=%BLD_SW% -W+ -H-"

rem ---- Bibliotecas do GetIt (JCL, ICS, Abbrevia) ------------------------------
if not defined JVCS_CATALOG if defined VD_CATALOG set "JVCS_CATALOG=%VD_CATALOG%"
if not defined BLD_DOCS for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')"`) do set "BLD_DOCS=%%D"
if not defined BLD_DOCS set "BLD_DOCS=%USERPROFILE%\Documents"
if not defined JVCS_CATALOG if not exist "%BLD_DOCS%\Embarcadero\Studio\%BDSVER%\CatalogRepository\" if exist "%USERPROFILE%\Documents\Embarcadero\Studio\%BDSVER%\CatalogRepository\" set "BLD_DOCS=%USERPROFILE%\Documents"
if not defined JVCS_CATALOG set "JVCS_CATALOG=%BLD_DOCS%\Embarcadero\Studio\%BDSVER%\CatalogRepository"
set "JVCS_CATALOG=%JVCS_CATALOG:"=%"
if "%JVCS_CATALOG:~-1%"=="\" set "JVCS_CATALOG=%JVCS_CATALOG:~0,-1%"
set "BLD_CATALL=%PUBLIC%\Documents\Embarcadero\Studio\%BDSVER%\CatalogRepository"
set "CAT_jcl_PAT=JEDICodeLibraryJCL JCL"
set "CAT_jcl_MARK=source\include\jedi\jedi.inc"
set "CAT_ics_PAT=ICS_VCL ICS"
set "CAT_ics_MARK=Source\Include\OverbyteIcsDefs.inc"
set "CAT_abbrevia_PAT=Abbrevia"
set "CAT_abbrevia_MARK=source\AbBase.pas"
call :find_cat jcl "%VD_JCL%"
call :find_cat ics "%VD_ICS%"
call :find_cat abbrevia "%VD_ABBREVIA%"
set "BLD_JCLDIR=%CAT_jcl_DIR%"
set "BLD_ICSDIR=%CAT_ics_DIR%"
set "BLD_ABBDIR=%CAT_abbrevia_DIR%"
if not defined BLD_JCLDIR set "BLD_JCLDIR=%JVCS_CATALOG%\JCL-nao-encontrada"
if not defined BLD_ICSDIR set "BLD_ICSDIR=%JVCS_CATALOG%\ICS-nao-encontrado"
if not defined BLD_ABBDIR set "BLD_ABBDIR=%JVCS_CATALOG%\Abbrevia-nao-encontrada"
if not defined JCL_PATH set "JCL_PATH=%BLD_JCLDIR%\lib\%VD_JCLLIB%\win32"
if not defined JCL_INC set "JCL_INC=%BLD_JCLDIR%\source\include;%BLD_JCLDIR%\source\include\jedi"
if not defined ICS_PATH set "ICS_PATH=%BLD_ICSDIR%\Lib\%BLD_CFG%\Win32\%BDSVER%"
if not defined ICS_INC set "ICS_INC=%BLD_ICSDIR%\Source\Include;%BLD_ICSDIR%\Source"
if not defined ABBREVIA_PATH set "ABBREVIA_PATH=%BLD_ABBDIR%\packages\11AndAbove\Delphi\Win32\%BLD_CFG%"
if not defined ABBREVIA_INC set "ABBREVIA_INC=%BLD_ABBDIR%\source"

rem  Units do JEDI VCS (absolutas: o dcc roda em src\)
set "BLD_JPATH=%BLD_JVCS%\src\common;%BLD_JVCS%\src\common\client;%BLD_JVCS%\src\comp\midware;%BLD_JVCS%\src\comp\crc;%BLD_JVCS%\src\comp\mwtools"
rem  J2G_OUTDIR / J2G_DCUDIR (opcional): pastas proprias de saida (builds paralelos)
set "BLD_OUTDIR=%BLD_ROOT%\bin\Win32"
set "BLD_DCUBASE=%BLD_ROOT%\dcu\Win32\%BLD_CFG%"
if defined J2G_OUTDIR set "BLD_OUTDIR=%J2G_OUTDIR:"=%"
if defined J2G_DCUDIR set "BLD_DCUBASE=%J2G_DCUDIR:"=%\%BLD_CFG%"
if defined J2G_DCUDIR set "BLD_LOGDIR=%J2G_DCUDIR:"=%\logs"

if "%BLD_INFO%"=="1" goto :show_info

if not "%VD_INSTALLED%"=="1" goto :not_installed
set "BLD_DCC=%BLD_BDSDIR%\bin\dcc32.exe"
set "BLD_BRCC=%BLD_BDSDIR%\bin\brcc32.exe"
if not exist "%BLD_DCC%" goto :no_dcc
set "BLD_LIBDIR=%BLD_BDSDIR%\lib\win32\%BLD_LIBCFG%"
set "BLD_RELDIR=%BLD_BDSDIR%\lib\win32\release"
if not exist "%BLD_LIBDIR%" goto :no_lib
if not exist "%BLD_LOGDIR%" mkdir "%BLD_LOGDIR%"
if not exist "%BLD_OUTDIR%" mkdir "%BLD_OUTDIR%"
call :write_props

set "BLD_UPATH=%BLD_LIBDIR%;%BLD_JPATH%;%JCL_PATH%;%ICS_PATH%;%ABBREVIA_PATH%"
set "BLD_IPATH=%BLD_SRC%;%BLD_JVCS%\src\comp\midware;%JCL_INC%;%ICS_INC%;%ABBREVIA_INC%"
set "BLD_RPATH=%BLD_RELDIR%;%BLD_IPATH%"

echo Raiz    : %BLD_ROOT%
echo Raiz JVCS: %BLD_JVCS% ^(%BLD_JVCSHOW%^)
echo Delphi  : %VD_NAME% - %BLD_BDSDIR% ^(BDSVER %BDSVER%^)
echo Config  : %BLD_CFG% Win32
echo Catalog : %JVCS_CATALOG%
echo Saida   : %BLD_OUTDIR%
call :chkdir JCL "%JCL_PATH%"
call :chkdir ICS "%ICS_PATH%"
call :chkdir Abbrevia "%ABBREVIA_PATH%"

set "BLD_RESULT=0"
for %%K in (%BLD_TARGETS%) do call :build_one %%K
if /i "%BLD_RESULT%"=="0" if exist "%BLD_JVCS%\3rdparty\fvcscrypt.dll" copy /y "%BLD_JVCS%\3rdparty\fvcscrypt.dll" "%BLD_OUTDIR%\" >nul
echo.
if "%BLD_RESULT%"=="0" echo Compilacao concluida sem erros.
if not "%BLD_RESULT%"=="0" echo Compilacao terminou com falhas - codigo %BLD_RESULT%. Logs em: %BLD_LOGDIR%
endlocal & exit /b %BLD_RESULT%

rem ==========================================================================
:build_one
set "BLD_K=%~1"
call set "BLD_NAME=%%PRJ_%BLD_K%_NAME%%"
set "BLD_LOG=%BLD_LOGDIR%\compilar_%BLD_K%_Win32_%BLD_CFG%.log"
set "BLD_DCUOUT=%BLD_DCUBASE%\%BLD_K%"
if not exist "%BLD_DCUOUT%" mkdir "%BLD_DCUOUT%"
echo.
echo ==== %BLD_K% : %BLD_NAME% - Win32 %BLD_CFG% ====
>"%BLD_LOG%" echo # compilar.bat - %BLD_NAME%.dpr - Win32 %BLD_CFG% - %VD_NAME% - %DATE% %TIME%
>>"%BLD_LOG%" echo # Raiz JVCS  : %BLD_JVCS% (%BLD_JVCSHOW%)
>>"%BLD_LOG%" echo # Defines    : %BLD_DEFINES%
>>"%BLD_LOG%" echo # Unit path  : %BLD_UPATH%
>>"%BLD_LOG%" echo # Include    : %BLD_IPATH%
pushd "%BLD_SRC%"
rem  .res fora de src\ (o -R aponta primeiro para a pasta de DCUs do alvo)
"%BLD_BRCC%" -fo"%BLD_DCUOUT%\%BLD_NAME%.res" "%BLD_NAME%.rc" >>"%BLD_LOG%" 2>&1
set "BLD_RC=%ERRORLEVEL%"
if "%BLD_RC%"=="0" "%BLD_DCC%" --no-config -B -Q %BLD_SW% --codepage:%BLD_CODEPAGE% "-D%BLD_DEFINES%" "-NS%BLD_NS%" "-U%BLD_UPATH%" "-I%BLD_IPATH%" "-R%BLD_DCUOUT%;%BLD_RPATH%" "-E%BLD_OUTDIR%" "-NU%BLD_DCUOUT%" "%BLD_NAME%.dpr" >>"%BLD_LOG%" 2>&1
if "%BLD_RC%"=="0" set "BLD_RC=%ERRORLEVEL%"
popd
if "%BLD_RC%"=="0" (
    echo [OK] %BLD_NAME%.exe
    findstr /i /c:"Warning:" "%BLD_LOG%" >nul && echo      ^(ha avisos no log: %BLD_LOG%^)
    goto :eof
)
set "BLD_RESULT=%BLD_RC%"
echo [FALHOU] %BLD_NAME% ^(veja o log: %BLD_LOG%^)
call :show_errors
goto :eof

rem ---- :find_cat CHAVE "VALOR_DO_INI" -> CAT_<chave>_DIR ---------------------
:find_cat
set "FC_R="
set "FC_V=%~2"
call set "FC_MARK=%%CAT_%~1_MARK%%"
call set "FC_PAT=%%CAT_%~1_PAT%%"
if defined FC_V call :fc_ini
if defined FC_R goto :fc_done
for %%C in ("%JVCS_CATALOG%" "%BLD_CATALL%") do if not defined FC_R for %%P in (%FC_PAT%) do for /d %%D in ("%%~C\%%P*") do call :fc_dir "%%~fD"
:fc_done
set "CAT_%~1_DIR=%FC_R%"
goto :eof

:fc_ini
if exist "%JVCS_CATALOG%\%FC_V%\" call :fc_dir "%JVCS_CATALOG%\%FC_V%"
if defined FC_R goto :eof
if exist "%BLD_CATALL%\%FC_V%\" call :fc_dir "%BLD_CATALL%\%FC_V%"
if defined FC_R goto :eof
set "FC_T=%FC_V::=%"
if "%FC_T%"=="%FC_V%" if not "%FC_V:~0,2%"=="\\" goto :eof
if exist "%FC_V%\" call :fc_dir "%FC_V%"
goto :eof

:fc_dir
if exist "%~1\%FC_MARK%" set "FC_R=%~f1" & goto :eof
for /d %%S in ("%~1\*") do if exist "%%~fS\%FC_MARK%" set "FC_R=%%~fS"
goto :eof

rem ---- :write_props - pastas do GetIt para os .dproj (lido por JediVCS2026.props)
rem  Gravado em <JVCS>\lib\paths (unico lugar que JediVCS2026.props le; /lib/ e
rem  ignorado pelo git do JEDI VCS).
:write_props
set "BLD_PROPSDIR=%BLD_JVCS%\lib\paths"
set "BLD_PROPS=%BLD_PROPSDIR%\JediVCS2026-%BDSVER%.props"
if not exist "%BLD_PROPSDIR%" mkdir "%BLD_PROPSDIR%" 2>nul
>"%BLD_PROPS%" echo ^<?xml version="1.0" encoding="utf-8"?^>
>>"%BLD_PROPS%" echo ^<!-- Gerado por jvcs2git tools\compilar.bat em %DATE% %TIME% - %VD_NAME% (BDS %BDSVER%). --^>
>>"%BLD_PROPS%" echo ^<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"^>
>>"%BLD_PROPS%" echo   ^<PropertyGroup^>
if defined CAT_jcl_DIR >>"%BLD_PROPS%" echo     ^<JvcsJclDir Condition="'$(JvcsJclDir)'==''"^>%CAT_jcl_DIR%^</JvcsJclDir^>
if defined CAT_ics_DIR >>"%BLD_PROPS%" echo     ^<JvcsIcsDir Condition="'$(JvcsIcsDir)'==''"^>%CAT_ics_DIR%^</JvcsIcsDir^>
if defined CAT_abbrevia_DIR >>"%BLD_PROPS%" echo     ^<JvcsAbbreviaDir Condition="'$(JvcsAbbreviaDir)'==''"^>%CAT_abbrevia_DIR%^</JvcsAbbreviaDir^>
>>"%BLD_PROPS%" echo     ^<JvcsJclLib Condition="'$(JvcsJclLib)'==''"^>%VD_JCLLIB%^</JvcsJclLib^>
>>"%BLD_PROPS%" echo   ^</PropertyGroup^>
>>"%BLD_PROPS%" echo ^</Project^>
goto :eof

:show_info
echo Raiz          : %BLD_ROOT%
echo Raiz JVCS     : %BLD_JVCS% ^(%BLD_JVCSHOW%^)
echo Delphi        : %VD_NAME% ^(BDS %BDSVER%^) - %BLD_BDSDIR%
if not "%VD_INSTALLED%"=="1" echo                 [NAO INSTALADO]
echo Catalog       : %JVCS_CATALOG%
call :chkdir JCL "%JCL_PATH%"
call :chkdir ICS "%ICS_PATH%"
call :chkdir Abbrevia "%ABBREVIA_PATH%"
echo JCL           : %JCL_PATH%
echo ICS           : %ICS_PATH%
echo Abbrevia      : %ABBREVIA_PATH%
echo Saida         : %BLD_OUTDIR%
endlocal & exit /b 0

:show_errors
setlocal EnableDelayedExpansion
set /a "BLD_N=0"
for /f "usebackq delims=" %%L in (`findstr /i /c:"Fatal:" /c:"Error:" /c:"error F" /c:"error E" "!BLD_LOG!"`) do (
    set /a "BLD_N+=1"
    if !BLD_N! leq %BLD_MAXERR% (
        set "BLD_LINE=%%L"
        echo     !BLD_LINE!
    )
)
endlocal
goto :eof

:chkdir
if not exist "%~2" echo [AVISO] %~1: pasta de DCUs nao encontrada: %~2
goto :eof

:usage
echo Uso: %~nx0 [cli^|gui^|all] [Debug^|Release] [/info]
echo      Padrao: all Release. Saida em bin\Win32.
echo      JVCS_ROOT: raiz de um checkout do JEDI_VCS ^(padrao: external\JEDI_VCS^).
echo      BDSROOT, JVCS_CATALOG: como no tools\compilar.bat do JEDI VCS.
endlocal & exit /b 0

:no_jvcs
echo [ERRO] JEDI_VCS nao encontrado em "%BLD_JVCS%".
echo        Rode: git submodule update --init   ^(ou defina JVCS_ROOT^)
endlocal & exit /b 1

:bad_ver
echo [ERRO] %VD_ERR%
endlocal & exit /b 1

:bad_what
echo [ERRO] Alvo invalido: "%BLD_WHAT%". Use cli, gui ou all.
endlocal & exit /b 1

:bad_cfg
echo [ERRO] Configuracao invalida: "%BLD_CFG%". Use Debug ou Release.
endlocal & exit /b 1

:not_installed
echo [ERRO] %VD_NAME% ^(BDS %BDSVER%^) nao esta instalado: falta "%BLD_BDSDIR%\bin\dcc32.exe".
endlocal & exit /b 1

:no_dcc
echo [ERRO] Compilador nao encontrado: "%BLD_DCC%"
endlocal & exit /b 1

:no_lib
echo [ERRO] Pasta de DCUs da RTL/VCL nao encontrada: "%BLD_LIBDIR%"
endlocal & exit /b 1
