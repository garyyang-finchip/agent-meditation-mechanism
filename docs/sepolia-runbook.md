# Sepolia evidence runbook

The evidence run executes `script/Evidence.s.sol` through `scripts/evidence-run.sh` in phases separated by real waiting time, and records every state snapshot and transaction under `deployments/`.

## What the run shows

| Phase | Actor | Actions | Expected registry state afterwards |
| --- | --- | --- | --- |
| A | deployer, subject | deploy registry; top the subject, controller and operator up to their funding targets; enroll with the worked-example baseline (all layers required; intervals 600 / 1800 / 3600 / 7200 s; due window 120 s; pulse 300 s); grant operator report + pulse | version 1, 0 records, all layers FRESH (never completed), signal PRESENT |
| A2 | operator, controller | pulse; record the worked-example cycle (layers 0–2 adopt, layer 3 kept, all four completed); controller sets floor (layer 0: 300 s; pulse 120 s) and demands layer 3 by +600 s | version 2, 2 records, all FRESH, floor v1, demand outstanding |
| wait 330 s | | | layer 0 OVERDUE under the floor, signal SILENT, other layers FRESH (snapshot `overdue`) |
| B | subject, operator | layer-3 cycle adopting the candidate strategy (clears the demand); layer-0 refresh cycle | version 4, 4 records, all FRESH, demand cleared |
| C | subject, operator | rollback of layers 0 and 3 to the state registered at version 2 (`restoresVersion = 2`); policy version 2; pulse | version 5, 6 records, policy v2, root equals `rootAt(2)` |
| D1 | subject, controller | subject records the start of its next cycle (`begin`); controller demands layer 2 | open start held by the subject; demand on layer 2 outstanding |
| D1b | subject | policy version 3, which forbids the `SELF` trigger; the subject's open start survives its own change | policy v3; open start unchanged |
| rejected | operator, subject | four calls the registry must reject, one per revision, sent as transactions that fail (below) | nothing changes |
| wait | | until 330 s after the recorded start | |
| D2 | subject | the cycle pinned to the recorded start: version 2, trigger `SELF`, layers 0 and 2, layer 0 completed at the start and layer 2 at the end | layer 0 OVERDUE at once (completed at the start, older than its 300 s floor interval), layer 2 FRESH, both `completedUnderPolicy = 2`; demand on layer 2 cleared by layer 2's completion; open start consumed (snapshot `perLayer`) |
| D3 | operator | layer-0 refresh under version 3; pulse | all FRESH, signal PRESENT (snapshot `final`) |

The four rejected calls are encoded in phase D1b against the registry's state and checked with `eth_call` before anything is sent; each passes every check before the one it demonstrates:

| Revision | Call | Expected error |
| --- | --- | --- |
| 2 | record whose reported start is one second before the previous cycle's end, under the version that governed that start | `StartBeforePreviousCycle()` |
| 3 | policy version that drops layer 2 while the controller's demand on it is outstanding | `LayerUnderObligation(2)` |
| 4 | `SELF` record started in the gap before the tightening, claiming version 2, not pinned to a recorded start | `TriggerNotAllowed()` (rule 8, current version) |
| 5 | late record that fits versions 2 and 3, with a layer completion time before the cycle's start | `InvalidCompletionTime(1)` |

The same driver runs against a local anvil with time travel instead of waiting (`bash scripts/evidence-run.sh anvil`), which is what CI does. The driver is always invoked through `bash`, because files uploaded through the GitHub web interface do not keep the executable bit.

## Prerequisites

- Foundry 1.7 or later (`forge`, `cast`, `anvil`), Node.js 22, and `npm ci` in the repository (the rejected-call step uses `ethers`).
- A Sepolia RPC endpoint in `RPC_URL` that returns revert data on `eth_call` (most do; with one that does not, set `REJECTED_ALLOW_UNDECODED=1`).
- A funded deployer key in `DEPLOYER_PK`.

Keys for the subject, controller and operator are generated on first run into `deployments/sepolia/keys.env` (ignored by git) and reused by later runs. In phase A the deployer tops each actor up to a target derived from the live gas price (`cast gas-price`) and the gas the actors used on Sepolia, with a 2x margin (subject about 5.5M gas, operator 2.0M, controller 0.8M; floor 0.0005 ETH each); override with `FUND_AGENT_WEI`, `FUND_OPERATOR_WEI`, `FUND_CONTROLLER_WEI`. Before sending anything the driver asks the node for the deployment's gas estimate (Sepolia's gas schedule priced the revision 1 deployment at about 26M gas, seven times a local EVM), prints the deployer balance against the phase A estimate and stops if it is short (`SKIP_PRECHECK=1` overrides).

## Run

```bash
export PATH=$HOME/.foga/foundry:$PATH # where a statically linked Foundry lives, if not already first on PATH
export RPC_URL=https://...            # Sepolia RPC
export DEPLOYER_PK=0x...              # funded deployer
npm ci
bash scripts/evidence-run.sh sepolia  # A, A2, wait, B, C, D1, D1b, rejected calls, wait, D2, D3, final
```

The run takes about eighteen minutes, most of it the two waits that let layer 0 age past its floor interval. Nothing is pushed from the machine that runs it: the records appear under `deployments/` and are uploaded like any other file.

Resume after an interruption at any step:

```bash
bash scripts/evidence-run.sh sepolia phaseA2   # or phaseB, phaseC, phaseD1, phaseD1b, rejected, phaseD2, phaseD3, final
```

Live runs pass `--skip-simulation --slow --gas-estimate-multiplier 150` to `forge script`. Skipping the local simulation makes every gas limit come from the node's own `eth_estimateGas`; this matters on Sepolia, whose current gas schedule prices contract deployment far above a local EVM (a first attempt with locally estimated limits ran out of gas at 5.5M on the registry deployment). The 1.5x margin sits on top of the node's estimate; `--slow` waits for each receipt before the next send. The rejected calls are sent by `scripts/evidence-rejected.js` with a fixed gas limit (600000, `REJECTED_GAS_LIMIT`), because gas estimation refuses a call that reverts.

## Records

- `deployments/sepolia/state-<phase>.json`: registry snapshots (versions, counts, root, last cycle end, open start, interface support, per-layer status, checkpoints, governing policy and demand, signal) after each phase and at the `overdue`, `perLayer` and `final` points.
- `deployments/sepolia/rejected.json`: the rejected calls with their transaction hashes, blocks, gas, status 0 and the decoded preflight error.
- `deployments/sepolia.json`: summary with the registry address, actor addresses, interface identifiers, snapshots, every transaction (phase, function, hash, block, gas, status) collected from `broadcast/Evidence.s.sol/11155111/*-latest.json`, and the rejected calls.
- Source verification: `forge verify-contract <registry> AgentMeditationRegistry --chain sepolia --verifier sourcify` (no API key needed), or an Etherscan verification with an API key.
- Repeated runs: a run that starts at phase A deploys a new registry. If `deployments/sepolia.json` exists, the driver first moves it to `deployments/sepolia-<date>.json` (the date of its final snapshot), so every run keeps its record; the actor keys in `deployments/sepolia/keys.env` are reused.

The run of 2026-11-09 (revision 1) is recorded in `deployments/sepolia.json` and walked through in `docs/sepolia-evidence.md`; the redeployment with revisions 2 to 5 will move it to `deployments/sepolia-2026-11-09.json`.
