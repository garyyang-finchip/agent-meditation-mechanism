# Changelog

## 0.6.1 (2026-11-18)

Evidence run for the Sepolia redeployment with revisions 2 to 5; no change to the specification, the contracts or the filing package.

- `script/Evidence.s.sol`: phase D. D1: the subject records a start, the controller demands layer 2. D1b: policy version 3 forbids the `SELF` trigger; four calls the registry must reject are encoded, one per revision (`StartBeforePreviousCycle()`, `LayerUnderObligation(2)`, `TriggerNotAllowed()` from rule 8, `InvalidCompletionTime(1)`). D2: the cycle pinned to the recorded start under version 2 with the `SELF` trigger, layer 0 completed at the start (reads overdue at once) and layer 2 at the end (clears its demand). D3: layer-0 refresh under version 3 and a pulse. Snapshots now carry the last cycle end, the open start, interface support, and per layer the governing policy version and the demand. Phase A tops actors up to their targets instead of sending the full amount.
- `scripts/evidence-rejected.js` (new): checks each rejected call with `eth_call` against its expected error, then sends it with a fixed gas limit and requires status 0; writes `deployments/<network>/rejected.json`.
- `scripts/evidence-run.sh`: steps `phaseD1`, `phaseD1b`, `rejected`, `phaseD2` (after waiting until 330 s past the recorded start), `phaseD3`; funding budgets from the gas the actors used on Sepolia; the precheck asks the node for the deployment's gas estimate and counts only actor top-ups.
- `scripts/evidence-summary.js`: interface identifiers, the new snapshots and the rejected calls in `deployments/<network>.json`.
- Runbook and design memo describe phase D; anvil rehearsal: 21 transactions and 4 rejected calls, every status as expected.

## 0.6.0 (2026-11-15)

Revision 5, after the fourth Magicians review post (topic 30304, post 11).

- Record: `CycleReport` gains `completedAt[4]`, the completion time of each layer in `completedLayers`; it must lie between the cycle's reported start and end (inclusive), be later than the layer's registered completion, and be zero for every other layer (error `InvalidCompletionTime(layer)`). `lastCompletedAt` and demand clearing use the layer's own time; `reportedEndedAt` keeps ordering the subject's cycles. A layer that finished early no longer inherits the cycle's end.
- Interface: the `report` signature changes, so the ERC-165 identifier of `IAgentMeditation` is now `0xe5b77145` (was `0x9c81b550`); `IAgentMeditationStart` is unchanged (`0xb17415a3`).
- Specification: Clock, cycle record structure, rule 6, acceptance, Demand, Rationale (per-layer freshness), Security Considerations, Off-chain documents, Test Cases (worked example values, 8, 10, 13, new 20).
- Schema and example: the cycle record document carries `completedAt` per completed layer; the worked example's record hash is now `0xc61bf3f0910e27bd5a91bc6c8c006e88e262a732021ed026804bedb76b813116`; vectors regenerated; tooling derives `completedAt` from the document and rejects a completed layer without a time inside the cycle.
- Tests: 102 (new `test/Review3.t.sol`: the reviewer's 10:00/11:00 cycle and its control, bounds, the zero rule, per-layer monotonicity, demand clearing by the layer's time); harness helper `setTimes`.
- Evidence script and driver updated for the new record layout; the Sepolia instance (revision 1) is to be redeployed with revisions 2 to 5.

## 0.5.0 (2026-11-14)

Revision 4, after the third Magicians review round (topic 30304, posts 8 and 9).

- Kernel: a cycle record under a superseded policy version must also fit the current version's `supportedLayers` and `allowedTriggers` (rule 8), unless it is pinned to a recorded start. A backdated start can no longer reach a layer or a trigger the current version forbids; a late record that fits both versions is accepted unchanged.
- Extension: `IAgentMeditationStart` (ERC-165 id `0xb17415a3`): `begin`, `cancelStart`, `openStartOf`; one open start per subject; the record that reports exactly that start from the account that recorded it is pinned; a pinned record consumes the start, a record of a later cycle voids it, a policy change voids it unless the subject or the changer recorded it. Errors `StartHeldByAnother`, `NoOpenStart`; events `CycleBegun`, `StartVoided`. The reference registry implements it.
- Specification: rule 8, Recorded start section, extension interface, Rationale (what a backdated start can reach; recorded start), Security Considerations (gap bounded in time not count, sealing record, accepted limits, recorded starts), Test Cases 13, 14, 18, 19.
- Tests: 96 (new `test/Review2.t.sol`: the reviewer's sequences for the current-version check, the two observations about revision 3, the extension and the attacks on it; the former residual-gap test now expects rejection). Vectors: extension interface id; `tools/lib/report.js` loads any ABI export by name.
- Evidence driver: a live run starting at phase A archives the previous `deployments/<network>.json` under a dated name before writing a new one.
- Core interface id unchanged (`0x9c81b550`); core ABI unchanged; registry ABI gains the extension's functions, events and errors.

## 0.4.0 (2026-11-11)

Revision 3, after the second Magicians review post (topic 30304, post 6).

- Kernel: `setPolicy` rejects a version that drops a layer with an outstanding demand, or a layer the floor requires, from `supportedLayers` (error `LayerUnderObligation(layer)`); other policy changes stay possible while an obligation is outstanding.
- Specification: Policy and floor section states the rule and that a floor may require an unsupported layer, which the subject's next policy version has to support; Rationale and Security Considerations updated; Test Case 17 added.
- Tests: 78 (new `Review1bTest`: the reviewer's sequence, withdrawal, floor variant, floor on a never-supported layer).
- Interface id unchanged (`0x9c81b550`); registry ABI gains one error.

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
