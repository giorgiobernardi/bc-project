import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1,  // Decreased runs for more aggressive optimization
        details: {
          yul: true,
          yulDetails: {
            stackAllocation: true,
            optimizerSteps: "dhfoDgvulfnTUtnIf"  // Aggressive optimization steps
          }
        }
      },
      viaIR: true  // Enable intermediate representation for better optimization
    }
  },
};

export default config;
