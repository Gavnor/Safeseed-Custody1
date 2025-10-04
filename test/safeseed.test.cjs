const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Safeseed End-to-End", function () {
  let custody, integration, owner, user, emergency1, emergency2, other, mockSafe;

  beforeEach(async function () {
    [owner, user, emergency1, emergency2, other] = await ethers.getSigners();

    // Deploy custody contract
    const Custody = await ethers.getContractFactory("SafeseedCustody");
    custody = await Custody.deploy();
    await custody.waitForDeployment();

    // Deploy integration contract with custody address
    const Integration = await ethers.getContractFactory("SafeseedIntegration");
    integration = await Integration.deploy(custody.target);
    await integration.waitForDeployment();

    // Transfer ownership of custody to integration contract
    await custody.transferOwnership(integration.target);

    // Deploy mock Gnosis Safe with user as owner
    const MockSafe = await ethers.getContractFactory("MockGnosisSafe");
    mockSafe = await MockSafe.deploy(user.address);
    await mockSafe.waitForDeployment();

    // Print DebugLog events after each setup
    let logs = await custody.queryFilter(custody.filters.DebugLog());
    if (logs.length > 0) {
      console.log("[DEBUG after setup]", logs.map(l => l.args[0]));
    }
  });

  it("registers a safe and sets emergency contacts", async function () {
    const safe = mockSafe.target;
    const timeLock = 3600;
    const emergencyContacts = [emergency1.address, emergency2.address];
    await expect(
      integration.connect(user).registerSafe(safe, timeLock, emergencyContacts)
    ).to.emit(integration, "SafeRegistered");
    expect(await integration.isSafeRegistered(safe)).to.be.true;
    const custodyInfo = await custody.custodies(safe);
    const contacts = custodyInfo.emergencyContacts || custodyInfo[4];
    expect(contacts).to.include(emergency1.address);
    expect(contacts).to.include(emergency2.address);
    const isAuthorized = await custody.authorizedCallers(safe, integration.target);
    expect(isAuthorized).to.be.true;
  });

  it("allows emergency freeze and unfreeze", async function () {
    const safe = mockSafe.target;
    const timeLock = 3600;
    const emergencyContacts = [emergency1.address];
    await integration.connect(user).registerSafe(safe, timeLock, emergencyContacts);
    // Print emergency contacts after registration
    const custodyInfoAfter = await custody.custodies(safe);
    const contactsAfter = custodyInfoAfter.emergencyContacts || custodyInfoAfter[4];
    console.log("[TEST] Emergency contacts after registration:", contactsAfter);
    // Fetch DebugLog events before freeze
    let logs = await custody.queryFilter(custody.filters.DebugLog());
    if (logs.length > 0) {
      console.log("[DEBUG before freeze]", logs.map(l => l.args[0]));
    }
    await expect(
      integration.connect(emergency1).emergencyFreeze(safe)
    ).to.emit(custody, "EmergencyFreeze");
    // Fetch DebugLog events after freeze
    logs = await custody.queryFilter(custody.filters.DebugLog());
    if (logs.length > 0) {
      console.log("[DEBUG after freeze]", logs.map(l => l.args[0]));
    }
    const custodyInfo = await custody.custodies(safe);
    const contacts = custodyInfo.emergencyContacts || custodyInfo[4];
    expect(contacts).to.include(emergency1.address);
    await expect(
      integration.connect(emergency1).emergencyUnfreeze(safe)
    ).to.emit(custody, "EmergencyUnfreeze");
  });

  it("prevents non-contacts from freezing", async function () {
    const safe = mockSafe.target;
    const timeLock = 3600;
    const emergencyContacts = [emergency1.address, emergency2.address];
    await integration.connect(user).registerSafe(safe, timeLock, emergencyContacts);
    await expect(
      integration.connect(other).emergencyFreeze(safe)
    ).to.be.revertedWith("Not an emergency contact");
  });

  it("initiates and approves recovery", async function () {
    const safe = mockSafe.target;
    const timeLock = 3600;
    const emergencyContacts = [emergency1.address, emergency2.address];
    await integration.connect(user).registerSafe(safe, timeLock, emergencyContacts);
    await expect(
      integration.connect(emergency1).initiateRecovery(safe, user.address)
    ).to.emit(custody, "RecoveryInitiated");
    const custodyInfo = await custody.custodies(safe);
    const contacts = custodyInfo.emergencyContacts || custodyInfo[4];
    expect(contacts).to.include(emergency1.address);
    expect(contacts).to.include(emergency2.address);
    await expect(
      integration.connect(emergency2).approveRecovery(safe)
    ).to.not.be.reverted;
  });
});

