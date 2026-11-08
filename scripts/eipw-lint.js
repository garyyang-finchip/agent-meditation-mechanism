#!/usr/bin/env node
"use strict";

/**
 * Lints the proposal of a filing package with eipw (the validator used by ethereum/ERCs CI),
 * under the ERCs repository configuration vendored at scripts/eipw.toml.
 *
 *   node scripts/eipw-lint.js [ercs-pr-package/ERCS/erc-9999.md]
 *
 * eipw reads every proposal the text references (requires header and ./eip-N.md links), so the
 * script stages the proposal in a temporary directory together with those proposals, fetched
 * from the ethereum/EIPs and ethereum/ERCs repositories and cached under node_modules/.cache.
 *
 * Exit status 1 when any error-level finding is reported. The finding that only exists because
 * the placeholder discussions-to has not been filled yet is reported but does not fail the run.
 */

const fs = require("fs");
const os = require("os");
const path = require("path");
const toml = require("smol-toml");
const eipw = require("eipw-lint-js");

const ROOT = path.join(__dirname, "..");
const DEFAULT_FILE = path.join(ROOT, "ercs-pr-package", "ERCS", "erc-9999.md");
const CACHE = path.join(ROOT, "node_modules", ".cache", "eipw-proposals");
const PLACEHOLDER = "ethereum-magicians.org/t/placeholder";
const SOURCES = [
  (n) => `https://raw.githubusercontent.com/ethereum/ERCs/master/ERCS/erc-${n}.md`,
  (n) => `https://raw.githubusercontent.com/ethereum/EIPs/master/EIPS/eip-${n}.md`,
];

function referencedProposals(text) {
  const numbers = new Set();
  const requires = text.match(/^requires:\s*(.+)$/m);
  if (requires) for (const n of requires[1].split(",")) numbers.add(n.trim());
  for (const m of text.matchAll(/\.\/eip-([0-9]+)\.md/g)) numbers.add(m[1]);
  const self = text.match(/^eip:\s*([0-9]+)$/m);
  if (self) numbers.delete(self[1]);
  return [...numbers].filter((n) => /^[0-9]+$/.test(n));
}

async function fetchProposal(n) {
  fs.mkdirSync(CACHE, {recursive: true});
  const cached = path.join(CACHE, `eip-${n}.md`);
  if (fs.existsSync(cached)) return fs.readFileSync(cached, "utf8");
  for (const make of SOURCES) {
    const res = await fetch(make(n));
    if (res.ok) {
      const text = await res.text();
      fs.writeFileSync(cached, text);
      return text;
    }
  }
  throw new Error(`could not fetch proposal ${n} from ethereum/ERCs or ethereum/EIPs`);
}

async function main() {
  const file = process.argv[2] ? path.resolve(process.argv[2]) : DEFAULT_FILE;
  if (!fs.existsSync(file)) {
    process.stderr.write(`no such file: ${file}\nrun scripts/make-filing-package.py first\n`);
    process.exit(2);
  }
  const text = fs.readFileSync(file, "utf8");
  const stage = fs.mkdtempSync(path.join(os.tmpdir(), "eipw-"));
  const staged = path.join(stage, path.basename(file));
  fs.writeFileSync(staged, text);
  for (const n of referencedProposals(text)) {
    fs.writeFileSync(path.join(stage, `eip-${n}.md`), await fetchProposal(n));
  }

  const options = toml.parse(fs.readFileSync(path.join(__dirname, "eipw.toml"), "utf8"));
  const config = {};
  if (options.lints) config.default_lints = options.lints;
  if (options.modifiers) config.default_modifiers = options.modifiers;

  const result = await eipw.lint([staged], config);
  let errors = 0;
  let tolerated = 0;
  const hasPlaceholder = text.includes(PLACEHOLDER);
  for (const snippet of result) {
    let rendered;
    try {
      rendered = String(eipw.format(snippet));
    } catch {
      rendered = snippet.title || "<unrenderable diagnostic>";
    }
    const isError = snippet.level === "Error";
    if (isError && hasPlaceholder && rendered.includes("preamble-re-discussions-to")) {
      tolerated++;
      process.stdout.write(`[tolerated until the thread exists] ${rendered}\n`);
      continue;
    }
    if (isError) errors++;
    process.stdout.write(rendered + "\n");
  }
  fs.rmSync(stage, {recursive: true, force: true});
  process.stdout.write(`eipw: ${errors} error(s), ${tolerated} tolerated placeholder finding(s), ${result.length} total\n`);
  process.exit(errors > 0 ? 1 : 0);
}

main().catch((e) => {
  process.stderr.write(`eipw failed: ${e.stack || e.message}\n`);
  process.exit(2);
});
