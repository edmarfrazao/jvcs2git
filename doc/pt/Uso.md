# Uso

[Índice](README.md) · [English](../en/Usage.md)

## Sintaxe

```
(a) jvcs2git-cli -identity <nome> [<host[:porta]>] [-user <u>] -out <pasta> (-project <nome|id> ... | -all) [opções]
(b) jvcs2git-cli <host[:porta]> -user <u> -out <pasta> (-project <nome|id> ... | -all) [opções]
    jvcs2git-cli ... -list [-include-deleted] [-json]            lista os projetos e sai
    jvcs2git-cli ... -dryrun (-project ... | -all) [-out <pasta>] só metadados: imprime o plano de commits
    jvcs2git-cli -selftest paths|blob [-json]                     testes internos, sem servidor
    jvcs2git-cli -help
```

`-project` pode ser repetido ou receber uma lista separada por vírgulas; aceita o nome (`exemplo01.dpr`) ou o
ID. A porta padrão é 2106.

## Senha e identidade

Precedência: **`-identity` > stdin redirecionado > prompt**. Não existe `-password` (código 2).

- **Forma (a), recomendada:** host, porta, usuário e senha vêm da identidade salva pelo cliente JEDI VCS
  (Server Login → *Store Password with identity*). Com `-identity` o stdin **nunca** é lido. Host ou usuário
  também dados na linha prevalecem e geram um aviso em `warnings`. Identidade inexistente, incompleta ou sem
  senha salva → código 4, sem tentar login.
- **Forma (b):** a senha é a primeira linha do stdin quando ele está redirecionado; EOF ou linha vazia →
  código 4 sem tentar login. No console interativo aparece um prompt sem eco.

Com `-identity`, o jvcs2git entra no mesmo mutex do wrapper da IA do JEDI VCS (`jvcs-ai.ps1`) e espera até
30 s; se o wrapper estiver ocupado, sai com 12. Assim um hook da IA não derruba a exportação no meio.

## Chave Blowfish (revisões cifradas)

A chave tem a mesma sensibilidade da senha: nunca vai para a linha de comando, log, JSON ou relatório.

| Origem | Como |
|---|---|
| Registro do cliente (padrão) | a chave gravada pelo cliente JEDI VCS em Properties → Crypt |
| `-encodekey-file <arquivo>` | Base64 na 1ª linha; o arquivo **não pode** ficar dentro de `-out` (código 2) |
| `-encodekey-stdin` | Base64 numa linha do stdin (depois da senha na forma (b); 1ª linha com `-identity`) |
| `-noencodekey` | ignora a chave do registro |

`-encodekey <base64>` não existe (código 2). Chave inválida (não Base64, ou fora de 8 a 65 bytes) gera aviso e
as revisões cifradas ficam como `encrypted`.

## Opções

| Opção | Efeito |
|---|---|
| `-out <pasta>` | pasta de saída (obrigatória na exportação) |
| `-branch <ramo>` | ramo do JEDI VCS (padrão `HEAD`) |
| `-branch-name <nome>` | branch do Git (padrão `main`; validado com `git check-ref-format`) |
| `-group <min>` / `-nogroup` | agrupa check-ins do mesmo usuário e comentário (padrão 10 min) / 1 commit por revisão |
| `-group-maxspan <h>` | intervalo máximo de um grupo datado pela hora do arquivo (padrão 168 h = 7 dias) |
| `-localtime` | datas com o fuso local (padrão `+0000`) |
| `-committer-date original` | committer = author (padrão: monotônico) |
| `-root <pasta>` | pasta do servidor usada como raiz do repositório |
| `-nodfmtext` | mantém `.dfm` binário como está (padrão: converte para texto) |
| `-authors <arquivo>` | mapa de autores (padrão `<out>\autores.txt`) |
| `-email-domain <dom>` | domínio do e-mail padrão (padrão `jedivcs.local`) |
| `-labels tag\|none` | labels como tags (padrão `tag`) |
| `-include-deleted` | inclui projetos removidos (não purgados) |
| `-skiphidden` | pula módulos ocultos |
| `-nolog` | não lê o log do servidor (datas pela hora do arquivo) |
| `-noattributes` | sem o commit inicial com `.gitattributes` (`* -text`) |
| `-nogit` | só gera `<out>\<repo>.fast-import` |
| `-keepcache` | mantém `<out>\.jvcs2git-cache` |
| `-force` | recria `<out>\<repo>` se ela foi gerada pelo jvcs2git |
| `-ignorecrc` | grava blobs com CRC divergente |
| `-strictcase` | aborta o projeto em colisão de caixa |
| `-blobtimeout <ms>` | tempo limite dos blobs e do log (padrão 120000) |
| `-log <arquivo>` | arquivo de log (padrão `<out>\jvcs2git.log`) |
| `-json` | uma linha JSON no stdout; mensagens na stderr |
| `-quiet` | sem mensagens na tela (o log e o JSON continuam) |

## Arquivos gerados

| Caminho | Conteúdo |
|---|---|
| `<out>\<repo>\` | repositório Git; `<repo>` = nome do projeto sem extensão, saneado |
| `<out>\<repo>.fast-import` | stream (regravado a cada execução) |
| `<out>\.jvcs2git-cache\` | blobs baixados; apagado só quando a exportação termina com código 0, salvo `-keepcache`/`-nogit` |
| `<out>\jvcs2git.log` | log; cada execução acrescenta um cabeçalho com data e hora |
| `<out>\jvcs2git-relatorio.md` | relatório (regravado) |
| `<out>\autores.txt` | mapa de autores, criado na 1ª execução (`-dryrun` ou exportação) |

O `autores.txt` tem uma linha por login: `login=Nome Completo <email@empresa>`. Logins ainda com o e-mail
padrão (`login@jedivcs.local`) aparecem em `unmappedAuthors`.

## JSON (`-json`)

Uma linha só, ASCII (`\uXXXX`). Exemplo de exportação:

```json
{"ok":false,"command":"export","exitCode":11,"message":"1 project(s), 0 failed, 1 skipped member(s)",
 "log":"D:/git/jvcs2git.log","report":"D:/git/jvcs2git-relatorio.md",
 "authorsFile":"D:/git/autores.txt","unmappedAuthors":["joao"],
 "projects":[{"id":1,"name":"exemplo01.dpr","ok":false,"exitCode":11,"repo":"D:/git/exemplo01",
   "modules":4,"revisions":30,"commits":12,"tags":1,"blobsDownloaded":55,"blobsFromCache":0,
   "bytesDownloaded":812345,"seconds":14.2,"dfmConverted":20,"dfmConvertFailed":0,
   "commitsDateFromLog":12,"commitsDateFromFile":0,"datesSubstituted":0,
   "skipped":[{"revisionId":55,"module":"x.pas","ext":".dfm","reason":"encrypted"}],"warnings":[]}]}
```

(Quebrado em linhas aqui só para leitura.) `ok` é verdadeiro só quando `exitCode` = 0. Campos de topo:
`ok`, `command` (`export`, `list`, `dryrun`, `selftest`), `exitCode`, `message`, `warnings[]` (só quando há),
`log`, `report`, `authorsFile` + `unmappedAuthors[]`, `projects[]`. No `-list`, `projects[]` traz
`{id, name, deleted}`.

Motivos de `skipped[].reason`: `encrypted`, `crcMismatch`, `noBlob`, `noMembers`, `noCommit`,
`dfmNotConverted`, `error`. `skipped[]` é por membro: uma revisão com o `.pas` gravado e o `.dfm` pulado ainda
gera commit.

Fluxos: com `-json` o stdout contém **apenas** a linha JSON; progresso e mensagens vão para a stderr e para o
log. Erro de uso imprime a ajuda na stderr e ainda emite o JSON com `exitCode` 2.

## Códigos de saída

| Código | Significado |
|---|---|
| 0 | ok |
| 2 | uso: opção desconhecida, `-password`/`-encodekey`, `-project` com `-all`, falta `-out`, `-encodekey-file` dentro de `-out`, `-branch-name` inválido |
| 4 | credencial: identidade inexistente/incompleta/sem senha, login recusado, senha ausente no stdin |
| 5 | projeto ou ramo do JEDI VCS não encontrado |
| 9 | servidor/conexão: servidor fora, sessão derrubada, falha depois de reconectar |
| 11 | parcial: houve membros pulados ou um projeto falhou em `-all` |
| 12 | ambiente: Git ausente, `fvcscrypt.dll` ausente, pasta sem gravação, pasta do repositório já existe, mutex do wrapper ocupado, falha do `git` |

Cada projeto em `projects[]` tem `ok` e `exitCode` próprios.

## Fluxo recomendado

1. `jvcs2git-cli -identity DEFAULT -list -json < NUL`
2. `jvcs2git-cli -identity DEFAULT -project exemplo01.dpr -out D:\git -dryrun -json < NUL`
3. Preencher `D:\git\autores.txt`.
4. `jvcs2git-cli -identity DEFAULT -project exemplo01.dpr -out D:\git -json < NUL`
5. `git -C D:\git\exemplo01 log --stat`, `git -C D:\git\exemplo01 tag -n`, ler `D:\git\jvcs2git-relatorio.md`.
