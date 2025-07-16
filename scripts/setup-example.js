// scripts/setup-example.js
const { ethers } = require("hardhat");

async function setupExample() {
    const [deployer, emergencyContact1, emergencyContact2] = await ethers.getSigners();

    // Deploy factory
    const SafeseedFactory = await ethers.getContractFactory("SafeseedFactory");
    const factory = await SafeseedFactory.deploy();
    await factory.deployed();

    console.log("✅ Factory deployed to:", factory.address);

    // Example Safe address (replace this with a real Gnosis Safe address when using for real)
    const safeAddress = "0x1234567890123456789012345678901234567890";

    // Configuration
    const config = {
        timeLock: 86400, // 24 hours
        emergencyContacts: [emergencyContact1.address, emergencyContact2.address],
        salt: ethers.utils.id("example_safe_v1")
    };

    console.log("🚀 Setting up Safeseed for Safe:", safeAddress);

    const setupTx = await factory.setupSafeseed(safeAddress, config);
    const receipt = await setupTx.wait();

    const event = receipt.events?.find(e => e.event === "SafeseedSetupComplete");

    if (event) {
        console.log("✅ Setup complete!");
        console.log("Safe:     ", event.args.safe);
        console.log("Custody:  ", event.args.custody);
        console.log("Integration:", event.args.integration);
    }

    // Optionally set a spending limit (ETH limit as example)
    const integrationAddress = await factory.getIntegrationForSafe(safeAddress);
    const integration = await ethers.getContractAt("SafeseedIntegration", integrationAddress);

    const ethLimit = ethers.utils.parseEther("1");
    const period = 86400;

    await integration.setSpendingLimit(
        safeAddress,
        ethers.constants.AddressZero,
        ethLimit,
        period
    );

    console.log("✅ ETH spending limit set: 1 ETH per 24h");
}

if (require.main === module) {
    setupExample()
        .then(() => process.exit(0))
        .catch(error => {
            console.error("❌ Error:", error);
            process.exit(1);
        });
    }
