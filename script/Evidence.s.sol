// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

/// @dev Minimal cheatcode surface for the evidence script (kept local; no library dependency).
interface ScriptVm {
    function envUint(string calldata) external view returns (uint256);
    function envString(string calldata) external view returns (string memory);
    function envOr(string calldata, string calldata) external view returns (string memory);
    function addr(uint256) external pure returns (address);
    function startBroadcast(uint256) external;
    function stopBroadcast() external;
    function readFile(string calldata) external view returns (string memory);
    function writeFile(string calldata, string calldata) external;
    function exists(string calldata) external returns (bool);
    function parseJsonAddress(string calldata, string calldata) external pure returns (address);
    function parseJsonUint(string calldata, string calldata) external pure returns (uint256);
    function parseJsonBytes32(string calldata, string calldata) external pure returns (bytes32);
    function toString(address) external pure returns (string memory);
    function toString(uint256) external pure returns (string memory);
    function toString(bytes32) external pure returns (string memory);
}

/// @title Evidence
/// @notice Evidence run of the Agent Meditation Mechanism reference registry on a live network.
///         Driven by scripts/evidence-run.sh in three phases separated by real waiting time.
///
///         Phase A: deploy, fund actors, enroll the subject with the worked-example baseline, authorize an
///                  operator. Phase A2 (next block or later): pulse, record the worked-example cycle
///                  (layers 0-2 change, layer 3 kept), controller sets a floor tighter than the policy and
///                  demands a layer-3 completion.
///         Phase B (after layer 0 has become overdue under the floor and the signal has gone silent):
///                  subject records a layer-3 cycle adopting the candidate strategy (clears the demand),
///                  operator records a layer-0 cycle that makes layer 0 fresh again.
///         Phase C: rollback of layers 0 and 3 to the state registered at version 2 (restoresVersion = 2),
///                  policy version 2, a pulse; final statuses are recorded.
contract Evidence {
    ScriptVm internal constant vm = ScriptVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint8 internal constant ALL = 0x0F;
    uint8 internal constant ALL_RIGHTS = 0x07;
    uint8 internal constant PERM_REPORT = 1;
    uint8 internal constant PERM_PULSE = 2;

    // Worked-example commitments (assets/erc-agent-meditation/vectors/example-mcp-timeout.json)
    bytes32 internal constant PRE0 = 0x053bdcecda479dd30b5bfd7a02661df67b79e978fea6888245df8aa167d6d282;
    bytes32 internal constant PRE1 = 0x3a8a0162793df87f7094634e37d9e5d3d8470bd43cc7fee5669f609d922ee9c3;
    bytes32 internal constant PRE2 = 0x3d3356ae1bc86136718f1ecd7f42d8a0570db2d21116c886cab291a789010585;
    bytes32 internal constant PRE3 = 0xbe9a1abba6f84ec051c3eb91bb19e2d3504d773da883b94aece5ee9e37c79e8e;
    bytes32 internal constant POST0 = 0xb5a33b6d3732e664a08a19ed068432a6ab1085bf7013b3ffce1ff88ec7dd8519;
    bytes32 internal constant POST1 = 0xd24fedfca7a64b7596414751a6d4a1ed7a89bf906bce4b453453a7b086d26641;
    bytes32 internal constant POST2 = 0x8f03de4a144d8d453c84d2d4546fb0f01af23bd6f7ba31d18dac0c6dd1a942f0;
    bytes32 internal constant RECORD_HASH = 0xdcbc7047b5bf0d600b98d7829fc37757bdac9406ec992128cc90e910e9645088;
    bytes32 internal constant POLICY_HASH = 0x5dfdd440a0eced1f62839fa0281f21cadacfa0f527642ea586b5f5c1ce5e41d9;

    // Follow-up states used by the evidence cycles (illustrative content hashes)
    bytes32 internal constant COGNITION_V2 = keccak256("evidence/cognition/verify-before-retry-adopted");
    bytes32 internal constant RUNTIME_V3 = keccak256("evidence/runtime/dependency-refresh");

    uint256 internal deployerPk;
    uint256 internal agentPk;
    uint256 internal controllerPk;
    uint256 internal operatorPk;
    address internal agent;
    address internal controller;
    address internal operator;
    string internal stateFile;

    function setUp() public {
        deployerPk = vm.envUint("DEPLOYER_PK");
        agentPk = vm.envUint("AGENT_PK");
        controllerPk = vm.envUint("CONTROLLER_PK");
        operatorPk = vm.envUint("OPERATOR_PK");
        agent = vm.addr(agentPk);
        controller = vm.addr(controllerPk);
        operator = vm.addr(operatorPk);
        stateFile = vm.envOr("EVIDENCE_STATE", "deployments/anvil/state.json");
    }

    // ------------------------------------------------------------------
    // Phase A
    // ------------------------------------------------------------------

    function phaseA() external {
        uint256 fund = vm.envUint("FUND_WEI");
        uint256 fundAgent = _envUintOr("FUND_AGENT_WEI", fund);
        uint256 fundController = _envUintOr("FUND_CONTROLLER_WEI", fund);
        uint256 fundOperator = _envUintOr("FUND_OPERATOR_WEI", fund);
        bool floorShort = _flag("SHORT_INTERVALS");

        vm.startBroadcast(deployerPk);
        AgentMeditationRegistry reg = new AgentMeditationRegistry();
        payable(agent).transfer(fundAgent);
        payable(controller).transfer(fundController);
        payable(operator).transfer(fundOperator);
        vm.stopBroadcast();

        // Subject enrolls with the worked-example baseline and a policy with evidence-friendly intervals.
        IAgentMeditation.Policy memory p =
            _policy(floorShort, POLICY_HASH, "ipfs://example/mcp-timeout-cycle/policy.json");
        bytes32[4] memory baseline = [PRE0, PRE1, PRE2, PRE3];

        vm.startBroadcast(agentPk);
        reg.enroll(baseline, p, controller, ALL_RIGHTS);
        reg.setOperator(operator, PERM_REPORT | PERM_PULSE);
        vm.stopBroadcast();

        _writeState(address(reg), "A");
    }

    /// @dev Second step of phase A, run once the enrollment block is final so that reported times are at or after it.
    function phaseA2() external {
        AgentMeditationRegistry reg = _registry();
        bool floorShort = _flag("SHORT_INTERVALS");
        bytes32[4] memory baseline = [PRE0, PRE1, PRE2, PRE3];
        uint48 now_ = reg.clock();

        // Operator pulses, then records the worked-example cycle (times taken from the live clock).
        IAgentMeditation.CycleReport memory r;
        r.baseVersion = 1;
        r.preRoot = reg.computeRoot(baseline);
        r.postCommitments = [POST0, POST1, POST2, PRE3];
        r.layerMask = ALL;
        r.completedLayers = ALL;
        r.opsMask = 0x0456;
        r.outcome = uint8(IAgentMeditation.Outcome.COMPLETED);
        r.trigger = 1; // EVENT
        r.policyVersion = 1;
        r.reportedStartedAt = now_;
        r.reportedEndedAt = now_;
        r.nextPlannedAt = now_ + (floorShort ? 600 : 86400);
        r.recordHash = RECORD_HASH;
        r.recordURI = "ipfs://example/mcp-timeout-cycle/cycle-record.json";

        vm.startBroadcast(operatorPk);
        reg.pulse(agent, now_ + (floorShort ? 300 : 21600));
        reg.report(agent, r);
        vm.stopBroadcast();

        // Controller sets a floor tighter than the policy for layer 0 and demands a layer-3 completion.
        IAgentMeditation.Floor memory f;
        f.requiredLayers = 0x01;
        f.maxInterval[0] = floorShort ? 300 : 43200;
        f.pulseInterval = floorShort ? 120 : 3600;
        vm.startBroadcast(controllerPk);
        reg.setFloor(agent, f);
        reg.demand(agent, 0x08, reg.clock() + (floorShort ? 600 : 86400));
        vm.stopBroadcast();

        _writeState(address(reg), "A2");
    }

    // ------------------------------------------------------------------
    // Phase B
    // ------------------------------------------------------------------

    function phaseB() external {
        AgentMeditationRegistry reg = _registry();
        IAgentMeditation.Head memory h = reg.headOf(agent);
        uint48 now_ = reg.clock();

        // Subject records a layer-3 cycle adopting the candidate strategy; this satisfies the controller's demand.
        IAgentMeditation.CycleReport memory r3;
        r3.baseVersion = h.stateVersion;
        r3.preRoot = h.root;
        r3.postCommitments = [POST0, POST1, POST2, COGNITION_V2];
        r3.layerMask = 0x08;
        r3.completedLayers = 0x08;
        r3.opsMask = uint16(1) << (3 * 4 + 2); // layer 3: update
        r3.outcome = uint8(IAgentMeditation.Outcome.COMPLETED);
        r3.trigger = 2; // COMMANDED
        r3.policyVersion = 1;
        r3.reportedStartedAt = now_;
        r3.reportedEndedAt = now_;
        r3.recordHash = keccak256("evidence/cycle-record/layer-3-adoption");

        vm.startBroadcast(agentPk);
        reg.report(agent, r3);
        vm.stopBroadcast();

        // Operator records a layer-0 cycle: layer 0 is fresh again after being overdue under the floor.
        IAgentMeditation.CycleReport memory r0;
        r0.baseVersion = h.stateVersion + 1;
        r0.preRoot = reg.computeRoot(r3.postCommitments);
        r0.postCommitments = [RUNTIME_V3, POST1, POST2, COGNITION_V2];
        r0.layerMask = 0x01;
        r0.completedLayers = 0x01;
        r0.opsMask = uint16(1) << 2; // layer 0: update
        r0.outcome = uint8(IAgentMeditation.Outcome.COMPLETED);
        r0.trigger = 0; // SCHEDULED
        r0.policyVersion = 1;
        r0.reportedStartedAt = now_;
        r0.reportedEndedAt = now_;
        r0.nextPlannedAt = now_ + 300;
        r0.recordHash = keccak256("evidence/cycle-record/layer-0-refresh");

        vm.startBroadcast(operatorPk);
        reg.report(agent, r0);
        vm.stopBroadcast();

        _writeState(address(reg), "B");
    }

    // ------------------------------------------------------------------
    // Phase C
    // ------------------------------------------------------------------

    function phaseC() external {
        AgentMeditationRegistry reg = _registry();
        bool floorShort = _flag("SHORT_INTERVALS");
        IAgentMeditation.Head memory h = reg.headOf(agent);
        uint48 now_ = reg.clock();

        // Rollback: layers 0 and 3 return to the state registered at version 2 (restoresVersion = 2).
        IAgentMeditation.CycleReport memory back;
        back.baseVersion = h.stateVersion;
        back.preRoot = h.root;
        back.postCommitments = [POST0, POST1, POST2, PRE3];
        back.layerMask = 0x09;
        back.completedLayers = 0x09;
        back.opsMask = (uint16(1) << 1) | (uint16(1) << (3 * 4 + 1)); // layer 0: repair, layer 3: repair
        back.outcome = uint8(IAgentMeditation.Outcome.COMPLETED);
        back.trigger = 3; // SELF
        back.policyVersion = 1;
        back.reportedStartedAt = now_;
        back.reportedEndedAt = now_;
        back.restoresVersion = 2;
        back.recordHash = keccak256("evidence/cycle-record/rollback-to-version-2");

        IAgentMeditation.Policy memory p2 =
            _policy(floorShort, keccak256("evidence/policy/v2"), "ipfs://example/policy-v2.json");
        p2.disclosure = 1;

        vm.startBroadcast(agentPk);
        reg.report(agent, back);
        reg.setPolicy(agent, p2);
        vm.stopBroadcast();

        vm.startBroadcast(operatorPk);
        reg.pulse(agent, 0);
        vm.stopBroadcast();

        _writeState(address(reg), "C");
    }

    // ------------------------------------------------------------------
    // Status snapshot (read-only)
    // ------------------------------------------------------------------

    function snapshot() external {
        AgentMeditationRegistry reg = _registry();
        _writeState(address(reg), vm.envOr("SNAPSHOT_LABEL", "snapshot"));
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _policy(bool short_, bytes32 hash, string memory uri)
        internal
        pure
        returns (IAgentMeditation.Policy memory p)
    {
        p.policyHash = hash;
        p.policyURI = uri;
        p.supportedLayers = ALL;
        p.requiredLayers = ALL;
        p.allowedTriggers = ALL;
        p.disclosure = 0;
        p.dueWindow = short_ ? 120 : 3600;
        p.pulseInterval = short_ ? 300 : 21600;
        p.maxInterval[0] = short_ ? 600 : 86400;
        p.maxInterval[1] = short_ ? 1800 : 604800;
        p.maxInterval[2] = short_ ? 3600 : 2592000;
        p.maxInterval[3] = short_ ? 7200 : 7776000;
    }

    function _registry() internal view returns (AgentMeditationRegistry) {
        string memory json = vm.readFile(stateFile);
        return AgentMeditationRegistry(vm.parseJsonAddress(json, ".registry"));
    }

    function _envUintOr(string memory name, uint256 fallback_) internal view returns (uint256) {
        string memory raw = vm.envOr(name, "");
        if (bytes(raw).length == 0) return fallback_;
        return vm.envUint(name);
    }

    function _flag(string memory name) internal view returns (bool) {
        return keccak256(bytes(vm.envOr(name, "0"))) == keccak256(bytes("1"));
    }

    function _writeState(address registry, string memory phase) internal {
        AgentMeditationRegistry reg = AgentMeditationRegistry(registry);
        string memory layers = "[";
        for (uint8 i = 0; i < 4; i++) {
            layers = string.concat(layers, i == 0 ? "" : ",", _layerJson(reg, i));
        }
        layers = string.concat(layers, "]");
        string memory json = string.concat(
            '{"phase":"', phase, '",', _actorsJson(registry), ",", _headJson(reg), ',"layers":', layers, "}\n"
        );
        vm.writeFile(stateFile, json);
    }

    function _actorsJson(address registry) internal view returns (string memory) {
        return string.concat(
            '"registry":"',
            vm.toString(registry),
            '","agent":"',
            vm.toString(agent),
            '","controller":"',
            vm.toString(controller),
            '","operator":"',
            vm.toString(operator),
            '"'
        );
    }

    function _headJson(AgentMeditationRegistry reg) internal view returns (string memory) {
        IAgentMeditation.Head memory h = reg.headOf(agent);
        (IAgentMeditation.SignalStatus ss, uint48 last, uint48 since) = reg.signalStatus(agent);
        string memory a = string.concat(
            '"clock":',
            vm.toString(uint256(reg.clock())),
            ',"stateVersion":',
            vm.toString(uint256(h.stateVersion)),
            ',"recordCount":',
            vm.toString(uint256(h.recordCount)),
            ',"policyVersion":',
            vm.toString(uint256(h.policyVersion)),
            ',"floorVersion":',
            vm.toString(uint256(h.floorVersion))
        );
        string memory b = string.concat(
            ',"root":"',
            vm.toString(h.root),
            '","signal":{"status":"',
            _signalName(ss),
            '","lastSignalAt":',
            vm.toString(uint256(last)),
            ',"silentSince":',
            vm.toString(uint256(since)),
            "}"
        );
        return string.concat(a, b);
    }

    function _layerJson(AgentMeditationRegistry reg, uint8 i) internal view returns (string memory) {
        (IAgentMeditation.MaintenanceStatus s, uint48 d, bool never) = reg.layerStatus(agent, i);
        IAgentMeditation.LayerCheckpoint memory cp = reg.checkpointOf(agent, i);
        string memory a = string.concat(
            '{"layer":',
            vm.toString(uint256(i)),
            ',"status":"',
            _statusName(s),
            '","deadline":',
            vm.toString(uint256(d)),
            ',"neverCompleted":',
            never ? "true" : "false"
        );
        string memory b = string.concat(
            ',"commitment":"',
            vm.toString(cp.commitment),
            '","lastCompletedAt":',
            vm.toString(uint256(cp.lastCompletedAt)),
            ',"lastChangedVersion":',
            vm.toString(uint256(cp.lastChangedVersion)),
            "}"
        );
        return string.concat(a, b);
    }

    function _statusName(IAgentMeditation.MaintenanceStatus s) internal pure returns (string memory) {
        if (s == IAgentMeditation.MaintenanceStatus.NOT_ENROLLED) return "NOT_ENROLLED";
        if (s == IAgentMeditation.MaintenanceStatus.UNSUPPORTED) return "UNSUPPORTED";
        if (s == IAgentMeditation.MaintenanceStatus.UNSCHEDULED) return "UNSCHEDULED";
        if (s == IAgentMeditation.MaintenanceStatus.FRESH) return "FRESH";
        if (s == IAgentMeditation.MaintenanceStatus.DUE) return "DUE";
        return "OVERDUE";
    }

    function _signalName(IAgentMeditation.SignalStatus s) internal pure returns (string memory) {
        if (s == IAgentMeditation.SignalStatus.NOT_ENROLLED) return "NOT_ENROLLED";
        if (s == IAgentMeditation.SignalStatus.NOT_TRACKED) return "NOT_TRACKED";
        if (s == IAgentMeditation.SignalStatus.PRESENT) return "PRESENT";
        return "SILENT";
    }
}
