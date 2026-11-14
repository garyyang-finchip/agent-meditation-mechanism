# Design memo: Agent Meditation Mechanism

Version 0.1.0 (2026-11-09). This memo records the design decisions behind the proposal and the reference implementation, including the corrections made during the two pre-drafting review rounds. The proposal text is normative; this memo explains it.

## 1. What is being standardized

An agent's identity is stable; its runtime, memories, skills, plans and judgment are not. Runtimes perform self-maintenance in the background and keep the results local. The proposal standardizes the part of that process that other parties need and that a neutral ledger can carry:

1. a stable subject and an explicit account of who may submit on its behalf;
2. versioned rules (the policy), with a floor set by a controller that the subject cannot relax;
3. one commitment per layer, the root of every registered state version, and the linkage of each cycle to the state it was computed against;
4. per-layer completion times, from which per-layer timeliness is derived;
5. per-cycle results that keep four facts apart: a layer was in scope, its routine completed, its state changed, and the whole cycle's outcome;
6. an activity signal that is explicitly not maintenance.

It does not standardize how maintenance is done, what a layer document contains beyond its envelope, or how an improvement is judged. Those stay off chain, committed to and described in the cycle record document.

## 2. Positioning relative to the other covenants

Every earlier covenant in this line is relational: registries and bindings between agents, between agents and rules, between agents and decisions. This one is first-person. The subject and the object of the record are the same agent. That has three consequences that run through the design:

- Only the subject (or its operator) writes records. A controller sets requirements and requests maintenance, never performs or reports it.
- Nothing in the kernel evaluates anyone. Status is a derived statement about registered timeliness, not a score.
- Other systems consume the records (identity liveness, assertions, safety compliance, dispute evidence, task preconditions) through adapters that read views; none is required.

## 3. The four layers

| Layer | Object | Off-chain routine | What the commitment covers |
| --- | --- | --- | --- |
| 0 Runtime | environment, code and configuration, dependencies, adapters (API/MCP), authorization configuration | self-debug, self-refresh, interface walk, compatibility checks, fault repair | runtime manifest: component and dependency versions, adapter schemas, authorization configuration, self-check suite |
| 1 Memory and skills | memory store and organization, skill inventory, harness configuration that manages them | deduplicate, consolidate, archive, detect conflicts, verify skill packages, tune retrieval | memory digest and organization, skill versions and package hashes, harness configuration hash |
| 2 Tasks and roles | current duties, short- and mid-term plans, tasks and their bindings to skills and services | re-plan, re-prioritize, check dependencies, select or migrate versions, schedule recovery | roles, plans, tasks with version bindings, services offered |
| 3 Cognition | self-model, assumptions, judgment strategies, reflection methods | reflect on failures, revise assumptions, map capability boundaries, form and evaluate new strategies | the self-model and strategy configuration, including the policy the subject maintains itself under |

Boundaries that matter:

- Layers 1 and 2 may mention the same skill. Layer 1 asks whether the skill is held, complete, current and worth keeping. Layer 2 asks which tasks use it and in which version. No duplication of definitions results.
- Order expresses abstraction, not execution. A cycle covers any non-empty subset; a policy may declare dependencies off chain. Not supported, not checked, checked but unchanged, and changed are four distinguishable results.
- An update is a candidate until adopted. Layer 0 updates are verified before adoption; layer 2 plan changes never alter commitments to counterparties, which only change through the mechanism that created them.
- Timed observations (balances, gas, reachability) are not state. They go into the cycle record, so that an ordinary payment or a network blip does not change the state root.
- Layer 3 is operationalized as self-model, assumptions with evidential status, judgment strategies and reflection methods. A cycle may conclude "existing strategy confirmed", "candidate formed, not adopted", or "candidate passed the designated evaluation and adopted". The kernel never judges cognition and defines no cognitive score; it records candidates, evaluations and adoption decisions.

## 4. Kernel objects

- **Subject and authorization.** `msg.sender` enrolls itself. Operators carry a permission bitmask (report, pulse, policy); a controller carries a rights bitmask (floor, demand, revoke operators) fixed at appointment and only shrinkable afterwards. Attribution of every record is to the subject.
- **Policy (versioned).** Supported and required layers, per-layer maximum intervals, allowed triggers, pulse interval, due window, disclosure level, commitment to the policy document. Versions are appended, never edited; each has an effective-from timepoint.
- **Floor (controller).** Required layers, per-layer intervals, pulse interval. Effective requirements are the union of required layers and the minimum of intervals.
- **Layer checkpoints.** Commitment, reported completion time of the last completed routine, recording time, governing policy version, state version of the last change.
- **State versions.** A counter that advances only when a commitment changes, with the root of every version kept so that a restore claim can be verified in-contract.
- **Cycle record.** Base version and pre-root, four post commitments, scope, completed layers, operations, outcome, trigger, governing policy version, reported start and end, planning hint, restore claim, record document hash.
- **Pulse.** Record count and activity signal only.
- **Demand.** Per-layer `(demandedAt, dueBy)` set by the controller; lowers the deadline until a completion at or after `demandedAt` clears it.
- **Open start (extension).** At most one per subject: `(startedAt, by)` recorded by the subject or a report operator before a cycle; a record that reports exactly that start from the same account is pinned to the policy version in effect at the start.

## 5. Invariants the registry enforces

1. A pulse changes the activity signal, the record count and the planning hint and nothing else.
2. Only layers in `completedLayers` move their completion time; the whole-cycle outcome never does it on their behalf.
3. A record must reference the current state version and root; a cycle computed against an outdated state cannot overwrite a newer one.
4. A layer outside the cycle's scope cannot change its commitment.
5. A completion cannot be registered with a time earlier than or equal to the layer's registered completion; an identical record cannot be registered twice.
6. Reported times are ordered: start at or before end, end at or before the clock.
7. A cycle is interpreted under the policy version in effect at its reported start; versions that took effect later or earlier are rejected.
8. A policy update never touches checkpoints; a longer interval never moves a deadline's anchor; only a completion moves the anchor.
9. The effective requirement of a layer is never looser than the floor; the subject cannot write the floor, change the controller or grow its rights.
10. A restore claim must match the root of the named earlier version.
11. A cycle's reported start is at or after the reported end of the subject's previously accepted cycle: cycle records of one subject are totally ordered and do not overlap, and backdating a start to reach an earlier policy version is limited to the gap since the last accepted cycle (revision 2, after the first review round).
12. Only a controller holding `RIGHT_DEMAND` issues or withdraws demands; a demand names only layers the current policy supports; an outstanding demand puts a layer without a timeliness requirement on the clock (revision 2).
13. A policy version cannot drop a layer that is under an obligation: one with an outstanding demand, or one the floor requires. The obligation is cleared by a qualifying completion or by the controller, never by the subject removing the layer (revision 3, after the second review post).
14. A record under a superseded policy version that is not pinned to a recorded start also fits the current version's supported layers and allowed triggers: the gap between the last accepted cycle and a policy change admits late records that fit both versions, and never content the current version forbids. A zero-length `FAILED` record under the new version seals the gap (revision 4, after the third review post).
15. A recorded start pins only the record that reports exactly that start from the account that recorded it; it is consumed by that record, voided by a record of a later cycle, and voided by a policy change made by anyone other than the subject or the recorder. An operator cannot replace the subject's open start (revision 4).

The reference test suite covers each of these; the first batch of tests was written against them before anything else, and the review-round cases are in `test/Review1.t.sol` and `test/Review2.t.sol`.

## 6. Time

- One clock domain per deployment (ERC-6372, timestamp mode in this version); intervals are seconds.
- Reported timepoints describe the off-chain cycle and are supplied by the submitter; recorded timepoints are read from the clock on acceptance. Both are kept.
- Timeliness follows reported completion times after ordering checks, so that a late submission keeps its true age. Activity follows recorded times.
- Never-completed required layers are anchored at the enrollment time, so enrollment alone never reads as recent maintenance, and a new requirement added long after enrollment can read as overdue immediately. That is the intended meaning.

## 7. Status

Per layer: `NOT_ENROLLED`, `UNSUPPORTED` (not required, not supported), `UNSCHEDULED` (supported, no requirement), `FRESH`, `DUE` (inside the due window before the deadline), `OVERDUE` (at or after the deadline). A controller demand lowers the deadline it is judged against.

Activity: `NOT_ENROLLED`, `NOT_TRACKED` (no pulse interval in effect), `PRESENT`, `SILENT`.

The two are independent and both are reported as what they are: a subject can be silent and fresh, or present and overdue. `FRESH` is never a health, readiness or capability statement; consumers that use "fresh before act" rules do so as consumers.

## 8. Commitment format and privacy

- Layer documents carry `schema` and `layer`; commitment = `keccak256(abi.encode(TAG_LAYER_COMMITMENT, layer, keccak256(schemaId), keccak256(JCS(document)), salt))`; root = `keccak256(abi.encode(TAG_STATE_ROOT, c0, c1, c2, c3))`.
- JCS (RFC 8785) fixes the serialization so that independent implementations commit to the same bytes.
- Salts protect guessable content and are disclosed together with the document. A hash alone is not privacy.
- Disclosure levels (commitment only, summary, full) are declared in the policy; a document that matches its commitment proves consistency with the registration, not correctness of the process.
- Layer 1 is not required to be a Merkle tree; any store works as long as a digest is declared.

## 9. Divergence and recovery

Adopting locally and registering on chain are two steps. The reference runner keeps a pending-synchronization marker, retries with the same base version, and after a partially applied cycle registers what actually happened (changed layers without completion, outcome `FAILED` or `ABORTED`). `headOf` returns registered state, never live state.

## 10. Deferred to extensions

A time limit on recorded starts, reminders by anyone, do-not-disturb announcements, batched records with batch roots, accumulated maintenance debt, third-party verification interfaces, and a binding form of `nextPlannedAt`. Each has a place in the design; none belongs in the first version.

## 11. Adapters

Informative only; see `docs/profiles.md`. Mirrors into ERC-8004 metadata, liveness and behavior facets of address-anchored agent identity registries, assertions about verified records, safety-framework compliance evidence, dispute evidence, task and swarm preconditions. Self-maintenance records are facts and evidence; they never write reputation, and ERC-8004 forbids owner or operator self-feedback in any case.

## 12. Evidence plan

Local rehearsal on anvil (`scripts/evidence-run.sh anvil`) and a live Sepolia run with the same driver: deploy; enroll with the worked-example baseline; pulse; record the worked-example cycle; floor and demand by the controller; wait until layer 0 is overdue under the floor and the signal is silent; layer-3 adoption cycle clearing the demand; layer-0 refresh; rollback of layers 0 and 3 to the state of version 2; policy version 2; pulse. Records are written to `deployments/`.
