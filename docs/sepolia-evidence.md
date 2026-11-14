# Sepolia evidence run

Run date: 2026-11-09 (blocks 12094378 to 12094420). Record: [`deployments/sepolia.json`](../deployments/sepolia.json). Driver: `scripts/evidence-run.sh sepolia` with `script/Evidence.s.sol` at repository state v0.1.3 (revision 1 of the registry). Revisions 2, 3 and 4 (v0.3.0, v0.4.0 and v0.5.0: start lower bound, `withdrawDemand` rights, demand layer validity, layers under obligation kept in the policy, current-version check, recorded-start extension) change the registry bytecode; the deployed instance predates them and a redeployment with the current contracts is the next evidence step. The driver archives this record as `deployments/sepolia-<date>.json` before a new run writes `deployments/sepolia.json`.

## Deployment

| Item | Value |
| --- | --- |
| Registry `AgentMeditationRegistry` | `0x184dF595404414f91aD11986C47B9a539eF9559f` |
| Creation transaction | `0x3a68a0f26f4f6bfc527963ce3d6b539e809a7f67fe39bd2b11fe654a0ff6abc1` (block 12094378) |
| Source verification | Sourcify, chain 11155111: `match` for creation and runtime bytecode (the build sets `bytecode_hash = "none"` and `cbor_metadata = false`, so no metadata hash is available for an exact match) |
| Compiler | solc 0.8.28, optimizer 200 runs, EVM `cancun` |
| Clock | `mode=timestamp` |
| Subject (agent) | `0x05D01638a215413910cF3A40d9BdA230dA8b82E1` |
| Controller | `0xE137daf9447fF49C53b12692A0881f1815755e91` (rights: floor, demand, revoke operators) |
| Operator | `0xA05b0F1796151c8a46d74Ec0A753231591DEDfcf` (permissions: report, pulse) |
| Deployer | `0xfa07f7a6D9e03c1De0f7241463c9dcAB76822080` |

All actor keys were generated for this run and hold no other role.

## Policy and floor used

The subject enrolled with the worked-example baseline (`assets/erc-agent-meditation/examples/mcp-timeout-cycle/baseline/`, policy hash `0x5dfdd440…41d9`) and evidence-friendly intervals: all four layers supported and required; `maxInterval` 600 / 1800 / 3600 / 7200 seconds for layers 0 to 3; `dueWindow` 120 s; `pulseInterval` 300 s; all triggers allowed. The controller's floor requires layer 0 every 300 s and a pulse every 120 s. With these values a ten-minute run shows every status transition that the specification defines.

## Transactions

| # | Block | Phase | Actor | Call | Gas used | Hash |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 12094378 | A | deployer | create `AgentMeditationRegistry` | 26,094,653 | `0x3a68a0f2…6abc1` |
| 2 | 12094379 | A | deployer | fund agent | 204,600 | `0x69640752…27932` |
| 3 | 12094380 | A | deployer | fund controller | 204,600 | `0x1e9dc257…34fa9` |
| 4 | 12094381 | A | deployer | fund operator | 204,600 | `0x90e43df6…d45fe` |
| 5 | 12094382 | A | agent | `enroll` (baseline, policy v1, controller with all rights) | 2,237,725 | `0x95a1f32f…57c8f` |
| 6 | 12094383 | A | agent | `setOperator` (report + pulse) | 130,960 | `0xfae83437…83a6e` |
| 7 | 12094386 | A2 | operator | `pulse` | 48,119 | `0x0e556942…3cc27` |
| 8 | 12094387 | A2 | operator | `report`: worked-example cycle, scope 0x0F, completed 0x0F, ops 0x0456, EVENT | 312,039 | `0x84902386…0b53e` |
| 9 | 12094388 | A2 | controller | `setFloor` (layer 0 every 300 s, pulse every 120 s) | 255,033 | `0x4173bffa…61929` |
| 10 | 12094389 | A2 | controller | `demand` (layer 3 within 600 s) | 131,949 | `0xf59b3cd6…8b953` |
| 11 | 12094416 | B | agent | `report`: layer 3 adopts the candidate strategy, COMMANDED (clears the demand) | 233,873 | `0x7e73abb3…cdc13` |
| 12 | 12094417 | B | operator | `report`: layer 0 refresh, SCHEDULED | 237,221 | `0xd1c1f8a8…09db6` |
| 13 | 12094418 | C | agent | `report`: layers 0 and 3 restored to the state of version 2, `restoresVersion = 2`, SELF | 266,697 | `0x7eb5083e…f52de` |
| 14 | 12094419 | C | agent | `setPolicy` (version 2, disclosure = summary) | 591,536 | `0x1c7473a5…4e1c0` |
| 15 | 12094420 | C | operator | `pulse` | 48,071 | `0x8a5a016d…e288a` |

Fifteen transactions, all successful, 31,201,676 gas in total. Full hashes are in `deployments/sepolia.json`.

## Registry state at each point

Snapshots after phases A, A2, B and C are the registry reads taken by the script run that produced those phases; `overdue` and `final` are read-only runs against the chain after the preceding transactions were mined. Times are clock values (seconds).

| Point | Clock | State version | Records | Policy / floor | Root | Signal | L0 | L1 | L2 | L3 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| after A | 1794189264 | 1 | 0 | 1 / 0 | `0x090e63d6…` (baseline) | PRESENT | FRESH, never completed, deadline +600 | FRESH, never, +1800 | FRESH, never, +3600 | FRESH, never, +7200 |
| after A2 | 1794189348 | 2 | 2 | 1 / 1 | `0x9918ebff…` (worked-example post state) | PRESENT | FRESH, completed 1794189348, deadline 1794189648 (floor 300 s) | FRESH, deadline 1794191148 | FRESH, deadline 1794192948 | FRESH, deadline 1794189948 (demand) |
| overdue | 1794189732 | 2 | 2 | 1 / 1 | `0x9918ebff…` | SILENT since 1794189504 (last signal 1794189384 + 120) | OVERDUE (deadline 1794189648 passed) | FRESH | FRESH | FRESH (demand deadline 1794189948 ahead) |
| after B | 1794189732 | 4 | 4 | 1 / 1 | `0x526cb627…` | PRESENT | FRESH, completed 1794189732, changed at v4 | FRESH | FRESH | FRESH, completed 1794189732, changed at v3, demand cleared, deadline 1794196932 |
| after C | 1794189756 | 5 | 6 | 2 / 1 | `0x9918ebff…` (= `rootAt(2)`) | PRESENT | FRESH, commitment back to the v2 value, changed at v5 | FRESH | FRESH | FRESH, commitment back to the v2 value, changed at v5 |
| final | 1794189792 | 5 | 6 | 2 / 1 | `0x9918ebff…` | PRESENT (pulse at 1794189792) | FRESH | FRESH | FRESH | FRESH |

## What the run demonstrates

1. **Enrollment is not maintenance.** After phase A every required layer is `FRESH` but flagged never completed, with deadlines counted from the enrollment time.
2. **Per-layer completion and change are separate.** The worked-example cycle completes all four layers and changes three; layer 3 keeps its commitment and `lastChangedVersion` stays 1 while its completion time moves.
3. **Floor and demand take effect without touching state.** The controller's floor lowers layer 0's deadline from +600 s to +300 s and tracks the pulse at 120 s; the demand lowers layer 3's deadline to the demanded time. The state version stays 2.
4. **Pulse is not maintenance, and activity is not timeliness.** At the overdue point the registry reports layer 0 `OVERDUE` and the signal `SILENT`; layers 1 to 3 are still `FRESH`. The same subject is `PRESENT` and `FRESH` on every layer six minutes later after two completions.
5. **A completion clears a demand only when it comes after it.** The layer-3 cycle in phase B (reported end 1794189732, demand made at 1794189384) clears the demand; layer 3's deadline returns to the policy interval.
6. **Rollback is a new version.** The phase C cycle restores layers 0 and 3 to their version-2 commitments; the registry accepts `restoresVersion = 2` because the resulting root equals `rootAt(2)`, and the state version advances to 5 rather than rewinding.
7. **Policy versions are appended.** Policy version 2 is recorded after the rollback cycle; the cycle itself was accepted under version 1, the version in effect when it started.

## Gas schedule note

The first attempt of phase A used locally estimated gas limits and the registry deployment ran out of gas at 5,509,063 gas (transaction `0x44e37ac2…0a2c6`, block 12094357, reverted). On Sepolia's current gas schedule the same deployment used 26,094,653 gas, and `enroll` used 2,237,725 against 484,313 on a local anvil. The driver therefore passes `--skip-simulation` on live networks so that every limit comes from the node's `eth_estimateGas`, with a 1.5x margin. At the base fee of the day (17 wei) the whole run cost well under 0.0001 ETH.

## Reproducing the reads

Any of the snapshots can be re-read from the chain:

```bash
cast call 0x184dF595404414f91aD11986C47B9a539eF9559f "headOf(address)" 0x05D01638a215413910cF3A40d9BdA230dA8b82E1 --rpc-url $RPC_URL
cast call 0x184dF595404414f91aD11986C47B9a539eF9559f "layerStatus(address,uint8)" 0x05D01638a215413910cF3A40d9BdA230dA8b82E1 0 --rpc-url $RPC_URL
cast call 0x184dF595404414f91aD11986C47B9a539eF9559f "rootAt(address,uint64)" 0x05D01638a215413910cF3A40d9BdA230dA8b82E1 2 --rpc-url $RPC_URL
```

Statuses move with the clock: by the time of reading, the short intervals of this run will have made the required layers `OVERDUE` and the signal `SILENT` again, which is the registry describing a subject that stopped maintaining itself after the run. Historical state is in the `CycleRecorded`, `Pulsed`, `PolicyUpdated`, `FloorUpdated` and `Demanded` events of the fifteen transactions above.
