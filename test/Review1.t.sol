// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

/// @dev Cases from the first Magicians review round (topic 30304, post 3): each pairs the honest call,
///      which reverts, with the variant that was accepted by revision 1, and shows what revision 2 does.
contract Review1Test is Harness {
    function setUp() public override {
        super.setUp();
        enrollDefault();
    }

    // ------------------------------------------------------------------
    // Finding 1: the policy pin is only as strong as the reported start
    // ------------------------------------------------------------------

    function _tightenToScheduledOnly() internal returns (uint48 tightenedAt) {
        IAgentMeditation.Policy memory p2 = defaultPolicy();
        p2.policyHash = keccak256("policy/v2-scheduled-only");
        p2.allowedTriggers = uint8(1) << TRIGGER_SCHEDULED;
        tightenedAt = uint48(block.timestamp);
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p2);
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT);
    }

    function test_review1_controlSelfTriggerRevertsUnderTightenedPolicy() public {
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly();
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.trigger = TRIGGER_SELF;
        r.policyVersion = 2;
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, r);
    }

    function test_review1_backdatedStartIsBoundedByThePreviousCycle() public {
        // an honest cycle is recorded after the tightening; its end becomes the floor for every later start
        vm.warp(T0 + 1 * HOUR);
        uint48 tightenedAt = _tightenToScheduledOnly();
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory honest = baseReport(bit(0), bit(0));
        honest.policyVersion = 2;
        honest.trigger = TRIGGER_SCHEDULED;
        submit(honest); // ends at T0 + 1h59

        // the operator backdates a SELF cycle to before the tightening and claims version 1
        vm.warp(T0 + 3 * HOUR);
        IAgentMeditation.CycleReport memory backdated = baseReport(bit(1), bit(1));
        backdated.policyVersion = 1;
        backdated.trigger = TRIGGER_SELF;
        backdated.reportedStartedAt = tightenedAt - 1;
        backdated.reportedEndedAt = T0 + 2 * HOUR + 30 minutes;
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.StartBeforePreviousCycle.selector);
        reg.report(AGENT, backdated);
    }

    function test_review1_residualGapIsClosedByTheCurrentVersionCheck() public {
        // with no accepted cycle between the last record and the tightening, a start inside that gap still
        // selects version 1 (revision 2 left this open); since revision 4 the record must also fit the current
        // version, so the SELF trigger version 2 forbids is refused (see Review2Test for the full set)
        vm.warp(T0 + 1 * HOUR);
        uint48 tightenedAt = _tightenToScheduledOnly();
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory backdated = baseReport(bit(0), bit(0));
        backdated.policyVersion = 1;
        backdated.trigger = TRIGGER_SELF;
        backdated.reportedStartedAt = tightenedAt - 1; // after enrollment, before the tightening
        backdated.reportedEndedAt = T0 + 90 minutes;
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, backdated);
    }

    function test_review1_removedLayerControlAndBound() public {
        // version 2 drops layer 3; the honest call reverts, the backdated variant is bounded once a cycle lands
        vm.warp(T0 + 1 * HOUR);
        IAgentMeditation.Policy memory p2 = defaultPolicy();
        p2.supportedLayers = 0x07;
        p2.requiredLayers = 0x07;
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p2);
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT);

        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory honest = baseReport(bit(3), bit(3));
        honest.policyVersion = 2;
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.LayerNotSupported.selector);
        reg.report(AGENT, honest);

        IAgentMeditation.CycleReport memory anchor = baseReport(bit(0), bit(0));
        anchor.policyVersion = 2;
        submit(anchor); // ends at T0 + 1h59

        vm.warp(T0 + 3 * HOUR);
        IAgentMeditation.CycleReport memory backdated = baseReport(bit(3), bit(3));
        backdated.policyVersion = 1;
        backdated.reportedStartedAt = T0 + 30 minutes;
        backdated.reportedEndedAt = T0 + 2 * HOUR + 30 minutes;
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.StartBeforePreviousCycle.selector);
        reg.report(AGENT, backdated);
    }

    function test_review1_pulsesDoNotBoundTheStart() public {
        // a long cycle may be accompanied by pulses; the bound comes from cycle records only
        vm.warp(T0 + 1 * HOUR);
        vm.prank(AGENT);
        reg.pulse(AGENT, 0);
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(1), bit(1));
        r.reportedStartedAt = T0 + 30 minutes; // before the pulse
        r.reportedEndedAt = T0 + 90 minutes;
        submit(r);
    }

    // ------------------------------------------------------------------
    // Finding 2: withdrawDemand requires RIGHT_DEMAND
    // ------------------------------------------------------------------

    function test_review1_withdrawDemandRequiresRightDemand() public {
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(0), T0 + 1 * HOUR);
        // the controller gives up RIGHT_DEMAND and keeps RIGHT_FLOOR
        vm.prank(CONTROLLER);
        reg.setController(AGENT, CONTROLLER, RIGHT_FLOOR);
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.demand(AGENT, bit(1), T0 + 1 * HOUR); // control: cannot issue
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.withdrawDemand(AGENT, bit(0)); // and now cannot withdraw either
        assertEq(reg.demandOf(AGENT, 0).dueBy, T0 + 1 * HOUR, "demand still outstanding");
    }

    // ------------------------------------------------------------------
    // Finding 3: layers a demand may name
    // ------------------------------------------------------------------

    function test_review1_demandOnUnsupportedLayerRejected() public {
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.supportedLayers = 0x07;
        p.requiredLayers = 0x07;
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.LayerNotSupported.selector);
        reg.demand(AGENT, bit(3), T0 + 1 * HOUR);
    }

    function test_review1_demandPutsAnUnscheduledLayerOnTheClock() public {
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.requiredLayers = 0x07; // layer 3 supported, not required
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.UNSCHEDULED, "unscheduled before the demand");

        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(3), T0 + 2 * HOUR);
        (IAgentMeditation.MaintenanceStatus s, uint48 d,) = reg.layerStatus(AGENT, 3);
        assertTrue(s == IAgentMeditation.MaintenanceStatus.FRESH, "on the clock");
        assertEq(d, T0 + 2 * HOUR, "judged against the demand");
        vm.warp(T0 + 2 * HOUR - 60 minutes); // inside the 1h due window
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.DUE, "due");
        vm.warp(T0 + 2 * HOUR);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.OVERDUE, "overdue");

        // completing the layer clears the demand and the layer returns to unscheduled
        vm.warp(T0 + 3 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(3), bit(3));
        r.reportedStartedAt = T0 + 2 * HOUR + 10 minutes;
        r.reportedEndedAt = T0 + 2 * HOUR + 40 minutes;
        submit(r);
        assertEq(reg.demandOf(AGENT, 3).demandedAt, 0, "demand cleared");
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.UNSCHEDULED, "back to unscheduled");
    }

    function test_review1_demandOnRequiredLayerStillLowersDeadline() public {
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(3), T0 + 2 * HOUR);
        assertEq(deadline(3), T0 + 2 * HOUR, "demand deadline wins over the 90-day interval");
    }
}

/// @dev Cases from the second review post (topic 30304, post 6): a policy change cannot drop a layer that is
///      under an obligation (outstanding demand, or floor requirement).
contract Review1bTest is Harness {
    function setUp() public override {
        super.setUp();
        enrollDefault();
    }

    function _policyWithout(uint8 dropped) internal pure returns (IAgentMeditation.Policy memory p) {
        p = defaultPolicy();
        p.supportedLayers = 0x0F & ~dropped;
        p.requiredLayers = 0x0F & ~dropped;
    }

    function test_review1b_policyCannotDropLayerWithOutstandingDemand() public {
        // the reviewer's exact sequence: demand on an unscheduled layer 3, then a policy that drops layer 3
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.requiredLayers = 0x07; // layer 3 supported, not required
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(3), T0 + 2 * HOUR);

        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.LayerUnderObligation.selector, uint8(3)));
        reg.setPolicy(AGENT, _policyWithout(bit(3)));

        // other policy changes remain possible while the demand is outstanding
        IAgentMeditation.Policy memory p3 = defaultPolicy();
        p3.requiredLayers = 0x07;
        p3.dueWindow = 2 * HOUR;
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p3);

        // once the demand is completed, the layer can be dropped
        vm.warp(T0 + 1 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(3), bit(3));
        submit(r);
        assertEq(reg.demandOf(AGENT, 3).demandedAt, 0, "demand cleared");
        vm.prank(AGENT);
        reg.setPolicy(AGENT, _policyWithout(bit(3)));
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.UNSUPPORTED, "dropped after completion");
    }

    function test_review1b_withdrawalAlsoFreesTheLayer() public {
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(2), T0 + 2 * HOUR);
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.LayerUnderObligation.selector, uint8(2)));
        reg.setPolicy(AGENT, _policyWithout(bit(2)));
        vm.prank(CONTROLLER);
        reg.withdrawDemand(AGENT, bit(2));
        vm.prank(AGENT);
        reg.setPolicy(AGENT, _policyWithout(bit(2)));
    }

    function test_review1b_policyCannotDropFloorRequiredLayer() public {
        IAgentMeditation.Floor memory f;
        f.requiredLayers = bit(3);
        f.maxInterval[3] = 30 * DAY;
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, f);
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.LayerUnderObligation.selector, uint8(3)));
        reg.setPolicy(AGENT, _policyWithout(bit(3)));

        // the floor may be relaxed by the controller, after which the layer can be dropped
        IAgentMeditation.Floor memory none;
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, none);
        vm.prank(AGENT);
        reg.setPolicy(AGENT, _policyWithout(bit(3)));
    }

    function test_review1b_floorMayRequireAnUnsupportedLayerAndBindsTheNextPolicy() public {
        // the subject never supported layer 3; the controller requires it anyway
        vm.prank(AGENT);
        reg.setPolicy(AGENT, _policyWithout(bit(3)));
        IAgentMeditation.Floor memory f;
        f.requiredLayers = bit(3);
        f.maxInterval[3] = 30 * DAY;
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, f);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.FRESH, "judged although unsupported");

        // the subject's next policy version must support the layer
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.LayerUnderObligation.selector, uint8(3)));
        reg.setPolicy(AGENT, _policyWithout(bit(3)));
        vm.prank(AGENT);
        reg.setPolicy(AGENT, defaultPolicy());
        assertEq(reg.requirementsOf(AGENT).supportedLayers, 0x0F, "support added");
    }
}
