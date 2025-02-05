import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import hre from "hardhat";
import { encodePacked, getAddress, keccak256, parseEther } from "viem";

describe("VotingPlatform", function() {
  const ONE_DAY = 86400;
  const REGISTRATION_DURATION = 10 * ONE_DAY;
  const DOMAIN_FEE = parseEther("1"); // 1 ETH
  const POWER_LEVEL = 2n;

  async function deployFixture() {
    const [owner, admin, voter1, voter2] = await hre.viem.getWalletClients();
    
    // Deploy contract
    const votingPlatform = await hre.viem.deployContract("VotingPlatform", [
      ONE_DAY,
      admin.account.address,
      owner.account.address
    ]);

    return {
      votingPlatform,
      owner,
      admin,
      voter1,
      voter2
    };
  }

  describe("Domain Management", function() {
    it("Should allow adding a domain with correct payment", async function() {
      const { votingPlatform, voter1 } = await loadFixture(deployFixture);

      await votingPlatform.write.addDomain(
        ["test.com", POWER_LEVEL, ""], 
        {value: DOMAIN_FEE}
      );

      const domains = await votingPlatform.read.getDomains();
      expect(domains[0]).to.equal("test.com");
    });

    it("Should fail adding domain without payment", async function() {
      const { votingPlatform } = await loadFixture(deployFixture);

      await expect(
        votingPlatform.write.addDomain(["test.com", POWER_LEVEL, ""])
      ).to.be.rejectedWith("Insufficient payment");
    });

    it("Should allow adding subdomains", async function() {
      const { votingPlatform } = await loadFixture(deployFixture);

      await votingPlatform.write.addDomain(
        ["parent.com", POWER_LEVEL, ""],
        {value: DOMAIN_FEE}
      );

      await votingPlatform.write.addDomain(
        ["sub.parent.com", POWER_LEVEL, "parent.com"],
        {value: DOMAIN_FEE}
      );

      const canAccess = await votingPlatform.read.canAccessDomain([
        "sub.parent.com",
        "parent.com"
      ]);
      expect(canAccess).to.be.true;
    });
  });

  describe("Voter Registration", function() {
    it("Should register voter with valid JWT", async function() {
      const { votingPlatform, voter1 } = await loadFixture(deployFixture);

      // Add domain first
      await votingPlatform.write.addDomain(
        ["test.com", POWER_LEVEL, ""],
        {value: DOMAIN_FEE}
      );

      // Mock JWT data with proper byte encoding
      const header = '{"alg":"RS256","kid":"mockKid"}';
      const payload = `{"email":"user@test.com","nonce":"${voter1.account.address}"}`;
      const mockSignature = keccak256(encodePacked(["bytes"], ["0x" + "00".repeat(32)])); // 32 bytes of zeros

      // Add Google key with proper byte encoding
      const mockModulus = keccak256(encodePacked(["bytes"],["0x" + "00".repeat(256)])); // 256 bytes for RSA modulus
    await votingPlatform.write.addModulus([{
      kid: "mockKid",
      modulus: mockModulus
    }]);

      await votingPlatform.write.registerWithDomain(
        header,
        payload,
        mockSignature
      );

      const voter = await votingPlatform.read.voters([voter1.account.address]);
      expect(voter.emailDomain).to.equal("test.com");
    });
});

describe("Proposal Management", function() {
    beforeEach(async function() {
      const { votingPlatform, admin, voter1 } = await loadFixture(deployFixture);
      
      // Setup domain
      await votingPlatform.write.addDomain(
        ["test.com", POWER_LEVEL, ""],
        {value: DOMAIN_FEE}
      );

      // Setup voter with proper byte encoding
      const header = '{"alg":"RS256","kid":"mockKid"}';
      const payload = `{"email":"user@test.com","nonce":"${voter1.account.address}"}`;
      const mockSignature = "0x" + "00".repeat(32);
      
      const mockModulus = keccak256(encodePacked(["bytes"],["0x" + "00".repeat(256)]));
      await votingPlatform.write.addModulus([{
        kid: "mockKid",
        modulus: mockModulus
      }]);

      await votingPlatform.write.registerWithDomain(
        header,
        payload,
        mockSignature
      );
    });

    it("Should create proposal by admin", async function() {
      const { votingPlatform, admin, voter1 } = await loadFixture(deployFixture);

      await votingPlatform.connect(admin).write.createProposal(
        ["QmTest", voter1.account.address, false]
      );

      const proposal = await votingPlatform.read.proposals(["QmTest"]);
      expect(proposal.ipfsHash).to.equal("QmTest");
    });

    it("Should allow voting on active proposal", async function() {
      const { votingPlatform, admin, voter1 } = await loadFixture(deployFixture);

      await votingPlatform.connect(admin).write.createProposal(
        ["QmTest", voter1.account.address, false]
      );

      await votingPlatform.connect(voter1).write.castVote(
        ["QmTest", true]
      );

      const proposal = await votingPlatform.read.proposals(["QmTest"]);
      expect(proposal.votedYes).to.equal(POWER_LEVEL);
    });
});
});