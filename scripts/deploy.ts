import { ethers } from "hardhat";

async function main() {
  // Deploy SafeseedCustody
  const Custody = await ethers.getContractFactory("SafeseedCustody");
  const custody = await Custody.deploy();
  await custody.waitForDeployment();
  console.log("SafeseedCustody deployed to:", await custody.getAddress());

  // Deploy SafeseedIntegration with custody address
  const Integration = await ethers.getContractFactory("SafeseedIntegration");
  const integration = await Integration.deploy(await custody.getAddress());
  await integration.waitForDeployment();
  console.log("SafeseedIntegration deployed to:", await integration.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
