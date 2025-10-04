// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SafeseedCustody.sol";

interface IGnosisSafe {
    function isOwner(address owner) external view returns (bool);
    function enableModule(address module) external;
    function disableModule(address prevModule, address module) external;
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external returns (bool success);
}

contract SafeseedIntegration is ReentrancyGuard, Ownable {
    event DebugRegisterSafe(address safe, uint256 timeLock, address[] emergencyContacts);
    event DebugCustodyAddress(address custody);
    using SafeERC20 for IERC20;

    SafeseedCustody public immutable custody;

    mapping(address => bool) public registeredSafes;

    event SafeRegistered(address indexed safe, address indexed user);
    event ModuleEnabled(address indexed safe);
    event ModuleDisabled(address indexed safe);

    constructor(address _custody) {
        emit DebugCustodyAddress(_custody);
        require(_custody != address(0), "Invalid custody");
        custody = SafeseedCustody(payable(_custody));
    }

    function registerSafe(
        address safe,
        uint256 timeLock,
        address[] calldata emergencyContacts
    ) external {
    emit DebugRegisterSafe(safe, timeLock, emergencyContacts);
    require(!registeredSafes[safe], "Already registered");
    require(IGnosisSafe(safe).isOwner(msg.sender), "Not a Safe owner");

    custody.initializeCustody(safe, timeLock, emergencyContacts);
    custody.addAuthorizedCaller(safe, address(this));
    registeredSafes[safe] = true;

    emit SafeRegistered(safe, msg.sender);
    }

    function setSpendingLimit(
        address safe,
        address token,
        uint256 limit,
        uint256 period
    ) external {
        require(registeredSafes[safe], "Not registered");
        require(IGnosisSafe(safe).isOwner(msg.sender), "Not a Safe owner");

        custody.setSpendingLimit(safe, token, limit, period);
    }

    function updateTimeLock(address safe, uint256 newDelay) external {
        require(registeredSafes[safe], "Not registered");
        require(IGnosisSafe(safe).isOwner(msg.sender), "Not a Safe owner");

        custody.updateTimeLock(safe, newDelay);
    }

    function addEmergencyContact(address safe, address contact) external {
        require(registeredSafes[safe], "Not registered");
        require(IGnosisSafe(safe).isOwner(msg.sender), "Not a Safe owner");

        custody.addEmergencyContact(safe, contact);
    }

    function removeEmergencyContact(address safe, address contact) external {
        require(registeredSafes[safe], "Not registered");
        require(IGnosisSafe(safe).isOwner(msg.sender), "Not a Safe owner");

        custody.removeEmergencyContact(safe, contact);
    }

    function enableModule(address safe) external {
        require(registeredSafes[safe], "Not registered");
        require(IGnosisSafe(safe).isOwner(msg.sender), "Not a Safe owner");

        IGnosisSafe(safe).enableModule(address(this));
        emit ModuleEnabled(safe);
    }

    function disableModule(address safe, address prevModule) external {
        require(registeredSafes[safe], "Not registered");
        require(IGnosisSafe(safe).isOwner(msg.sender), "Not a Safe owner");

        IGnosisSafe(safe).disableModule(prevModule, address(this));
        emit ModuleDisabled(safe);
    }

    // Emergency functions

    function emergencyFreeze(address safe) external {
        require(registeredSafes[safe], "Not registered");
        require(custody.isEmergencyContact(safe, msg.sender), "Not an emergency contact");
        custody.emergencyFreeze(safe);
    }

    function emergencyUnfreeze(address safe) external {
        require(registeredSafes[safe], "Not registered");
        require(custody.isEmergencyContact(safe, msg.sender), "Not an emergency contact");
        custody.emergencyUnfreeze(safe);
    }

    function initiateRecovery(address safe, address newOwner) external {
        require(registeredSafes[safe], "Not registered");
        require(custody.isEmergencyContact(safe, msg.sender), "Not an emergency contact");
        custody.initiateRecovery(safe, newOwner);
    }

    function approveRecovery(address safe) external {
        require(registeredSafes[safe], "Not registered");
        require(custody.isEmergencyContact(safe, msg.sender), "Not an emergency contact");
        custody.approveRecovery(safe);
    }

    function executeRecovery(address safe) external {
        require(registeredSafes[safe], "Not registered");
        custody.executeRecovery(safe);
    }

    function isSafeRegistered(address safe) external view returns (bool) {
        return registeredSafes[safe];
    }
}
