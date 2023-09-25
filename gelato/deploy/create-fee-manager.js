const fs = require("fs");
const dotenv = require("dotenv");
const ethers = require("ethers");

const { AutomateSDK } = require("@gelatonetwork/automate-sdk");
const {
  Web3FunctionBuilder,
} = require("@gelatonetwork/web3-functions-sdk/builder");

const hre = require("hardhat");

const network = hre.network;

dotenv.config();

if (!process.env.PK1) throw new Error("Missing env PK1");
const pk = process.env.PK1;

const PROVIDER_URL_KEY = `ALCHEMY_URL_${network.name.toUpperCase()}`;
if (!process.env[PROVIDER_URL_KEY]) throw new Error("Missing env PROVIDER_URL");
const providerUrl = process.env[PROVIDER_URL_KEY];

const chainId = network.config.chainId;

let usdcAddress,
  usdrAddress,
  pearlPairFactoryAddress,
  pearlRouterAddress,
  pearlVEAPIAddress;

if (chainId == 137) {
  usdcAddress = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
  usdrAddress = "0x40379a439D4F6795B6fc9aa5687dB461677A2dBa";
  wusdrAddress = "0x00e8c0E92eB3Ad88189E7125Ec8825eDc03Ab265";
  pearlPairFactoryAddress = "0xEaF188cdd22fEEBCb345DCb529Aa18CA9FcB4FBd";
  pearlRouterAddress = "0xcC25C0FD84737F44a7d38649b69491BBf0c7f083";
  pearlVEAPIAddress = "0xF23131360b6C77b10B05deEdbB49dB9b96d6D1f7";
} else {
  usdcAddress = "0x4b64cCe8Af0f1983fb990B152fb2Ff637d26B636";
  usdrAddress = "0x8885a6E2f1F4BC383963eD848438A8bEC243886F";
  wusdrAddress = "0x7E83396108203f8c2FF4C2ECa0B42788AF45cadb";
  pearlPairFactoryAddress = "0x1a630bf205bbd30707375d395c2F5001b88442B1";
  pearlRouterAddress = "0xd61b7Ad7fA5F0dfeC5bED359cE51b58f1ccCAC18";
  pearlVEAPIAddress = "0x8dBBddf5fe516147D8964f1C8762D2cfe46265cF";
}

const basePath = `deployments/${network.name}`;

const { address: feeManagerAddress } = JSON.parse(
  fs.readFileSync(`${basePath}/CaviarFeeManager.json`, "utf-8")
);
const { address: managerAddress } = JSON.parse(
  fs.readFileSync(`${basePath}/CaviarManager.json`, "utf-8")
);
const { address: strategyAddress } = JSON.parse(
  fs.readFileSync(`${basePath}/CaviarStrategy.json`, "utf-8")
);

const main = async () => {
  // Instance provider & signer
  const provider = new ethers.providers.JsonRpcProvider(providerUrl);
  const wallet = new ethers.Wallet(pk, provider);
  const automate = new AutomateSDK(chainId, wallet);

  // Deploy Web3Function on IPFS
  console.log("Deploying Web3Function on IPFS...");
  const web3Function = "gelato/w3f/fee-manager/index.ts";
  const cid = await Web3FunctionBuilder.deploy(web3Function);
  console.log(`Web3Function IPFS CID: ${cid}`);

  process.exit(0)

  // Create task using automate-sdk
  console.log("Creating automate task...");
  const { taskId, tx } = await automate.createBatchExecTask(
    {
      name: "Web3Function - Caviar Fee Manager",
      web3FunctionHash: cid,
      web3FunctionArgs: {
        useAggregator: false, // network.name === 'polygon'
        usdcAddress,
        usdrAddress,
        wusdrAddress,
        pearlPairFactoryAddress,
        pearlRouterAddress,
        pearlVEAPIAddress,
        feeManagerAddress,
        managerAddress,
        strategyAddress,
      },
    },
    { gasPrice: chainId === 137 ? 140_000_000_000 : 2_000_000_000 }
  );
  await tx.wait(2);
  console.log(`Task created, taskId: ${taskId} (tx hash: ${tx.hash})`);
  console.log(
    `> https://beta.app.gelato.network/task/${taskId}?chainId=${chainId}`
  );

  const { address: gelatoCaller } = await automate.getDedicatedMsgSender();

  for (const address of [managerAddress, feeManagerAddress, strategyAddress]) {
    const contract = new ethers.Contract(
      address,
      [
        "function addKeeper(address _account)",
        "function isKeeper(address _account) view returns (bool)",
      ],
      wallet
    );

    const isKeeper = await contract.isKeeper(gelatoCaller);
    if (!isKeeper) {
      await contract.addKeeper(gelatoCaller, { nonce, gasPrice: chainId === 137 ? 140_000_000_000 : 2_000_000_000 }).then((tx) => tx.wait(2));
    }
  }
};

main()
  .then(() => {
    process.exit();
  })
  .catch((err) => {
    console.error("Error:", err.message);
    process.exit(1);
  });
