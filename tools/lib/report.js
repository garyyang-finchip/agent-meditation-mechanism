"use strict";

const fs = require("fs");
const path = require("path");
const {ethers} = require("ethers");
const commit = require("./commit");

const ABI_PATH = path.join(__dirname, "..", "..", "assets", "erc-agent-meditation", "abi", "IAgentMeditation.json");

const OUTCOMES = {completed: 0, partial: 1, aborted: 2, failed: 3};
const TRIGGERS = {scheduled: 0, event: 1, commanded: 2, self: 3};
const OPS = {clean: 0, repair: 1, update: 2, iterate: 3};
const LAYER_FILES = ["runtime.json", "memory-skills.json", "tasks-roles.json", "cognition.json"];

function loadAbi() {
  return JSON.parse(fs.readFileSync(ABI_PATH, "utf8"));
}

function iface() {
  return new ethers.Interface(loadAbi());
}

/** ERC-165 interface id: XOR of every function selector of the interface. */
function interfaceId(abi = loadAbi()) {
  let acc = 0n;
  for (const f of abi) {
    if (f.type !== "function") continue;
    const frag = ethers.FunctionFragment.from(f);
    acc ^= BigInt(frag.selector);
  }
  return "0x" + acc.toString(16).padStart(8, "0");
}

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

/** Read the four layer state documents of a directory and commit them. */
function commitStateDir(dir, salts) {
  const layers = [];
  for (let i = 0; i < 4; i++) {
    const doc = readJson(path.join(dir, LAYER_FILES[i]));
    const salt = salts ? salts[i] : commit.ZERO;
    layers.push({layer: i, file: LAYER_FILES[i], ...commit.commitLayerDocument(i, doc, salt)});
  }
  const root = commit.stateRoot(layers.map((l) => l.commitment));
  return {layers, commitments: layers.map((l) => l.commitment), root};
}

/** Build the on-chain Policy struct (array form, interface order) from a policy document. */
function policyStruct(policyDoc, policyURI = "") {
  const o = policyDoc.onchain;
  return [
    commit.contentHash(policyDoc), // policyHash
    policyURI,
    o.supportedLayers,
    o.requiredLayers,
    o.allowedTriggers,
    o.disclosure,
    o.dueWindow,
    o.pulseInterval,
    o.maxInterval,
  ];
}

/**
 * Build a CycleReport (array form, interface order) from a cycle record document and the pre/post commitments.
 * The record document is the off-chain source of truth; this function derives the on-chain summary from it.
 */
function buildReport(recordDoc, pre, post, options = {}) {
  let layerMask = 0;
  let completedLayers = 0;
  let opsMask = 0;
  for (const l of recordDoc.layers) {
    if (!l.scope) continue;
    layerMask |= 1 << l.layer;
    if (l.completed) completedLayers |= 1 << l.layer;
    for (const c of l.changes || []) {
      if (!(c.op in OPS)) throw new Error(`unknown op ${c.op}`);
      opsMask |= 1 << (l.layer * 4 + OPS[c.op]);
    }
  }
  if (!(recordDoc.outcome in OUTCOMES)) throw new Error(`unknown outcome ${recordDoc.outcome}`);
  if (!(recordDoc.trigger in TRIGGERS)) throw new Error(`unknown trigger ${recordDoc.trigger}`);
  const postCommitments = post.commitments.slice();
  // Layers out of scope must carry the pre-state commitment; the kernel rejects anything else.
  for (let i = 0; i < 4; i++) {
    if ((layerMask & (1 << i)) === 0 && postCommitments[i] !== pre.commitments[i]) {
      throw new Error(`layer ${i} is out of scope but its commitment differs from the pre state`);
    }
  }
  return {
    struct: [
      BigInt(recordDoc.baseVersion), // baseVersion
      pre.root, // preRoot
      postCommitments,
      layerMask,
      completedLayers,
      opsMask,
      OUTCOMES[recordDoc.outcome],
      TRIGGERS[recordDoc.trigger],
      recordDoc.policyVersion,
      recordDoc.reportedStartedAt,
      recordDoc.reportedEndedAt,
      recordDoc.nextPlannedAt || 0,
      BigInt(recordDoc.restoresVersion || 0),
      commit.recordHash(recordDoc),
      options.recordURI || "",
    ],
    summary: {
      layerMask,
      completedLayers,
      opsMask,
      changedLayers: post.commitments.reduce((m, c, i) => (c !== pre.commitments[i] ? m | (1 << i) : m), 0),
      outcome: OUTCOMES[recordDoc.outcome],
      trigger: TRIGGERS[recordDoc.trigger],
      recordHash: commit.recordHash(recordDoc),
      postRoot: post.root,
    },
  };
}

function encodeReport(subject, reportStruct) {
  return iface().encodeFunctionData("report", [subject, reportStruct]);
}

function encodeEnroll(baseline, policyStructArr, controller, rights) {
  return iface().encodeFunctionData("enroll", [baseline, policyStructArr, controller, rights]);
}

function encodePulse(subject, nextPlannedAt) {
  return iface().encodeFunctionData("pulse", [subject, nextPlannedAt]);
}

/** Serialize bigint-containing structures for JSON output. */
function jsonable(v) {
  return JSON.parse(JSON.stringify(v, (_k, x) => (typeof x === "bigint" ? x.toString() : x)));
}

module.exports = {
  ABI_PATH,
  OUTCOMES,
  TRIGGERS,
  OPS,
  LAYER_FILES,
  loadAbi,
  iface,
  interfaceId,
  readJson,
  commitStateDir,
  policyStruct,
  buildReport,
  encodeReport,
  encodeEnroll,
  encodePulse,
  jsonable,
};
