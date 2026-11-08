// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

contract EnrollmentTest is Harness {
    function test_enroll_setsBaselineHeadAndPolicy() public {
        enrollDefault();
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertTrue(h.enrolled, "enrolled");
        assertEq(h.controller, CONTROLLER, "controller");
        assertEq(h.controllerRights, ALL_RIGHTS, "rights");
        assertEq(h.stateVersion, 1, "state version 1");
        assertEq(h.policyVersion, 1, "policy version 1");
        assertEq(h.floorVersion, 0, "no floor");
        assertEq(h.recordCount, 0, "no records yet");
        assertEq(h.root, reg.computeRoot(baseline()), "root");
        assertEq(h.enrolledAt, T0, "enrolledAt");
        assertEq(h.lastSignalAt, T0, "enrollment is an activity signal");
        assertEq(reg.rootAt(AGENT, 1), h.root, "rootAt(1)");
        assertEq(reg.policyEffectiveFrom(AGENT, 1), T0, "policy v1 effective at enrollment");
        for (uint8 i = 0; i < 4; i++) {
            IAgentMeditation.LayerCheckpoint memory cp = reg.checkpointOf(AGENT, i);
            assertEq(cp.commitment, baseline()[i], "baseline commitment");
            assertEq(cp.lastCompletedAt, 0, "never completed");
            assertEq(cp.lastChangedVersion, 1, "changed at v1");
        }
        IAgentMeditation.Policy memory p = reg.policyOf(AGENT, 1);
        assertEq(p.policyHash, keccak256("policy/v1"), "policy hash stored");
        assertEq(p.maxInterval[3], 90 * DAY, "interval stored");
    }

    function test_enroll_twiceReverts() public {
        enrollDefault();
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.AlreadyEnrolled.selector);
        reg.enroll(baseline(), defaultPolicy(), CONTROLLER, ALL_RIGHTS);
    }

    function test_enroll_rejectsInvalidPolicies() public {
        IAgentMeditation.Policy memory p = defaultPolicy();

        p.supportedLayers = 0;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidPolicy.selector);
        reg.enroll(baseline(), p, address(0), 0);

        p = defaultPolicy();
        p.supportedLayers = 0x03;
        p.requiredLayers = 0x07; // required must be a subset of supported
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidPolicy.selector);
        reg.enroll(baseline(), p, address(0), 0);

        p = defaultPolicy();
        p.maxInterval[2] = 0; // required layer needs an interval
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidPolicy.selector);
        reg.enroll(baseline(), p, address(0), 0);

        p = defaultPolicy();
        p.allowedTriggers = 0;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidPolicy.selector);
        reg.enroll(baseline(), p, address(0), 0);

        p = defaultPolicy();
        p.disclosure = 3;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidPolicy.selector);
        reg.enroll(baseline(), p, address(0), 0);
    }

    function test_enroll_rejectsInvalidControllerCombinations() public {
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidController.selector);
        reg.enroll(baseline(), defaultPolicy(), address(0), 1); // rights without controller

        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidController.selector);
        reg.enroll(baseline(), defaultPolicy(), AGENT, 1); // self as controller

        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidController.selector);
        reg.enroll(baseline(), defaultPolicy(), CONTROLLER, 0x08); // unknown right bit
    }

    function test_enroll_unsupportedLayerMayCarryAnyCommitment() public {
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.supportedLayers = 0x07;
        p.requiredLayers = 0x07;
        vm.prank(AGENT);
        reg.enroll(baseline(), p, address(0), 0);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.UNSUPPORTED, "L4 unsupported");
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.FRESH, "L1 fresh right after enrollment");
    }

    // ------------------------------------------------------------------
    // Controller lifecycle
    // ------------------------------------------------------------------

    function test_controller_subjectMayAppointWhenNone() public {
        enrollNoController();
        vm.prank(AGENT);
        reg.setController(AGENT, CONTROLLER, RIGHT_FLOOR);
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(h.controller, CONTROLLER, "appointed");
        assertEq(h.controllerRights, RIGHT_FLOOR, "rights");
    }

    function test_controller_subjectCannotChangeExistingController() public {
        enrollDefault();
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setController(AGENT, STRANGER, ALL_RIGHTS);

        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setController(AGENT, address(0), 0); // subject cannot renounce the controller either
    }

    function test_controller_mayTransferWithSubsetRightsOnly() public {
        enrollDefault();
        vm.prank(CONTROLLER);
        reg.setController(AGENT, STRANGER, RIGHT_FLOOR | RIGHT_DEMAND);
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(h.controller, STRANGER, "transferred");
        assertEq(h.controllerRights, RIGHT_FLOOR | RIGHT_DEMAND, "shrunk on transfer");

        // the new controller cannot grow its rights back
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.InvalidController.selector);
        reg.setController(AGENT, STRANGER, ALL_RIGHTS);
    }

    function test_controller_mayShrinkOwnRightsAndRenounce() public {
        enrollDefault();
        vm.prank(CONTROLLER);
        reg.setController(AGENT, CONTROLLER, RIGHT_DEMAND);
        assertEq(reg.headOf(AGENT).controllerRights, RIGHT_DEMAND, "shrunk");

        vm.prank(CONTROLLER);
        reg.setController(AGENT, address(0), 0);
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(h.controller, address(0), "renounced");
        assertEq(h.controllerRights, 0, "no rights");

        // after renunciation the subject may appoint again
        vm.prank(AGENT);
        reg.setController(AGENT, STRANGER, RIGHT_FLOOR);
        assertEq(reg.headOf(AGENT).controller, STRANGER, "re-appointed");
    }

    function test_controller_strangerCannotTouch() public {
        enrollDefault();
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setController(AGENT, STRANGER, ALL_RIGHTS);
    }

    // ------------------------------------------------------------------
    // Operators
    // ------------------------------------------------------------------

    function test_operator_grantAndRevokeBySubject() public {
        enrollDefault();
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT | PERM_PULSE);
        assertEq(reg.operatorPermissions(AGENT, OPERATOR), PERM_REPORT | PERM_PULSE, "granted");
        vm.prank(AGENT);
        reg.revokeOperator(AGENT, OPERATOR);
        assertEq(reg.operatorPermissions(AGENT, OPERATOR), 0, "revoked");
    }

    function test_operator_controllerWithRightMayRevokeButNotGrant() public {
        enrollDefault();
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, ALL_PERMISSIONS);
        vm.prank(CONTROLLER);
        reg.revokeOperator(AGENT, OPERATOR);
        assertEq(reg.operatorPermissions(AGENT, OPERATOR), 0, "controller revoked");

        // setOperator always acts on msg.sender's own record; the controller cannot grant on the subject
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.NotEnrolled.selector);
        reg.setOperator(OPERATOR, ALL_PERMISSIONS);
    }

    function test_operator_controllerWithoutRightCannotRevoke() public {
        vm.prank(AGENT);
        reg.enroll(baseline(), defaultPolicy(), CONTROLLER, RIGHT_FLOOR);
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT);
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.revokeOperator(AGENT, OPERATOR);
    }

    function test_operator_rejectsInvalidGrants() public {
        enrollDefault();
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setOperator(AGENT, PERM_REPORT); // self
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setOperator(OPERATOR, 0x08); // unknown permission bit
    }

    function test_supportsInterface() public view {
        assertTrue(reg.supportsInterface(type(IAgentMeditation).interfaceId), "IAgentMeditation");
        assertTrue(reg.supportsInterface(0x01ffc9a7), "ERC-165");
        assertTrue(!reg.supportsInterface(0xffffffff), "invalid id");
        assertEq(reg.CLOCK_MODE(), "mode=timestamp", "clock mode");
        assertEq(reg.clock(), T0, "clock");
    }
}
