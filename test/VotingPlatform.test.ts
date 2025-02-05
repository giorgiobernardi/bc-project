import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import hre from "hardhat";
import { parseEther } from "viem";


describe("VotingPlatform", function () {
  const ONE_DAY = 86400;
  const REGISTRATION_DURATION = 10 * ONE_DAY;
  const DOMAIN_FEE = parseEther("1"); // 1 ETH
  const POWER_LEVEL = 2n;

  async function deployFixture() {

    const owner = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
    const admin = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

    const headerJson = '{"alg":"RS256","kid":"fa072f75784642615087c7182c101341e18f7a3a","typ":"JWT"}';

    const payloadJson = '{"iss":"https://accounts.google.com","azp":"148714805290-dj5sljtj437rr5nu8hcpo85pm869201e.apps.googleusercontent.com","aud":"148714805290-dj5sljtj437rr5nu8hcpo85pm869201e.apps.googleusercontent.com","sub":"105004160682025368425","hd":"studenti.unitn.it","email":"giorgio.bernardi@studenti.unitn.it","email_verified":true,"nonce":"85_W5RqtiPb0zmq4gnJ5z_-5ImY","nbf":1738764364,"name":"Giorgio Bernardi","picture":"https://lh3.googleusercontent.com/a/ACg8ocKtJQzvuCjQd5Oafm_j6hjqNjqgKCIptou5fuJa3NQPvljEWQ=s96-c","given_name":"Giorgio","family_name":"Bernardi","iat":1738764664,"exp":1738768264,"jti":"f2073c8e8f56b898b6d9f73326548e5e0b58bf0a"}';

    const mockSignature = "0x9e21e61bad1c217b80c2a48d97a473809e659e999207a8ce691f4ab084f5665dcdfb4bdd5f7e84173712c17eac2f87f2f88bcbfd02be6d9ec6d8643c408e5e6499883729270520d4dc5e4c79d35d6bb7004c2e2a736bbe2698fdb90f307a058da3ca0914b335577b2f13c8c896b0a82e257495212097948b61e897feee9fce8ccf283dca12b904cfe20a101d3c5bc9164c5b5642b79a79ba3b261ca93c4ca87fd7dd92b4ef88d95903a909c2edb20965149c57164d9a047e3d8089dd08f5203068968863c6925f179cad839454ffe1ca4b2c86865fcf3e713cf8a6c54df2c4ec14031f3456b31192ab50c739a556440f87c207529013e3c548b6f8e534e9996e";

    // Add Google key with proper byte encoding
    const mockModulus = "0xa657ae1744720ec113ca0667f3d46919514d3311bf85d6159ef6c769dbccd6d631b3d8210eaf77345c5e8edfbed50970a4b437cae558fc22a57640168333d597cfa85017b9c61f63ce92d44ea732ad2d5a14bbb301ed77f8e4da754135f30be1cfd82841ff34ae0e48ced0ff80178f38e044ede5871aa58b821b8c6fb708623805c6a345c8f9fc6c5ffb93ca5001e1c83ee6bfebf187870dcc2f89aca7e694eced62a376783ff062affebf0b927d52d580709d04cf4602e45c4e324876ee3a0ee6651ab3c92b1a716a2094ce803617402d504eef8738244dbe2ea014ca849034cfe6804ad9c0cf0eae4bd13f10d146a748f47406e3931deb025e70c07717725f";

    const kid = "fa072f75784642615087c7182c101341e18f7a3a";

    // Deploy contract
    const votingPlatform = await hre.viem.deployContract("VotingPlatform", [
      ONE_DAY,
      admin,
      owner
    ]);

    return {
      votingPlatform,
      owner,
      admin,
      headerJson,
      payloadJson,
      mockSignature,
      mockModulus,
      kid
    };
  }

  describe("Domain Management", function () {
    it("Should allow adding a domain with correct payment", async function () {
      const { votingPlatform } = await loadFixture(deployFixture);

      await votingPlatform.write.addDomain(
        ["test.com", POWER_LEVEL, ""],
        { value: DOMAIN_FEE }
      );

      const domains = await votingPlatform.read.getDomains();
      expect(domains[0]).to.equal("test.com");
    });

    it("Should fail adding domain without payment", async function () {
      const { votingPlatform } = await loadFixture(deployFixture);

      await expect(
        votingPlatform.write.addDomain(["test.com", POWER_LEVEL, ""])
      ).to.be.rejectedWith("Insufficient payment");
    });

    it("Should allow adding subdomains", async function () {
      const { votingPlatform } = await loadFixture(deployFixture);

      await votingPlatform.write.addDomain(
        ["parent.com", POWER_LEVEL, ""],
        { value: DOMAIN_FEE }
      );

      await votingPlatform.write.addDomain(
        ["sub.parent.com", POWER_LEVEL, "parent.com"],
        { value: DOMAIN_FEE }
      );

      const canAccess = await votingPlatform.read.canAccessDomain([
        "sub.parent.com",
        "parent.com"
      ]);
      expect(canAccess).to.be.true;
    });
  });

  describe("Voter Registration", function () {
    it("Should register voter with valid JWT", async function () {
      const { votingPlatform, kid, mockModulus, headerJson, payloadJson, mockSignature, owner } = await loadFixture(deployFixture);

      // Add domain first
      await votingPlatform.write.addDomain(
        ["studenti.unitn.it", POWER_LEVEL, ""],
        { value: DOMAIN_FEE }
      );

      // error: signature should be the RSA of the header and payload!


      await votingPlatform.write.addModulus([[{
        kid: kid,
        modulus: mockModulus
      }]]);

      await votingPlatform.write.registerWithDomain(
        [headerJson,
          payloadJson,
          mockSignature]
      );

      const voter = await votingPlatform.read.voters([owner]);
      expect(voter[1]).to.equal("studenti.unitn.it");
    });
  });

  describe("Proposal Management", function () {

    it("Should create proposal by admin", async function () {
      const { votingPlatform, admin, owner, headerJson, payloadJson, mockSignature, mockModulus, kid } = await loadFixture(deployFixture);

      await votingPlatform.write.addDomain(
        ["studenti.unitn.it", POWER_LEVEL, ""],
        { value: DOMAIN_FEE }
      );

      await votingPlatform.write.addModulus([[{
        kid: kid,
        modulus: mockModulus
      }]]);

      await votingPlatform.write.registerWithDomain(
        [headerJson,
          payloadJson,
          mockSignature]
      );

      // Then make the contract call as the impersonated account
      await votingPlatform.write.createProposal(
        ["QmTest", owner, false],
        { account: admin } // Use account option to specify the sender
      );

      const proposal = await votingPlatform.read.proposals(["QmTest"]);
      expect(proposal[0]).to.equal("QmTest");
    });

    it("Should allow voting on active proposal", async function () {
      const { votingPlatform, owner, admin, headerJson, payloadJson, mockSignature, kid, mockModulus } = await loadFixture(deployFixture);

      await votingPlatform.write.addDomain(
        ["studenti.unitn.it", POWER_LEVEL, ""],
        { value: DOMAIN_FEE }
      );

      await votingPlatform.write.addModulus([[{
        kid: kid,
        modulus: mockModulus
      }]]);

      await votingPlatform.write.registerWithDomain(
        [headerJson,
          payloadJson,
          mockSignature]
      );

      await votingPlatform.write.createProposal(
        ["QmTest", owner, false],
        { account: admin } // Use account option to specify the sender

      );

      await votingPlatform.write.castVote(
        ["QmTest", true]
      );

      const proposal = await votingPlatform.read.proposals(["QmTest"]);
      expect(proposal[1]).to.equal(POWER_LEVEL);
    });
  });
});