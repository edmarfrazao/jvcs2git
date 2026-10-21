# Changelog

Todas as mudanças relevantes do **jvcs2git**. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões em [SemVer](https://semver.org/lang/pt-BR/).

## [Não publicado]

## [0.1.1] — 2026-10-20

### Corrigido
- Arquivo de 0 bytes era pulado como `noBlob` (e o check-in que só tinha ele não virava commit); agora entra
  vazio no Git. `noBlob` fica só para blob ausente no servidor.

### Testes
- Caso 10 em `tests\teste-jvcs2git.ps1`: projeto `zz-teste-jvcs2git-vazio.dpr` (criado pelo console no servidor
  de teste se faltar) com um arquivo vazio; 76 casos.

## [0.1.0] — 2026-10-20

Primeira versão. Unidades do JEDI VCS: submódulo `external/JEDI_VCS` na tag `v2.5.0.2026-beta6-build2063` (`65908e1`).

### Adicionado
- Exporta projetos do JEDI VCS 2.5 para repositórios Git (um por projeto) **pelo protocolo do servidor**
  (Firebird, MSSQL, Oracle, MySQL sem cliente de banco), com `git fast-import`.
- `jvcs2git-cli.exe` (console: `-list`, `-dryrun`, exportação, `-selftest paths|blob`, `-json` numa linha,
  códigos de saída 0/2/4/5/9/11/12) e `jvcs2git.exe` (janela) sobre as mesmas units.
- Senha só por identidade salva (`-identity`), stdin redirecionado ou prompt sem eco; não existe `-password`.
  Chave Blowfish só do registro do cliente, `-encodekey-file` ou `-encodekey-stdin`.
- Histórico completo: revisões ordenadas pelo RevisionID, autores por `autores.txt` (gerado na 1ª execução),
  datas do log do servidor (heurística usuário+comentário) ou do arquivo, validadas (nada antes de 1980 nem
  no futuro) e committer monotônico; check-ins agrupados por usuário+comentário (`-group`, `-nogroup`,
  `-group-maxspan`, padrão 168 h para datas de arquivo).
- Labels como tags anotadas (nomes válidos para o git, colisões sem diferença de caixa), "tag aproximada"
  no relatório quando nem todas as revisões rotuladas estão no commit.
- `.dfm` binário convertido para texto (`-nodfmtext` mantém os bytes), membros removidos viram `D`,
  caminhos fora da raiz em `_externos/`, nomes inválidos no Windows saneados, uma grafia por módulo.
- Cache de blobs com retomada (`-keepcache`, `-nogit`), `-force` só para repositório gerado pelo jvcs2git,
  relatório `jvcs2git-relatorio.md` e log `jvcs2git.log`.
- Exclusão mútua com o wrapper de IA do JEDI VCS (mesmo mutex da identidade).
- Skills pt/en para IA, documentação en/pt, `tests\teste-jvcs2git.ps1`, `tools\compilar.bat`,
  `tools\gerar-release.ps1`.
