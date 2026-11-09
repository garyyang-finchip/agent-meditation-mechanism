# Changelog

## 0.1.2 (2026-11-09)

- Evidence driver: actor funding scaled to the live gas price with per-actor overrides; deployer balance pre-check before phase A; Foundry PATH note in the runbook.

## 0.1.1 (2026-11-09)

- `discussions-to` set to the Ethereum Magicians thread (topic 30304); README, Magicians post draft and PR description carry the thread, the pull request (ethereum/ERCs #2155) and the repository URL (`agent-meditation-mechanism`).
- Filing package generator prints the placeholder note only while the placeholder is still present.

## 0.1.0 (2026-11-09)

First complete draft.

- Proposal text `ERCS/erc-agent-meditation.md` (placeholder number 9999; requires ERC-165 and ERC-6372).
- Reference implementation: `IAgentMeditation`, `AgentMeditationRegistry` (timestamp clock, four layer checkpoints, versioned policy, controller floor and demands, cycle records with linkage checks, pulse, derived status views).
- 64 Foundry tests over a dependency-free cheatcode base: enrollment and authorization, cycle records, status derivation, events, vectors and worked-example replay.
- Reference tooling: RFC 8785 canonicalization, commitments and roots, vectors generator and checker, meditation runner producing enrollment, report and pulse calldata with optional submission.
- JSON Schemas for the four layer state documents, the policy document and the cycle record document.
- Worked example `mcp-timeout-cycle` (layers 0–2 adopt, layer 3 forms a candidate and keeps its state) with vectors reproduced in the proposal's Test Cases.
- Evidence script and driver rehearsed on anvil; Sepolia runbook.
- Filing package generator, eipw and markdownlint runners under the ethereum/ERCs configurations, text checks, CI.
