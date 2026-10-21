# Perguntas frequentes

[Índice](README.md) · [English](../en/FAQ.md)

**Preciso instalar o cliente do banco (Firebird, MSSQL...)?**
Não. O jvcs2git fala com o servidor de aplicação do JEDI VCS pelo protocolo, como o cliente.

**O jvcs2git altera alguma coisa no servidor?**
Não. Só usa requisições de leitura e nunca faz checkout (não cria entradas de checkout no log).

**Como passo a senha?**
Salve a identidade no cliente JEDI VCS e use `-identity <nome>`. Sem identidade, a senha vem da primeira linha
do stdin redirecionado ou do prompt sem eco. Não existe `-password`.

**Saiu com 4.**
Identidade inexistente, sem senha salva, login recusado ou (forma `<host> -user`) stdin vazio. Salve a
identidade com *Store Password with identity*.

**Saiu com 9 no meio da exportação.**
Outra sessão do mesmo usuário entrou (janela do JEDI VCS, IDE, wrapper da IA) ou o servidor caiu. Feche o que
estiver aberto e rode de novo com a mesma `-out`: os blobs já baixados vêm do cache.

**Saiu com 12 dizendo que a pasta já existe.**
`<out>\<repo>` já existe. Use outra `-out` ou `-force` (que só apaga pastas geradas pelo jvcs2git).

**Saiu com 12 e "another jvcs-ai call ... is running".**
O wrapper da IA está usando a mesma identidade. Espere ele terminar e não chame o wrapper durante a exportação.

**Há revisões com `encrypted`.**
O arquivo usa criptografia Blowfish. O administrador grava a chave no cliente JEDI VCS (Properties → Crypt) ou
usa `-encodekey-file <arquivo>` (fora da pasta de saída), e roda de novo.

**Há revisões com `crcMismatch`.**
O conteúdo no servidor não confere com o CRC gravado. Avalie; `-ignorecrc` grava mesmo assim.

**Os commits saíram com datas estranhas.**
Sem o log do servidor (desligado ou `-nolog`), a data é a hora do arquivo na estação. Veja `commitsDateFromFile`
e `datesSubstituted` no relatório.

**Os autores saíram como `login <login@jedivcs.local>`.**
O `autores.txt` não foi preenchido. Rode `-dryrun` primeiro, preencha o arquivo e exporte de novo com `-force`.

**Posso exportar só o `.fast-import`?**
Sim, com `-nogit`. Depois: `git init -q repo`, `git -C repo fast-import < <repo>.fast-import`,
`git -C repo checkout -q main`.

**O checkout no Windows acusa colisão de caminhos.**
Não deveria: o jvcs2git fixa uma grafia por módulo e renomeia colisões. Se acontecer, abra uma issue com o
relatório (sem dados confidenciais).
