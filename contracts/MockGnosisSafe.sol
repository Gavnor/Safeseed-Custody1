// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockGnosisSafe {
    address public owner;
    constructor(address _owner) {
        owner = _owner;
    }
    function isOwner(address _owner) external view returns (bool) {
        return _owner == owner;
    }
}
