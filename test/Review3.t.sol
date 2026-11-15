// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

/// @dev Cases from the fourth Magicians review post (topic 30304, post 11): a cycle that covers several layers
///      ends when its last routine ends, and a layer that finished earlier must not inherit the cycle's end as
///      its completion time. Since revision 5 every completed layer carries its own completion time.
contract Review3Test is Harness {
    uint48 internal constant TEN = T0 + 10 * HOUR; // "10:00"
    uint48 internal constant ELEVEN = T0 + 11 * HOUR; // "11:00"

    function setUp() public override {
        super.setUp();
        // layer 0 (runtime) on a 30-minute interval, the other layers on the default ones
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.maxInterval[0] = 30 minutes;
        p.dueWindow = 5 minutes;
        vm.prank(AGENT);
        reg.enroll(baseline(), p, CONTROLLER, ALL_RIGHTS);
    }

    /// @dev The reviewer's cycle: runtime check done at 10:00, memory review done at 11:00, one record at 11:00.
    function _reviewerCycle() internal view returns (IAgentMeditation.CycleReport memory r) {
        r = baseReport(bit(0) | bit(1), bit(0) | bit(1));
        setTimes(r, T0 + 9 * HOUR + 30 minutes, ELEVEN);
        r.completedAt[0] = TEN;
        r.completedAt[1] = ELEVEN;
    }

    function test_review3_eachLayerKeepsItsOwnCompletionTime() public {
        vm.warp(ELEVEN);
        submit(_reviewerCycle());
        assertEq(reg.checkpointOf(AGENT, 0).lastCompletedAt, TEN, "runtime completed at 10:00");
        assertEq(reg.checkpointOf(AGENT, 1).lastCompletedAt, ELEVEN, "memory completed at 11:00");
        assertEq(reg.headOf(AGENT).lastCycleEndedAt, ELEVEN, "the cycle ended at 11:00");

        // the runtime layer is judged from 10:00: overdue since 10:30, whatever the cycle's end
        (IAgentMeditation.MaintenanceStatus s, uint48 d,) = reg.layerStatus(AGENT, 0);
        assertTrue(s == IAgentMeditation.MaintenanceStatus.OVERDUE, "runtime overdue at 11:00");
        assertEq(d, TEN + 30 minutes, "deadline 10:30");
        assertTrue(status(1) == IAgentMeditation.MaintenanceStatus.FRESH, "memory fresh");
    }

    function test_review3_controlCycleEndIsNotTheCompletionTime() public {
        // the same cycle reported with both layers completing at the end makes the runtime layer read fresh;
        // the registry cannot tell, which is why the record has to carry the time per layer
        vm.warp(ELEVEN);
        IAgentMeditation.CycleReport memory r = _reviewerCycle();
        r.completedAt[0] = ELEVEN;
        submit(r);
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.FRESH, "claims a completion at 11:00");
        assertEq(reg.checkpointOf(AGENT, 0).lastCompletedAt, ELEVEN, "registered as claimed");
    }

    function test_review3_completionTimeMustLieInsideTheCycle() public {
        vm.warp(ELEVEN);
        IAgentMeditation.CycleReport memory r = _reviewerCycle();
        r.completedAt[0] = r.reportedStartedAt - 1;
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.InvalidCompletionTime.selector, uint8(0)));
        reg.report(AGENT, r);

        r = _reviewerCycle();
        r.completedAt[1] = ELEVEN + 1;
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.InvalidCompletionTime.selector, uint8(1)));
        reg.report(AGENT, r);

        r = _reviewerCycle();
        r.completedAt[0] = r.reportedStartedAt; // the bounds are inclusive
        r.completedAt[1] = r.reportedEndedAt;
        submit(r);
    }

    function test_review3_uncompletedLayerCarriesNoCompletionTime() public {
        vm.warp(ELEVEN);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0) | bit(1), bit(0)); // layer 1 in scope, not completed
        r.completedAt[1] = ELEVEN;
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.InvalidCompletionTime.selector, uint8(1)));
        reg.report(AGENT, r);
        r.completedAt[1] = 0;
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 1).lastCompletedAt, 0, "no completion registered for layer 1");
    }

    function test_review3_monotonicityIsPerLayerCompletionTime() public {
        vm.warp(ELEVEN);
        submit(_reviewerCycle()); // runtime at 10:00, memory at 11:00

        // a cycle starting exactly at the previous end may claim a completion at that second for a layer that
        // completed earlier, not for the layer whose registered completion is that second
        vm.warp(ELEVEN + 1 * HOUR);
        IAgentMeditation.CycleReport memory repeat = baseReport(bit(1), bit(1));
        setTimes(repeat, ELEVEN, ELEVEN + 30 minutes);
        repeat.completedAt[1] = ELEVEN; // equal to the registered completion of layer 1
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.CompletionNotMonotonic.selector, uint8(1)));
        reg.report(AGENT, repeat);

        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        setTimes(r, ELEVEN, ELEVEN + 30 minutes);
        r.completedAt[0] = ELEVEN; // later than 10:00, although at the previous cycle's end
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 0).lastCompletedAt, ELEVEN, "advanced to 11:00");

        // a completion time before the cycle's own start is rejected as a time, not as a repeat
        vm.warp(ELEVEN + 2 * HOUR);
        IAgentMeditation.CycleReport memory again = baseReport(bit(0), bit(0));
        setTimes(again, ELEVEN + 30 minutes, ELEVEN + 90 minutes);
        again.completedAt[0] = ELEVEN + 10 minutes;
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.InvalidCompletionTime.selector, uint8(0)));
        reg.report(AGENT, again);
    }

    function test_review3_demandIsClearedByTheLayersCompletionTimeNotTheCycleEnd() public {
        // demand on the runtime layer at 10:30; the reviewer's cycle completed that layer at 10:00 and ended at
        // 11:00: the cycle's end is after the demand, the completion is not, so the demand stands
        vm.warp(TEN + 30 minutes);
        vm.prank(CONTROLLER);
        reg.demand(AGENT, bit(0) | bit(1), ELEVEN + 1 * HOUR);
        vm.warp(ELEVEN);
        submit(_reviewerCycle());
        assertEq(reg.demandOf(AGENT, 0).demandedAt, TEN + 30 minutes, "runtime demand still outstanding");
        assertEq(reg.demandOf(AGENT, 1).demandedAt, 0, "memory demand cleared by a completion at 11:00");
    }
}
