Safeseed is an experimental custody and integration setup built on smart contracts. The goal is to provide a safer and more transparent way for users to manage assets through their Safe, with an added layer of security and automation.

The project is organized around three main contracts. The SafeseedFactory contract handles deployment and linking of all components. The SafeseedCustody contract is responsible for holding assets securely, applying time locks and safety checks. The SafeseedIntegration contract connects a Safe with custody and registers emergency contacts for recovery and oversight.

Safeseed is designed to address common security issues in asset management. It reduces single points of failure, enables automated setup from a single deploy, and allows flexibility by letting Safe owners plug into custody and integration without modifying core contracts. In short, it acts as a starter kit for secure smart asset management.

To set up the project, clone the repository and move into the folder. Run npm install to install dependencies, then compile with npx hardhat compile. You can deploy the contracts locally using Hardhat by running npx hardhat run scripts/deploy.js --network hardhat.

The project uses an environment file (.env) to store keys and other sensitive information. This file should never be committed. A .env.example template is provided for safe configuration.

At the current stage, the contracts compile and deploy successfully and have been tested locally with Hardhat. The next steps include expanding integration logic, auditing, and deploying to test networks.

Safeseed is licensed under MIT, meaning it is free to fork, test, modify, and improve.