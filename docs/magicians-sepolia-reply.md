# Ethereum Magicians reply: Sepolia evidence (draft)

---

**Sepolia evidence run (2026-11-09).** The reference registry is deployed on Sepolia at `0x184dF595404414f91aD11986C47B9a539eF9559f` (Sourcify: creation and runtime bytecode match; creation tx `0x3a68a0f26f4f6bfc527963ce3d6b539e809a7f67fe39bd2b11fe654a0ff6abc1`). Fifteen transactions in blocks 12094378–12094420, all successful; the record with every hash, gas figure and registry snapshot is in the repository at `deployments/sepolia.json`, with a walkthrough in `docs/sepolia-evidence.md`.

The run uses three fresh keys (subject, controller, operator) and short intervals so that every status transition shows within ten minutes:

1. **Enroll** with the worked-example baseline; all four layers read `FRESH` but *never completed*, deadlines counted from enrollment.
2. **Worked-example cycle** recorded by the operator: scope and completion `0x0F`, operations `0x0456`; layers 0–2 adopt new commitments (state version 2), layer 3 keeps its commitment while its completion time moves.
3. **Controller floor and demand**: layer 0 required every 300 s and a pulse every 120 s; layer 3 demanded within 600 s. Deadlines move, state does not.
4. **Overdue snapshot** (read from the chain 330 s later): layer 0 `OVERDUE`, signal `SILENT` since 1794189504, layers 1–3 `FRESH`. Activity and timeliness are reported separately, and a pulse would not have changed the layer status.
5. **Layer-3 cycle** adopting the candidate strategy (COMMANDED trigger) clears the demand because its reported end is after the demand; **layer-0 cycle** makes layer 0 fresh again (state version 4).
6. **Rollback**: layers 0 and 3 restored to their version-2 commitments with `restoresVersion = 2`; accepted because the resulting root equals `rootAt(2)`; the state version advances to 5 rather than rewinding.
7. **Policy version 2** appended after the rollback cycle, which itself was interpreted under version 1 (the version in effect when it started); final pulse.

One operational note for implementers: Sepolia's current gas schedule prices the registry deployment at about 26.1M gas (a local EVM estimates 3.7M), and `enroll` at 2.24M against 0.48M locally. The evidence driver now takes every gas limit from the node (`--skip-simulation`) after a first deployment attempt ran out of gas at 5.5M.
