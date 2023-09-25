const { ethers, deployments, network } = require("hardhat");

async function main() {
  const { deploy, execute, read } = deployments;
  const null_address = ethers.constants.AddressZero;

  const beginTimestamp = Math.floor(new Date().getTime() / 1000);

  let pearl_address,
    vePearl_address,
    pearlVoter_address,
    pearlRewardsDistributor_address,
    usdcAddress,
    usdrAddress,
    wusdrAddress,
    cvrPearlLPToken,
    cvrPearlLPTokenGauge,
    tngblTreasury,
    rebaseIncentiveVault;

  if (network.name === "polygon") {
    pearl_address = "0x7238390d5f6F64e67c3211C343A410E2A3DEc142";
    vePearl_address = "0x017A26B18E4DA4FE1182723a39311e67463CF633";
    pearlVoter_address = "0xa26C2A6BfeC5512c13Ae9EacF41Cb4319d30cCF0";
    pearlRewardsDistributor_address =
      "0x3171632622d7385adfe295AcaB2e50DDF6df9616";
    usdcAddress = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
    usdrAddress = "0x40379a439D4F6795B6fc9aa5687dB461677A2dBa";
    wusdrAddress = "0x00e8c0E92eB3Ad88189E7125Ec8825eDc03Ab265";
    cvrPearlLPToken = "0x700D6E1167472bDc312D9cBBdc7c58C7f4F45120";
    cvrPearlLPTokenGauge = "0xe4A9ABD56c4c42807e70909Df5853347d20274cE";
    tngblTreasury = "0x6ceD48EfBb581A141667D7487222E42a3FA17cf7"; // for the 20% USDC fee for TNGBL
    rebaseIncentiveVault = "0xbDC1851f669f1E2Fef5990e86C2Fb2CbCC8552B6"; // for the 50% rebase fee
  } else {
    // Mumbai addresses below
    pearl_address = "0x607Ed4f1296C800b3ABCb82Af24Ef382BdA1B181";
    vePearl_address = "0x4735cf16f00DFaDa85D313bE3E2bd39B04522b69";
    pearlVoter_address = "0x61Ac2395cef37e58798abBa762442D8a283B95Ee";
    pearlRewardsDistributor_address =
      "0x1A1e400915A4Bb6e3791590eDA79bFF16DEf419D";
    usdcAddress = "0x4b64cCe8Af0f1983fb990B152fb2Ff637d26B636";
    usdrAddress = "0x8885a6E2f1F4BC383963eD848438A8bEC243886F";
    wusdrAddress = "0x7E83396108203f8c2FF4C2ECa0B42788AF45cadb";
    cvrPearlLPToken = "0x88171cc6416c94739a9c7e9058fa21741761536a";
    cvrPearlLPTokenGauge = "0x89a1dcce918267f2fd339445fd14d93be8359596";
    tngblTreasury = "0xff7AFa1153c4D56756000b29FF534f309129aC26"; // for the 20% USDC fee for TNGBL
    rebaseIncentiveVault = "0xbDC1851f669f1E2Fef5990e86C2Fb2CbCC8552B6"; // for the 50% rebase fee
  }

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());

  console.log("\n=== Deploying Caviar FeeManager ===");
  const feeManager = await deploy("CaviarFeeManager", {
    from: deployer.address,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: ["FeeManager"],
        },
      },
    },
    waitConfirmations: 2,
  });
  console.log("FeeManager address: ", feeManager.address);

  if (feeManager.newlyDeployed) {
    await hre
      .run("verify:verify", {
        address: feeManager.address,
      })
      .catch(() => console.warn("> not verified"));
  }

  const rewardTokens = [];
  for (const token of [
    "0x00e8c0E92eB3Ad88189E7125Ec8825eDc03Ab265", // USDR
    "0x40379a439D4F6795B6fc9aa5687dB461677A2dBa", // WUSDR
    "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // WMATIC
    "0xc2132D05D31c914a87C6611C10748AEb04B58e8F", // USDT
    "0x49e6A20f1BBdfEeC2a8222E052000BbB14EE6007", // TNGBL
    "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", // WETH
    "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC
    "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063", // DAI
    "0x7238390d5f6F64e67c3211C343A410E2A3DEc142", // PEARL
  ]) {
    const isRewardToken = await read("CaviarFeeManager", {}, "isToken", token);
    if (!isRewardToken) {
      rewardTokens.push(token);
    }
  }

  if (rewardTokens.length !== 0) {
    if (rewardTokens.length === 1) {
      await execute(
        "CaviarFeeManager",
        {
          from: deployer.address,
          log: true,
          waitConfirmations: 2,
        },
        "addRewardToken",
        rewardTokens[0]
      );
    } else {
      await execute(
        "CaviarFeeManager",
        {
          from: deployer.address,
          log: true,
          waitConfirmations: 2,
        },
        "addRewardTokens",
        rewardTokens
      );
    }
  }

  if (
    await read("CaviarFeeManager", {}, "usdc").then((a) => a !== usdcAddress)
  ) {
    await execute(
      "CaviarFeeManager",
      {
        from: deployer.address,
        log: true,
        waitConfirmations: 2,
      },
      "setUSDC",
      usdcAddress
    );
  }

  if (
    await read("CaviarFeeManager", {}, "usdr").then((a) => a !== usdrAddress)
  ) {
    await execute(
      "CaviarFeeManager",
      {
        from: deployer.address,
        log: true,
        waitConfirmations: 2,
      },
      "setUSDR",
      usdrAddress
    );
  }

  if (
    await read("CaviarFeeManager", {}, "wusdr").then((a) => a !== wusdrAddress)
  ) {
    await execute(
      "CaviarFeeManager",
      {
        from: deployer.address,
        log: true,
        waitConfirmations: 2,
      },
      "setWUSDR",
      wusdrAddress
    );
  }
/*
  await execute(
    "CaviarFeeManager",
    {
      from: deployer.address,
      log: true,
      waitConfirmations: 2,
    },
    "setFees",
    80,
    20,
    50
  );
*/
  console.log("\n=== Deploying Caviar Token ===");
  const caviar = await deploy("Caviar", {
    from: deployer.address,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
        },
      },
    },
    waitConfirmations: 2,
  });
  console.log("Caviar address: ", caviar.address);

  if (caviar.newlyDeployed) {
    await hre
      .run("verify:verify", {
        address: caviar.address,
      })
      .catch(() => console.warn("> not verified"));
  }

  console.log("\n=== Deploying CaviarChefs ===");

  const period = ["hardhat", "localhost", "mumbai"].includes(network.name)
    ? 1200
    : 7 * 86400;

  const caviarStakingChef = await deploy("CaviarStakingChef", {
    contract: "CaviarChef",
    from: deployer.address,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            "StakingChef",
            wusdrAddress,
            caviar.address,
            period,
          ],
        },
      },
      waitConfirmations: 2,
    },
  });
  console.log("CaviarStakingChef address: ", caviarStakingChef.address);
  if (caviarStakingChef.newlyDeployed) {
    await hre
      .run("verify:verify", {
        address: caviarStakingChef.address,
      })
      .catch(() => console.warn("> not verified"));
  }

  const caviarRebaseChef = await deploy("CaviarRebaseChef", {
    contract: "CaviarRebaseChef",
    from: deployer.address,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: ["RebaseChef", caviar.address, period],
        },
      },
    },
    waitConfirmations: 2,
  });
  console.log("CaviarRebaseChef address: ", caviarRebaseChef.address);
  if (caviarRebaseChef.newlyDeployed) {
    await hre
      .run("verify:verify", {
        address: caviarRebaseChef.address,
      })
      .catch(() => console.warn("> not verified"));
  }

  console.log("\n=== Deploying Caviar Strategy ===");
  const caviarStrategy = await deploy("CaviarStrategy", {
    from: deployer.address,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            "CaviarStrategy",
            pearl_address,
            vePearl_address,
            pearlVoter_address,
            feeManager.address,
            pearlRewardsDistributor_address,
            2,
          ],
        },
      },
    },
    waitConfirmations: 2,
  });

  console.log("CaviarStrategy address: ", caviarStrategy.address);
  if (caviarStrategy.newlyDeployed) {
    await hre
      .run("verify:verify", {
        address: caviarStrategy.address,
      })
      .catch(() => console.warn("> not verified"));
  }

  console.log("\n=== Deploying CaviarManager ===");
  const caviarManager = await deploy("CaviarManager", {
    from: deployer.address,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            "Manager",
            caviarStrategy.address,
            caviar.address,
            pearl_address,
            vePearl_address,
            null_address,
            feeManager.address,
            2,
          ],
        },
      },
    },
    waitConfirmations: 2,
  });

  console.log("CaviarManager address: ", caviarManager.address);
  if (caviarManager.newlyDeployed) {
    await hre
      .run("verify:verify", {
        address: caviarManager.address,
      })
      .catch(() => console.warn("> not verified"));
  }

  console.log("\n=== Deploying CaviarLPChef ===");
  const caviarLPChef = await deploy("CaviarLPChef", {
    contract: "CaviarLPChef",
    from: deployer.address,
    log: true,
    proxy: {
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            "LPChef",
            caviar.address,
            cvrPearlLPToken,
            period,
            caviarManager.address,
            pearl_address,
            cvrPearlLPTokenGauge,
          ],
        }
      },
    },
    waitConfirmations: 2,
  });
  console.log("CaviarLPChef address: ", caviarLPChef.address);
  if (caviarLPChef.newlyDeployed) {
    await hre
      .run("verify:verify", {
        address: caviarLPChef.address,
      })
      .catch(() => console.warn("> not verified"));
  }

  console.log("\n=== Setting CaviarManager to the Strategy ===");
  let readAddress = await read(
    "CaviarStrategy",
    { from: deployer.address, log: true },
    "caviarManager"
  );
  if (readAddress !== caviarManager.address) {
    tx = await execute(
      "CaviarStrategy",
      { from: deployer.address, log: true },
      "setCaviarManager",
      caviarManager.address
    );
  }
  console.log("done");

  console.log("\n=== Setting CaviarManager to the FeeManager ===");

  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "caviarManager"
  );
  if (readAddress !== caviarManager.address) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setCaviarManager",
      caviarManager.address
    );
  }
  console.log("done");

  console.log("\n=== Setting Operator in Caviar token ===");

  readAddress = await read(
    "Caviar",
    { from: deployer.address, log: true },
    "operator"
  );
  if (readAddress !== caviarManager.address) {
    tx = await execute(
      "Caviar",
      { from: deployer.address, log: true },
      "setOperator",
      caviarManager.address
    );
  }
  console.log("done");

  console.log("\n=== Setting BeginTimestamp ===");
  const timestampBegin = await read(
    "CaviarManager",
    { from: deployer.address, log: true },
    "beginTimestamp"
  );
  if (Number(timestampBegin) !== beginTimestamp) {
    tx = await execute(
      "CaviarManager",
      { from: deployer.address, log: true },
      "setBeginTimestamp",
      beginTimestamp
    );
  }
  console.log("done");

  console.log("\n=== Setting Underlying in CaviarLPChef ===");
  readAddress = await read(
    "CaviarLPChef",
    { from: deployer.address, log: true },
    "underlying"
  );
  if (readAddress !== cvrPearlLPToken) {
    tx = await execute(
      "CaviarLPChef",
      { from: deployer.address, log: true },
      "setUnderlyingToken",
      cvrPearlLPToken
    );
  }
  console.log("done");

  console.log("\n=== Setting pearlPair in CaviarManager ===");
  readAddress = await read(
    "CaviarManager",
    { from: deployer.address, log: true },
    "pearlPair"
  );
  if (readAddress !== cvrPearlLPToken) {
    tx = await execute(
      "CaviarManager",
      { from: deployer.address, log: true },
      "setPearlPair",
      cvrPearlLPToken
    );
  }
  console.log("done");

  console.log("\n=== Setting gaugeForLP in CaviarLPChef ===");
  readAddress = await read(
    "CaviarLPChef",
    { from: deployer.address, log: true },
    "gaugeForLP"
  );
  if (readAddress !== cvrPearlLPTokenGauge) {
    tx = await execute(
      "CaviarLPChef",
      { from: deployer.address, log: true },
      "setGaugeForLP",
      cvrPearlLPTokenGauge
    );
  }
  console.log("done");

  console.log("\n=== Setting stakingChef in CaviarRebaseChef ===");
  readAddress = await read(
    "CaviarRebaseChef",
    { from: deployer.address, log: true },
    "stakingChef"
  );
  if (readAddress !== caviarStakingChef.address) {
    tx = await execute(
      "CaviarRebaseChef",
      { from: deployer.address, log: true },
      "setStakingChef",
      caviarStakingChef.address
    );
  }
  console.log("done");

  console.log("\n=== Setting rebaseChef in CaviarChef ===");
  readAddress = await read(
    "CaviarStakingChef",
    { from: deployer.address, log: true },
    "rebaseChef"
  );
  if (readAddress !== caviarRebaseChef.address) {
    tx = await execute(
      "CaviarStakingChef",
      { from: deployer.address, log: true },
      "setRebaseChef",
      caviarRebaseChef.address
    );
  }
  console.log("done");

  console.log("\n=== Setting pearlPair in CaviarFeeManager ===");
  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "pearlPair"
  );
  if (readAddress !== cvrPearlLPToken) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setPearlPair",
      cvrPearlLPToken
    );
  }
  console.log("done");

  console.log("\n=== Setting chefs in CaviarFeeManager ===");
  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "rebaseChef"
  );
  if (readAddress !== caviarRebaseChef.address) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setRebaseChef",
      caviarRebaseChef.address
    );
  }
  console.log("done");
  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "stakingChef"
  );
  if (readAddress !== caviarStakingChef.address) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setStakingChef",
      caviarStakingChef.address
    );
  }
  console.log("done");
  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "lpChef"
  );
  if (readAddress !== caviarLPChef.address) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setLPChef",
      caviarLPChef.address
    );
  }
  console.log("done");
  console.log("\n=== Setting caviar in CaviarFeeManager ===");
  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "caviar"
  );
  if (readAddress !== caviar.address) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setCaviar",
      caviar.address
    );
  }
  console.log("done");
  console.log("\n=== Setting TNGBL treasury vault ===");
  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "treasury"
  );
  if (readAddress !== tngblTreasury) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setTreasury",
      tngblTreasury
    );
  }
  console.log("done");
  console.log("\n=== Setting rebase incentive vault ===");
  readAddress = await read(
    "CaviarFeeManager",
    { from: deployer.address, log: true },
    "incentiveVault"
  );
  if (readAddress !== rebaseIncentiveVault) {
    tx = await execute(
      "CaviarFeeManager",
      { from: deployer.address, log: true },
      "setIncentiveVault",
      rebaseIncentiveVault
    );
  }
  console.log("done");
  console.log("\n=== Setting pearl token in CaviarManager ===");
  readAddress = await read(
    "CaviarManager",
    { from: deployer.address, log: true },
    "pearl"
  );
  if (readAddress !== pearl_address) {
    tx = await execute(
      "CaviarManager",
      { from: deployer.address, log: true },
      "setPearl",
      pearl_address
    );
  }
  console.log("done");
  console.log("\n=== Setting pearl token in CaviarStrategy ===");
  readAddress = await read(
    "CaviarStrategy",
    { from: deployer.address, log: true },
    "pearl"
  );
  if (readAddress !== pearl_address) {
    tx = await execute(
      "CaviarStrategy",
      { from: deployer.address, log: true },
      "setPearl",
      pearl_address
    );
  }
  console.log("done");
  console.log("\n=== Setting pearl token in CaviarLPChef ===");
  readAddress = await read(
    "CaviarLPChef",
    { from: deployer.address, log: true },
    "pearl"
  );
  if (readAddress !== pearl_address) {
    tx = await execute(
      "CaviarLPChef",
      { from: deployer.address, log: true },
      "setPearl",
      pearl_address
    );
  }
  console.log("done");
  console.log("\n=== Setting vePearl token in CaviarManager ===");
  readAddress = await read(
    "CaviarManager",
    { from: deployer.address, log: true },
    "vePearl"
  );
  if (readAddress !== pearl_address) {
    tx = await execute(
      "CaviarManager",
      { from: deployer.address, log: true },
      "setVEPearl",
      vePearl_address
    );
  }
  console.log("done");
  console.log("\n=== Setting vePearl token in CaviarStrategy ===");
  readAddress = await read(
    "CaviarStrategy",
    { from: deployer.address, log: true },
    "vePearl"
  );
  if (readAddress !== pearl_address) {
    tx = await execute(
      "CaviarStrategy",
      { from: deployer.address, log: true },
      "setVEPearl",
      vePearl_address
    );
  }
  console.log("done");
  console.log("\n=== Setting pearlVoter in CaviarStrategy ===");
  readAddress = await read(
    "CaviarStrategy",
    { from: deployer.address, log: true },
    "pearlVoter"
  );
  if (readAddress !== pearlVoter_address) {
    tx = await execute(
      "CaviarStrategy",
      { from: deployer.address, log: true },
      "setPearlVoter",
      pearlVoter_address
    );
  }
  console.log("done");
  console.log("\n=== Setting pearlRewardsDistributor in CaviarStrategy ===");
  readAddress = await read(
    "CaviarStrategy",
    { from: deployer.address, log: true },
    "pearlRewardsDistributor"
  );
  if (readAddress !== pearlRewardsDistributor_address) {
    tx = await execute(
      "CaviarStrategy",
      { from: deployer.address, log: true },
      "setPearlRewardsDistributor",
      pearlRewardsDistributor_address
    );
  }
  console.log("done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
