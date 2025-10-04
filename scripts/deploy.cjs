const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("Account balance:", balance.toString());

    // Deploy Factory
    const SafeseedFactory = await ethers.getContractFactory("SafeseedFactory");
    const factory = await SafeseedFactory.deploy();
    await factory.waitForDeployment();

        const factoryAddress = await factory.getAddress();
        console.log("SafeseedFactory deployed to:", factoryAddress);

        // Deploy a sample custody contract
        const salt = ethers.keccak256(ethers.toUtf8Bytes("safeseed_v1"));
        const custodyTx = await factory.deployCustody(salt);
        const custodyReceipt = await custodyTx.wait();
        const custodyEvent = custodyReceipt.logs
            .map(log => factory.interface.parseLog(log))
            .find(e => e.name === "CustodyDeployed");
        const custodyAddress = custodyEvent?.args?.custody;
        console.log("Sample SafeseedCustody deployed to:", custodyAddress);

    // Deploy integration contract
        const integrationTx = await factory.deployIntegration(custodyAddress);
        const integrationReceipt = await integrationTx.wait();
        const integrationEvent = integrationReceipt.logs
            .map(log => factory.interface.parseLog(log))
            .find(e => e.name === "IntegrationDeployed");
        const integrationAddress = integrationEvent?.args?.integration;
        console.log("Sample SafeseedIntegration deployed to:", integrationAddress);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
