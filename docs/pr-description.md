# ethereum/ERCs pull request description (draft)

Title: `Add ERC: Agent Meditation Mechanism`

---

This PR adds a new draft ERC, **Agent Meditation Mechanism**: a minimal registry through which an AI agent records its own self-maintenance as attributable, versioned state across four fixed layers (runtime; memory and skills; tasks and roles; cognition), with per-layer completion checkpoints, a versioned policy, a controller floor, linkage checks between successive states, and an activity signal kept apart from maintenance timeliness.

- Discussion: `<Ethereum Magicians thread URL>`
- Reference repository: https://github.com/garyyang-finchip/agent-meditation
- Requires: ERC-165, ERC-6372 (normative). Other proposals are referenced descriptively only.

Assets included: interface and reference registry (Solidity 0.8.28), ABI exports, JSON Schemas for the four layer documents, the policy document and the cycle record document, a worked example with its documents, salts and cycle record, and vectors (commitments, roots, interface id, canonicalization). The Test Cases section is self-contained and reproduces the vectors.

Local checks: eipw under `config/eipw.toml` (0 findings), markdownlint under `config/.markdownlint.yaml` (0 findings), 64 Foundry tests passing from a fresh clone.
