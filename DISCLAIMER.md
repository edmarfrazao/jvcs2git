# Aviso de isenção de garantia · Disclaimer of warranty

## 🇧🇷 Português

**O jvcs2git é fornecido "no estado em que se encontra" ("as is"), sem garantia de qualquer tipo, expressa ou
implícita**, incluindo, sem limitação, garantias de funcionamento, comercialização, adequação a um propósito específico
ou não violação de direitos.

O jvcs2git é uma ferramenta de **uso único**: exporta projetos de um arquivo JEDI VCS 2.5 para repositórios Git. Ele só
**lê** o servidor JEDI VCS (não altera projetos, módulos nem revisões), mas **não há garantia de que o histórico
exportado esteja completo ou correto no seu ambiente**.

Antes de abandonar o JEDI VCS, cada usuário ou organização deve:

1. **Fazer backup completo** do servidor JEDI VCS (banco de dados e arquivos) e **guardá-lo** mesmo depois da migração.
2. **Validar** cada repositório gerado: `git log --stat`, `git tag -n`, o relatório `jvcs2git-relatorio.md` (revisões
   puladas, datas substituídas, avisos) e uma compilação do projeto a partir do checkout.
3. **Testar primeiro** num ambiente de testes ou com um projeto pequeno.

Os autores e colaboradores **não se responsabilizam** por perda de dados, interrupção de trabalho, danos diretos ou
indiretos, ou quaisquer outras consequências decorrentes do uso deste produto. O uso é por conta e risco de quem o
executa.

Os termos de garantia e responsabilidade das licenças aplicáveis (Mozilla Public License 1.1 e licença do MidWare, ver
[`LICENSE`](LICENSE)) continuam valendo integralmente.

---

## 🇺🇸 English

**jvcs2git is provided "as is", without warranty of any kind, express or implied**, including but not limited to
warranties of operation, merchantability, fitness for a particular purpose, or non-infringement.

jvcs2git is a **one-shot** tool: it exports projects from a JEDI VCS 2.5 archive to Git repositories. It only **reads**
the JEDI VCS server (it does not change projects, modules or revisions), but **there is no guarantee that the exported
history is complete or correct in your environment**.

Before retiring JEDI VCS, every user or organization must:

1. **Take a full backup** of the JEDI VCS server (database and files) and **keep it** after the migration.
2. **Validate** every generated repository: `git log --stat`, `git tag -n`, the `jvcs2git-relatorio.md` report (skipped
   revisions, substituted dates, warnings) and a build of the project from the checkout.
3. **Try it first** on a test environment or with a small project.

The authors and contributors **accept no liability** for data loss, work interruption, direct or indirect damages, or
any other consequences arising from the use of this product. Use it at your own risk.

The warranty and liability terms of the applicable licenses (Mozilla Public License 1.1 and the MidWare license, see
[`LICENSE`](LICENSE)) remain fully in effect.
