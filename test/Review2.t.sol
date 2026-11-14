// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {IAgentMeditationStart} from "../assets/erc-agent-meditation/contracts/IAgentMeditationStart.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

/// @dev Cases from the third Magicians review round (topic 30304, posts 8 and 9): the current-version check on
///      records under a superseded policy version, the two observations about revision 3, and the recorded-start
///      extension with the attacks on it.
contract Review2Test is Harness {
    address internal constant OPERATOR_B = address(0x0B2);

    function setUp() public override {
        super.setUp();
        enrollDefault();
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT);
    }

    /// @dev Version 2 at the current block: SCHEDULED trigger only, all layers kept.
    function _tightenToScheduledOnly(address by) internal returns (uint48 tightenedAt) {
        IAgentMeditation.Policy memory p2 = defaultPolicy();
        p2.policyHash = keccak256("policy/v2-scheduled-only");
        p2.allowedTriggers = uint8(1) << TRIGGER_SCHEDULED;
        tightenedAt = uint48(block.timestamp);
        vm.prank(by);
        reg.setPolicy(AGENT, p2);
    }

    /// @dev A SELF cycle on layer 0 claiming version 1 with the given reported times.
    function _selfUnderV1(uint48 startedAt, uint48 endedAt) internal view returns (IAgentMeditation.CycleReport memory r) {
        r = baseReport(bit(0), bit(0));
        r.policyVersion = 1;
        r.trigger = TRIGGER_SELF;
        r.reportedStartedAt = startedAt;
        r.reportedEndedAt = endedAt;
    }

    function _openStart() internal view returns (uint48 at, address by) {
        (at, by) = reg.openStartOf(AGENT);
    }

    // ------------------------------------------------------------------
    // (a) current-version check
    // ------------------------------------------------------------------

    function test_review2_backdatedSelfCycleInTheGapIsRejected() public {
        vm.warp(T0 + 1 * HOUR);
        uint48 tightenedAt = _tightenToScheduledOnly(AGENT);
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = _selfUnderV1(tightenedAt - 1, T0 + 90 minutes);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, r);
    }

    function test_review2_backdatedCycleOnADroppedLayerIsRejected() public {
        vm.warp(T0 + 1 * HOUR);
        IAgentMeditation.Policy memory p2 = defaultPolicy();
        p2.supportedLayers = 0x07;
        p2.requiredLayers = 0x07;
        vm.prank(AGENT);
        reg.setPolicy(AGENT, p2);
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(3), bit(3));
        r.policyVersion = 1;
        r.reportedStartedAt = T0 + 30 minutes;
        r.reportedEndedAt = T0 + 90 minutes;
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.LayerNotSupported.selector);
        reg.report(AGENT, r);
    }

    function test_review2_lateRecordThatFitsBothVersionsKeepsItsAgeAndVersion() public {
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly(AGENT);
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.policyVersion = 1;
        r.trigger = TRIGGER_SCHEDULED; // allowed by both versions
        r.reportedStartedAt = T0 + 20 minutes;
        r.reportedEndedAt = T0 + 40 minutes;
        vm.prank(OPERATOR);
        reg.report(AGENT, r);
        IAgentMeditation.LayerCheckpoint memory cp = reg.checkpointOf(AGENT, 0);
        assertEq(cp.completedUnderPolicy, 1, "governed by version 1");
        assertEq(cp.lastCompletedAt, T0 + 40 minutes, "keeps its reported age");
        assertEq(cp.lastCompletedRecordedAt, T0 + 2 * HOUR, "recorded now");
    }

    function test_review2_gapAdmitsSeveralLateRecordsButNoForbiddenContent() public {
        // observation 1: the gap is bounded in time, not in the number of records; three sequential late
        // records that fit both versions are accepted, a fourth that uses the forbidden trigger is not
        vm.warp(T0 + 1 * HOUR);
        uint48 tightenedAt = _tightenToScheduledOnly(AGENT);
        vm.warp(T0 + 2 * HOUR);
        for (uint48 k = 0; k < 3; k++) {
            IAgentMeditation.CycleReport memory r = baseReport(bit(1), bit(1));
            r.policyVersion = 1;
            r.reportedStartedAt = T0 + 10 minutes + k * 10 minutes;
            r.reportedEndedAt = T0 + 15 minutes + k * 10 minutes;
            r.postCommitments[1] = keccak256(abi.encode("memory", k));
            vm.prank(OPERATOR);
            reg.report(AGENT, r);
        }
        assertEq(reg.headOf(AGENT).stateVersion, 4, "three late records, three state versions");
        IAgentMeditation.CycleReport memory bad = _selfUnderV1(T0 + 40 minutes, tightenedAt - 1);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, bad);
    }

    function test_review2_zeroLengthRecordSealsTheGap() public {
        // observation 2: a zero-length FAILED record under the new version moves lastCycleEndedAt to the
        // change, after which no start can be placed before it; the cost is one FAILED record in the history
        vm.warp(T0 + 1 * HOUR);
        uint48 tightenedAt = _tightenToScheduledOnly(AGENT);
        IAgentMeditation.CycleReport memory seal = baseReport(bit(0), 0);
        seal.policyVersion = 2;
        seal.reportedStartedAt = tightenedAt;
        seal.reportedEndedAt = tightenedAt;
        submit(seal);
        assertEq(reg.headOf(AGENT).lastCycleEndedAt, tightenedAt, "sealed at the change");
        assertEq(reg.checkpointOf(AGENT, 0).lastCompletedAt, 0, "a FAILED record completes nothing");

        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = baseReport(bit(0), bit(0));
        r.policyVersion = 1;
        r.reportedStartedAt = tightenedAt - 1;
        r.reportedEndedAt = T0 + 90 minutes;
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.StartBeforePreviousCycle.selector);
        reg.report(AGENT, r);
    }

    function test_review2_threeVersionsAcceptedLimit() public {
        // version 3 allows the SELF trigger again; an unpinned record may then claim version 1 for a start in
        // the gap, because the property promised is only that what is accepted fits the version in force now
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly(AGENT);
        vm.warp(T0 + 2 * HOUR);
        vm.prank(AGENT);
        reg.setPolicy(AGENT, defaultPolicy()); // version 3
        vm.warp(T0 + 3 * HOUR);
        IAgentMeditation.CycleReport memory r = _selfUnderV1(T0 + 30 minutes, T0 + 50 minutes);
        vm.prank(OPERATOR);
        reg.report(AGENT, r);
        assertEq(reg.checkpointOf(AGENT, 0).completedUnderPolicy, 1, "claims version 1, visibly");
    }

    // ------------------------------------------------------------------
    // (b) recorded start
    // ------------------------------------------------------------------

    function test_review2_cycleInFlightAtTheChangeKeepsItsPin() public {
        vm.warp(T0 + 30 minutes);
        vm.prank(AGENT);
        uint48 startedAt = reg.begin(AGENT);
        assertEq(startedAt, T0 + 30 minutes, "start recorded at the clock");
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly(AGENT); // the subject's own start survives its own change
        (uint48 at, address by) = _openStart();
        assertEq(at, startedAt, "still open");
        assertEq(by, AGENT, "held by the subject");

        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = _selfUnderV1(startedAt, T0 + 90 minutes);
        submit(r);
        assertEq(reg.checkpointOf(AGENT, 0).completedUnderPolicy, 1, "governed by the version at the start");
        (at,) = _openStart();
        assertEq(at, 0, "the pinned record consumed the start");
    }

    function test_review2_reportedStartMustEqualTheRecordedStartAndComeFromItsRecorder() public {
        vm.warp(T0 + 30 minutes);
        vm.prank(AGENT);
        uint48 startedAt = reg.begin(AGENT);
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly(AGENT);
        vm.warp(T0 + 2 * HOUR);

        // one second off the recorded start: not pinned, so the current-version check applies
        IAgentMeditation.CycleReport memory off = _selfUnderV1(startedAt + 1, T0 + 90 minutes);
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, off);

        // the exact start, but from an operator that did not record it: not pinned either
        IAgentMeditation.CycleReport memory borrowed = _selfUnderV1(startedAt, T0 + 90 minutes);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, borrowed);

        (uint48 at,) = _openStart();
        assertEq(at, startedAt, "rejected records leave the start open");
    }

    function test_review2_startRecordedAtTheChangeIsUnderTheNewVersion() public {
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly(AGENT);
        vm.prank(AGENT);
        uint48 startedAt = reg.begin(AGENT); // same second as the change
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = _selfUnderV1(startedAt, T0 + 90 minutes);
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.PolicyVersionNotGoverning.selector);
        reg.report(AGENT, r); // version 1 was no longer in effect at the start
        r.policyVersion = 2;
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, r); // and version 2 forbids the trigger; the pin changes nothing here
    }

    function test_review2_oneRecordedStartPinsOneCycleOnly() public {
        vm.warp(T0 + 30 minutes);
        vm.prank(AGENT);
        uint48 startedAt = reg.begin(AGENT);
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly(AGENT);
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory first = _selfUnderV1(startedAt, startedAt); // zero-length, pinned
        first.completedLayers = 0;
        first.outcome = uint8(IAgentMeditation.Outcome.FAILED);
        submit(first);
        // the same start again: the ordering rule still allows it (start == lastCycleEndedAt), the pin is gone
        IAgentMeditation.CycleReport memory second = _selfUnderV1(startedAt, T0 + 90 minutes);
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, second);
    }

    function test_review2_beginRequiresReportPermission() public {
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.begin(AGENT);
        vm.prank(AGENT);
        reg.setOperator(OPERATOR_B, PERM_PULSE);
        vm.prank(OPERATOR_B);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.begin(AGENT);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.NotEnrolled.selector);
        reg.begin(STRANGER);
        vm.prank(OPERATOR);
        reg.begin(AGENT);
        (, address by) = _openStart();
        assertEq(by, OPERATOR, "operator with report permission may begin");
    }

    function test_review2_subjectOrRecorderCancelsAStart() public {
        vm.prank(AGENT);
        vm.expectRevert(AgentMeditationRegistry.NoOpenStart.selector);
        reg.cancelStart(AGENT);

        vm.prank(OPERATOR);
        reg.begin(AGENT);
        vm.prank(STRANGER);
        vm.expectRevert(AgentMeditationRegistry.Unauthorized.selector);
        reg.cancelStart(AGENT);
        vm.expectEmit(true, false, false, true);
        emit IAgentMeditationStart.StartVoided(AGENT, T0, OPERATOR);
        vm.prank(OPERATOR);
        reg.cancelStart(AGENT); // the recorder voids its own start

        vm.warp(T0 + 10 minutes);
        vm.prank(OPERATOR);
        reg.begin(AGENT);
        vm.prank(AGENT);
        reg.cancelStart(AGENT); // the subject voids any start
        (uint48 at,) = _openStart();
        assertEq(at, 0, "cleared");
    }

    function test_review2_startHeldByAnOperatorDoesNotSurviveTheSubjectsChange() public {
        vm.warp(T0 + 30 minutes);
        vm.prank(OPERATOR);
        uint48 startedAt = reg.begin(AGENT);
        vm.warp(T0 + 1 * HOUR);
        vm.expectEmit(true, false, false, true);
        emit IAgentMeditationStart.StartVoided(AGENT, startedAt, AGENT);
        _tightenToScheduledOnly(AGENT);
        (uint48 at,) = _openStart();
        assertEq(at, 0, "voided by the change");
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory r = _selfUnderV1(startedAt, T0 + 90 minutes);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.TriggerNotAllowed.selector);
        reg.report(AGENT, r);
    }

    function test_review2_startSurvivesAChangeByItsRecorderOrBySubject() public {
        // an operator that holds policy permission changes the policy itself: its own start survives
        vm.prank(AGENT);
        reg.setOperator(OPERATOR, PERM_REPORT | PERM_POLICY);
        vm.warp(T0 + 30 minutes);
        vm.prank(OPERATOR);
        uint48 startedAt = reg.begin(AGENT);
        vm.warp(T0 + 1 * HOUR);
        _tightenToScheduledOnly(OPERATOR);
        (uint48 at, address by) = _openStart();
        assertEq(at, startedAt, "survives the recorder's own change");
        assertEq(by, OPERATOR, "still the operator's");

        // the subject's start survives a change made by an operator with policy permission
        vm.prank(AGENT);
        reg.begin(AGENT); // replaces the operator's start
        vm.warp(T0 + 2 * HOUR);
        vm.prank(OPERATOR);
        reg.setPolicy(AGENT, defaultPolicy());
        (at, by) = _openStart();
        assertEq(at, T0 + 1 * HOUR, "the subject's start is kept");
        assertEq(by, AGENT, "held by the subject");

        // a start of one operator does not survive a change by another operator
        vm.prank(AGENT);
        reg.setOperator(OPERATOR_B, PERM_POLICY);
        vm.prank(AGENT);
        reg.cancelStart(AGENT);
        vm.prank(OPERATOR);
        reg.begin(AGENT);
        vm.prank(OPERATOR_B);
        reg.setPolicy(AGENT, defaultPolicy());
        (at,) = _openStart();
        assertEq(at, 0, "voided by another account's change");
    }

    function test_review2_operatorCannotReplaceTheSubjectsStartButTheSubjectReplacesAny() public {
        vm.prank(AGENT);
        uint48 subjectStart = reg.begin(AGENT);
        vm.warp(T0 + 10 minutes);
        vm.prank(OPERATOR);
        vm.expectRevert(AgentMeditationRegistry.StartHeldByAnother.selector);
        reg.begin(AGENT);
        (uint48 at, address by) = _openStart();
        assertEq(at, subjectStart, "unchanged");
        assertEq(by, AGENT, "unchanged");

        vm.prank(AGENT);
        reg.cancelStart(AGENT);
        vm.prank(OPERATOR);
        uint48 operatorStart = reg.begin(AGENT);
        vm.warp(T0 + 20 minutes);
        vm.prank(OPERATOR);
        reg.begin(AGENT); // the recorder may replace its own start
        vm.expectEmit(true, false, false, true);
        emit IAgentMeditationStart.CycleBegun(AGENT, T0 + 20 minutes, T0 + 20 minutes, AGENT);
        vm.prank(AGENT);
        reg.begin(AGENT); // and the subject replaces an operator's start
        (at, by) = _openStart();
        assertEq(by, AGENT, "now the subject's");
        assertTrue(operatorStart < at, "replaced by a later start");
    }

    function test_review2_laterCycleRecordClosesTheStartAndEarlierOneDoesNot() public {
        vm.warp(T0 + 1 * HOUR);
        vm.prank(AGENT);
        uint48 startedAt = reg.begin(AGENT);

        // a late record of a cycle that ended before the start leaves the start open
        vm.warp(T0 + 2 * HOUR);
        IAgentMeditation.CycleReport memory earlier = baseReport(bit(1), bit(1));
        earlier.reportedStartedAt = T0 + 20 minutes;
        earlier.reportedEndedAt = T0 + 40 minutes;
        submit(earlier);
        (uint48 at,) = _openStart();
        assertEq(at, startedAt, "a cycle that ended before the start does not touch it");

        // a record whose end is after the start makes the start unusable under the ordering rule; it is cleared
        IAgentMeditation.CycleReport memory later = baseReport(bit(2), bit(2));
        later.reportedStartedAt = T0 + 70 minutes;
        later.reportedEndedAt = T0 + 80 minutes;
        vm.expectEmit(true, false, false, true);
        emit IAgentMeditationStart.StartVoided(AGENT, startedAt, AGENT);
        submit(later);
        (at,) = _openStart();
        assertEq(at, 0, "cleared by the later cycle");
    }

    function test_review2_beginChangesNothingElse() public {
        IAgentMeditation.Head memory before = reg.headOf(AGENT);
        vm.warp(T0 + 1 * HOUR);
        vm.expectEmit(true, false, false, true);
        emit IAgentMeditationStart.CycleBegun(AGENT, T0 + 1 * HOUR, 0, AGENT);
        vm.prank(AGENT);
        reg.begin(AGENT);
        IAgentMeditation.Head memory after_ = reg.headOf(AGENT);
        assertEq(after_.recordCount, before.recordCount, "not a record");
        assertEq(after_.lastSignalAt, before.lastSignalAt, "not an activity signal");
        assertEq(after_.stateVersion, before.stateVersion, "no state change");
        assertEq(after_.lastCycleEndedAt, before.lastCycleEndedAt, "no ordering change");
        assertTrue(reg.supportsInterface(type(IAgentMeditationStart).interfaceId), "extension reported");
    }
}
