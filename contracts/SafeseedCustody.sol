// contracts/SafeseedCustody.sol // SPDX-License-Identifier: MIT pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; import "@openzeppelin/contracts/access/Ownable.sol"; import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**

@title SafeseedCustody

@dev Enhanced custody contract that works with Gnosis Safe

Provides additional security features like time locks, spending limits, and emergency controls */ contract SafeseedCustody is ReentrancyGuard, Ownable { using ECDSA for bytes32; using SafeERC20 for IERC20;

// Events event CustodyCreated(address indexed safe, address indexed creator, uint256 timestamp); event TimeLockSet(address indexed safe, uint256 delay); event SpendingLimitSet(address indexed safe, address indexed token, uint256 limit, uint256 period); event EmergencyFreeze(address indexed safe, address indexed freezer, uint256 timestamp); event EmergencyUnfreeze(address indexed safe, address indexed unfreezer, uint256 timestamp); event RecoveryInitiated(address indexed safe, address indexed initiator, uint256 timestamp); event RecoveryExecuted(address indexed safe, address indexed executor, uint256 timestamp); event TransactionProposed(address indexed safe, bytes32 indexed txHash, uint256 executeTime); event TransactionExecuted(address indexed safe, bytes32 indexed txHash, bool success); event EmergencyContactAdded(address indexed safe, address indexed contact); event EmergencyContactRemoved(address indexed safe, address indexed contact);

// Structs struct CustodyInfo { bool exists; bool frozen; uint256 timeLock; uint256 lastActivity; address[] emergencyContacts; mapping(address => SpendingLimit) spendingLimits; mapping(bytes32 => TimeLockTransaction) pendingTransactions; }

struct SpendingLimit { uint256 limit; uint256 spent; uint256 resetTime; uint256 period; }

struct TimeLockTransaction { address to; uint256 value; bytes data; uint256 executeTime; bool executed; address proposer; }

struct RecoveryRequest { address newOwner; uint256 initiatedAt; uint256 executionTime; bool executed; mapping(address => bool) approvals; uint256 approvalCount; }

// State variables mapping(address => CustodyInfo) public custodies; mapping(address => RecoveryRequest) public recoveryRequests; mapping(address => mapping(address => bool)) public authorizedCallers;

uint256 public constant RECOVERY_DELAY = 7 days; uint256 public constant MAX_EMERGENCY_CONTACTS = 5; uint256 public constant MIN_TIMELOCK = 1 hours; uint256 public constant MAX_TIMELOCK = 30 days;

// Modifiers modifier onlyValidCustody(address safe) { require(custodies[safe].exists, "Custody does not exist"); _; }

modifier notFrozen(address safe) { require(!custodies[safe].frozen, "Custody is frozen"); _; }

modifier onlyEmergencyContact(address safe) { require(isEmergencyContact(safe, msg.sender), "Not an emergency contact"); _; }

modifier onlyAuthorized(address safe) { require(authorizedCallers[safe][msg.sender] || msg.sender == owner(), "Not authorized"); _; }

// Function to receive ETH receive() external payable {} }


