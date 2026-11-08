// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Harness} from "./Harness.sol";
import {IAgentMeditation} from "../assets/erc-agent-meditation/contracts/IAgentMeditation.sol";
import {AgentMeditationRegistry} from "../assets/erc-agent-meditation/contracts/AgentMeditationRegistry.sol";

/// @dev Cross-checks the JSON vectors produced by tools/vectors.js against the Solidity implementation,
///      and replays the worked example on the registry.
contract VectorsTest is Harness {
    string internal constant EXAMPLE = "assets/erc-agent-meditation/vectors/example-mcp-timeout.json";
    string internal constant IFACE = "assets/erc-agent-meditation/vectors/interface.json";

    function test_vectors_interfaceId() public view {
        string memory json = vm.readFile(IFACE);
        bytes memory raw = vm.parseJsonBytes(json, ".interfaceId");
        assertEq(raw.length, 4, "4-byte identifier");
        bytes4 expected = bytes4(raw);
        assertEq(bytes32(expected), bytes32(type(IAgentMeditation).interfaceId), "interface id matches tooling");
        assertTrue(reg.supportsInterface(expected), "registry reports the vector id");
    }

    function test_vectors_tagsAndCommitments() public view {
        string memory json = vm.readFile(EXAMPLE);
        assertEq(vm.parseJsonBytes32(json, ".tags.layerCommitment"), reg.TAG_LAYER_COMMITMENT(), "layer tag");
        assertEq(vm.parseJsonBytes32(json, ".tags.stateRoot"), reg.TAG_STATE_ROOT(), "root tag");

        bytes32[4] memory pre;
        bytes32[4] memory post;
        for (uint8 i = 0; i < 4; i++) {
            pre[i] = _checkLayer(json, ".pre.layers[", i);
            post[i] = _checkLayer(json, ".post.layers[", i);
        }
        assertEq(reg.computeRoot(pre), vm.parseJsonBytes32(json, ".pre.root"), "pre root");
        assertEq(reg.computeRoot(post), vm.parseJsonBytes32(json, ".post.root"), "post root");
    }

    function _checkLayer(string memory json, string memory prefix, uint8 i) internal view returns (bytes32 c) {
        string memory base = string.concat(prefix, _digit(i), "]");
        uint8 layer = uint8(vm.parseJsonUint(json, string.concat(base, ".layer")));
        bytes32 schemaHash = vm.parseJsonBytes32(json, string.concat(base, ".schemaHash"));
        bytes32 contentHash = vm.parseJsonBytes32(json, string.concat(base, ".contentHash"));
        bytes32 salt = vm.parseJsonBytes32(json, string.concat(base, ".salt"));
        string memory schemaId = vm.parseJsonString(json, string.concat(base, ".schemaId"));
        c = vm.parseJsonBytes32(json, string.concat(base, ".commitment"));
        assertEq(layer, i, "layer index");
        assertEq(keccak256(bytes(schemaId)), schemaHash, "schema hash is keccak256 of the schema id");
        assertEq(reg.computeLayerCommitment(layer, schemaHash, contentHash, salt), c, "commitment recomputed");
    }

    function test_vectors_workedExampleReplay() public {
        string memory json = vm.readFile(EXAMPLE);
        address subject = vm.parseJsonAddress(json, ".subject");
        assertEq(subject, AGENT, "example subject is the harness agent");

        // Policy from the vector
        IAgentMeditation.Policy memory p;
        p.policyHash = vm.parseJsonBytes32(json, ".policy.struct[0]");
        p.policyURI = vm.parseJsonString(json, ".policy.struct[1]");
        p.supportedLayers = uint8(vm.parseJsonUint(json, ".policy.struct[2]"));
        p.requiredLayers = uint8(vm.parseJsonUint(json, ".policy.struct[3]"));
        p.allowedTriggers = uint8(vm.parseJsonUint(json, ".policy.struct[4]"));
        p.disclosure = uint8(vm.parseJsonUint(json, ".policy.struct[5]"));
        p.dueWindow = uint48(vm.parseJsonUint(json, ".policy.struct[6]"));
        p.pulseInterval = uint48(vm.parseJsonUint(json, ".policy.struct[7]"));
        uint256[] memory intervals = vm.parseJsonUintArray(json, ".policy.struct[8]");
        for (uint8 i = 0; i < 4; i++) {
            p.maxInterval[i] = uint48(intervals[i]);
        }
        assertEq(p.policyHash, vm.parseJsonBytes32(json, ".policy.policyHash"), "policy hash");

        // Report from the vector
        IAgentMeditation.CycleReport memory r;
        r.baseVersion = uint64(vm.parseJsonUint(json, ".report[0]"));
        r.preRoot = vm.parseJsonBytes32(json, ".report[1]");
        bytes32[] memory posts = vm.parseJsonBytes32Array(json, ".report[2]");
        for (uint8 i = 0; i < 4; i++) {
            r.postCommitments[i] = posts[i];
        }
        r.layerMask = uint8(vm.parseJsonUint(json, ".report[3]"));
        r.completedLayers = uint8(vm.parseJsonUint(json, ".report[4]"));
        r.opsMask = uint16(vm.parseJsonUint(json, ".report[5]"));
        r.outcome = uint8(vm.parseJsonUint(json, ".report[6]"));
        r.trigger = uint8(vm.parseJsonUint(json, ".report[7]"));
        r.policyVersion = uint32(vm.parseJsonUint(json, ".report[8]"));
        r.reportedStartedAt = uint48(vm.parseJsonUint(json, ".report[9]"));
        r.reportedEndedAt = uint48(vm.parseJsonUint(json, ".report[10]"));
        r.nextPlannedAt = uint48(vm.parseJsonUint(json, ".report[11]"));
        r.restoresVersion = uint64(vm.parseJsonUint(json, ".report[12]"));
        r.recordHash = vm.parseJsonBytes32(json, ".report[13]");
        r.recordURI = vm.parseJsonString(json, ".report[14]");

        // Calldata produced by the tooling equals the ABI encoding of the parsed struct
        bytes memory expectedCalldata = vm.parseJsonBytes(json, ".calldata");
        assertEq(
            keccak256(abi.encodeWithSelector(reg.report.selector, subject, r)),
            keccak256(expectedCalldata),
            "calldata matches tooling"
        );

        // Replay: enroll with the pre state before the cycle started, then record the cycle after it ended
        bytes32[4] memory pre;
        for (uint8 i = 0; i < 4; i++) {
            pre[i] = vm.parseJsonBytes32(json, string.concat(".pre.layers[", _digit(i), "].commitment"));
        }
        vm.warp(r.reportedStartedAt - 600);
        vm.prank(AGENT);
        reg.enroll(pre, p, CONTROLLER, ALL_RIGHTS);
        assertEq(reg.headOf(AGENT).root, r.preRoot, "enrolled root is the pre root");

        vm.warp(r.reportedEndedAt + 300);
        vm.prank(AGENT);
        uint64 seq = reg.report(AGENT, r);
        assertEq(seq, 1, "first record");
        IAgentMeditation.Head memory h = reg.headOf(AGENT);
        assertEq(h.stateVersion, 2, "layers 0-2 changed: version 2");
        assertEq(h.root, vm.parseJsonBytes32(json, ".post.root"), "root is the post root");
        assertEq(h.nextPlannedAt, r.nextPlannedAt, "planning hint");
        uint8 expectedChanged = uint8(vm.parseJsonUint(json, ".summary.changedLayers"));
        assertEq(expectedChanged, 0x07, "layers 0-2 changed, layer 3 kept");
        for (uint8 i = 0; i < 4; i++) {
            IAgentMeditation.LayerCheckpoint memory cp = reg.checkpointOf(AGENT, i);
            assertEq(cp.commitment, r.postCommitments[i], "post commitment registered");
            assertEq(cp.lastCompletedAt, r.reportedEndedAt, "every layer completed its routine");
            assertEq(cp.lastChangedVersion, (expectedChanged & (1 << i)) != 0 ? 2 : 1, "change version");
        }
        assertEq(reg.rootAt(AGENT, 1), r.preRoot, "history: version 1");
        assertEq(reg.rootAt(AGENT, 2), h.root, "history: version 2");
    }

    function _digit(uint8 i) internal pure returns (string memory) {
        bytes memory b = new bytes(1);
        b[0] = bytes1(uint8(48 + i));
        return string(b);
    }
}
