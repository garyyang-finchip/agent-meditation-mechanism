# Changelog

## 0.3.0 (2026-11-10)

Revision 2, after the first Magicians review round (topic 30304, post 3).

- Kernel: a cycle's `reportedStartedAt` must be at or after the subject's `lastCycleEndedAt` (new head field; error `StartBeforePreviousCycle`), so cycle records are totally ordered per subject and a reported start cannot be backdated past the previously accepted cycle to reach an earlier policy version.
- Kernel: `withdrawDemand` requires `RIGHT_DEMAND`, like `demand`.
- Kernel: `demand` rejects layers outside the current policy's `supportedLayers`; an outstanding demand on a supported layer without a timeliness requirement puts that layer on the clock (`FRESH` / `DUE` / `OVERDUE` against `dueBy`) instead of reading `UNSCHEDULED`.
- Specification: time-ordering rule, Demand section, status derivation, Head structure, Rationale (sequential cycles) and Security Considerations (the policy pin is only as strong as the reported start; `completedUnderPolicy`; start commitment extension) updated; Test Cases 14-16 added.
- Tests: 74 (new `test/Review1.t.sol` with the reviewer's control/variant pairs and the residual-gap case).
- Interface id unchanged (`0x9c81b550`); ABI exports regenerated (Head output, registry errors). The Sepolia instance is revision 1; redeployment deferred to the next batch.

## 0.2.1 (2026-11-09)

- Sepolia evidence run recorded: registry `0x184dF595404414f91aD11986C47B9a539eF9559f` (Sourcify match), 15 transactions in blocks 12094378-12094420; `deployments/sepolia.json`, `docs/sepolia-evidence.md`, README deployment table, Magicians reply draft.
- PR description and Magicians post drafts carry the ERC-8490 wording.

## 0.2.0 (2026-11-09)

- Number assigned: ERC-8490. Proposal text carries `eip: 8490` and `../assets/eip-8490/` links; `discussions-to` points at the retitled thread; filing package defaults to `erc-8490`; README, Magicians post draft and PR description updated.

## 0.1.3 (2026-11-09)

- Evidence driver: live runs use `--skip-simulation` so gas limits come from the node's `eth_estimateGas` (the registry deployment ran out of gas on Sepolia with locally estimated limits).

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
