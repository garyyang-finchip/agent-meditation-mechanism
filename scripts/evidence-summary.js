#!/usr/bin/env node
"use strict";

/**
 * Collects the forge broadcast records of an evidence run into deployments/<network>.json.
 *
 *   node scripts/evidence-summary.js <network>
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const network = process.argv[2] || "anvil";
const outDir = path.join(ROOT, "deployments", network);
const state = JSON.parse(fs.readFileSync(path.join(outDir, "state.json"), "utf8"));

function readSnapshot(label) {
  const p = path.join(outDir, `state-${label}.json`);
  return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : null;
}

function readJson(p) {
  return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : null;
}

/** ERC-165 identifiers of the interfaces the deployed registry reports, from the vectors. */
function interfaceIds() {
  const v = readJson(path.join(ROOT, "assets", "erc-agent-meditation", "vectors", "interface.json"));
  if (!v) return null;
  return {
    IAgentMeditation: v.interfaceId,
    IAgentMeditationStart: v.extensions?.IAgentMeditationStart?.interfaceId ?? null,
  };
}

function collectBroadcasts() {
  const root = path.join(ROOT, "broadcast", "Evidence.s.sol");
  if (!fs.existsSync(root)) return [];
  const txs = [];
  for (const chainId of fs.readdirSync(root)) {
    const dir = path.join(root, chainId);
    for (const file of fs.readdirSync(dir)) {
      if (!file.endsWith("-latest.json")) continue; // one file per script function, named after it
      const run = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
      const phase = file.replace(/-latest\.json$/, "");
      const receipts = new Map((run.receipts || []).map((r) => [r.transactionHash, r]));
      for (const t of run.transactions || []) {
        const r = receipts.get(t.hash) || {};
        txs.push({
          phase,
          chainId: Number(chainId),
          type: t.transactionType,
          contract: t.contractName || null,
          function: t.function || null,
          from: t.transaction?.from || null,
          to: t.transaction?.to || t.contractAddress || null,
          hash: t.hash,
          blockNumber: r.blockNumber ? Number(r.blockNumber) : null,
          gasUsed: r.gasUsed ? Number(r.gasUsed) : null,
          status: r.status || null,
        });
      }
    }
  }
  txs.sort((a, b) => (a.blockNumber || 0) - (b.blockNumber || 0));
  return txs;
}

const summary = {
  network,
  registry: state.registry,
  actors: {agent: state.agent, controller: state.controller, operator: state.operator},
  interfaces: interfaceIds(),
  snapshots: {
    afterPhaseA: readSnapshot("A"),
    afterPhaseA2: readSnapshot("A2"),
    overdue: readSnapshot("overdue"),
    afterPhaseB: readSnapshot("B"),
    afterPhaseC: readSnapshot("C"),
    afterPhaseD1: readSnapshot("D1"),
    afterPhaseD1b: readSnapshot("D1b"),
    perLayer: readSnapshot("perLayer"),
    final: readSnapshot("final"),
  },
  transactions: collectBroadcasts(),
  rejectedCalls: readJson(path.join(outDir, "rejected.json")) || [],
};

const outFile = path.join(ROOT, "deployments", `${network}.json`);
fs.writeFileSync(outFile, JSON.stringify(summary, null, 2) + "\n");
process.stdout.write(
  `wrote ${path.relative(ROOT, outFile)} (${summary.transactions.length} transactions, ${summary.rejectedCalls.length} rejected calls)\n`
);
