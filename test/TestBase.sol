// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @dev Minimal Foundry cheatcode surface used by this repository's tests.
///      Kept local so the repository has no library dependency.
interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function expectEmit(bool, bool, bool, bool) external;
    function readFile(string calldata) external view returns (string memory);
    function parseJson(string calldata, string calldata) external pure returns (bytes memory);
    function parseJsonBytes32(string calldata, string calldata) external pure returns (bytes32);
    function parseJsonUint(string calldata, string calldata) external pure returns (uint256);
    function parseJsonString(string calldata, string calldata) external pure returns (string memory);
    function parseJsonBytes32Array(string calldata, string calldata) external pure returns (bytes32[] memory);
    function parseJsonUintArray(string calldata, string calldata) external pure returns (uint256[] memory);
    function parseJsonBytes(string calldata, string calldata) external pure returns (bytes memory);
    function parseJsonAddress(string calldata, string calldata) external pure returns (address);
    function label(address, string calldata) external;
    function snapshotState() external returns (uint256);
    function revertToState(uint256) external returns (bool);
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool v, string memory what) internal pure {
        require(v, what);
    }

    function assertEq(uint256 a, uint256 b, string memory what) internal pure {
        require(a == b, what);
    }

    function assertEq(bytes32 a, bytes32 b, string memory what) internal pure {
        require(a == b, what);
    }

    function assertEq(address a, address b, string memory what) internal pure {
        require(a == b, what);
    }

    function assertEq(bool a, bool b, string memory what) internal pure {
        require(a == b, what);
    }

    function assertEq(string memory a, string memory b, string memory what) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), what);
    }
}
