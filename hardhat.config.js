

require("ts-node/register");
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  networks: {
    hardhat: {},
    // Example for mainnet/testnet, use .env for sensitive data
    ...(process.env.ALCHEMY_API_KEY && process.env.DEPLOYER_KEY ? {
      goerli: {
        url: `https://eth-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
        accounts: [process.env.DEPLOYER_KEY]
      }
    } : {})
  },
  // Keep deployment addresses here if needed
};
