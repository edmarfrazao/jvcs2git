# jvcs2git — exportador do JEDI VCS para Git

[English](README.md) · **Português (Brasil)**

O **jvcs2git** migra projetos do **JEDI VCS 2.5** (sucessor do **FreeVCS**) para o **Git** com todo o
histórico: cada revisão, autor, data e comentário de check-in, e os labels do JEDI VCS como tags do Git. Ele
conversa com o servidor de aplicação do JEDI VCS pelo próprio protocolo (não precisa de cliente de banco:
arquivos em Firebird, MSSQL, Oracle ou MySQL funcionam igual) e monta os repositórios com **`git fast-import`**:
sem working tree, sem laço de `git add`, sem problema de maiúsculas. Escrito em **Delphi** 13, sobre as units
do cliente JEDI VCS.

- Um repositório Git por projeto do JEDI VCS (módulos compartilhados aparecem em cada projeto que os usa).
- Check-ins do mesmo usuário com o mesmo comentário viram um commit só (`-group 10`, ou `-nogroup`).
- Hora real do check-in tirada do log do servidor; datas em UTC (ou `-localtime`).
- `.dfm` binário convertido para texto; membros da família (`.pas` + `.dfm`) no mesmo commit.
- Labels exportados como tags anotadas; mapa de autores `login=Nome <email>`.
- Relatório de tudo o que ficou de fora (revisões cifradas, erro de CRC, blob ausente) em Markdown e JSON.
- Janela para o administrador do arquivo (`jvcs2git.exe`) e console para scripts e agentes de IA
  (`jvcs2git-cli.exe`, saída JSON e códigos de saída), mais uma [skill do Claude Code](skills/pt/jvcs2git/SKILL.md).

Ele só **lê** o servidor JEDI VCS: nunca altera projetos, módulos ou revisões e nunca faz checkout.

## Requisitos

- Windows; **Git 2.x no PATH** (testado com 2.54; nenhuma versão específica exigida).
- `fvcscrypt.dll` ao lado dos executáveis (vem no zip).
- Servidor JEDI VCS 2.5 e um usuário com direito de **Archive Admin**.
- Feche a janela do JEDI VCS e não rode o wrapper da IA (`jvcs-ai.ps1`) nem seus hooks durante a exportação:
  num servidor sem branching, um novo login do mesmo usuário derruba a sessão anterior.

## Uso rápido

Salve o login no cliente JEDI VCS (Server Login → *Store Password with identity*) e use-o com `-identity` (a
senha é lida da identidade salva, nunca da linha de comando):

```bat
jvcs2git-cli -identity DEFAULT -list -json < NUL
jvcs2git-cli -identity DEFAULT -project meuapp.dpr -out D:\git -dryrun -json < NUL
rem  preencha D:\git\autores.txt  (login=Nome Completo <email>)
jvcs2git-cli -identity DEFAULT -project meuapp.dpr -out D:\git -json < NUL
```

Sem identidade salva: `jvcs2git-cli servidor:2106 -user admin -project meuapp.dpr -out D:\git` pede a senha
(sem eco) ou a lê da primeira linha do stdin redirecionado. Não existe opção `-password`.

Saída em `<out>`:

| Caminho | Conteúdo |
|---|---|
| `<out>\<repo>\` | o repositório Git (branch `main`) |
| `<out>\<repo>.fast-import` | o stream do `git fast-import` |
| `<out>\.jvcs2git-cache\` | blobs baixados (retomada após queda; apagado no fim salvo `-keepcache`/`-nogit`) |
| `<out>\jvcs2git.log` | log (acrescentado a cada execução) |
| `<out>\jvcs2git-relatorio.md` | relatório: contagens, membros pulados, avisos |
| `<out>\autores.txt` | mapa de autores `login=Nome <email>` |

## Fluxo recomendado

1. `-list -json`: descobrir o nome exato ou o ID do projeto.
2. `-dryrun`: plano de commits sem baixar conteúdo; cria o `autores.txt` e lista `unmappedAuthors`.
3. Preencher o `autores.txt`. **O Git não permite corrigir autores depois sem reescrever o histórico.**
4. Exportar.
5. Validar: `git log --stat`, `git tag -n`, `jvcs2git-relatorio.md` (pulados, datas substituídas, avisos) e
   uma compilação do projeto a partir do checkout. Guarde o backup do JEDI VCS.

## Códigos de saída

| Código | Significado |
|---|---|
| 0 | ok |
| 2 | erro de uso |
| 4 | credencial (identidade inexistente ou sem senha, login recusado, senha ausente no stdin) |
| 5 | projeto (ou ramo do JEDI VCS) não encontrado |
| 9 | servidor/conexão (servidor fora, sessão derrubada por outro login) |
| 11 | parcial: membros pulados, ou um projeto falhou com `-all` |
| 12 | ambiente: Git ausente, `fvcscrypt.dll` ausente, pasta sem gravação, pasta do repositório já existe, mutex do wrapper da IA ocupado |

Com `-json` o stdout tem só uma linha JSON (`ok`, `command`, `exitCode`, `message`, `projects[]` com
`skipped[]` e `warnings[]`...); as mensagens vão para a stderr. Veja [doc/pt/Uso.md](doc/pt/Uso.md).

## Limitações

- **Módulos renomeados ou movidos:** o servidor guarda só o nome e a pasta atuais; todo o histórico sai com o
  caminho atual.
- **Módulos removidos do projeto** não aparecem (o servidor não os lista para o projeto).
- **Ramos:** só o ramo selecionado do JEDI VCS (`HEAD` por padrão) é exportado.
- **Datas:** o servidor guarda a hora real do check-in só no log; sem o log (`-nolog`, log desligado) a data do
  commit é a hora do arquivo na estação. Datas inválidas (zero, antes de 1980, futuro) são substituídas e
  listadas no relatório; a data de committer é monotônica para o `git log --since` funcionar.
- **Labels:** um label marca uma revisão por módulo; a tag aponta para o commit com a mais recente delas ("tag
  aproximada" no relatório quando o estado difere).
- **Caixa:** a grafia do nome é fixada por módulo (pela revisão mais recente); pastas saem em minúsculas;
  módulos que diferem só pela caixa são renomeados e avisados.
- **Revisões cifradas** precisam da chave Blowfish (registro do cliente ou `-encodekey-file`); sem ela são
  puladas e relatadas.
- **Conteúdo** copiado byte a byte; só nomes e comentários passam de cp1252 para UTF-8.

Mais em [doc/pt/Limitacoes.md](doc/pt/Limitacoes.md).

## Como funciona

Para cada projeto: lê módulos, revisões, histórico por módulo, labels e o log do servidor (requisições só de
leitura `GET_*`, nunca checkout); ordena as revisões pelo ID; agrupa em commits; baixa cada membro com
`GET_SINGLE_BLOB` (descompacta ou decifra, confere o CRC, converte `.dfm` binário, guarda em cache); escreve o
stream do `git fast-import`; depois `git init`, `git fast-import` e `git checkout`. Detalhes em
[doc/pt/Como-funciona.md](doc/pt/Como-funciona.md).

## Compilação

Delphi 13 (Win32) com JCL, ICS 9 e Abbrevia do GetIt. As units do JEDI VCS vêm do submódulo
`external/JEDI_VCS`, fixado na tag `v2.5.0.2026-beta6-build2063` (`65908e1`):

```bat
git clone --recurse-submodules https://github.com/edmarfrazao/jvcs2git
cd jvcs2git
tools\compilar.bat            rem all Release -> bin\Win32\jvcs2git.exe, jvcs2git-cli.exe, fvcscrypt.dll
tools\compilar.bat cli Debug
```

Os `.dproj` em `src\` abrem na IDE (`tools\msbuild\jvcs2git.props`). `JVCS_ROOT` pode apontar para um checkout
local do JEDI VCS **só para desenvolvimento**, na mesma tag do submódulo. Veja
[doc/pt/Como-compilar.md](doc/pt/Como-compilar.md).

Testes contra um servidor **de teste**: `tests\executar.bat` ([tests/teste-jvcs2git.ps1](tests/teste-jvcs2git.ps1)).

## Trabalhos anteriores

Dois exportadores anteriores (2018, sem manutenção) foram estudados:

- [DGH2112/JEDIVCSToGit](https://github.com/DGH2112/JEDIVCSToGit), de David Hoyle — lê o banco com
  FireDAC/MSSQL e faz `git add` + `git commit --date` por revisão.
- [hbannw/JcvsToGit](https://github.com/hbannw/JcvsToGit) — época do FreeVCS/DBISAM; gera um stream
  `git fast-import`, agrupa check-ins por dia e usuário e converte `.dfm` binário.

O jvcs2git mantém as boas ideias deles (fast-import, agrupamento, mapa de autores, `.dfm` em texto) e
acrescenta acesso pelo protocolo do servidor (qualquer banco), datas UTC do log do servidor, labels como tags,
relatório do que ficou de fora, retomada e uma CLI para automação e IA.

## Licença

Código deste repositório: [Mozilla Public License 1.1](LICENSE). Os executáveis incorporam também units MPL 1.1
do JEDI VCS (submódulo `external/JEDI_VCS`, veja
[external/JEDI_VCS/doc/original/license.txt](external/JEDI_VCS/doc/original/license.txt)) e o MidWare de
François Piette (freeware somente para uso não comercial; versão alterada).

This product is based on MidWare. Freeware source code is available at http://www.overbyte.be.

## Aviso

O jvcs2git é fornecido **"no estado em que se encontra"**, sem garantia de qualquer tipo. Faça backup do
servidor JEDI VCS e valide cada repositório gerado antes de aposentar o arquivo. Veja
[DISCLAIMER.md](DISCLAIMER.md).
