# Matt Pocock workflows

Use the installed skill that fits the work. The installed SKILL.md owns its
process; this guide supplies repository context.

| Work                                | Skill                         | Evidence                                                     |
| ----------------------------------- | ----------------------------- | ------------------------------------------------------------ |
| Research tools or upstream behavior | mattpocock-research           | Primary sources, dated findings under docs/research          |
| Name domain concepts                | mattpocock-domain-modeling    | CONTEXT.md is a glossary only                                |
| Design module interfaces            | mattpocock-codebase-design    | Native services options plus small homelab policy            |
| Diagnose failures                   | mattpocock-diagnosing-bugs    | Reproduce with the pinned inputs and smallest relevant check |
| Test-first feature work             | mattpocock-tdd                | Observable module interface and runtime behavior             |
| Review a fixed change               | mattpocock-code-review        | CONTRIBUTING.md and the identified requirement               |
| Write agent guidance                | mattpocock-writing-for-agents | Short AGENTS.md with conditional pointers                    |

For substantial work use agent-workflow and retain the agreed requirements,
exact base, decisions, check results and next action in a private local brief.
Independent writers use separate worktrees. Reviewers receive a fixed patch.
Only create an ADR for a costly, non-obvious decision with a real tradeoff.
