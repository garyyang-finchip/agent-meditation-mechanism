#!/usr/bin/env node
"use strict";

/**
 * Sends the calls of an evidence run that the registry must reject, as transactions that fail on chain.
 *
 *   node scripts/evidence-rejected.js <network>
 *
 * Reads deployments/<network>/rejected-calls.json (written by phase D1b of script/Evidence.s.sol); needs RPC_URL,
 * AGENT_PK and OPERATOR_PK. For every call it first runs eth_call from the same account and checks that the call
 * reverts with the expected registry error; only then it sends the transaction with a fixed gas limit (no gas
 * estimation, which would refuse a reverting call) and waits for the receipt, which must show status 0.
 * Results go to deployments/<network>/rejected.json. Nothing is sent if any preflight disagrees.
 */

const fs = require("fs");
const path = require("path");
const {ethers} = require("ethers");

const ROOT = path.join(__dirname, "..");
const network = process.argv[2] || "anvil";
const outDir = path.join(ROOT, "deployments", network);
const callsFile = path.join(outDir, "rejected-calls.json");
const resultFile = path.join(outDir, "rejected.json");
const GAS_LIMIT = BigInt(process.env.REJECTED_GAS_LIMIT || "600000");

const abi = JSON.parse(
  fs.readFileSync(path.join(ROOT, "assets", "erc-agent-meditation", "abi", "AgentMeditationRegistry.json"), "utf8")
);
const registryInterface = new ethers.Interface(abi);

function decodeRevert(data) {
  if (!data || data === "0x") return "(no revert data)";
  const parsed = registryInterface.parseError(data);
  if (!parsed) return `(unknown error ${data.slice(0, 10)})`;
  return `${parsed.name}(${parsed.args.map((a) => a.toString()).join(",")})`;
}

function revertDataOf(err) {
  // ethers v6 puts revert data on CALL_EXCEPTION errors; some nodes nest it in the JSON-RPC error.
  return err?.data ?? err?.info?.error?.data ?? err?.error?.data ?? null;
}

async function main() {
  const rpc = process.env.RPC_URL;
  if (!rpc) throw new Error("set RPC_URL");
  const provider = new ethers.JsonRpcProvider(rpc);
  const wallets = {
    agent: new ethers.Wallet(process.env.AGENT_PK, provider),
    operator: new ethers.Wallet(process.env.OPERATOR_PK, provider),
  };
  const calls = JSON.parse(fs.readFileSync(callsFile, "utf8"));

  // Preflight every call before sending any.
  for (const c of calls) {
    const from = wallets[c.from];
    if (!from) throw new Error(`unknown sender ${c.from}`);
    let decoded;
    try {
      await provider.call({from: from.address, to: c.to, data: c.data});
      decoded = "(did not revert)";
    } catch (err) {
      c.revertData = revertDataOf(err);
      decoded = decodeRevert(c.revertData);
    }
    c.decoded = decoded;
    // Some public endpoints drop revert data; REJECTED_ALLOW_UNDECODED=1 accepts a revert whose reason is not returned.
    const undecodedOk = decoded === "(no revert data)" && process.env.REJECTED_ALLOW_UNDECODED === "1";
    const ok = decoded === c.expected || undecodedOk;
    process.stdout.write(`preflight r${c.revision} ${c.label}: ${decoded} ${ok ? "(as expected)" : `(expected ${c.expected})`}\n`);
    if (!ok) throw new Error(`preflight of ${c.label} did not revert with ${c.expected}; nothing sent`);
  }

  const latest = await provider.getBlock("latest");
  const priority = BigInt(await provider.send("eth_maxPriorityFeePerGas", []).catch(() => "0x0"));
  const maxFee = (latest.baseFeePerGas ?? 0n) * 2n + priority;

  const results = [];
  for (const c of calls) {
    const wallet = wallets[c.from];
    const tx = await wallet.sendTransaction({
      to: c.to,
      data: c.data,
      gasLimit: GAS_LIMIT,
      maxFeePerGas: maxFee,
      maxPriorityFeePerGas: priority,
    });
    let receipt;
    try {
      receipt = await tx.wait();
    } catch (err) {
      receipt = err?.receipt ?? (await provider.getTransactionReceipt(tx.hash));
    }
    const status = receipt ? `0x${receipt.status.toString(16)}` : null;
    process.stdout.write(`sent r${c.revision} ${c.label}: ${tx.hash} block ${receipt?.blockNumber} status ${status}\n`);
    if (status !== "0x0") throw new Error(`${c.label} did not fail on chain (status ${status})`);
    results.push({
      label: c.label,
      revision: c.revision,
      from: wallet.address,
      to: c.to,
      hash: tx.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: Number(receipt.gasUsed),
      status,
      expectedError: c.expected,
      preflightRevertData: c.revertData,
      preflightDecoded: c.decoded,
    });
  }
  fs.writeFileSync(resultFile, JSON.stringify(results, null, 2) + "\n");
  process.stdout.write(`wrote ${path.relative(ROOT, resultFile)} (${results.length} rejected calls)\n`);
}

main().catch((err) => {
  process.stderr.write(`${err.message || err}\n`);
  process.exit(1);
});
