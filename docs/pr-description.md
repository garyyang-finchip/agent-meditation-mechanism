# ethereum/ERCs pull request description

Title: `Add ERC-8490: Agent Meditation Mechanism`

---

This PR adds **ERC-8490: Agent Meditation Mechanism** (number assigned 2026-11-09): a minimal registry through which an AI agent records its own self-maintenance as attributable, versioned state across four fixed layers (runtime; memory and skills; tasks and roles; cognition), with per-layer completion checkpoints, a versioned policy, a controller floor, linkage checks between successive states, and an activity signal kept apart from maintenance timeliness.

- Discussion: https://ethereum-magicians.org/t/erc-8490-agent-meditation-mechanism/30304
- Reference repository: https://github.com/garyyang-finchip/agent-meditation-mechanism
- Requires: ERC-165, ERC-6372 (normative). Other proposals are referenced descriptively only.

Assets included: interface, optional recorded-start extension interface and reference registry (Solidity 0.8.28), ABI exports, JSON Schemas for the four layer documents, the policy document and the cycle record document, a worked example with its documents, salts and cycle record, and vectors (commitments, roots, interface id, canonicalization). The Test Cases section is self-contained and reproduces the vectors.

Local checks: eipw under `config/eipw.toml` (0 findings), markdownlint under `config/.markdownlint.yaml` (0 findings), CodeSpell with the repository whitelist (0 findings), 96 Foundry tests passing from a fresh clone. A Sepolia evidence run of the reference registry (enrollment, worked-example cycle, controller floor and demand, overdue and silent snapshot, adoption, refresh, rollback to an earlier version, policy version 2) has completed; its record is published in the reference repository.
