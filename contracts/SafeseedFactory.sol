// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./SafeseedCustody.sol";
import "./SafeseedIntegration.sol";

/**
 * @title SafeseedFactory
 * @dev Factory contract for deploying Safeseed custody and integration contracts
 */
contract SafeseedFactory is Ownable {
    // Events
    event CustodyDeployed(address indexed custody, address indexed deployer, bytes32 salt);
    event IntegrationDeployed(address indexed integration, address indexed custody, address indexed deployer);
    event SafeseedSetupComplete(
        address indexed safe,
        address indexed custody,
        address indexed integration,
        address deployer
    );

    // State variables
    mapping(address => address) public safeToCustody;
    mapping(address => address) public safeToIntegration;
    mapping(address => bool) public isDeployedByCustody;
    mapping(address => bool) public isDeployedByIntegration;

    address[] public allCustodyContracts;
    address[] public allIntegrationContracts;

    // Deployment configuration
    struct DeploymentConfig {
        uint256 timeLock;
        address[] emergencyContacts;
        bytes32 salt;
    }

    /**
     * @dev Deploy custody contract using CREATE2
     * @param salt Salt for CREATE2 deployment
     * @return custody Address of deployed custody contract
     */
    function deployCustody(bytes32 salt) public returns (address custody) {
        bytes memory bytecode = type(SafeseedCustody).creationCode;
        custody = Create2.deploy(0, salt, bytecode);

        SafeseedCustody(custody).transferOwnership(msg.sender);

        isDeployedByCustody[custody] = true;
        allCustodyContracts.push(custody);

        emit CustodyDeployed(custody, msg.sender, salt);
    }

    /**
     * @dev Deploy integration contract
     * @param custody Address of custody contract
     * @return integration Address of deployed integration contract
     */
    function deployIntegration(address custody) public returns (address integration) {
        require(custody != address(0), "Invalid custody address");

        bytes memory bytecode = abi.encodePacked(
            type(SafeseedIntegration).creationCode,
            abi.encode(custody)
        );

        bytes32 salt = keccak256(abi.encodePacked(custody, msg.sender, block.timestamp));
        integration = Create2.deploy(0, salt, bytecode);

        SafeseedIntegration(integration).transferOwnership(msg.sender);

        isDeployedByIntegration[integration] = true;
        allIntegrationContracts.push(integration);

        emit IntegrationDeployed(integration, custody, msg.sender);
    }

    /**
     * @dev Deploy complete Safeseed setup (custody + integration)
     */
    function deployComplete(
        DeploymentConfig calldata config
    ) public returns (address custody, address integration) {
        custody = deployCustody(config.salt);
        integration = deployIntegration(custody);
    }

    /**
     * @dev Setup Safeseed for a specific Safe
     */
    function setupSafeseed(
        address safe,
        DeploymentConfig calldata config
    ) external {
        require(safe != address(0), "Invalid Safe address");
        require(safeToCustody[safe] == address(0), "Already setup");

        (address custody, address integration) = deployComplete(config);

        SafeseedIntegration(integration).registerSafe(
            safe,
            config.timeLock,
            config.emergencyContacts
        );

        safeToCustody[safe] = custody;
        safeToIntegration[safe] = integration;

        emit SafeseedSetupComplete(safe, custody, integration, msg.sender);
    }

    /**
     * @dev Predict custody address
     */
    function predictCustodyAddress(bytes32 salt) external view returns (address) {
        bytes memory bytecode = type(SafeseedCustody).creationCode;
        return Create2.computeAddress(salt, keccak256(bytecode), address(this));
    }

    /**
     * @dev Predict integration address
     */
    function predictIntegrationAddress(address custody) external view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(SafeseedIntegration).creationCode,
            abi.encode(custody)
        );

        bytes32 salt = keccak256(abi.encodePacked(custody, msg.sender, block.timestamp));
        return Create2.computeAddress(salt, keccak256(bytecode), address(this));
    }

    // View functions
    function getCustodyForSafe(address safe) external view returns (address) {
        return safeToCustody[safe];
    }

    function getIntegrationForSafe(address safe) external view returns (address) {
        return safeToIntegration[safe];
    }

    function getAllCustodyContracts() external view returns (address[] memory) {
        return allCustodyContracts;
    }

    function getAllIntegrationContracts() external view returns (address[] memory) {
        return allIntegrationContracts;
    }

    function getCustodyCount() external view returns (uint256) {
        return allCustodyContracts.length;
    }

    function getIntegrationCount() external view returns (uint256) {
        return allIntegrationContracts.length;
    }
}
