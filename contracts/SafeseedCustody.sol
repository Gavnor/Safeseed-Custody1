// contracts/SafeseedCustody.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SafeseedCustody
 * @dev Enhanced custody contract that works with Gnosis Safe
 * Provides security features like time locks, spending limits, and emergency controls
 */
contract SafeseedCustody is ReentrancyGuard, Ownable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // Events
    event CustodyCreated(address indexed safe, address indexed creator, uint256 timestamp);
    event TimeLockSet(address indexed safe, uint256 delay);
    event SpendingLimitSet(address indexed safe, address indexed token, uint256 limit, uint256 period);
    event EmergencyFreeze(address indexed safe, address indexed freezer, uint256 timestamp);
    event EmergencyUnfreeze(address indexed safe, address indexed unfreezer, uint256 timestamp);
    event RecoveryInitiated(address indexed safe, address indexed initiator, uint256 timestamp);
    event RecoveryExecuted(address indexed safe, address indexed executor, uint256 timestamp);
    event TransactionProposed(address indexed safe, bytes32 indexed txHash, uint256 executeTime);
    event TransactionExecuted(address indexed safe, bytes32 indexed txHash, bool success);
    event EmergencyContactAdded(address indexed safe, address indexed contact);
    event EmergencyContactRemoved(address indexed safe, address indexed contact);

    // Structs
    struct SpendingLimit {
        uint256 limit;
        uint256 spent;
        uint256 resetTime;
        uint256 period;
    }

    struct TimeLockTransaction {
        address to;
        uint256 value;
        bytes data;
        uint256 executeTime;
        bool executed;
        address proposer;
    }

    struct RecoveryRequest {
        address newOwner;
        uint256 initiatedAt;
        uint256 executionTime;
        bool executed;
        mapping(address => bool) approvals;
        uint256 approvalCount;
    }

    struct CustodyInfo {
        bool exists;
        bool frozen;
        uint256 timeLock;
        uint256 lastActivity;
        address[] emergencyContacts;
        mapping(address => SpendingLimit) spendingLimits;
        mapping(bytes32 => TimeLockTransaction) pendingTransactions;
    }

    // State variables
    mapping(address => CustodyInfo) public custodies;
    mapping(address => RecoveryRequest) public recoveryRequests;
    mapping(address => mapping(address => bool)) public authorizedCallers;

    uint256 public constant RECOVERY_DELAY = 7 days;
    uint256 public constant MAX_EMERGENCY_CONTACTS = 5;
    uint256 public constant MIN_TIMELOCK = 1 hours;
    uint256 public constant MAX_TIMELOCK = 30 days;

    // Modifiers
    modifier onlyValidCustody(address safe) {
        require(custodies[safe].exists, "Custody does not exist");
        _;
    }

    modifier notFrozen(address safe) {
        require(!custodies[safe].frozen, "Custody is frozen");
        _;
    }

    modifier onlyEmergencyContact(address safe) {
        require(isEmergencyContact(safe, msg.sender), "Not an emergency contact");
        _;
    }

    modifier onlyAuthorized(address safe) {
        require(authorizedCallers[safe][msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    // --- Core Functions ---

    function initializeCustody(
        address safe,
        uint256 timeLock,
        address[] calldata emergencyContacts
    ) external onlyOwner {
        require(!custodies[safe].exists, "Custody already exists");
        require(timeLock >= MIN_TIMELOCK && timeLock <= MAX_TIMELOCK, "Invalid time lock");

        CustodyInfo storage info = custodies[safe];
        info.exists = true;
        info.timeLock = timeLock;
        info.lastActivity = block.timestamp;

        for (uint256 i = 0; i < emergencyContacts.length; i++) {
            require(emergencyContacts[i] != address(0), "Invalid contact");
            info.emergencyContacts.push(emergencyContacts[i]);
        }

        emit CustodyCreated(safe, msg.sender, block.timestamp);
    }

    function setSpendingLimit(
        address safe,
        address token,
        uint256 limit,
        uint256 period
    ) external onlyAuthorized(safe) onlyValidCustody(safe) {
        custodies[safe].spendingLimits[token] = SpendingLimit({
            limit: limit,
            spent: 0,
            resetTime: block.timestamp + period,
            period: period
        });

        emit SpendingLimitSet(safe, token, limit, period);
    }

    function checkSpendingLimit(
        address safe,
        address token,
        uint256 amount
    ) external view returns (bool) {
        SpendingLimit memory limit = custodies[safe].spendingLimits[token];
        if (limit.limit == 0) return true;

        uint256 spent = limit.spent;
        if (block.timestamp > limit.resetTime) {
            spent = 0;
        }

        return spent + amount <= limit.limit;
    }

    function updateSpending(
        address safe,
        address token,
        uint256 amount
    ) external onlyAuthorized(safe) onlyValidCustody(safe) {
        SpendingLimit storage limit = custodies[safe].spendingLimits[token];
        if (block.timestamp > limit.resetTime) {
            limit.spent = amount;
            limit.resetTime = block.timestamp + limit.period;
        } else {
            limit.spent += amount;
        }
    }

    function emergencyFreeze(address safe) external onlyEmergencyContact(safe) onlyValidCustody(safe) {
        custodies[safe].frozen = true;
        emit EmergencyFreeze(safe, msg.sender, block.timestamp);
    }

    function emergencyUnfreeze(address safe) external onlyEmergencyContact(safe) onlyValidCustody(safe) {
        custodies[safe].frozen = false;
        emit EmergencyUnfreeze(safe, msg.sender, block.timestamp);
    }

    function proposeTimeLockTransaction(
        address safe,
        address to,
        uint256 value,
        bytes memory data
    ) external onlyAuthorized(safe) onlyValidCustody(safe) notFrozen(safe) returns (bytes32) {
        uint256 executeTime = block.timestamp + custodies[safe].timeLock;
        bytes32 txHash = keccak256(abi.encodePacked(safe, to, value, data, executeTime, block.number));

        custodies[safe].pendingTransactions[txHash] = TimeLockTransaction({
            to: to,
            value: value,
            data: data,
            executeTime: executeTime,
            executed: false,
            proposer: msg.sender
        });

        emit TransactionProposed(safe, txHash, executeTime);
        return txHash;
    }

    function executeTimeLockTransaction(
        address safe,
        bytes32 txHash
    ) external onlyAuthorized(safe) onlyValidCustody(safe) notFrozen(safe) nonReentrant returns (bool) {
        TimeLockTransaction storage txn = custodies[safe].pendingTransactions[txHash];
        require(!txn.executed, "Already executed");
        require(block.timestamp >= txn.executeTime, "Time lock not expired");

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        txn.executed = true;

        emit TransactionExecuted(safe, txHash, success);
        return success;
    }

    function initiateRecovery(address safe, address newOwner) external onlyEmergencyContact(safe) onlyValidCustody(safe) {
        RecoveryRequest storage req = recoveryRequests[safe];
        require(req.initiatedAt == 0, "Already initiated");

        req.newOwner = newOwner;
        req.initiatedAt = block.timestamp;
        req.executionTime = block.timestamp + RECOVERY_DELAY;
        req.approvals[msg.sender] = true;
        req.approvalCount = 1;

        emit RecoveryInitiated(safe, msg.sender, block.timestamp);
    }

    function approveRecovery(address safe) external onlyEmergencyContact(safe) onlyValidCustody(safe) {
        RecoveryRequest storage req = recoveryRequests[safe];
        require(req.initiatedAt != 0, "No active request");
        require(!req.approvals[msg.sender], "Already approved");

        req.approvals[msg.sender] = true;
        req.approvalCount += 1;
    }

    function executeRecovery(address safe) external onlyEmergencyContact(safe) onlyValidCustody(safe) {
        RecoveryRequest storage req = recoveryRequests[safe];
        require(block.timestamp >= req.executionTime, "Delay not met");
        require(!req.executed, "Already executed");
        require(req.approvalCount >= 2, "Not enough approvals");

        req.executed = true;
        transferOwnership(req.newOwner);

        emit RecoveryExecuted(safe, msg.sender, block.timestamp);
    }

    function updateTimeLock(address safe, uint256 newDelay) external onlyAuthorized(safe) onlyValidCustody(safe) {
        require(newDelay >= MIN_TIMELOCK && newDelay <= MAX_TIMELOCK, "Invalid delay");
        custodies[safe].timeLock = newDelay;

        emit TimeLockSet(safe, newDelay);
    }

    function addEmergencyContact(address safe, address contact) external onlyAuthorized(safe) onlyValidCustody(safe) {
        require(custodies[safe].emergencyContacts.length < MAX_EMERGENCY_CONTACTS, "Max contacts reached");
        custodies[safe].emergencyContacts.push(contact);

        emit EmergencyContactAdded(safe, contact);
    }

    function removeEmergencyContact(address safe, address contact) external onlyAuthorized(safe) onlyValidCustody(safe) {
        address[] storage contacts = custodies[safe].emergencyContacts;
        for (uint256 i = 0; i < contacts.length; i++) {
            if (contacts[i] == contact) {
                contacts[i] = contacts[contacts.length - 1];
                contacts.pop();
                emit EmergencyContactRemoved(safe, contact);
                break;
            }
        }
    }

    function addAuthorizedCaller(address safe, address caller) external onlyOwner {
        authorizedCallers[safe][caller] = true;
    }

    function removeAuthorizedCaller(address safe, address caller) external onlyOwner {
        authorizedCallers[safe][caller] = false;
    }

    function isEmergencyContact(address safe, address contact) public view returns (bool) {
        address[] memory contacts = custodies[safe].emergencyContacts;
        for (uint256 i = 0; i < contacts.length; i++) {
            if (contacts[i] == contact) return true;
        }
        return false;
    }

    /// @dev Allow receiving ETH
    receive() external payable {}
}
