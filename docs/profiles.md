# Adapters and profiles (informative)

The kernel is self-contained. The following adapters describe how other systems can consume its records. None of them changes the semantics of the kernel and none is required to implement the proposal. Where another proposal is mentioned by number, its own text governs; where one is described by concept, the adapter is written against the concept so that it can be bound to any registry of that kind.

## ERC-8004 identity metadata

An agent registered in the ERC-8004 identity registry may mirror its head into metadata, for example under the key `maintenance`, as a compact encoding of `(registry, stateVersion, root, lastCompletedAt[0..3])`, refreshed when a cycle is recorded. The mirror is a convenience for discovery; the registry of this proposal is the source. ERC-8004's reputation registry does not accept feedback from an agent's owner or approved operator, and self-maintenance records are not reputation: they are facts and evidence that other parties may weigh.

## Address-anchored agent identity registries (liveness and behavior facets)

A registry that derives an agent's liveness from recent activity can read `signalStatus` and the recorded completion times as additional liveness evidence. A behavior facet can summarize maintenance behavior over a window: number of cycles, per-layer completions, overdue episodes and their lengths, rollbacks. The facet is issued by the registry's own rules; this proposal supplies the inputs.

## Assertion registries (verified records)

An issuer that re-runs a subject's self-check suite, replays a layer-3 evaluation, or verifies a disclosed document against its commitment can assert the result against the cycle record (subject, record sequence, record hash). The assertion is the issuer's; the record is the subject's. This is how a self-reported record becomes third-party evidence without the kernel carrying a verifier interface.

## Safety frameworks (adopted specifications)

A safety specification can require a maintenance policy with given minimums, and can treat the subject's policy hash and its floor as the adopted specification and the cycle records as compliance evidence. An intervener with a controller relationship can use `demand` to require a completion by a deadline. A cycle may not remove an adopted safety binding by changing a layer commitment; a runner that knows about a binding refuses such a change and records the refusal.

## Dispute resolution

A dispute about a subject's state at a time can cite the state version and root registered at that time, demand disclosure of the committed documents and salts, and compare them to the subject's observed behavior. A record is attributable and time-ordered; whether its content was true is what the dispute decides.

## Task and swarm mechanisms

A task mechanism can require, as a consumer rule, that a worker's layer 0 (and possibly layer 2) be `FRESH` before a reservation is accepted, or that a worker not be in an announced maintenance window at a deadline. A swarm charter can require every member's layer 0 to be `FRESH` before a joint action. These are preconditions chosen by the consumer; the kernel supplies `layerStatus`.

## Reference runner integration

The reference runner (`tools/runner.js`) is deliberately generic: it reads four layer documents, a policy document and a cycle record document and produces the on-chain calls. A concrete agent runtime integrates by producing those documents from its own routines: a self-check suite produces layer-0 checks and the runtime manifest; a memory consolidation job produces the layer-1 digest and changes; a planner produces layer-2 plans and bindings; a reflection step produces layer-3 candidates, evaluations and adoption decisions. The cell prototype of this line is expected to expose this as a `meditate` command that runs the four routines and registers the cycle.
