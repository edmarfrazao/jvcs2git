@echo off
rem ==========================================================================
rem  executar.bat - roda tests\teste-jvcs2git.ps1 (Windows PowerShell 5.1)
rem
rem  Uso: executar.bat [-Servidor host:porta] [-Identidade DEFAULT]
rem                    [-Console <jvcs.exe>] [-Saida <pasta>] [-Cli <jvcs2git-cli.exe>]
rem                    [-Projeto exemplo01.dpr] [-ProjetoLabels ex4ia.dpr]
rem  Console padrao: %JVCS_ROOT%\bin\client\Win32\jvcs.exe, depois
rem  %ProgramFiles(x86)%\JEDI\JVCS 2026\jvcs.exe.
rem  So rode contra um servidor JEDI VCS de TESTE.
rem  Codigo de saida: 0 = nada falhou; 1 = houve falha.
rem ==========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0teste-jvcs2git.ps1" %*
exit /b %ERRORLEVEL%
