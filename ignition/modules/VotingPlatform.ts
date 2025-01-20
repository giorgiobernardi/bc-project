import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const ONE_HOUR = 3600; // 1 hour in seconds
const ONE_DAY = 86400; // 1 day in seconds

export default buildModule("VotingPlatform", (m) => {
  const votingPlatform = m.contract("VotingPlatform", [
    ONE_HOUR, // minVotingDelay
    ONE_DAY   // votingPeriod
  ]);

  return { votingPlatform };
});