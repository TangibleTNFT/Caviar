const { upgrades } = require("hardhat");

async function main() {
  const null_address = "0x0000000000000000000000000000000000000000";
  const caviarChef_address = "0xD8C61EDe8CD9EE7B93855c3f110191e95eDF2979";
  const bscLqdr_address = "0xE5c6155ed2924e50f998e28eff932d9B5a126974";
  let tx;

  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());

  console.log("\n=== Deploying CaviarChefSecondRewarder ===");
  const CaviarChefSecondRewarder = await ethers.getContractFactory(
    "CaviarChefSecondRewarder"
  );
  const caviarChefSecondRewarder = await upgrades.deployProxy(
    CaviarChefSecondRewarder,
    ["CaviarChefSecondRewarder", bscLqdr_address, 0, caviarChef_address]
  );
  console.log(
    "CaviarChefSecondRewarder address: ",
    caviarChefSecondRewarder.address
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
