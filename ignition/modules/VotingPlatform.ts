import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const ONE_DAY = 86400; // 1 day in seconds
const ADMIN_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"; // Hardhat's first account

export default buildModule("VotingPlatform", (m) => {
  const votingPlatform = m.contract("VotingPlatform", [
    ONE_DAY,  // votingPeriod
    ADMIN_ADDRESS // admin address
  ]);

  return { votingPlatform };
});