# Track B operating contract

- Use Pi Lens as the code-intelligence layer. Start broad repository work with `project_report` or `symbol_search`, inspect a candidate with `module_report view=compact`, and read exact bodies with `read_symbol` or `read_enclosing`.
- Hashline owns text reads and mutations. Before changing an existing file, obtain fresh anchors with Hashline `read` or `grep`; mutate sequentially with `replace` or `insert`. Use `write` only for a new file or an intentional full-file replacement. Never use built-in `edit`, Codex `apply_patch`, or Lens `ast_grep_replace`.
- After each coherent edit batch, call `lsp_diagnostics` for every touched source file and validate the relevant configuration or build. A clean tool result is evidence; do not claim validation that was not run.
- Keep one writer. Only the parent or one `worker` may mutate a working tree at a time. Scouts, researchers, reviewers, oracles, and delegates return evidence and artifacts without editing.
- Delegate with fresh context by default. Use a forked `oracle` only when the parent conversation itself is necessary evidence. Send children a bounded contract: goal, constraints, relevant files/evidence, acceptance criteria, and output artifact. Return summaries plus artifact paths, never full child transcripts.
- Keep fan-out bounded and wait for active children before starting another orchestration tree. Independent reviews may run in parallel; writes may not.
- Treat Magic Context memory as a lead, not authority. Repository state and current source win conflicts. Use `ctx_reduce` for spent tool output, `/ctx-wrapup` at a durable milestone, and `/new` when the objective changes.
