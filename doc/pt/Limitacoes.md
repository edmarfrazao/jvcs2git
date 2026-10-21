# Limitações

[Índice](README.md) · [English](../en/Limitations.md)

- **Git 2.x no PATH** (testado com 2.54; nenhuma versão específica exigida). `fvcscrypt.dll` ao lado dos exes.
- **Sessão única:** num servidor sem branching, um login novo do mesmo usuário derruba a sessão anterior —
  inclusive a janela do JEDI VCS, a IDE, o wrapper `jvcs-ai.ps1` e seus hooks. Use um usuário admin dedicado ou
  feche tudo. O jvcs2git detecta a queda, guarda o cache e sai com 9; rode de novo com a mesma `-out`.
- **Módulos renomeados ou movidos:** o servidor guarda só o nome e a pasta atuais; o histórico inteiro sai com
  o caminho atual.
- **Módulos removidos do projeto** não aparecem (o servidor não os lista para o projeto). Projeto removido mas
  não purgado continua exportável com `-include-deleted`.
- **Ramos:** só o ramo selecionado do JEDI VCS (`-branch`, padrão `HEAD`).
- **Datas:** a hora real vem do log do servidor por heurística (usuário + comentário, sem ID de revisão). Sem
  log, a data é a hora do arquivo na estação. Datas inválidas são substituídas e listadas; a data de committer é
  monotônica.
- **Labels:** um label marca uma revisão por módulo; a tag aponta para o commit que contém a mais recente
  ("tag aproximada" quando nem todas as revisões rotuladas estão naquele estado).
- **Caixa:** grafia fixada por módulo pela revisão mais recente (renomes só de caixa não são preservados);
  pastas em minúsculas; colisões entre módulos são renomeadas (`-<ModuleID>`) e avisadas.
- **Caminhos inválidos para o Git for Windows** (`:` do drive, UNC, nomes reservados, ponto/espaço final) são
  normalizados e avisados. Caminhos acima de 255 caracteres já foram truncados pelo próprio servidor.
- **Membros:** membro que deixa de ser enviado num check-in é removido no commit correspondente; membro
  pulado por erro mantém o conteúdo anterior e vai para o relatório.
- **Revisões cifradas** precisam da chave Blowfish; sem ela ficam como `encrypted`.
- **Conteúdo** é copiado sem recodificar; só nomes e comentários passam de cp1252 para UTF-8. `.dfm` binário vira
  texto (salvo `-nodfmtext`).
- **Timeouts:** 12 s por requisição; blobs e o log usam `-blobtimeout` (padrão 120 s). Em arquivos enormes,
  `-nolog` é a saída de emergência.
- **Uso único:** autores e datas não se corrigem depois sem reescrever o histórico. Preencha o `autores.txt`
  antes da exportação real.
