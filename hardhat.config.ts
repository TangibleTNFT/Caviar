// hardhat.config.ts

import "dotenv/config"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-solhint"
import "@tenderly/hardhat-tenderly"
import "@nomiclabs/hardhat-waffle"
import "hardhat-abi-exporter"
import "hardhat-deploy"
import "hardhat-deploy-ethers"
import "hardhat-gas-reporter"
import "hardhat-spdx-license-identifier"
import "hardhat-typechain"
import "hardhat-watcher"
import "solidity-coverage"
import '@openzeppelin/hardhat-upgrades';

import { HardhatUserConfig } from "hardhat/types"
import { removeConsoleLog } from "hardhat-preprocessor"

const accounts = {
  mnemonic: process.env.MNEMONIC || "testaa test test test test test test test test test test junk",
  // accountsBalance: "990000000000000000000",
}

const config: HardhatUserConfig = {
  abiExporter: {
    path: "./abi",
    clear: false,
    flat: true,
    // only: [],
    // except: []
  },
  defaultNetwork: "hardhat",
  etherscan: {
    apiKey: process.env.BNBSCAN_API_KEY,
  },
  gasReporter: {
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    currency: "USD",
    enabled: process.env.REPORT_GAS === "true",
    excludeContracts: ["contracts/mocks/", "contracts/libraries/"],
  },
  mocha: {
    timeout: 20000000000000000,
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    dev: {
      // Default to 1
      default: 1,
      // dev address mainnet
      // 1: "",
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://polygon-rpc.com/",
      },
    },
    localhost: {
      live: false,
      saveDeployments: true,
      tags: ["local"],
    },
    polygon: {
      url: "https://polygon-rpc.com",
      chainId: 137,
      live: true,
      saveDeployments: true,
      gasPrice: 20 * 1000000000,
    },
    fantom: {
      url: "https://rpcapi-tracing.fantom.network/",
      chainId: 250,
      live: true,
      saveDeployments: true,
      gasPrice: 200 * 1000000000,
    },
    bnb: {
      url: "https://bsc-dataseed1.binance.org/",
      chainId: 56,
      gasPrice: 10 * 1000000000,
    },
    bnbtestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      gasPrice: 5 * 1000000000,
    },
    arbi: {
      url: "https://rpc.ankr.com/arbitrum/",
      chainId: 42161,
      gasPrice: 0.1 * 1000000000,
    },
  },
  paths: {
    artifacts: "artifacts",
    cache: "cache",
    deploy: "deploy",
    deployments: "deployments",
    imports: "imports",
    sources: "contracts",
    tests: "test",
  },
  preprocess: {
    eachLine: removeConsoleLog((bre) => bre.network.name !== "hardhat" && bre.network.name !== "localhost"),
  },
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.2",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  tenderly: {
    project: process.env.TENDERLY_PROJECT!,
    username: process.env.TENDERLY_USERNAME!,
  },
  typechain: {
    outDir: "types",
    target: "ethers-v5",
  },
}

export default config
