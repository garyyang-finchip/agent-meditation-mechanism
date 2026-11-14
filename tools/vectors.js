#!/usr/bin/env node
"use strict";

/**
 * Generates (or checks, with --check) the test vectors under assets/erc-agent-meditation/vectors.
 *
 *   node tools/vectors.js          # write vectors
 *   node tools/vectors.js --check  # recompute and compare, exit 1 on any difference
 */

const fs = require("fs");
const path = require("path");
const commit = require("./lib/commit");
const R = require("./lib/report");

const ROOT = path.join(__dirname, "..");
const ASSETS = path.join(ROOT, "assets", "erc-agent-meditation");
const VECTORS = path.join(ASSETS, "vectors");
const EXAMPLE = path.join(ASSETS, "examples", "mcp-timeout-cycle");

function build() {
  const salts = R.readJson(path.join(EXAMPLE, "salts.json"));
  const pre = R.commitStateDir(path.join(EXAMPLE, "baseline"), salts.baseline);
  const post = R.commitStateDir(path.join(EXAMPLE, "post"), salts.post);
  const record = R.readJson(path.join(EXAMPLE, "cycle-record.json"));
  const policyDoc = R.readJson(path.join(EXAMPLE, "policy.json"));
  const built = R.buildReport(record, pre, post, {recordURI: "ipfs://example/mcp-timeout-cycle/cycle-record.json"});

  const example = {
    description: "Worked example: an MCP-timeout event cycle. Layers 0-2 adopt new states, layer 3 forms a candidate and keeps its state.",
    tags: {layerCommitment: commit.TAG_LAYER_COMMITMENT, stateRoot: commit.TAG_STATE_ROOT},
    subject: record.subject,
    policy: {
      document: "examples/mcp-timeout-cycle/policy.json",
      policyHash: commit.contentHash(policyDoc),
      struct: R.jsonable(R.policyStruct(policyDoc, "")),
    },
    pre: {
      layers: pre.layers.map(stripFile),
      root: pre.root,
    },
    post: {
      layers: post.layers.map(stripFile),
      root: post.root,
    },
    record: {
      document: "examples/mcp-timeout-cycle/cycle-record.json",
      recordHash: commit.recordHash(record),
      canonicalLength: Buffer.byteLength(commit.canonicalize(record), "utf8"),
    },
    report: R.jsonable(built.struct),
    summary: built.summary,
    calldata: R.encodeReport(record.subject, built.struct),
  };

  const jcs = {
    description: "RFC 8785 canonicalization vectors (UTF-8 bytes hashed with keccak256).",
    cases: [
      {input: {b: 1, a: [true, null, "x"], c: {z: 1.5, y: "é"}}, canonical: commit.canonicalize({b: 1, a: [true, null, "x"], c: {z: 1.5, y: "é"}})},
      {input: {"€": 1, A: 2, a: 3, "": 4}, canonical: commit.canonicalize({"€": 1, A: 2, a: 3, "": 4})},
      {input: {n: 1e21, m: 0.000001, k: -0, s: "line\nbreak\ttab\"quote\\"}, canonical: commit.canonicalize({n: 1e21, m: 0.000001, k: -0, s: "line\nbreak\ttab\"quote\\"})},
    ],
  };
  for (const c of jcs.cases) c.keccak256 = commit.contentHash(c.input);

  const selectors = (name) =>
    R.loadAbi(name)
      .filter((f) => f.type === "function")
      .map((f) => {
        const frag = require("ethers").FunctionFragment.from(f);
        return {signature: frag.format("sighash"), selector: frag.selector};
      })
      .sort((a, b) => (a.signature < b.signature ? -1 : 1));
  const iface = {
    description:
      "ERC-165 interface identifiers: IAgentMeditation (required) and IAgentMeditationStart (optional recorded-start extension); each is the XOR of the interface's function selectors.",
    interfaceId: R.interfaceId(),
    functions: selectors("IAgentMeditation"),
    extensions: {
      IAgentMeditationStart: {
        interfaceId: R.interfaceId(R.loadAbi("IAgentMeditationStart")),
        functions: selectors("IAgentMeditationStart"),
      },
    },
  };

  return {
    "example-mcp-timeout.json": example,
    "jcs.json": jcs,
    "interface.json": iface,
  };
}

function stripFile(l) {
  const {file, ...rest} = l;
  return {...rest, document: `examples/mcp-timeout-cycle/<set>/${file}`};
}

function main() {
  const check = process.argv.includes("--check");
  const vectors = build();
  let failed = false;
  fs.mkdirSync(VECTORS, {recursive: true});
  for (const [name, value] of Object.entries(vectors)) {
    const p = path.join(VECTORS, name);
    const text = JSON.stringify(value, null, 2) + "\n";
    if (check) {
      const current = fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "";
      if (current !== text) {
        failed = true;
        process.stderr.write(`vector mismatch: ${name}\n`);
      } else {
        process.stdout.write(`ok: ${name}\n`);
      }
    } else {
      fs.writeFileSync(p, text);
      process.stdout.write(`wrote ${path.relative(ROOT, p)}\n`);
    }
  }
  if (failed) process.exit(1);
}

main();
