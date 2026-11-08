#!/usr/bin/env node
"use strict";

/**
 * Reference meditation runner (off-chain side of the Agent Meditation Mechanism).
 *
 * The runner does not perform the maintenance itself; it turns the artifacts an agent's own
 * routines produce (four layer state documents, a policy document, a cycle record document)
 * into the commitments and the on-chain calls the kernel expects, and optionally submits them.
 *
 *   node tools/runner.js commit  --state <dir> [--salts salts.json --set baseline|post]
 *   node tools/runner.js enroll  --state <dir> --policy policy.json [--controller 0x.. --rights N] [--salts ... --set ...]
 *   node tools/runner.js report  --pre <dir> --post <dir> --record cycle-record.json [--salts salts.json]
 *                                [--subject 0x..] [--record-uri uri] [--out report.json]
 *   node tools/runner.js pulse   --subject 0x.. [--next <timepoint>]
 *
 * Submission (any command that produces calldata): --rpc <url> --key <hex> --registry <address>
 */

const fs = require("fs");
const path = require("path");
const {ethers} = require("ethers");
const R = require("./lib/report");

function parseArgs(argv) {
  const out = {_: []};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const k = a.slice(2);
      const v = i + 1 < argv.length && !argv[i + 1].startsWith("--") ? argv[++i] : "true";
      out[k] = v;
    } else {
      out._.push(a);
    }
  }
  return out;
}

function saltsFor(args, which) {
  if (!args.salts) return undefined;
  const s = R.readJson(args.salts);
  const key = which || args.set || "baseline";
  if (!s[key]) throw new Error(`salts file has no set '${key}'`);
  return s[key];
}

async function maybeSubmit(args, calldata, label) {
  if (!args.rpc) return null;
  if (!args.key || !args.registry) throw new Error("--rpc requires --key and --registry");
  const provider = new ethers.JsonRpcProvider(args.rpc);
  const wallet = new ethers.Wallet(args.key, provider);
  const tx = await wallet.sendTransaction({to: args.registry, data: calldata});
  process.stderr.write(`${label}: sent ${tx.hash}\n`);
  const receipt = await tx.wait();
  process.stderr.write(`${label}: mined in block ${receipt.blockNumber}, status ${receipt.status}\n`);
  return {hash: tx.hash, blockNumber: receipt.blockNumber, status: receipt.status};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const cmd = args._[0];
  if (!cmd) {
    process.stderr.write(fs.readFileSync(__filename, "utf8").split("\n").slice(3, 17).join("\n") + "\n");
    process.exit(2);
  }

  if (cmd === "commit") {
    const state = R.commitStateDir(args.state, saltsFor(args));
    print({root: state.root, layers: state.layers});
    return;
  }

  if (cmd === "enroll") {
    const state = R.commitStateDir(args.state, saltsFor(args));
    const policyDoc = R.readJson(args.policy);
    const policy = R.policyStruct(policyDoc, args["policy-uri"] || "");
    const controller = args.controller || ethers.ZeroAddress;
    const rights = Number(args.rights || 0);
    const calldata = R.encodeEnroll(state.commitments, policy, controller, rights);
    const result = {baseline: state.commitments, root: state.root, policy: R.jsonable(policy), controller, rights, calldata};
    result.tx = await maybeSubmit(args, calldata, "enroll");
    print(result);
    return;
  }

  if (cmd === "report") {
    const pre = R.commitStateDir(args.pre, saltsFor(args, args["pre-set"] || "baseline"));
    const post = R.commitStateDir(args.post, saltsFor(args, args["post-set"] || "post"));
    const record = R.readJson(args.record);
    const subject = args.subject || record.subject;
    if (!subject) throw new Error("--subject or record.subject required");
    const built = R.buildReport(record, pre, post, {recordURI: args["record-uri"] || ""});
    const calldata = R.encodeReport(subject, built.struct);
    const result = {
      subject,
      pre: {root: pre.root, commitments: pre.commitments},
      post: {root: post.root, commitments: post.commitments},
      report: R.jsonable(built.struct),
      summary: built.summary,
      calldata,
    };
    result.tx = await maybeSubmit(args, calldata, "report");
    if (args.out) fs.writeFileSync(args.out, JSON.stringify(result, null, 2) + "\n");
    print(result);
    return;
  }

  if (cmd === "pulse") {
    const subject = args.subject;
    if (!subject) throw new Error("--subject required");
    const next = Number(args.next || 0);
    const calldata = R.encodePulse(subject, next);
    const result = {subject, nextPlannedAt: next, calldata};
    result.tx = await maybeSubmit(args, calldata, "pulse");
    print(result);
    return;
  }

  throw new Error(`unknown command ${cmd}`);
}

function print(obj) {
  process.stdout.write(JSON.stringify(obj, null, 2) + "\n");
}

main().catch((e) => {
  process.stderr.write(`error: ${e.message}\n`);
  process.exit(1);
});
