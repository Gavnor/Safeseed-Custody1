import { expect } from "chai";
import { ethers } from "hardhat";

describe("Safeseed System Integration", function () {
  let factory: any, custody: any, integration: any, owner: any, user: any, emergency1: any, emergency2: any;

  beforeEach(async function () {
    [owner, user, emergency1, emergency2] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("SafeseedFactory");
    factory = await Factory.deploy();
    await factory.waitForDeployment();

    // Deploy custody via factory
    const salt = ethers.keccak256(ethers.toUtf8Bytes("test_salt"));
    const custodyTx = await factory.deployCustody(salt);
    const custodyReceipt = await custodyTx.wait();
    const custodyEvent = custodyReceipt.logs
      .map((log: any) => factory.interface.parseLog(log))
      .find((e: any) => e.name === "CustodyDeployed");
    const custodyAddress = custodyEvent.args.custody;
    const Custody = await ethers.getContractFactory("SafeseedCustody");
    custody = Custody.attach(custodyAddress);

    // Deploy integration via factory
    const integrationTx = await factory.deployIntegration(custodyAddress);
    const integrationReceipt = await integrationTx.wait();
    const integrationEvent = integrationReceipt.logs
      .map((log: any) => factory.interface.parseLog(log))
      .find((e: any) => e.name === "IntegrationDeployed");
    const integrationAddress = integrationEvent.args.integration;
    const Integration = await ethers.getContractFactory("SafeseedIntegration");
    integration = Integration.attach(integrationAddress);
  });

  it("should initialize custody and register a safe", async function () {
    // Simulate a Gnosis Safe address (just use a random address for test)
    const safe = ethers.Wallet.createRandom().address;
    const timeLock = 3600; // 1 hour
    const emergencyContacts = [emergency1.address, emergency2.address];

    // Register safe
    await expect(
      integration.connect(user).registerSafe(safe, timeLock, emergencyContacts)
    ).to.emit(integration, "SafeRegistered");

    // Check registration
    expect(await integration.isSafeRegistered(safe)).to.be.true;
    const [exists, , , , contacts] = await custody.custodies(safe);
    expect(exists).to.be.true;
    expect(contacts).to.include(emergency1.address);
    expect(contacts).to.include(emergency2.address);
  });

  it("should allow emergency freeze and unfreeze", async function () {
    const safe = ethers.Wallet.createRandom().address;
    const timeLock = 3600;
    const emergencyContacts = [emergency1.address];
    await integration.connect(user).registerSafe(safe, timeLock, emergencyContacts);

    // Emergency freeze
    await expect(
      integration.connect(emergency1).emergencyFreeze(safe)
    ).to.emit(custody, "EmergencyFreeze");

    // Emergency unfreeze
    await expect(
      integration.connect(emergency1).emergencyUnfreeze(safe)
    ).to.emit(custody, "EmergencyUnfreeze");
  });

  it("should initiate and approve recovery", async function () {
    const safe = ethers.Wallet.createRandom().address;
    const timeLock = 3600;
    const emergencyContacts = [emergency1.address, emergency2.address];
    await integration.connect(user).registerSafe(safe, timeLock, emergencyContacts);

    // Initiate recovery
    await expect(
      integration.connect(emergency1).initiateRecovery(safe, user.address)
    ).to.emit(custody, "RecoveryInitiated");

    // Approve recovery
    await expect(
      integration.connect(emergency2).approveRecovery(safe)
    ).to.not.be.reverted;
  });
});
