// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";

contract EventsTest is Harness {
    function test_events_enrollment() public {
        bytes32 root = reg.computeRoot(baseline());
        vm.expectEmit(true, true, false, true);
        emit IAgentMeditation.Enrolled(AGENT, CONTROLLER, ALL_RIGHTS, root, T0);
        vm.expectEmit(true, true, false, true);
        emit IAgentMeditation.PolicyUpdated(AGENT, 1, keccak256("policy/v1"), T0, AGENT);
        enrollDefault();
    }

    function test_events_cycleRecordedAndLayerChanged() public {
        enrollDefault();
        vm.warp(T0 + 1 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0) | bit(2), bit(0) | bit(2));
        r.postCommitments[0] = keccak256("runtime/v2");
        r.opsMask = opBit(0, OP_UPDATE);

        vm.expectEmit(true, true, true, true);
        emit IAgentMeditation.LayerCommitmentChanged(AGENT, 0, 2, C0, keccak256("runtime/v2"));
        vm.expectEmit(true, true, false, true);
        emit IAgentMeditation.CycleRecorded(AGENT, 1, 1, 2, r, bit(0), T0 + 1 * HOUR, AGENT);
        submit(r);
    }

    function test_events_pulse() public {
        enrollDefault();
        vm.warp(T0 + 2 * HOUR);
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_PULSE);
        vm.expectEmit(true, true, false, true);
        emit IAgentMeditation.Pulsed(AGENT, 1, T0 + 2 * HOUR, T0 + 8 * HOUR, OPERATOR);
        vm.prank(OPERATOR);
        reg.pulse(AGENT, T0 + 8 * HOUR);
    }

    function test_events_policyFloorDemandController() public {
        enrollDefault();
        vm.warp(T0 + 1);
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.policyHash = keccak256("policy/v2");
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_POLICY);
        vm.expectEmit(true, true, false, true);
        emit IAgentMeditation.PolicyUpdated(AGENT, 2, keccak256("policy/v2"), T0 + 1, OPERATOR);
        vm.prank(OPERATOR);
        reg.setPolicy(AGENT, p);

        IAgentMeditation.Floor memory f;
        f.requiredLayers = bit(0);
        f.maxInterval[0] = HOUR;
        vm.expectEmit(true, true, false, true);
        emit IAgentMeditation.FloorUpdated(AGENT, 1, T0 + 1, CONTROLLER);
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, f);

        vm.expectEmit(true, false, false, true);
        emit IAgentMeditation.Demanded(AGENT, bit(1), T0 + DAY, CONTROLLER);
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(1), T0 + DAY);

        vm.expectEmit(true, false, false, true);
        emit IAgentMeditation.DemandWithdrawn(AGENT, bit(1), CONTROLLER);
        vm.prank(CONTROLLER);
        reg.withdrawDemand(AGENT, bit(1));

        vm.expectEmit(true, true, true, true);
        emit IAgentMeditation.ControllerChanged(AGENT, CONTROLLER, STRANGER, RIGHT_FLOOR);
        vm.prank(CONTROLLER);
        reg.setController(AGENT, STRANGER, RIGHT_FLOOR);

        vm.expectEmit(true, true, true, true);
        emit IAgentMeditation.OperatorSet(AGENT, OPERATOR, 0, AGENT);
        vm.prank(AGENT);
        reg.revokeOperator(AGENT, OPERATOR);
    }
}
