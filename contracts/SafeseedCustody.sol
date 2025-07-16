// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SafeseedCustody
 * @dev Enhanced custody contract designed to integrate with Gnosis Safe
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
        uint256 approvalCount;
        mapping(address => bool) approvals;
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

    // Constants
    uint256 public constant RECOVERY_DELAY = 7 days;
    uint256 public constant MAX_EMERGENCY_CONTACTS = 5;
    uint256 public constant MIN_TIMELOCK = 1 hours;
    uint256 public constant MAX_TIMELOCK = 30 days;

    // State variables
    mapping(address => CustodyInfo) internal _custodies;
    mapping(address => RecoveryRequest) public recoveryRequests;
    mapping(address => mapping(address => bool)) public authorizedCallers;

    // Modifiers
    modifier onlyValidCustody(address safe) {
        require(_custodies[safe].exists, "Custody not found");
        _;
    }

    modifier notFrozen(address safe) {
        require(!_custodies[safe].frozen, "Custody is frozen");
        _;
    }

    modifier onlyEmergencyContact(address safe) {
        require(isEmergencyContact(safe, msg.sender), "Not emergency contact");
        _;
    }

    modifier onlyAuthorized(address safe) {
        require(authorizedCallers[safe][msg.sender] || msg.sender == owner(), "Unauthorized");
        _;
    }

    // External view getter for public access
    function custodies(address safe) external view returns (
        bool exists,
        bool frozen,
        uint256 timeLock,
        uint256 lastActivity,
        address[] memory contacts
    ) {
        CustodyInfo storage c = _custodies[safe];
        return (c.exists, c.frozen, c.timeLock, c.lastActivity, c.emergencyContacts);
    }

    // --- Core Functions ---

    function initializeCustody(
        address safe,
        uint256 timeLock,
        address[] calldata emergencyContacts
    ) external onlyOwner {
        require(!_custodies[safe].exists, "Already initialized");
        require(timeLock >= MIN_TIMELOCK && timeLock <= MAX_TIMELOCK, "Invalid timelock");
        require(emergencyContacts.length <= MAX_EMERGENCY_CONTACTS, "Too many contacts");

        CustodyInfo storage info = _custodies[safe];
        info.exists = true;
        info.timeLock = timeLock;
        info.lastActivity = block.timestamp;

        for (uint256 i = 0; i < emergencyContacts.length; i++) {
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
        _custodies[safe].spendingLimits[token] = SpendingLimit({
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
    ) external view onlyValidCustody(safe) returns (bool) {
        SpendingLimit memory limit = _custodies[safe].spendingLimits[token];
        if (block.timestamp > limit.resetTime) return amount <= limit.limit;
        return limit.spent + amount <= limit.limit;
    }

    function updateSpending(
        address safe,
        address token,
        uint256 amount
    ) external onlyAuthorized(safe) onlyValidCustody(safe) {
        SpendingLimit storage limit = _custodies[safe].spendingLimits[token];

        if (block.timestamp > limit.resetTime) {
            limit.spent = amount;
            limit.resetTime = block.timestamp + limit.period;
        } else {
            limit.spent += amount;
        }
    }

    function proposeTimeLockTransaction(
        address safe,
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyAuthorized(safe) onlyValidCustody(safe) returns (bytes32) {
        uint256 executeTime = block.timestamp + _custodies[safe].timeLock;

        bytes32 txHash = keccak256(abi.encodePacked(safe, to, value, data, executeTime));
        _custodies[safe].pendingTransactions[txHash] = TimeLockTransaction({
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
    ) external onlyAuthorized(safe) onlyValidCustody(safe) notFrozen(safe) nonReentrant {
        TimeLockTransaction storage txn = _custodies[safe].pendingTransactions[txHash];
        require(!txn.executed, "Already executed");
        require(block.timestamp >= txn.executeTime, "Time lock not expired");

        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        emit TransactionExecuted(safe, txHash, success);
    }

    // --- Emergency & Recovery ---

    function emergencyFreeze(address safe) external onlyEmergencyContact(safe) {
        _custodies[safe].frozen = true;
        emit EmergencyFreeze(safe, msg.sender, block.timestamp);
    }

    function emergencyUnfreeze(address safe) external onlyEmergencyContact(safe) {
        _custodies[safe].frozen = false;
        emit EmergencyUnfreeze(safe, msg.sender, block.timestamp);
    }

    function addEmergencyContact(address safe, address contact) external onlyAuthorized(safe) onlyValidCustody(safe) {
        require(_custodies[safe].emergencyContacts.length < MAX_EMERGENCY_CONTACTS, "Max contacts");
        _custodies[safe].emergencyContacts.push(contact);
        emit EmergencyContactAdded(safe, contact);
    }

    function removeEmergencyContact(address safe, address contact) external onlyAuthorized(safe) onlyValidCustody(safe) {
        address[] storage contacts = _custodies[safe].emergencyContacts;
        for (uint i = 0; i < contacts.length; i++) {
            if (contacts[i] == contact) {
                contacts[i] = contacts[contacts.length - 1];
                contacts.pop();
                emit EmergencyContactRemoved(safe, contact);
                break;
            }
        }
    }

    function isEmergencyContact(address safe, address contact) public view returns (bool) {
        address[] memory contacts = _custodies[safe].emergencyContacts;
        for (uint i = 0; i < contacts.length; i++) {
            if (contacts[i] == contact) return true;
        }
        return false;
    }

    function updateTimeLock(address safe, uint256 newDelay) external onlyAuthorized(safe) onlyValidCustody(safe) {
        require(newDelay >= MIN_TIMELOCK && newDelay <= MAX_TIMELOCK, "Invalid delay");
        _custodies[safe].timeLock = newDelay;
        emit TimeLockSet(safe, newDelay);
    }

    function addAuthorizedCaller(address safe, address caller) external onlyAuthorized(safe) onlyValidCustody(safe) {
        authorizedCallers[safe][caller] = true;
    }

    function removeAuthorizedCaller(address safe, address caller) external onlyAuthorized(safe) onlyValidCustody(safe) {
        authorizedCallers[safe][caller] = false;
    }

    // Receive ETH
    receive() external payable {}
}
