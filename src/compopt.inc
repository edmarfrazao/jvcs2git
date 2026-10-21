(* jvcs2git - opcoes de compilacao (compartilhado pelos dois .dpr e pelas units
   do JEDI VCS que fazem {$I compopt.inc}: JVCSConnect, JVCSClientObjBase,
   JVCSClientDispatcher, TZHandling, JVCSForms).
   Copia de JEDI_VCS src\jvcs\COMPOPT.INC SEM {$APPTYPE}: cada .dpr declara o seu
   (jvcs2git-cli.dpr = CONSOLE; jvcs2git.dpr = GUI, o padrao).
   JVCSCONSOLECLIENT vale para os dois: evita que TZHandling puxe VCSBase
   (cliente GUI inteiro do JEDI VCS). *)

{$IFDEF JVCS_INMAKE}
  // usado so por makefiles que definem tudo por fora
{$ELSE}

  {$A+,B-,E-,F-,G+,H+,I+,J+,K-,M-,N+,P+,S-,T-,U-,V+,W-,X+,Y+,Z1}
  {$MINSTACKSIZE $00004000}
  {$MAXSTACKSIZE $00100000}

  {$DEFINE JVCSCONSOLECLIENT}

{$ENDIF JVCS_INMAKE}
