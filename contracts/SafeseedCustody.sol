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
 * @dev Enhanced custody contract for integration with Gnosis Safe
 */
contract SafeseedCustody is ReentrancyGuard, Ownable {
    event DebugLog(string message);

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

    // Helper to convert address to string (for debug)
    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = '0';
        s[1] = 'x';
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            uint8 hi = uint8(b) / 16;
            uint8 lo = uint8(b) - 16 * hi;
            s[2*i + 2] = char(hi);
            s[2*i + 3] = char(lo);
        }
        return string(s);
    }
    function char(uint8 b) internal pure returns (bytes1 c) {
        if (b < 10) return bytes1(b + 0x30);
        else return bytes1(b + 0x57);
    }
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

    // State
    mapping(address => CustodyInfo) private _custodies;
    mapping(address => RecoveryRequest) private _recoveryRequests;
    mapping(address => mapping(address => bool)) public authorizedCallers;

    uint256 public constant RECOVERY_DELAY = 7 days;
    uint256 public constant MAX_EMERGENCY_CONTACTS = 5;
    uint256 public constant MIN_TIMELOCK = 1 hours;
    uint256 public constant MAX_TIMELOCK = 30 days;

    // Modifiers
    modifier onlyValidCustody(address safe) {
        require(_custodies[safe].exists, "Custody does not exist");
        _;
    }

    modifier notFrozen(address safe) {
        require(!_custodies[safe].frozen, "Custody is frozen");
        _;
    }

    modifier onlyEmergencyContact(address safe) {
        bool isContact = isEmergencyContact(safe, msg.sender);
        address[] storage contacts = _custodies[safe].emergencyContacts;
        emit DebugLog(string(abi.encodePacked(
            "[DEBUG] onlyEmergencyContact: msg.sender=", toAsciiString(msg.sender),
            ", contacts=", contacts.length > 0 ? toAsciiString(contacts[0]) : "none",
            contacts.length > 1 ? string(abi.encodePacked(", ", toAsciiString(contacts[1]))) : "",
            contacts.length > 2 ? string(abi.encodePacked(", ", toAsciiString(contacts[2]))) : "",
            contacts.length > 3 ? string(abi.encodePacked(", ", toAsciiString(contacts[3]))) : "",
            contacts.length > 4 ? string(abi.encodePacked(", ", toAsciiString(contacts[4]))) : ""
        )));
        require(isContact, "Not an emergency contact");
        _;

    }

    modifier onlyAuthorized(address safe) {
        require(authorizedCallers[safe][msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    // Public Read
    function custodies(address safe) public view returns (
        bool exists, bool frozen, uint256 timeLock, uint256 lastActivity, address[] memory emergencyContacts
    ) {
        CustodyInfo storage c = _custodies[safe];
        return (c.exists, c.frozen, c.timeLock, c.lastActivity, c.emergencyContacts);
    }

    // Main functions
    function initializeCustody(address safe, uint256 timeLock, address[] calldata contacts) external onlyOwner {
        require(!_custodies[safe].exists, "Already initialized");
        require(timeLock >= MIN_TIMELOCK && timeLock <= MAX_TIMELOCK, "Invalid time lock");
        require(contacts.length <= MAX_EMERGENCY_CONTACTS, "Too many contacts");

        _custodies[safe].exists = true;
        _custodies[safe].timeLock = timeLock;
        _custodies[safe].lastActivity = block.timestamp;

        for (uint256 i = 0; i < contacts.length; i++) {
            _custodies[safe].emergencyContacts.push(contacts[i]);
        }

        emit CustodyCreated(safe, msg.sender, block.timestamp);
    }

    function setSpendingLimit(address safe, address token, uint256 limit, uint256 period)
        external
        onlyAuthorized(safe)
        onlyValidCustody(safe)
    {
        require(period > 0, "Period must be > 0");
        SpendingLimit storage s = _custodies[safe].spendingLimits[token];
        s.limit = limit;
        s.period = period;
        s.spent = 0;
        s.resetTime = block.timestamp + period;

        emit SpendingLimitSet(safe, token, limit, period);
    }

    function checkSpendingLimit(address safe, address token, uint256 amount)
        external
        view
        returns (bool)
    {
        SpendingLimit storage s = _custodies[safe].spendingLimits[token];

        if (block.timestamp >= s.resetTime) {
            return amount <= s.limit;
        } else {
            return (s.spent + amount) <= s.limit;
        }
    }

    function updateSpending(address safe, address token, uint256 amount)
        external
        onlyAuthorized(safe)
        onlyValidCustody(safe)
    {
        SpendingLimit storage s = _custodies[safe].spendingLimits[token];

        if (block.timestamp >= s.resetTime) {
            s.spent = amount;
            s.resetTime = block.timestamp + s.period;
        } else {
            s.spent += amount;
        }
    }

    function updateTimeLock(address safe, uint256 newDelay)
        external
        onlyAuthorized(safe)
        onlyValidCustody(safe)
    {
        require(newDelay >= MIN_TIMELOCK && newDelay <= MAX_TIMELOCK, "Invalid delay");
        _custodies[safe].timeLock = newDelay;
        emit TimeLockSet(safe, newDelay);
    }

    function proposeTimeLockTransaction(
        address safe,
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyAuthorized(safe) onlyValidCustody(safe) returns (bytes32) {
        bytes32 txHash = keccak256(abi.encodePacked(safe, to, value, data, block.timestamp));
        TimeLockTransaction storage txn = _custodies[safe].pendingTransactions[txHash];

        txn.to = to;
        txn.value = value;
        txn.data = data;
        txn.executeTime = block.timestamp + _custodies[safe].timeLock;
        txn.executed = false;
        txn.proposer = msg.sender;

        emit TransactionProposed(safe, txHash, txn.executeTime);
        return txHash;
    }

    function executeTimeLockTransaction(address safe, bytes32 txHash)
        external
        nonReentrant
        onlyAuthorized(safe)
        onlyValidCustody(safe)
        notFrozen(safe)
    {
        TimeLockTransaction storage txn = _custodies[safe].pendingTransactions[txHash];

        require(!txn.executed, "Already executed");
        require(block.timestamp >= txn.executeTime, "Too early");

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        txn.executed = true;

        emit TransactionExecuted(safe, txHash, success);
    }

    function emergencyFreeze(address safe)
        external
        onlyEmergencyContact(safe)
        onlyValidCustody(safe)
    {
        _custodies[safe].frozen = true;
        emit EmergencyFreeze(safe, msg.sender, block.timestamp);
    }

    function emergencyUnfreeze(address safe)
        external
        onlyEmergencyContact(safe)
        onlyValidCustody(safe)
    {
        _custodies[safe].frozen = false;
        emit EmergencyUnfreeze(safe, msg.sender, block.timestamp);
    }

    function addEmergencyContact(address safe, address contact)
        external
        onlyAuthorized(safe)
        onlyValidCustody(safe)
    {
        _custodies[safe].emergencyContacts.push(contact);
        emit EmergencyContactAdded(safe, contact);
    }

    function removeEmergencyContact(address safe, address contact)
        external
        onlyAuthorized(safe)
        onlyValidCustody(safe)
    {
        address[] storage list = _custodies[safe].emergencyContacts;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == contact) {
                list[i] = list[list.length - 1];
                list.pop();
                emit EmergencyContactRemoved(safe, contact);
                break;
            }
        }
    }

    function isEmergencyContact(address safe, address user) public view returns (bool) {
        address[] storage contacts = _custodies[safe].emergencyContacts;
        for (uint256 i = 0; i < contacts.length; i++) {
            if (contacts[i] == user) return true;
        }
        return false;
    }


    function addAuthorizedCaller(address safe, address caller)
        external
        onlyAuthorized(safe)
        onlyValidCustody(safe)
    {
        authorizedCallers[safe][caller] = true;
    }

    // --- Recovery Functions ---
    function initiateRecovery(address safe, address newOwner)
        external
        onlyEmergencyContact(safe)
        onlyValidCustody(safe)
    {
        RecoveryRequest storage req = _recoveryRequests[safe];
        require(!req.executed, "Recovery already executed");
        req.newOwner = newOwner;
        req.initiatedAt = block.timestamp;
        req.executionTime = block.timestamp + RECOVERY_DELAY;
        req.executed = false;
        req.approvalCount = 0;
        // Reset approvals
        address[] storage contacts = _custodies[safe].emergencyContacts;
        for (uint256 i = 0; i < contacts.length; i++) {
            req.approvals[contacts[i]] = false;
        }
        emit RecoveryInitiated(safe, msg.sender, block.timestamp);
    }

    function approveRecovery(address safe)
        external
        onlyEmergencyContact(safe)
        onlyValidCustody(safe)
    {
        RecoveryRequest storage req = _recoveryRequests[safe];
        require(!req.executed, "Recovery already executed");
        require(req.initiatedAt > 0, "No recovery initiated");
        require(!req.approvals[msg.sender], "Already approved");
        req.approvals[msg.sender] = true;
        req.approvalCount += 1;
    }

    function executeRecovery(address safe)
        external
        onlyValidCustody(safe)
    {
        RecoveryRequest storage req = _recoveryRequests[safe];
        require(!req.executed, "Recovery already executed");
        require(req.initiatedAt > 0, "No recovery initiated");
        require(block.timestamp >= req.executionTime, "Recovery delay not passed");
        // Require majority approval
        address[] storage contacts = _custodies[safe].emergencyContacts;
        require(contacts.length > 0, "No emergency contacts");
        require(req.approvalCount > contacts.length / 2, "Not enough approvals");
        req.executed = true;
        // Transfer ownership (assumes Safe is Ownable)
        (bool success, ) = safe.call(abi.encodeWithSignature("transferOwnership(address)", req.newOwner));
        require(success, "Ownership transfer failed");
        emit RecoveryExecuted(safe, msg.sender, block.timestamp);
    }

    // Receive ETH
    receive() external payable {}
}
