"use strict";

const {ethers} = require("ethers");
const {canonicalize} = require("./jcs");

const coder = ethers.AbiCoder.defaultAbiCoder();

const TAG_LAYER_COMMITMENT = ethers.keccak256(ethers.toUtf8Bytes("AgentMeditationMechanism/LayerCommitment/v1"));
const TAG_STATE_ROOT = ethers.keccak256(ethers.toUtf8Bytes("AgentMeditationMechanism/StateRoot/v1"));

const LAYERS = ["runtime", "memory-skills", "tasks-roles", "cognition"];
const LAYER_SCHEMAS = [
  "amm.layer.runtime/1",
  "amm.layer.memory-skills/1",
  "amm.layer.tasks-roles/1",
  "amm.layer.cognition/1",
];
const ZERO = "0x" + "00".repeat(32);

/** keccak256 of the canonical (RFC 8785) UTF-8 serialization of a JSON document. */
function contentHash(doc) {
  return ethers.keccak256(ethers.toUtf8Bytes(canonicalize(doc)));
}

/** keccak256 of a schema identifier string. */
function schemaHash(schemaId) {
  return ethers.keccak256(ethers.toUtf8Bytes(schemaId));
}

/** Layer commitment: keccak256(abi.encode(TAG, uint8 layer, bytes32 schemaHash, bytes32 contentHash, bytes32 salt)). */
function layerCommitment(layer, schemaHashHex, contentHashHex, salt = ZERO) {
  if (!(layer >= 0 && layer <= 3)) throw new RangeError("layer must be 0..3");
  return ethers.keccak256(
    coder.encode(
      ["bytes32", "uint8", "bytes32", "bytes32", "bytes32"],
      [TAG_LAYER_COMMITMENT, layer, schemaHashHex, contentHashHex, salt],
    ),
  );
}

/** Commitment of a layer state document, validating that its `schema` and `layer` members match. */
function commitLayerDocument(layer, doc, salt = ZERO) {
  if (doc.layer !== layer) throw new Error(`document layer ${doc.layer} does not match ${layer}`);
  if (doc.schema !== LAYER_SCHEMAS[layer]) {
    throw new Error(`document schema ${doc.schema} does not match ${LAYER_SCHEMAS[layer]}`);
  }
  const sh = schemaHash(doc.schema);
  const ch = contentHash(doc);
  return {schemaId: doc.schema, schemaHash: sh, contentHash: ch, salt, commitment: layerCommitment(layer, sh, ch, salt)};
}

/** State root over four layer commitments. */
function stateRoot(commitments) {
  if (commitments.length !== 4) throw new RangeError("four commitments required");
  return ethers.keccak256(coder.encode(["bytes32", "bytes32", "bytes32", "bytes32", "bytes32"], [TAG_STATE_ROOT, ...commitments]));
}

/** Commitment to an off-chain cycle record document. */
function recordHash(doc) {
  return contentHash(doc);
}

module.exports = {
  TAG_LAYER_COMMITMENT,
  TAG_STATE_ROOT,
  LAYERS,
  LAYER_SCHEMAS,
  ZERO,
  canonicalize,
  contentHash,
  schemaHash,
  layerCommitment,
  commitLayerDocument,
  stateRoot,
  recordHash,
};
