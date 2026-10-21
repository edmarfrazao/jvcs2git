# IA (skill do Claude Code)

[Índice](README.md) · [English](../en/AI.md)

O `jvcs2git-cli.exe` foi feito para ser chamado por agentes de IA: senha só pela identidade salva, uma linha
JSON no stdout e códigos de saída estáveis. A skill `jvcs2git` ensina o fluxo ao Claude Code.

## Instalação

Copie a pasta da skill para `.claude\skills\` do projeto (ou para `%USERPROFILE%\.claude\skills\`):

- português: [`skills/pt/jvcs2git`](../../skills/pt/jvcs2git/SKILL.md)
- inglês: [`skills/en/jvcs2git`](../../skills/en/jvcs2git/SKILL.md)

Copie a pasta inteira, com `scripts\localizar-jvcs2git.ps1`.

## Localização do exe

O script `scripts\localizar-jvcs2git.ps1` (só leitura) devolve `{ok, cli, gui, source, exitCode}` e procura,
nesta ordem:

1. variável de ambiente `JVCS2GIT_HOME` (pasta dos exes ou raiz com `bin\Win32`);
2. `<projeto>\.claude\jvcs2git.managed.json` com `{"home": "<pasta dos exes>"}` (ou `"cli"`);
3. `bin\Win32` (ou a própria pasta do zip extraído), da pasta atual para cima.

Código 12 = não encontrado.

## Regras que a skill impõe

- Sempre `-identity <nome>` com stdin vazio (`< NUL`) e `-json`.
- Nunca pedir, receber, mostrar ou passar senha ou chave Blowfish; nunca ler o registro do JEDI VCS.
- Fluxo: `-list` → `-dryrun` → preencher `autores.txt` com o administrador → exportação → validação.
- Nunca `-all` sem o administrador confirmar a pasta; nunca apagar a pasta de saída; `-force` e `-ignorecrc` só
  com aprovação.
- Não chamar o wrapper `jvcs-ai.ps1` nem editar fontes Delphi durante a exportação (os hooks fazem login com a
  mesma identidade).
- Tabela de ação por código de saída (0, 2, 4, 5, 9, 11, 12) e por motivo de `skipped[]`.

## Exemplo de pedido

> Exporte o projeto ex4ia.dpr para D:\git e me diga o que ficou de fora.

A IA localiza o exe, roda `-list`, `-dryrun`, mostra os `unmappedAuthors` e pede o preenchimento do
`autores.txt`, exporta e resume `skipped[]`, `warnings` e o relatório.
