// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

contract StatusTest is Harness {
    function setUp() public override {
        super.setUp();
        enrollDefault();
    }

    // ------------------------------------------------------------------
    // Per-layer timeliness
    // ------------------------------------------------------------------

    function test_status_notEnrolled() public view {
        (IAgentMeditation.MaintenanceStatus s, uint48 d, bool never) = reg.layerStatus(STRANGER, 0);
        assertTrue(s == IAgentMeditation.MaintenanceStatus.NOT_ENROLLED, "not enrolled");
        assertEq(d, 0, "no deadline");
        assertTrue(never, "never completed");
        (IAgentMeditation.SignalStatus ss,,) = reg.signalStatus(STRANGER);
        assertTrue(ss == IAgentMeditation.SignalStatus.NOT_ENROLLED, "signal not enrolled");
    }

    function test_status_neverCompletedCountsFromEnrollment() public {
        (IAgentMeditation.MaintenanceStatus s, uint48 d, bool never) = reg.layerStatus(AGENT, 0);
        assertTrue(s == IAgentMeditation.MaintenanceStatus.FRESH, "fresh after enrollment");
        assertEq(d, T0 + 1 * DAY, "deadline = enrolledAt + interval");
        assertTrue(never, "never completed flagged");

        vm.warp(T0 + 1 * DAY - HOUR); // inside the due window
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.DUE, "due");
        vm.warp(T0 + 1 * DAY - HOUR - 1);
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.FRESH, "fresh just before the window");
        vm.warp(T0 + 1 * DAY);
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.OVERDUE, "overdue at the deadline");
    }

    function test_status_perLayerFreshnessIsIndependent() public {
        vm.warp(T0 + 12 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0)); // only L1 completed
        submit(r);
        assertEq(deadline(0), r.reportedEndedAt + 1 * DAY, "L1 deadline moved");
        assertEq(deadline(3), T0 + 90 * DAY, "L4 deadline untouched");
        vm.warp(T0 + 90 * DAY);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.OVERDUE, "L4 overdue on its own clock");
    }

    function test_status_partialCompletionRefreshesOnlyCompletedLayers() public {
        vm.warp(T0 + 6 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(0x0F, bit(0) | bit(1));
        r.outcome = uint8(IAgentMeditation.Outcome.PARTIAL);
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 0).lastCompletedAt, r.reportedEndedAt, "L1 refreshed");
        assertEq(reg.checkpointOf(AGENT, 1).lastCompletedAt, r.reportedEndedAt, "L2 refreshed");
        assertEq(reg.checkpointOf(AGENT, 2).lastCompletedAt, 0, "L3 not refreshed");
        assertEq(reg.checkpointOf(AGENT, 3).lastCompletedAt, 0, "L4 not refreshed");
        assertEq(deadline(2), T0 + 30 * DAY, "L3 deadline unchanged");
    }

    function test_status_unsupportedAndUnscheduled() public {
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.supportedLayers = 0x07; // L4 unsupported
        p.requiredLayers = 0x03; // L3 supported but unscheduled
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.UNSUPPORTED, "L4 unsupported");
        assertTrue(status(2) == IAgentMeditation.MaintenanceStatus.UNSCHEDULED, "L3 unscheduled");
        assertEq(deadline(2), 0, "no deadline when unscheduled");
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.FRESH, "L1 fresh");
    }

    function test_status_policyChangeDoesNotEraseOverdue() public {
        vm.warp(T0 + 2 * DAY); // L1 overdue (1 day interval, never completed)
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.OVERDUE, "overdue before change");
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.maxInterval[0] = 3 * DAY; // loosened
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        // the anchor stays the enrollment time (no completion exists); the new interval does not reset it
        assertEq(deadline(0), T0 + 3 * DAY, "deadline recomputed from the same anchor");
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.FRESH, "within the loosened interval now");
        vm.warp(T0 + 3 * DAY);
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.OVERDUE, "overdue again at the new deadline");
        // a completion is the only thing that moves the anchor
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        submit(r);
        assertEq(deadline(0), r.reportedEndedAt + 3 * DAY, "anchor moved by completion");
    }

    function test_status_policyChangeCannotReinterpretPastCompletion() public {
        vm.warp(T0 + 6 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        submit(r);
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.maxInterval[0] = 12 * HOUR; // tightened afterwards
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        assertEq(reg.checkpointOf(AGENT, 0).completedUnderPolicy, 1, "completion keeps its governing version");
        assertEq(deadline(0), r.reportedEndedAt + 12 * HOUR, "current requirement applies to the next deadline");
    }

    // ------------------------------------------------------------------
    // Floors and demands (controller)
    // ------------------------------------------------------------------

    function test_floor_tightensButSubjectCannotRelaxBelowIt() public {
        IAgentMeditation.Floor memory f;
        f.requiredLayers = bit(0) | bit(3);
        f.maxInterval[0] = 12 * HOUR;
        f.maxInterval[3] = 30 * DAY;
        f.pulseInterval = 1 * HOUR;
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, f);

        IAgentMeditation.Requirements memory req = reg.requirementsOf(AGENT);
        assertEq(req.maxInterval[0], 12 * HOUR, "floor tighter than policy");
        assertEq(req.maxInterval[3], 30 * DAY, "floor tighter than policy (L4)");
        assertEq(req.maxInterval[1], 7 * DAY, "policy where the floor is silent");
        assertEq(req.pulseInterval, 1 * HOUR, "pulse floor");

        // the subject loosens its own policy: the effective requirement stays at the floor
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.maxInterval[0] = 10 * DAY;
        p.requiredLayers = 0x06; // drops L1 and L4 from its own requirements
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        req = reg.requirementsOf(AGENT);
        assertEq(req.requiredLayers, 0x0F, "floor keeps L1 and L4 required");
        assertEq(req.maxInterval[0], 12 * HOUR, "floor interval survives");
        assertEq(req.maxInterval[3], 30 * DAY, "floor interval survives (L4)");
        assertEq(reg.headOf(AGENT).floorVersion, 1, "floor version");
    }

    function test_floor_requiredLayerUnsupportedByPolicyIsStillJudged() public {
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.supportedLayers = 0x07;
        p.requiredLayers = 0x07;
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.UNSUPPORTED, "unsupported before floor");
        IAgentMeditation.Floor memory f;
        f.requiredLayers = bit(3);
        f.maxInterval[3] = 30 * DAY;
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, f);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.FRESH, "floor requirement judged");
        vm.warp(T0 + 30 * DAY);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.OVERDUE, "and becomes overdue");
    }

    function test_floor_authorizationAndValidation() public {
        IAgentMeditation.Floor memory f;
        f.requiredLayers = bit(0);
        f.maxInterval[0] = 1 * HOUR;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setFloor(AGENT, f);
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setFloor(AGENT, f);

        IAgentMeditation.Floor memory bad;
        bad.requiredLayers = bit(1); // required without interval
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.InvalidFloor.selector);
        reg.setFloor(AGENT, bad);

        // controller without RIGHT_FLOOR
        vm.prank(CONTROLLER);
        reg.setController(AGENT, CONTROLLER, RIGHT_DEMAND);
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setFloor(AGENT, f);
    }

    function test_demand_shortensDeadlineUntilSatisfied() public {
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(3), T0 + 2 * HOUR); // L4 by T0 + 2h
        assertEq(deadline(3), T0 + 2 * HOUR, "demand deadline");
        vm.warp(T0 + 90 * 60); // 1.5h: inside the 1h due window
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.DUE, "due");
        vm.warp(T0 + 2 * HOUR);
        assertTrue(status(3) == IAgentMeditation.MaintenanceStatus.OVERDUE, "overdue");

        // completion after the demand satisfies it
        vm.warp(T0 + 3 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(3), bit(3));
        r.reportedStartedAt = T0 + 2 * HOUR + 30 minutes;
        r.reportedEndedAt = T0 + 2 * HOUR + 50 minutes;
        submit(r);
        assertEq(reg.demandOf(AGENT, 3).demandedAt, 0, "demand cleared");
        assertEq(deadline(3), r.reportedEndedAt + 90 * DAY, "back to the policy interval");
    }

    function test_demand_completionBeforeDemandDoesNotSatisfyIt() public {
        vm.warp(T0 + 1 * HOUR);
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(0), T0 + 3 * HOUR);
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.reportedStartedAt = T0 + 10 minutes;
        r.reportedEndedAt = T0 + 50 minutes; // ended before the demand was made
        submit(r);
        assertEq(reg.demandOf(AGENT, 0).demandedAt, T0 + 1 * HOUR, "demand still outstanding");
        assertEq(deadline(0), T0 + 3 * HOUR, "still judged against the demand");
    }

    function test_demand_authorizationAndWithdrawal() public {
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.demand(AGENT, bit(0), T0 + 1 * HOUR);
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.InvalidDemand.selector);
        reg.demand(AGENT, bit(0), T0); // not in the future
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.InvalidLayerMask.selector);
        reg.demand(AGENT, 0, T0 + 1 * HOUR);

        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(0) | bit(1), T0 + 1 * HOUR);
        vm.prank(CONTROLLER);
        reg.withdrawDemand(AGENT, bit(0));
        assertEq(reg.demandOf(AGENT, 0).demandedAt, 0, "L1 demand withdrawn");
        assertEq(reg.demandOf(AGENT, 1).dueBy, T0 + 1 * HOUR, "L2 demand kept");

        vm.prank(CONTROLLER);
        reg.setController(AGENT, CONTROLLER, RIGHT_FLOOR); // drops RIGHT_DEMAND
        vm.prank(CONTROLLER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.demand(AGENT, bit(0), T0 + 1 * HOUR);
    }

    // ------------------------------------------------------------------
    // Activity signal
    // ------------------------------------------------------------------

    function test_signal_presentThenSilent() public {
        (IAgentMeditation.SignalStatus s, uint48 last, uint48 since) = reg.signalStatus(AGENT);
        assertTrue(s == IAgentMeditation.SignalStatus.PRESENT, "present at enrollment");
        assertEq(last, T0, "last signal");
        assertEq(since, 0, "not silent");
        vm.warp(T0 + 6 * HOUR);
        assertTrue(signal() == IAgentMeditation.SignalStatus.PRESENT, "present at the boundary");
        vm.warp(T0 + 6 * HOUR + 1);
        (s, last, since) = reg.signalStatus(AGENT);
        assertTrue(s == IAgentMeditation.SignalStatus.SILENT, "silent after the interval");
        assertEq(since, T0 + 6 * HOUR, "silent since the boundary");
        vm.prank(AGENT);
        reg.pulse(AGENT, 0);
        assertTrue(signal() == IAgentMeditation.SignalStatus.PRESENT, "pulse restores the signal");
    }

    function test_signal_notTrackedWithoutInterval() public {
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.pulseInterval = 0;
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        vm.warp(T0 + 30 * DAY);
        assertTrue(signal() == IAgentMeditation.SignalStatus.NOT_TRACKED, "not tracked");
        // a floor may still track it
        IAgentMeditation.Floor memory f;
        f.pulseInterval = 1 * DAY;
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, f);
        assertTrue(signal() == IAgentMeditation.SignalStatus.SILENT, "tracked by floor and silent");
    }

    function test_signal_isSeparateFromMaintenance() public {
        // silent but fresh, and present but overdue, both exist
        vm.warp(T0 + 7 * HOUR);
        assertTrue(signal() == IAgentMeditation.SignalStatus.SILENT, "silent");
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.FRESH, "but fresh");
        vm.warp(T0 + 2 * DAY);
        vm.prank(AGENT);
        reg.pulse(AGENT, 0);
        assertTrue(signal() == IAgentMeditation.SignalStatus.PRESENT, "present");
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.OVERDUE, "but overdue");
    }

    // ------------------------------------------------------------------
    // Self-modification cannot widen authority
    // ------------------------------------------------------------------

    function test_selfPolicyChangeCannotWidenAuthority() public {
        IAgentMeditation.Floor memory f;
        f.requiredLayers = 0x0F;
        f.maxInterval[0] = 1 * HOUR;
        f.maxInterval[1] = 1 * DAY;
        f.maxInterval[2] = 1 * DAY;
        f.maxInterval[3] = 7 * DAY;
        f.pulseInterval = 2 * HOUR;
        vm.prank(CONTROLLER);
        reg.setFloor(AGENT, f);

        // an L4 cycle "revises the self-model" and the subject then relaxes its own policy as far as it can
        IAgentMeditation.CycleReport memory r = baseReport(bit(3), bit(3));
        r.postCommitments[3] = keccak256("cognition/v2-relaxed-standards");
        r.opsMask = opBit(3, OP_ITERATE);
        submit(r);
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.requiredLayers = bit(3);
        p.maxInterval[3] = 365 * DAY;
        p.pulseInterval = 0;
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);

        IAgentMeditation.Requirements memory req = reg.requirementsOf(AGENT);
        assertEq(req.requiredLayers, 0x0F, "floor requirements remain");
        assertEq(req.maxInterval[0], 1 * HOUR, "floor L1 remains");
        assertEq(req.maxInterval[3], 7 * DAY, "floor L4 remains");
        assertEq(req.pulseInterval, 2 * HOUR, "floor pulse interval remains");

        // and none of this touched the controller relationship
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(h.controller, CONTROLLER, "controller unchanged");
        assertEq(h.controllerRights, ALL_RIGHTS, "rights unchanged");
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.setFloor(AGENT, f); // the subject still cannot write the floor
    }
}
