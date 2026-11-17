// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {IAgentMeditationStart} from "../assets/erc-agent-meditation/contracts/IAgentMeditationStart.sol";
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
    function toString(bytes calldata) external pure returns (string memory);
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
///                  policy version 2, a pulse.
///         Phase D (revisions 2 to 5): the subject records the start of its next cycle and the controller demands
///                  layer 2 (D1); the subject tightens its policy to version 3, which forbids the SELF trigger,
///                  and four calls that the registry must reject are prepared, one per revision, which the driver
///                  sends as transactions that fail (D1b); once layer 0 has aged past its floor interval, the
///                  subject records the cycle pinned to its recorded start under version 2 with the SELF trigger,
///                  layer 0 completed at the start and layer 2 at the end (D2): layer 0 reads overdue at once and
///                  the demand on layer 2 is cleared by layer 2's own completion; the operator refreshes layer 0
///                  under version 3 and pulses (D3).
contract Evidence {
    ScriptVm internal constant vm = ScriptVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint8 internal constant ALL = 0x0F;
    uint8 internal constant ALL_RIGHTS = 0x07;
    uint8 internal constant PERM_REPORT = 1;
    uint8 internal constant PERM_PULSE = 2;
    uint8 internal constant TRIGGER_SCHEDULED = 0;
    uint8 internal constant TRIGGER_SELF = 3;

    // Worked-example commitments (assets/erc-agent-meditation/vectors/example-mcp-timeout.json)
    bytes32 internal constant PRE0 = 0x053bdcecda479dd30b5bfd7a02661df67b79e978fea6888245df8aa167d6d282;
    bytes32 internal constant PRE1 = 0x3a8a0162793df87f7094634e37d9e5d3d8470bd43cc7fee5669f609d922ee9c3;
    bytes32 internal constant PRE2 = 0x3d3356ae1bc86136718f1ecd7f42d8a0570db2d21116c886cab291a789010585;
    bytes32 internal constant PRE3 = 0xbe9a1abba6f84ec051c3eb91bb19e2d3504d773da883b94aece5ee9e37c79e8e;
    bytes32 internal constant POST0 = 0xb5a33b6d3732e664a08a19ed068432a6ab1085bf7013b3ffce1ff88ec7dd8519;
    bytes32 internal constant POST1 = 0xd24fedfca7a64b7596414751a6d4a1ed7a89bf906bce4b453453a7b086d26641;
    bytes32 internal constant POST2 = 0x8f03de4a144d8d453c84d2d4546fb0f01af23bd6f7ba31d18dac0c6dd1a942f0;
    bytes32 internal constant RECORD_HASH = 0xc61bf3f0910e27bd5a91bc6c8c006e88e262a732021ed026804bedb76b813116;
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
    string internal callsFile;

    function setUp() public {
        deployerPk = vm.envUint("DEPLOYER_PK");
        agentPk = vm.envUint("AGENT_PK");
        controllerPk = vm.envUint("CONTROLLER_PK");
        operatorPk = vm.envUint("OPERATOR_PK");
        agent = vm.addr(agentPk);
        controller = vm.addr(controllerPk);
        operator = vm.addr(operatorPk);
        stateFile = vm.envOr("EVIDENCE_STATE", "deployments/anvil/state.json");
        callsFile = vm.envOr("EVIDENCE_CALLS", "deployments/anvil/rejected-calls.json");
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
        // Actor keys are reused across runs: top each actor up to its target instead of sending the full amount.
        if (agent.balance < fundAgent) payable(agent).transfer(fundAgent - agent.balance);
        if (controller.balance < fundController) payable(controller).transfer(fundController - controller.balance);
        if (operator.balance < fundOperator) payable(operator).transfer(fundOperator - operator.balance);
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
        r.completedAt = [now_, now_, now_, now_];
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
        r3.completedAt[3] = now_;
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
        r0.completedAt[0] = now_;
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
        back.completedAt[0] = now_;
        back.completedAt[3] = now_;
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
    // Phase D (revisions 2 to 5)
    // ------------------------------------------------------------------

    /// @dev The subject records the start of its next cycle; the controller demands a completion of layer 2.
    function phaseD1() external {
        AgentMeditationRegistry reg = _registry();
        bool floorShort = _flag("SHORT_INTERVALS");

        vm.startBroadcast(agentPk);
        reg.begin(agent);
        vm.stopBroadcast();

        vm.startBroadcast(controllerPk);
        reg.demand(agent, 0x04, reg.clock() + (floorShort ? 1800 : 86400));
        vm.stopBroadcast();

        _writeState(address(reg), "D1");
    }

    /// @dev Run in a later block than D1: the subject tightens its policy (version 3 forbids the SELF trigger); the
    ///      open start survives because the subject recorded it. Writes the four calls the registry must reject.
    function phaseD1b() external {
        AgentMeditationRegistry reg = _registry();
        bool floorShort = _flag("SHORT_INTERVALS");
        IAgentMeditation.Policy memory p3 =
            _policy(floorShort, keccak256("evidence/policy/v3"), "ipfs://example/policy-v3.json");
        p3.disclosure = 1;
        p3.allowedTriggers = ALL & ~uint8(1 << TRIGGER_SELF);

        vm.startBroadcast(agentPk);
        reg.setPolicy(agent, p3);
        vm.stopBroadcast();

        _writeState(address(reg), "D1b");
        _writeRejectedCalls(reg, floorShort);
    }

    /// @dev Once layer 0 has aged past its floor interval: the cycle pinned to the recorded start, governed by
    ///      version 2 and using the SELF trigger version 3 forbids; layer 0 completed at the start, layer 2 at the end.
    function phaseD2() external {
        AgentMeditationRegistry reg = _registry();
        IAgentMeditation.Head memory h = reg.headOf(agent);
        (uint48 startedAt,) = reg.openStartOf(agent);
        require(startedAt != 0, "no open start");
        uint48 now_ = reg.clock();

        IAgentMeditation.CycleReport memory r = _keepReport(reg, h, 0x05);
        r.trigger = TRIGGER_SELF;
        r.policyVersion = 2;
        r.reportedStartedAt = startedAt;
        r.reportedEndedAt = now_;
        r.completedAt[0] = startedAt;
        r.completedAt[2] = now_;
        r.recordHash = keccak256("evidence/cycle-record/pinned-two-layer-cycle");

        vm.startBroadcast(agentPk);
        reg.report(agent, r);
        vm.stopBroadcast();

        _writeState(address(reg), "D2");
    }

    /// @dev The operator refreshes layer 0 under version 3 and pulses.
    function phaseD3() external {
        AgentMeditationRegistry reg = _registry();
        IAgentMeditation.Head memory h = reg.headOf(agent);
        uint48 now_ = reg.clock();

        IAgentMeditation.CycleReport memory r = _keepReport(reg, h, 0x01);
        r.opsMask = 1; // layer 0: clean
        r.trigger = TRIGGER_SCHEDULED;
        r.policyVersion = h.policyVersion;
        r.reportedStartedAt = now_;
        r.reportedEndedAt = now_;
        r.completedAt[0] = now_;
        r.recordHash = keccak256("evidence/cycle-record/layer-0-refresh-under-v3");

        vm.startBroadcast(operatorPk);
        reg.report(agent, r);
        reg.pulse(agent, 0);
        vm.stopBroadcast();

        _writeState(address(reg), "D3");
    }

    /// @dev One call per revision that the registry must reject, encoded against the state after D1b. Each must
    ///      pass every check before the one it demonstrates.
    function _writeRejectedCalls(AgentMeditationRegistry reg, bool floorShort) internal {
        IAgentMeditation.Head memory h = reg.headOf(agent);
        uint48 gapStart = h.lastCycleEndedAt; // after the previous cycle, before the tightening, under version 2
        uint48 v2From = reg.policyEffectiveFrom(agent, 2);
        if (v2From > gapStart) gapStart = v2From;
        string memory c2 = _rejectStartBeforePreviousCycle(reg, h);
        string memory c3 = _rejectDropLayerUnderDemand(reg, floorShort);
        string memory c4 = _rejectForbiddenTriggerInTheGap(reg, h, gapStart);
        string memory c5 = _rejectCompletionOutsideTheCycle(reg, h, gapStart);
        vm.writeFile(callsFile, string.concat("[", c2, ",", c3, ",", c4, ",", c5, "]\n"));
    }

    /// @dev Revision 2: a start one second before the previous cycle's end, under the version that governed it.
    function _rejectStartBeforePreviousCycle(AgentMeditationRegistry reg, IAgentMeditation.Head memory h)
        internal
        view
        returns (string memory)
    {
        IAgentMeditation.CycleReport memory r = _keepReport(reg, h, 0x02);
        r.policyVersion = 1;
        r.reportedStartedAt = h.lastCycleEndedAt - 1;
        r.reportedEndedAt = reg.clock();
        r.completedAt[1] = r.reportedEndedAt;
        r.recordHash = keccak256("evidence/rejected/start-before-previous-cycle");
        bytes memory data = abi.encodeCall(IAgentMeditation.report, (agent, r));
        return _callJson("start-before-previous-cycle", 2, "operator", reg, data, "StartBeforePreviousCycle()");
    }

    /// @dev Revision 3: a policy version that drops layer 2 while the controller's demand on it is outstanding.
    function _rejectDropLayerUnderDemand(AgentMeditationRegistry reg, bool floorShort)
        internal
        view
        returns (string memory)
    {
        IAgentMeditation.Policy memory p = _policy(
            floorShort, keccak256("evidence/policy/v4-drops-layer-2"), "ipfs://example/policy-v4-attempt.json"
        );
        p.disclosure = 1;
        p.allowedTriggers = ALL & ~uint8(1 << TRIGGER_SELF);
        p.supportedLayers = 0x0B;
        p.requiredLayers = 0x0B;
        bytes memory data = abi.encodeCall(IAgentMeditation.setPolicy, (agent, p));
        return _callJson("drop-layer-under-demand", 3, "agent", reg, data, "LayerUnderObligation(2)");
    }

    /// @dev Revision 4: a SELF cycle started in the gap before the tightening, claiming version 2, not pinned.
    function _rejectForbiddenTriggerInTheGap(
        AgentMeditationRegistry reg,
        IAgentMeditation.Head memory h,
        uint48 gapStart
    ) internal view returns (string memory) {
        IAgentMeditation.CycleReport memory r = _keepReport(reg, h, 0x02);
        r.trigger = TRIGGER_SELF;
        r.policyVersion = 2;
        r.reportedStartedAt = gapStart;
        r.reportedEndedAt = reg.clock();
        r.completedAt[1] = r.reportedEndedAt;
        r.recordHash = keccak256("evidence/rejected/superseded-version-forbidden-trigger");
        bytes memory data = abi.encodeCall(IAgentMeditation.report, (agent, r));
        return _callJson("superseded-version-forbidden-trigger", 4, "operator", reg, data, "TriggerNotAllowed()");
    }

    /// @dev Revision 5: a late record that fits both versions, with a layer completion time before the cycle's start.
    function _rejectCompletionOutsideTheCycle(
        AgentMeditationRegistry reg,
        IAgentMeditation.Head memory h,
        uint48 gapStart
    ) internal view returns (string memory) {
        IAgentMeditation.CycleReport memory r = _keepReport(reg, h, 0x02);
        r.policyVersion = 2;
        r.reportedStartedAt = gapStart;
        r.reportedEndedAt = reg.clock();
        r.completedAt[1] = gapStart - 1;
        r.recordHash = keccak256("evidence/rejected/completion-outside-the-cycle");
        bytes memory data = abi.encodeCall(IAgentMeditation.report, (agent, r));
        return _callJson("completion-outside-the-cycle", 5, "operator", reg, data, "InvalidCompletionTime(1)");
    }

    function _callJson(
        string memory label,
        uint256 revision,
        string memory from,
        AgentMeditationRegistry reg,
        bytes memory data,
        string memory expected
    ) internal pure returns (string memory) {
        return string.concat(
            '{"label":"',
            label,
            '","revision":',
            vm.toString(revision),
            ',"from":"',
            from,
            '","to":"',
            vm.toString(address(reg)),
            '","expected":"',
            expected,
            '","data":"',
            vm.toString(data),
            '"}'
        );
    }

    /// @dev A completed cycle over `mask` that keeps every commitment, shaped against the current head.
    function _keepReport(AgentMeditationRegistry reg, IAgentMeditation.Head memory h, uint8 mask)
        internal
        view
        returns (IAgentMeditation.CycleReport memory r)
    {
        r.baseVersion = h.stateVersion;
        r.preRoot = h.root;
        for (uint8 i = 0; i < 4; i++) {
            r.postCommitments[i] = reg.checkpointOf(agent, i).commitment;
        }
        r.layerMask = mask;
        r.completedLayers = mask;
        r.outcome = uint8(IAgentMeditation.Outcome.COMPLETED);
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
            '{"phase":"',
            phase,
            '",',
            _actorsJson(registry),
            ",",
            _headJson(reg),
            ",",
            _extrasJson(reg),
            ',"layers":',
            layers,
            "}\n"
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

    function _extrasJson(AgentMeditationRegistry reg) internal view returns (string memory) {
        IAgentMeditation.Head memory h = reg.headOf(agent);
        (uint48 at, address by) = reg.openStartOf(agent);
        string memory a = string.concat(
            '"lastCycleEndedAt":',
            vm.toString(uint256(h.lastCycleEndedAt)),
            ',"openStart":{"at":',
            vm.toString(uint256(at)),
            ',"by":"',
            vm.toString(by),
            '"}'
        );
        string memory b = string.concat(
            ',"interfaces":{"IAgentMeditation":',
            reg.supportsInterface(type(IAgentMeditation).interfaceId) ? "true" : "false",
            ',"IAgentMeditationStart":',
            reg.supportsInterface(type(IAgentMeditationStart).interfaceId) ? "true" : "false",
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
            ',"completedUnderPolicy":',
            vm.toString(uint256(cp.completedUnderPolicy)),
            ',"lastChangedVersion":',
            vm.toString(uint256(cp.lastChangedVersion))
        );
        IAgentMeditation.Demand memory dm = reg.demandOf(agent, i);
        string memory c = string.concat(
            ',"demand":{"demandedAt":',
            vm.toString(uint256(dm.demandedAt)),
            ',"dueBy":',
            vm.toString(uint256(dm.dueBy)),
            "}}"
        );
        return string.concat(a, b, c);
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
