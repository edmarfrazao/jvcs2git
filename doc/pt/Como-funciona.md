# Como funciona

[Índice](README.md) · [English](../en/How-it-works.md)

## Protocolo

O jvcs2git usa as mesmas classes de requisição do cliente JEDI VCS (`TJVCSConnection` e os objetos
`TJVCSGet*`) e só faz requisições de leitura. Por projeto:

| Requisição | Para quê |
|---|---|
| `GET_PROJECT_LIST` | projetos (nome, ID, removido) |
| `GET_PROJECT_MODULE_LIST` | módulos: nome e pasta atuais (ocultos incluídos, salvo `-skiphidden`) |
| `GET_REVISION_LIST` | revisões do projeto: só `ModuleID`, `RevisionID`, versão, revisão, oculto |
| `GET_MODULE_HISTORY` | por módulo: uma linha por membro; usuário, comentário e data do arquivo |
| `GET_LABELS`, `GET_LABELS_BY_PROJECT` | labels e as revisões que eles marcam |
| `GET_LOG_ENTRIES`, `GET_LOG_COMMENT` | log do servidor (hora real dos check-ins) |
| `GET_USERS` | logins para o mapa de autores |
| `GET_SINGLE_BLOB` | conteúdo de cada membro (não grava log no servidor) |

`GET_CHECKOUT_MODULE` nunca é usado: ele grava entrada no log do servidor.

## Datas e log

O servidor guarda em cada revisão só a hora do **arquivo** na estação de quem fez o check-in (`ORIGTIME`), que
pode ser dias antes do check-in. A hora real fica no log do servidor, que não tem o ID da revisão: o jvcs2git
liga cada entrada do log a uma revisão por usuário + comentário, do mais novo para o mais antigo.

Data de uma revisão: a primeira válida entre hora do log, hora do arquivo (maior entre os membros), data do
módulo (só para a última revisão), data do commit anterior + 1 s e agora. Válida = de 1980-01-01 até agora + 1
dia. Data substituída é anotada na mensagem do commit e no relatório (`datesSubstituted`).

- **author date** = data da revisão (UTC `+0000`, ou o fuso local com `-localtime`);
- **committer date** = monotônica (nunca volta no tempo), para `git log --since/--until` funcionar;
  `-committer-date original` faz committer = author.

O relatório conta os commits datados pelo log e pelo arquivo (`commitsDateFromLog`, `commitsDateFromFile`).

## Agrupamento

As revisões são ordenadas pelo **ID da revisão** (gerador crescente do servidor), nunca pela data. Revisões
consecutivas viram um commit quando têm o mesmo usuário, o mesmo comentário, o módulo ainda não está no
grupo e:

- datas do log nas duas: diferença de até `-group` minutos (padrão 10);
- alguma datada pelo arquivo: são adjacentes na lista do projeto, com teto de `-group-maxspan` horas
  (padrão 168, 7 dias) entre a mais antiga e a mais nova.

Data do commit = a maior do grupo. `-nogroup` gera um commit por revisão.

Mensagem do commit: o comentário de check-in (ou `(sem comentário)`), mais a linha
`JEDI VCS: <projeto>; <módulo> <versão.revisão> (rev <id>)[, ...]`.

## Caminhos

- Raiz: `-root`, ou a pasta do módulo com o nome do projeto (`.dpr`), ou o prefixo comum das pastas.
- Fora da raiz: `_externos/<letra>/<resto>` (sem `:`) ou `_externos/unc/<servidor>/<share>/<resto>`.
- Componentes inválidos no Windows (`< > : " | ? *`, nomes reservados como `nul`, ponto ou espaço final) são
  corrigidos e avisados.
- Grafia do nome: uma por módulo, do item do ZIP da revisão mais recente (aceito só se igual ao nome do
  servidor ignorando a caixa); pastas em minúsculas. Colisão de caixa entre módulos → sufixo `-<ModuleID>` e
  aviso (`-strictcase` aborta o projeto).

## Conteúdo

`GET_SINGLE_BLOB` devolve o arquivo compactado (ZIP) ou cifrado (Blowfish). O jvcs2git descompacta ou decifra,
confere o CRC32 **antes** de qualquer conversão e:

- `.dfm`/`.fmx` binário (`TPF0`) → texto com `ObjectBinaryToText` (salvo `-nodfmtext`); falha → grava o
  binário e conta em `dfmConvertFailed`;
- CRC divergente → pulado (`crcMismatch`), salvo `-ignorecrc`;
- sem conteúdo → `noBlob`; cifrado sem chave → `encrypted`.

Um membro que some numa revisão (ex.: a unit perdeu o `.dfm`) é removido no commit correspondente. Um membro
pulado por erro mantém o conteúdo anterior.

## git fast-import

O stream começa com `feature done` e termina com `done` (stream truncado é recusado). Commit inicial com
`.gitattributes` = `* -text` (bytes exatos; `-noattributes` desliga), 1 s antes da primeira revisão. Depois:

```
git init -q <repo>
git -C <repo> symbolic-ref HEAD refs/heads/main
git -C <repo> fast-import --quiet --export-marks=.git/jvcs2git.marks < <repo>.fast-import
git -C <repo> checkout -q main
```

Sem `git init -b`: funciona em qualquer Git 2.x e ignora o `init.defaultBranch` da máquina. A versão do Git vai
para o log.

## Tags

Cada label com revisões no projeto vira uma tag anotada no commit que contém a revisão rotulada mais recente
(tagger = autor desse commit; mensagem = descrição do label + módulos e versões). Nome saneado pelas regras do
`git check-ref-format`; colisão (ignorando a caixa) recebe `-<LabelID>`. Se a revisão rotulada foi pulada, a tag
vai para o commit anterior mais próximo ("tag aproximada"); sem nenhum commit, a tag não é criada (`noCommit`).

## Cache e retomada

Cada blob baixado é gravado em `<out>\.jvcs2git-cache\<RevisionID><ext>.tmp` e renomeado só depois de conferido
o CRC. Na retomada, um arquivo do cache só é aceito se não for `.tmp` e se o tamanho bater com o do histórico; do
contrário é baixado de novo. O JSON mostra `blobsDownloaded` e `blobsFromCache`.

O cache é apagado só quando a exportação termina com código 0; com `-nogit`, `-keepcache`, revisões puladas (11) ou falha ele fica, para tentar de novo (por exemplo, depois de gravar a chave Blowfish). Depois
de uma queda (código 9), rode de novo com a mesma `-out`.

## Pasta existente e `-force`

Se `<out>\<repo>` já existe e não está vazia, o jvcs2git sai com 12 e não apaga nada. Com `-force`, apaga e
recria a pasta **só** se ela contém `.git\jvcs2git.marks` (repositório gerado pelo próprio jvcs2git); caso
contrário continua 12. O `<repo>.fast-import` e o relatório são regravados; o log é acrescentado.
