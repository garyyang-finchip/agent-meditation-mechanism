# ERC-8490: Agent Meditation Mechanism

Reference repository for **ERC-8490 Agent Meditation Mechanism** (AMM), a draft ERC: attributable, versioned self-maintenance records of an AI agent across four fixed layers: runtime; memory and skills; tasks and roles; cognition.

- Proposal text: [`ERCS/erc-agent-meditation.md`](ERCS/erc-agent-meditation.md) (filed as `ERCS/erc-8490.md` in ethereum/ERCs)
- Reference implementation: [`assets/erc-agent-meditation/contracts/`](assets/erc-agent-meditation/contracts/)
- Schemas, worked example and vectors: [`assets/erc-agent-meditation/`](assets/erc-agent-meditation/)
- Design memo: [`docs/design-memo.md`](docs/design-memo.md)
- Adapters and profiles (informative): [`docs/profiles.md`](docs/profiles.md)
- Ethereum Magicians thread: [ERC-8490: Agent Meditation Mechanism](https://ethereum-magicians.org/t/erc-8490-agent-meditation-mechanism/30304)
- ethereum/ERCs pull request: [#2155](https://github.com/ethereum/ERCs/pull/2155)

## What it is

An agent keeps its identity while its code, memories, skills, plans and ways of judging keep changing. Runtimes already do this maintenance in the background (self-checks, dependency walks, memory consolidation, re-planning, reflection), and the results stay local. This proposal defines the shared, on-chain part: the registration of a subject, of versioned rules, of one commitment per layer before and after each maintenance cycle, of per-layer completion times, and of results, so that another party can ask which state is registered, which layers were checked and changed, under which rules, and with what outcome.

It is a first-person mechanism. Only the subject or an operator it authorizes writes records about the subject. A controller (owner, principal, deployer) can set a floor of minimum requirements and request maintenance, and can never submit a record or change state. Everyone else reads.

What the registry checks: who submitted; linkage of each record to the state it was computed against; that layers outside a cycle's scope did not change; that completions never go backwards in time; that the declared outcome agrees with the per-layer completions; that a cycle is interpreted under the policy version in effect when it started. What it does not and cannot check: that the off-chain routine ran, that a check passed, or that a change is an improvement.

## The four layers

| Index | Layer | Describes |
| --- | --- | --- |
| 0 | Runtime | code, dependencies, adapters (API/MCP bindings), authorization configuration, self-check suite |
| 1 | Memory and skills | memory organization and digest, skill inventory and package hashes, harness configuration |
| 2 | Tasks and roles | roles, plans, tasks with their version bindings, services offered |
| 3 | Cognition | self-model, assumptions and their evidence, judgment strategies, reflection methods, the maintenance policy itself |

Each layer is committed with `keccak256(abi.encode(TAG, layer, keccak256(schemaId), keccak256(JCS(document)), salt))`; the four commitments form the state root. Timed observations (balances, reachability) never enter a layer document; they go into the cycle record.

## Kernel objects

| Object | Role |
| --- | --- |
| Policy (versioned) | what the subject maintains, which layers carry a deadline and at which interval, accepted triggers, pulse tracking, disclosure level |
| Floor (controller) | minimum requirements the policy cannot relax |
| Layer checkpoints | current commitment, last completion time (reported and recorded), governing policy version, last change version |
| Cycle record | scope, completed layers, operations, outcome, trigger, governing policy version, reported times, post commitments, restore claim, record hash |
| Pulse | activity signal only; refreshes nothing else |

Derived views: `layerStatus` (FRESH / DUE / OVERDUE per layer, or UNSCHEDULED / UNSUPPORTED / NOT_ENROLLED) and `signalStatus` (PRESENT / SILENT / NOT_TRACKED), kept independent of each other.

## Repository layout

```text
ERCS/erc-agent-meditation.md        proposal text (source; the filing package renames it)
assets/erc-agent-meditation/
  contracts/                        IAgentMeditation.sol, AgentMeditationRegistry.sol (+ ERC-165/6372 interfaces)
  abi/                              ABI exports
  schemas/                          JSON Schemas of the four layer documents, the policy and the cycle record
  examples/mcp-timeout-cycle/       worked example: baseline and post documents, policy, salts, cycle record
  vectors/                          commitments, roots, interface id, canonicalization vectors
test/                               Foundry tests (dependency-free cheatcode base)
tools/                              reference tooling: JCS, commitments, vectors, meditation runner
script/Evidence.s.sol               evidence run (deploy, enroll, cycles, floor, demand, rollback, policy v2)
scripts/                            filing package, eipw and markdownlint runners, evidence driver and summary
docs/                               design memo, profiles, commitment format, Magicians post, runbooks
deployments/                        evidence records
```

## Build and test

Requirements: Foundry (1.7 or later) and Node.js 22. No Solidity library dependencies.

```bash
forge build
forge test
npm ci
npm run vectors:check              # recompute vectors and compare
npm run filing                     # ercs-pr-package/ (ERCS/erc-8490.md + assets/erc-8490/)
npm run filing:lint                # eipw under the ethereum/ERCs configuration
npm run filing:markdownlint        # markdownlint under the ethereum/ERCs configuration
scripts/evidence-run.sh anvil      # full evidence rehearsal on a local anvil
```

## Reference runner

`tools/runner.js` turns an agent's own artifacts (four layer documents, a policy document, a cycle record document) into commitments and calls:

```bash
node tools/runner.js commit --state assets/erc-agent-meditation/examples/mcp-timeout-cycle/baseline \
  --salts assets/erc-agent-meditation/examples/mcp-timeout-cycle/salts.json --set baseline

node tools/runner.js report \
  --pre  assets/erc-agent-meditation/examples/mcp-timeout-cycle/baseline \
  --post assets/erc-agent-meditation/examples/mcp-timeout-cycle/post \
  --record assets/erc-agent-meditation/examples/mcp-timeout-cycle/cycle-record.json \
  --salts assets/erc-agent-meditation/examples/mcp-timeout-cycle/salts.json
```

Add `--rpc <url> --key <hex> --registry <address>` to submit. The runner does not perform maintenance; it registers what an agent's routines produced.

## Status

- ERC text, reference implementation, tests, tooling, worked example and vectors: complete
- Number ERC-8490 assigned in ethereum/ERCs pull request #2155 (open, awaiting editor review); Ethereum Magicians topic 30304
- Sepolia evidence run: pending (see [`docs/sepolia-runbook.md`](docs/sepolia-runbook.md))

## License

CC0-1.0 for the proposal text and its assets. See [`LICENSE.md`](LICENSE.md).
