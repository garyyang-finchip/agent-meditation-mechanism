#!/usr/bin/env bash
# Evidence run driver for the Agent Meditation Mechanism reference registry.
#
#   bash scripts/evidence-run.sh anvil           # local rehearsal on a fresh anvil (time travel between phases)
#   bash scripts/evidence-run.sh sepolia         # live run; needs RPC_URL and a funded DEPLOYER_PK (see docs/sepolia-runbook.md)
#   bash scripts/evidence-run.sh sepolia phaseB  # resume at a step (phaseA, phaseA2, phaseB, phaseC, phaseD1,
#                                                #   phaseD1b, rejected, phaseD2, phaseD3, final)
#
# Run it through bash: files uploaded through the GitHub web interface do not keep the executable bit.
#
# Keys for the agent, controller and operator are generated once per network into
# deployments/<network>/keys.env (ignored by git) and reused on resume.
set -euo pipefail

NETWORK="${1:-anvil}"
START_AT="${2:-phaseA}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="deployments/$NETWORK"
mkdir -p "$OUT"
export EVIDENCE_STATE="$OUT/state.json"
export EVIDENCE_CALLS="$OUT/rejected-calls.json"
export SHORT_INTERVALS="${SHORT_INTERVALS:-1}"
export FUND_WEI="${FUND_WEI:-3000000000000000}"   # 0.003 ETH per actor

WAIT_SECONDS="${WAIT_SECONDS:-330}"               # floor for layer 0 is 300 s with SHORT_INTERVALS=1 (both waits)
ANVIL_PID=""

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

cleanup() {
  if [[ -n "$ANVIL_PID" ]]; then kill "$ANVIL_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

new_key() { cast wallet new --json | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j=JSON.parse(d);const w=Array.isArray(j)?j[0]:j;console.log(w.private_key)})'; }

if [[ "$NETWORK" == "anvil" ]]; then
  if [[ -z "${RPC_URL:-}" ]]; then
    anvil --port 8545 --silent --block-time 1 &
    ANVIL_PID=$!
    sleep 2
    export RPC_URL="http://127.0.0.1:8545"
  fi
  # anvil account #0
  export DEPLOYER_PK="${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
  FORGE_EXTRA=()
else
  : "${RPC_URL:?set RPC_URL}"
  : "${DEPLOYER_PK:?set DEPLOYER_PK (funded deployer)}"
  # Live networks: skip the local simulation so gas limits come from the node (eth_estimateGas under the
  # chain's own gas schedule), with a 1.5x margin; --slow waits for each receipt before the next send.
  FORGE_EXTRA=(--skip-simulation --slow --gas-estimate-multiplier 150)
fi

# Actor funding scaled to the live gas price; gas budgets follow what the actors used on Sepolia in the first run
# plus phase D, with a 2x margin; floor 0.0005 ETH each. Phase A tops each actor up to its target.
GAS_PRICE_WEI="$(cast gas-price --rpc-url "$RPC_URL")"
scaled() { local units="$1"; local v=$(( GAS_PRICE_WEI * units * 2 )); local floor=500000000000000; echo $(( v > floor ? v : floor )); }
export FUND_AGENT_WEI="${FUND_AGENT_WEI:-$(scaled 5500000)}"
export FUND_OPERATOR_WEI="${FUND_OPERATOR_WEI:-$(scaled 2000000)}"
export FUND_CONTROLLER_WEI="${FUND_CONTROLLER_WEI:-$(scaled 800000)}"

if [[ -f "$OUT/keys.env" ]]; then
  # shellcheck disable=SC1090
  source "$OUT/keys.env"
else
  AGENT_PK="$(new_key)"; CONTROLLER_PK="$(new_key)"; OPERATOR_PK="$(new_key)"
  printf 'export AGENT_PK=%s\nexport CONTROLLER_PK=%s\nexport OPERATOR_PK=%s\n' "$AGENT_PK" "$CONTROLLER_PK" "$OPERATOR_PK" > "$OUT/keys.env"
  chmod 600 "$OUT/keys.env"
fi
export AGENT_PK CONTROLLER_PK OPERATOR_PK

run_phase() {
  local sig="$1"
  log "running $sig on $NETWORK"
  forge script script/Evidence.s.sol:Evidence --sig "$sig" --rpc-url "$RPC_URL" --broadcast "${FORGE_EXTRA[@]}" -vv
}

snapshot() {
  local label="$1"
  SNAPSHOT_LABEL="$label" EVIDENCE_STATE="$OUT/state.json" forge script script/Evidence.s.sol:Evidence --sig "snapshot()" --rpc-url "$RPC_URL" -vv >/dev/null
  cp "$OUT/state.json" "$OUT/state-$label.json"
  log "snapshot $label: $(node -e 'const s=require(require("path").resolve(process.argv[1]));console.log(s.layers.map(l=>`L${l.layer}=${l.status}`).join(" ")+" signal="+s.signal.status)' "$OUT/state-$label.json")"
}

next_block() {
  if [[ "$NETWORK" == "anvil" ]]; then
    cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null; sleep 2
  else
    log "waiting for the enrollment block to be behind us"; sleep 20
  fi
}

wait_for_overdue() {
  if [[ "$NETWORK" == "anvil" ]]; then
    log "advancing anvil time by $WAIT_SECONDS seconds"
    cast rpc --rpc-url "$RPC_URL" evm_increaseTime "$WAIT_SECONDS" >/dev/null
    cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
  else
    log "waiting $WAIT_SECONDS seconds for layer 0 to become overdue under the floor"
    sleep "$WAIT_SECONDS"
  fi
}

# A new run on a live network starts a new registry; the record of the previous run is kept under a dated name
# (the date of its final snapshot's clock value) before the summary writes deployments/<network>.json again.
archive_previous() {
  local record="deployments/$NETWORK.json"
  [[ "$NETWORK" != "anvil" && -f "$record" ]] || return 0
  local stamp; stamp="$(node -e 'const r=require(require("path").resolve(process.argv[1]));const c=r.snapshots&&r.snapshots.final&&r.snapshots.final.clock;console.log(c?new Date(Number(c)*1000).toISOString().slice(0,10):"undated")' "$record")"
  local target="deployments/$NETWORK-$stamp.json"
  local n=2; while [[ -e "$target" ]]; do target="deployments/$NETWORK-$stamp-$n.json"; n=$((n+1)); done
  mv "$record" "$target"
  log "archived the previous record as $target"
}

precheck() {
  local deployer; deployer="$(cast wallet address --private-key "$DEPLOYER_PK")"
  local balance; balance="$(cast balance "$deployer" --rpc-url "$RPC_URL")"
  # The node prices the deployment under its own gas schedule (Sepolia charged about 7x a local EVM in the first run).
  local initcode; initcode="$(forge inspect assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol:AgentMeditationRegistry bytecode)"
  local deploy_gas; deploy_gas="$(cast estimate --rpc-url "$RPC_URL" --from "$deployer" --create "$initcode" 2>/dev/null || echo 35000000)"
  local shortfall=0 who target bal
  for who in AGENT CONTROLLER OPERATOR; do
    local pk_var="${who}_PK" fund_var="FUND_${who}_WEI"
    bal="$(cast balance "$(cast wallet address --private-key "${!pk_var}")" --rpc-url "$RPC_URL")"
    target="${!fund_var}"
    if (( bal < target )); then shortfall=$(( shortfall + target - bal )); fi
  done
  # 2x the deployment estimate covers the 1.5x gas limit and fee headroom the node checks up front.
  local need=$(( GAS_PRICE_WEI * deploy_gas * 2 + shortfall + GAS_PRICE_WEI * 400000 ))
  log "deployer $deployer balance $(cast from-wei "$balance") ETH; gas price $(cast from-wei "$GAS_PRICE_WEI" gwei) gwei"
  log "deployment estimate $deploy_gas gas; actor top-ups $(cast from-wei "$shortfall") ETH; phase A needs about $(cast from-wei "$need") ETH"
  if [[ "$balance" -lt "$need" && "${SKIP_PRECHECK:-0}" != "1" ]]; then
    echo "deployer balance is below the phase A estimate; top it up, lower FUND_*_WEI, or set SKIP_PRECHECK=1" >&2
    exit 3
  fi
}

# Phase D2 needs layer 0's completion at the recorded start to be older than its floor interval.
wait_after_start() {
  local registry agent started now remaining
  registry="$(node -e 'console.log(require(require("path").resolve(process.argv[1])).registry)' "$OUT/state.json")"
  agent="$(cast wallet address --private-key "$AGENT_PK")"
  started="$(cast call "$registry" "openStartOf(address)(uint48,address)" "$agent" --rpc-url "$RPC_URL" | head -n1 | awk '{print $1}')"
  now="$(cast block latest --field timestamp --rpc-url "$RPC_URL")"
  remaining=$(( started + WAIT_SECONDS - now ))
  if (( remaining <= 0 )); then return 0; fi
  if [[ "$NETWORK" == "anvil" ]]; then
    log "advancing anvil time by $remaining seconds after the recorded start"
    cast rpc --rpc-url "$RPC_URL" evm_increaseTime "$remaining" >/dev/null
    cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
  else
    log "waiting $remaining seconds for layer 0's completion at the recorded start to pass its floor interval"
    sleep "$remaining"
  fi
}

case "$START_AT" in
  phaseA)
    precheck
    archive_previous
    run_phase "phaseA()"; cp "$OUT/state.json" "$OUT/state-A.json"
    next_block
    ;&
  phaseA2)
    run_phase "phaseA2()"; cp "$OUT/state.json" "$OUT/state-A2.json"
    wait_for_overdue
    snapshot "overdue"
    ;&
  phaseB)
    run_phase "phaseB()"; cp "$OUT/state.json" "$OUT/state-B.json"
    ;&
  phaseC)
    run_phase "phaseC()"; cp "$OUT/state.json" "$OUT/state-C.json"
    ;&
  phaseD1)
    run_phase "phaseD1()"; cp "$OUT/state.json" "$OUT/state-D1.json"
    next_block
    ;&
  phaseD1b)
    run_phase "phaseD1b()"; cp "$OUT/state.json" "$OUT/state-D1b.json"
    ;&
  rejected)
    log "sending the four calls the registry must reject (one per revision)"
    node scripts/evidence-rejected.js "$NETWORK"
    wait_after_start
    ;&
  phaseD2)
    run_phase "phaseD2()"; cp "$OUT/state.json" "$OUT/state-D2.json"
    snapshot "perLayer"
    ;&
  phaseD3)
    run_phase "phaseD3()"; cp "$OUT/state.json" "$OUT/state-D3.json"
    ;&
  final)
    snapshot "final"
    node scripts/evidence-summary.js "$NETWORK"
    ;;
  *)
    echo "unknown start phase: $START_AT" >&2; exit 2;;
esac

log "done; records under $OUT"
