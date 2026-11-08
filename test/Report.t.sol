// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

contract ReportTest is Harness {
    function setUp() public override {
        super.setUp();
        enrollDefault();
    }

    // ------------------------------------------------------------------
    // Linkage and state versions
    // ------------------------------------------------------------------

    function test_report_noChangeKeepsStateVersion() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        uint64 seq = submit(r);
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(seq, 1, "first record");
        assertEq(h.recordCount, 1, "record count");
        assertEq(h.stateVersion, 1, "no commitment changed: version unchanged");
        assertEq(h.root, reg.computeRoot(baseline()), "root unchanged");
        assertEq(h.nextPlannedAt, r.nextPlannedAt, "planning hint stored");
        assertEq(h.lastSignalAt, T0, "report is an activity signal (same second here)");
    }

    function test_report_changeAdvancesStateVersionAndRootHistory() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0) | bit(1), bit(0) | bit(1));
        r.postCommitments[0] = keccak256("runtime/v2");
        r.opsMask = opBit(0, OP_REPAIR) | opBit(1, OP_CLEAN);
        submit(r);
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(h.stateVersion, 2, "version advanced");
        assertEq(h.root, reg.computeRoot(r.postCommitments), "root updated");
        assertEq(reg.rootAt(AGENT, 2), h.root, "rootAt(2)");
        assertEq(reg.rootAt(AGENT, 1), reg.computeRoot(baseline()), "rootAt(1) kept");
        assertEq(reg.checkpointOf(AGENT, 0).lastChangedVersion, 2, "L1 changed at v2");
        assertEq(reg.checkpointOf(AGENT, 1).lastChangedVersion, 1, "L2 unchanged (completed, kept)");
        assertEq(reg.checkpointOf(AGENT, 1).lastCompletedAt, r.reportedEndedAt, "L2 completion recorded");
    }

    function test_report_staleBaseVersionRejected() public {
        IAgentMeditation.CycleReport memory a = baseReport(bit(0), bit(0));
        a.postCommitments[0] = keccak256("runtime/v2");
        // a second cycle computed against the same base, before the first lands
        IAgentMeditation.CycleReport memory b = baseReport(bit(3), bit(3));
        b.postCommitments[3] = keccak256("cognition/v2");
        submit(a);
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.BaseVersionMismatch.selector);
        reg.report(AGENT, b); // would overwrite on the basis of an outdated state
    }

    function test_report_preRootMismatchRejected() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.preRoot = keccak256("wrong");
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.PreRootMismatch.selector);
        reg.report(AGENT, r);
    }

    function test_report_unscopedLayerCannotChange() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.postCommitments[3] = keccak256("cognition/sneaky");
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.UnscopedLayerChanged.selector, uint8(3)));
        reg.report(AGENT, r);
    }

    function test_report_scopedButNotCompletedLayerMayChange() public {
        // partial modification followed by failure is recorded as what actually happened
        IAgentMeditation.CycleReport memory r = baseReport(bit(0) | bit(1), 0);
        r.outcome = uint8(IAgentMeditation.Outcome.FAILED);
        r.postCommitments[1] = keccak256("memory/half-written");
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 1).commitment, keccak256("memory/half-written"), "actual state registered");
        assertEq(reg.checkpointOf(AGENT, 1).lastCompletedAt, 0, "but not a completion");
        assertEq(reg.headOf(AGENT).stateVersion, 2, "version advanced by the change");
    }

    function test_report_replayOfNoChangeCycleRejectedByMonotonicCompletion() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        submit(r);
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.CompletionNotMonotonic.selector, uint8(0)));
        reg.report(AGENT, r); // identical report: same reportedEndedAt cannot be re-registered as a completion
    }

    // ------------------------------------------------------------------
    // Shape checks
    // ------------------------------------------------------------------

    function test_report_shape_emptyOrOutOfRangeMask() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.layerMask = 0;
        r.completedLayers = 0;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidLayerMask.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), bit(0));
        r.layerMask = 0x10;
        r.completedLayers = 0;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidLayerMask.selector);
        reg.report(AGENT, r);
    }

    function test_report_shape_completedMustBeSubsetOfScope() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.completedLayers = bit(0) | bit(2);
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidCompletedLayers.selector);
        reg.report(AGENT, r);
    }

    function test_report_shape_opsOutsideScopeRejected() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.opsMask = opBit(2, OP_UPDATE);
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidOpsMask.selector);
        reg.report(AGENT, r);
    }

    function test_report_shape_zeroOpsCompletionIsLegal() public {
        // checked, nothing to change
        IAgentMeditation.CycleReport memory r = baseReport(bit(2), bit(2));
        r.opsMask = 0;
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 2).lastCompletedAt, r.reportedEndedAt, "completion without changes");
    }

    function test_report_shape_outcomeConsistency() public {
        IAgentMeditation.CycleReport memory r;

        r = baseReport(bit(0) | bit(1), bit(0));
        r.outcome = uint8(IAgentMeditation.Outcome.COMPLETED); // but only one of two completed
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidOutcome.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0) | bit(1), bit(0) | bit(1));
        r.outcome = uint8(IAgentMeditation.Outcome.PARTIAL); // all completed is not partial
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidOutcome.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), 0);
        r.outcome = uint8(IAgentMeditation.Outcome.PARTIAL); // none completed is not partial
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidOutcome.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), bit(0));
        r.outcome = uint8(IAgentMeditation.Outcome.FAILED); // a completion is not a failure
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidOutcome.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), bit(0));
        r.outcome = uint8(IAgentMeditation.Outcome.ABORTED); // everything completed is not aborted
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidOutcome.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), bit(0));
        r.outcome = 7;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidOutcome.selector);
        reg.report(AGENT, r);

        // ABORTED with some completed layers is legal
        r = baseReport(bit(0) | bit(1) | bit(2), bit(0));
        r.outcome = uint8(IAgentMeditation.Outcome.ABORTED);
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 0).lastCompletedAt, r.reportedEndedAt, "L1 completed within an aborted cycle");
        assertEq(reg.checkpointOf(AGENT, 1).lastCompletedAt, 0, "L2 not completed");
    }

    function test_report_shape_triggerRange() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.trigger = 4;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidTrigger.selector);
        reg.report(AGENT, r);
    }

    // ------------------------------------------------------------------
    // Time
    // ------------------------------------------------------------------

    function test_report_timeOrder() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.reportedEndedAt = r.reportedStartedAt - 1;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidTimeOrder.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), bit(0));
        r.reportedEndedAt = uint48(block.timestamp) + 1; // the future
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidTimeOrder.selector);
        reg.report(AGENT, r);
    }

    function test_report_completionTimeMustNotGoBackwards() public {
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r1 = baseReport(bit(0), bit(0)); // ended at T0 + 1h59
        submit(r1);
        vm.warp(T0 + 4 * HOUR);
        IAgentMeditation.CycleReport memory late = baseReport(bit(0), bit(0));
        late.reportedStartedAt = T0 + 1 * HOUR;
        late.reportedEndedAt = T0 + 1 * HOUR + 30 minutes; // older than the registered completion
        vm.prank(AGENT);
        vm.expectRevert(abi.encodeWithSelector(AgentMeditationRegistry.CompletionNotMonotonic.selector, uint8(0)));
        reg.report(AGENT, late);
    }

    function test_report_lateSubmissionKeepsItsReportedCompletionTime() public {
        // a cycle that ended 20 hours ago and is submitted now counts from its reported end, not from now
        vm.warp(T0 + 23 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.reportedStartedAt = T0 + 2 * HOUR;
        r.reportedEndedAt = T0 + 3 * HOUR;
        submit(r);
        IAgentMeditation.LayerCheckpoint memory cp = reg.checkpointOf(AGENT, 0);
        assertEq(cp.lastCompletedAt, T0 + 3 * HOUR, "reported completion kept");
        assertEq(cp.lastCompletedRecordedAt, T0 + 23 * HOUR, "recording time kept separately");
        assertEq(deadline(0), T0 + 3 * HOUR + 1 * DAY, "deadline follows the reported completion");
    }

    // ------------------------------------------------------------------
    // Governing policy version
    // ------------------------------------------------------------------

    function test_report_policyVersionMustGovernStartTime() public {
        vm.warp(T0 + 1 * HOUR);
        IAgentMeditation.Policy memory p2 = defaultPolicy();
        p2.policyHash = keccak256("policy/v2");
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p2); // v2 effective from T0 + 1h

        vm.warp(T0 + 2 * HOUR);
        // cycle started under v1 (before v2 took effect) and reports under v1: accepted
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.policyVersion = 1;
        r.reportedStartedAt = T0 + 30 minutes;
        r.reportedEndedAt = T0 + 90 minutes;
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 0).completedUnderPolicy, 1, "completed under v1");

        // cycle started after v2 took effect cannot claim v1
        IAgentMeditation.CycleReport memory r2 = baseReport(bit(1), bit(1));
        r2.policyVersion = 1;
        r2.reportedStartedAt = T0 + 1 * HOUR; // exactly when v2 took effect: v2 governs
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.PolicyVersionNotGoverning.selector);
        reg.report(AGENT, r2);

        // cycle started before v2 cannot claim v2
        IAgentMeditation.CycleReport memory r3 = baseReport(bit(1), bit(1));
        r3.policyVersion = 2;
        r3.reportedStartedAt = T0 + 30 minutes;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.PolicyVersionNotGoverning.selector);
        reg.report(AGENT, r3);

        // unknown versions
        IAgentMeditation.CycleReport memory r4 = baseReport(bit(1), bit(1));
        r4.policyVersion = 0;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.PolicyVersionNotGoverning.selector);
        reg.report(AGENT, r4);
        r4.policyVersion = 3;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.PolicyVersionNotGoverning.selector);
        reg.report(AGENT, r4);
    }

    function test_report_governingPolicyDecidesSupportedLayersAndTriggers() public {
        IAgentMeditation.Policy memory p = defaultPolicy();
        p.supportedLayers = 0x07;
        p.requiredLayers = 0x07;
        p.allowedTriggers = uint8(1) << TRIGGER_SCHEDULED;
        vm.warp(T0 + 1);
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p);
        vm.warp(T0 + 1 * HOUR);

        IAgentMeditation.CycleReport memory r = baseReport(bit(3), bit(3));
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.LayerNotSupported.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), bit(0));
        r.trigger = TRIGGER_SELF;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, r);

        r = baseReport(bit(0), bit(0));
        r.trigger = TRIGGER_SCHEDULED;
        submit(r);
    }

    // ------------------------------------------------------------------
    // Rollback
    // ------------------------------------------------------------------

    function test_report_rollbackIsANewVersionThatRestoresAnOldRoot() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(1), bit(1));
        r.postCommitments[1] = keccak256("memory/v2");
        submit(r); // version 2

        vm.warp(T0 + 1 * HOUR);
        IAgentMeditation.CycleReport memory back = baseReport(bit(1), bit(1));
        back.postCommitments[1] = C1; // restore the baseline memory state
        back.restoresVersion = 1;
        back.opsMask = opBit(1, OP_REPAIR);
        submit(back);
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(h.stateVersion, 3, "rollback appends a version");
        assertEq(h.root, reg.rootAt(AGENT, 1), "root equals version 1");
        assertEq(reg.rootAt(AGENT, 2), reg.computeRoot(r.postCommitments), "history kept");
    }

    function test_report_rollbackClaimMustMatchHistory() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(1), bit(1));
        r.postCommitments[1] = keccak256("memory/v2");
        submit(r); // version 2

        vm.warp(T0 + 1 * HOUR);
        IAgentMeditation.CycleReport memory bad = baseReport(bit(1), bit(1));
        bad.postCommitments[1] = keccak256("memory/v3");
        bad.restoresVersion = 1; // claims to restore v1 but does not
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidRestore.selector);
        reg.report(AGENT, bad);

        bad.restoresVersion = 2; // current version is not an earlier version
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.InvalidRestore.selector);
        reg.report(AGENT, bad);
    }

    // ------------------------------------------------------------------
    // Pulse
    // ------------------------------------------------------------------

    function test_pulse_updatesSignalOnly() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        submit(r);
        IAgentMeditation.Head memory h0 = reg.headOf(AGENT);
        IAgentMeditation.LayerCheckpoint memory cp0 = reg.checkpointOf(AGENT, 0);

        vm.warp(T0 + 5 * HOUR);
        vm.prank(AGENT);
        uint64 seq = reg.pulse(AGENT, T0 + 6 * HOUR);
        IAgentMeditation.Head memory h1 = reg.headOf(AGENT);
        assertEq(seq, 2, "pulse counted as a record");
        assertEq(h1.recordCount, 2, "record count");
        assertEq(h1.lastSignalAt, T0 + 5 * HOUR, "signal refreshed");
        assertEq(h1.nextPlannedAt, T0 + 6 * HOUR, "planning hint");
        assertEq(h1.stateVersion, h0.stateVersion, "state version untouched");
        assertEq(h1.root, h0.root, "root untouched");
        IAgentMeditation.LayerCheckpoint memory cp0After = reg.checkpointOf(AGENT, 0);
        assertEq(cp0After.lastCompletedAt, cp0.lastCompletedAt, "maintenance time untouched");
        assertEq(cp0After.lastCompletedRecordedAt, cp0.lastCompletedRecordedAt, "recording time untouched");
        assertEq(cp0After.commitment, cp0.commitment, "commitment untouched");
    }

    function test_pulse_doesNotExtendAnyDeadline() public {
        uint48 d0 = deadline(0);
        vm.warp(T0 + 20 * HOUR);
        vm.prank(AGENT);
        reg.pulse(AGENT, 0);
        assertEq(deadline(0), d0, "deadline unchanged by pulse");
        vm.warp(T0 + 1 * DAY);
        assertTrue(status(0) == IAgentMeditation.MaintenanceStatus.OVERDUE, "overdue despite pulses");
    }

    // ------------------------------------------------------------------
    // Authorization of records
    // ------------------------------------------------------------------

    function test_report_authorization() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.report(AGENT, r);

        vm.prank(CONTROLLER); // a controller does not meditate for the subject
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.report(AGENT, r);

        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_PULSE);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.report(AGENT, r); // pulse permission is not report permission

        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT);
        vm.prank(OPERATOR);
        reg.report(AGENT, r); // attributed to the subject
        assertEq(reg.checkpointOf(AGENT, 0).lastCompletedAt, r.reportedEndedAt, "operator submission registered");
    }

    function test_pulse_authorization() public {
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.pulse(AGENT, 0);
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_POLICY);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.pulse(AGENT, 0);
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT);
        vm.prank(OPERATOR);
        reg.pulse(AGENT, 0); // report permission includes pulse
    }

    function test_report_notEnrolledSubject() public {
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.NotEnrolled.selector);
        reg.report(STRANGER, r);
    }
}
