import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const ONE_DAY = 86400; // 1 day in seconds
const OWNER_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"; // Hardhat's first account
const ADMIN_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; // Hardhat's second account
export default buildModule("VotingPlatform", (m) => {
  const votingPlatform = m.contract("VotingPlatform", [
    ONE_DAY,  // votingPeriod
    ADMIN_ADDRESS, // admin address i.e. the backend address
    OWNER_ADDRESS // owner address
  ]);

  return { votingPlatform };
});