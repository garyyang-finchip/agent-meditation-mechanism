# Commitment format

## Layer state documents

Each layer state document is a JSON document with at least:

```json
{"schema": "amm.layer.runtime/1", "layer": 0}
```

Schema identifiers of this version:

| Layer | schema |
| --- | --- |
| 0 | `amm.layer.runtime/1` |
| 1 | `amm.layer.memory-skills/1` |
| 2 | `amm.layer.tasks-roles/1` |
| 3 | `amm.layer.cognition/1` |

JSON Schemas are under `assets/erc-agent-meditation/schemas/`. They fix the envelope and the shape of the known members and allow additional members, so an implementation can carry what it needs without leaving the format.

## Canonicalization

Documents are serialized with the JSON Canonicalization Scheme (RFC 8785): object members sorted by UTF-16 code units, numbers and strings serialized as ECMAScript does, no whitespace. `tools/lib/jcs.js` implements it without dependencies; `assets/erc-agent-meditation/vectors/jcs.json` holds vectors.

## Commitments

```text
TAG_LAYER_COMMITMENT = keccak256("AgentMeditationMechanism/LayerCommitment/v1")
                     = 0xc76b0a7a69207b3cf002d75e6493bc9fe99e8d75b5096ead1276bc4339b69d85
TAG_STATE_ROOT       = keccak256("AgentMeditationMechanism/StateRoot/v1")
                     = 0xe2251470d039826c2565c6e003924bb890e07cd981b370528c245e47f1c3e7c6

schemaHash  = keccak256(utf8(schema))
contentHash = keccak256(utf8(JCS(document)))
commitment  = keccak256(abi.encode(TAG_LAYER_COMMITMENT, uint8 layer, bytes32 schemaHash, bytes32 contentHash, bytes32 salt))
root        = keccak256(abi.encode(TAG_STATE_ROOT, c0, c1, c2, c3))
recordHash  = keccak256(utf8(JCS(cycleRecordDocument)))
policyHash  = keccak256(utf8(JCS(policyDocument)))
```

The layer index inside the commitment separates the domains of the four layers; the tag separates this format from any other use of the same hash function; the schema hash binds the document to the schema it claims.

## Salts

A salt is a `bytes32` chosen by the subject. It is zero for documents whose content is public, and random for documents whose content could be guessed from public information (a memory digest, a cognition document). Salts are kept with the documents and disclosed with them. The registry stores commitments only; it never sees salts or documents.

## What is not in a commitment

Timed observations: balances, gas, endpoint reachability, resource usage, the wall-clock time of a check. They belong to the cycle record document so that the state root changes only when the state changes.

## Tooling

```bash
node tools/runner.js commit --state <dir with the four documents> [--salts salts.json --set baseline|post]
node tools/vectors.js --check
```

The Solidity helpers `computeLayerCommitment` and `computeRoot` on the registry reproduce the same values in-contract, which the test `test_vectors_tagsAndCommitments` verifies against the JSON vectors.
