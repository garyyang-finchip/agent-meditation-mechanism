// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {TestBase} from "./TestBase.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

/// @dev Shared fixtures for the kernel tests.
abstract contract Harness is TestBase {
    AgentMeditationRegistry internal reg;

    address internal constant AGENT = address(0xA6E7);
    address internal constant CONTROLLER = address(0xC0DE);
    address internal constant OPERATOR = address(0x0B);
    address internal constant STRANGER = address(0xBAD);

    uint48 internal constant T0 = 1_700_000_000;

    uint8 internal constant RIGHT_FLOOR = 1;
    uint8 internal constant RIGHT_DEMAND = 2;
    uint8 internal constant RIGHT_REVOKE_OPERATORS = 4;
    uint8 internal constant ALL_RIGHTS = 7;
    uint8 internal constant PERM_REPORT = 1;
    uint8 internal constant PERM_PULSE = 2;
    uint8 internal constant PERM_POLICY = 4;
    uint8 internal constant ALL_PERMISSIONS = 7;
    uint8 internal constant OP_CLEAN = 0;
    uint8 internal constant OP_REPAIR = 1;
    uint8 internal constant OP_UPDATE = 2;
    uint8 internal constant OP_ITERATE = 3;
    uint8 internal constant TRIGGER_SCHEDULED = 0;
    uint8 internal constant TRIGGER_EVENT = 1;
    uint8 internal constant TRIGGER_COMMANDED = 2;
    uint8 internal constant TRIGGER_SELF = 3;

    uint48 internal constant DAY = 86400;
    uint48 internal constant HOUR = 3600;

    bytes32 internal constant C0 = keccak256("baseline/runtime");
    bytes32 internal constant C1 = keccak256("baseline/memory-skills");
    bytes32 internal constant C2 = keccak256("baseline/tasks-roles");
    bytes32 internal constant C3 = keccak256("baseline/cognition");

    function setUp() public virtual {
        vm.warp(T0);
        reg = new AgentMeditationRegistry();
        vm.label(AGENT, "agent");
        vm.label(CONTROLLER, "controller");
        vm.label(OPERATOR, "operator");
    }

    // ------------------------------------------------------------------
    // Builders
    // ------------------------------------------------------------------

    function baseline() internal pure returns (bytes32[4] memory b) {
        b[0] = C0;
        b[1] = C1;
        b[2] = C2;
        b[3] = C3;
    }

    /// @dev Default policy: all layers supported and required; 1d / 7d / 30d / 90d; 1h due window; 6h pulse.
    function defaultPolicy() internal pure returns (IAgentMeditation.Policy memory p) {
        p.policyHash = keccak256("policy/v1");
        p.policyURI = "ipfs://policy-v1";
        p.supportedLayers = 0x0F;
        p.requiredLayers = 0x0F;
        p.allowedTriggers = 0x0F;
        p.disclosure = 0;
        p.dueWindow = HOUR;
        p.pulseInterval = 6 * HOUR;
        p.maxInterval[0] = 1 * DAY;
        p.maxInterval[1] = 7 * DAY;
        p.maxInterval[2] = 30 * DAY;
        p.maxInterval[3] = 90 * DAY;
    }

    function enrollDefault() internal {
        vm.prank(AGENT);
        reg.enroll(baseline(), defaultPolicy(), CONTROLLER, ALL_RIGHTS);
    }

    function enrollNoController() internal {
        vm.prank(AGENT);
        reg.enroll(baseline(), defaultPolicy(), address(0), 0);
    }

    /// @dev A report shaped against the current head: scope `mask`, completed `completed`, all commitments kept.
    function baseReport(uint8 mask, uint8 completed) internal view returns (IAgentMeditation.CycleReport memory r) {
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        r.baseVersion = h.stateVersion;
        r.preRoot = h.root;
        for (uint8 i = 0; i < 4; i++) {
            r.postCommitments[i] = reg.checkpointOf(AGENT, i).commitment;
        }
        r.layerMask = mask;
        r.completedLayers = completed;
        r.opsMask = 0;
        if (completed == mask) r.outcome = uint8(IAgentMeditation.Outcome.COMPLETED);
        else if (completed == 0) r.outcome = uint8(IAgentMeditation.Outcome.FAILED);
        else r.outcome = uint8(IAgentMeditation.Outcome.PARTIAL);
        r.trigger = TRIGGER_SCHEDULED;
        r.policyVersion = h.policyVersion;
        uint48 now_ = uint48(block.timestamp);
        if (now_ >= h.enrolledAt + 10 minutes) {
            r.reportedStartedAt = now_ - 10 minutes;
            r.reportedEndedAt = now_ - 1 minutes;
        } else {
            r.reportedStartedAt = h.enrolledAt;
            r.reportedEndedAt = now_;
        }
        r.nextPlannedAt = uint48(block.timestamp) + 1 days;
        r.restoresVersion = 0;
        r.recordHash = keccak256(abi.encode("record", block.timestamp, mask, completed));
        r.recordURI = "";
    }

    function submit(IAgentMeditation.CycleReport memory r) internal returns (uint64 seq) {
        vm.prank(AGENT);
        seq = reg.report(AGENT, r);
    }

    function bit(uint8 layer) internal pure returns (uint8) {
        return uint8(1) << layer;
    }

    function opBit(uint8 layer, uint8 op) internal pure returns (uint16) {
        return uint16(1) << (layer * 4 + op);
    }

    function status(uint8 layer) internal view returns (IAgentMeditation.MaintenanceStatus s) {
        (s,,) = reg.layerStatus(AGENT, layer);
    }

    function deadline(uint8 layer) internal view returns (uint48 d) {
        (, d,) = reg.layerStatus(AGENT, layer);
    }

    function signal() internal view returns (IAgentMeditation.SignalStatus s) {
        (s,,) = reg.signalStatus(AGENT);
    }
}
