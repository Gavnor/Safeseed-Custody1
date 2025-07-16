// scripts/deploy.js
/**
 * Hardhat deployment script for Safeseed contracts
 */
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Deploy Factory
    const SafeseedFactory = await ethers.getContractFactory("SafeseedFactory");
    const factory = await SafeseedFactory.deploy();
    await factory.deployed();
    
    console.log("SafeseedFactory deployed to:", factory.address);

    // Deploy a sample custody contract
    const salt = ethers.utils.id("safeseed_v1");
    const custodyTx = await factory.deployCustody(salt);
    const custodyReceipt = await custodyTx.wait();
    
    const custodyAddress = custodyReceipt.events?.find(
        event => event.event === "CustodyDeployed"
    )?.args?.custody;
    
    console.log("Sample SafeseedCustody deployed to:", custodyAddress);

    // Deploy integration contract
    const integrationTx = await factory.deployIntegration(custodyAddress);
    const integrationReceipt = await integrationTx.wait();
    
    const integrationAddress = integrationReceipt.events?.find(
        event => event.event === "IntegrationDeployed"
    )?.args?.integration;
    
    console.log("Sample SafeseedIntegration deployed to:", integrationAddress);

    // Verify contracts if on a public network
    if (network.name !== "hardhat" && network.name !== "localhost") {
        console.log("Waiting for block confirmations...");
        await factory.deployTransaction.wait(5);
        
        try {
            await hre.run("verify:verify", {
                address: factory.address,
                constructorArguments: [],
            });
            console.log("SafeseedFactory verified");
        } catch (error) {
            console.log("Verification failed:", error.message);
        }
    }

    return {
        factory: factory.address,
        custody: custodyAddress,
        integration: integrationAddress
    };
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

module.exports = { main };
      
