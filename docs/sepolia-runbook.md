# Sepolia evidence runbook

The evidence run executes `script/Evidence.s.sol` through `scripts/evidence-run.sh` in phases separated by real waiting time, and records every state snapshot and transaction under `deployments/`.

## What the run shows

| Phase | Actor | Actions | Expected registry state afterwards |
| --- | --- | --- | --- |
| A | deployer, subject | deploy registry; fund subject, controller and operator; enroll with the worked-example baseline (all layers required; intervals 600 / 1800 / 3600 / 7200 s; due window 120 s; pulse 300 s); grant operator report + pulse | version 1, 0 records, all layers FRESH (never completed), signal PRESENT |
| A2 | operator, controller | pulse; record the worked-example cycle (layers 0–2 adopt, layer 3 kept, all four completed); controller sets floor (layer 0: 300 s; pulse 120 s) and demands layer 3 by +600 s | version 2, 2 records, all FRESH, floor v1, demand outstanding |
| wait 330 s | | | layer 0 OVERDUE under the floor, signal SILENT, other layers FRESH (snapshot `overdue`) |
| B | subject, operator | layer-3 cycle adopting the candidate strategy (clears the demand); layer-0 refresh cycle | version 4, 4 records, all FRESH, demand cleared |
| C | subject, operator | rollback of layers 0 and 3 to the state registered at version 2 (`restoresVersion = 2`); policy version 2; pulse | version 5, 6 records, policy v2, root equals `rootAt(2)` |

The same driver runs against a local anvil with time travel instead of waiting (`scripts/evidence-run.sh anvil`), which is what CI does.

## Prerequisites

- Foundry 1.7 or later (`forge`, `cast`, `anvil`) and Node.js 22.
- A Sepolia RPC endpoint in `RPC_URL`.
- A funded deployer key in `DEPLOYER_PK` (about 0.05 Sepolia ETH covers deployment, three small transfers and the run with margin at usual Sepolia gas prices).

Keys for the subject, controller and operator are generated on first run into `deployments/sepolia/keys.env` (ignored by git) and reused when resuming. In phase A the deployer funds them from the live gas price (`cast gas-price`) with a 2x margin over their gas budgets (subject about 1.1M gas, operator 0.45M, controller 0.2M; floor 0.0005 ETH each); override with `FUND_AGENT_WEI`, `FUND_OPERATOR_WEI`, `FUND_CONTROLLER_WEI`. Before sending anything the driver prints the deployer balance against the phase A estimate and stops if it is short.

## Run

```bash
export PATH=$HOME/.foga/foundry:$PATH # where a statically linked Foundry lives, if not already first on PATH
export RPC_URL=https://...            # Sepolia RPC
export DEPLOYER_PK=0x...              # funded deployer
scripts/evidence-run.sh sepolia       # phases A, A2, wait 330 s, B, C, final
```

The run takes about ten minutes, most of it the wait that lets layer 0 become overdue under the floor. Nothing is pushed from the machine that runs it: the records appear under `deployments/` and are uploaded like any other file.

Resume after an interruption at any phase:

```bash
scripts/evidence-run.sh sepolia phaseA2
scripts/evidence-run.sh sepolia phaseB
scripts/evidence-run.sh sepolia phaseC
scripts/evidence-run.sh sepolia final
```

Live runs pass `--slow --gas-estimate-multiplier 150` to `forge script`; gas limits come from the node's estimates, which matter on Sepolia where the current gas schedule prices some operations several times higher than a local anvil does.

## Records

- `deployments/sepolia/state-<phase>.json`: registry snapshots (versions, counts, root, per-layer status and checkpoints, signal) after each phase and at the overdue point.
- `deployments/sepolia.json`: summary with the registry address, actor addresses, snapshots and every transaction (phase, function, hash, block, gas, status), collected from `broadcast/Evidence.s.sol/11155111/*-latest.json`.
- Source verification: `forge verify-contract <registry> AgentMeditationRegistry --chain sepolia --verifier sourcify` (no API key needed), or an Etherscan verification with an API key.

After the run, `docs/sepolia-evidence.md` is written from `deployments/sepolia.json` and the registry address is added to the README and to the Magicians thread.
