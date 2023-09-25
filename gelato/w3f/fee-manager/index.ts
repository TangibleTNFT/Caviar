import { Web3Function, Web3FunctionContext, Web3FunctionResult } from "@gelatonetwork/web3-functions-sdk"
import { utils, Contract, providers, ethers } from "ethers"

import axios from "axios"

const ERC20_ABI = ["function decimals() view returns (uint8)"]

const FEE_MANAGER_ABI = [
  "function checkConvertibleRewards() view returns (bool canConvert, address token, uint256 amount)",
  "function pendingTngblFee() view returns (uint256)",
  "function convertRewardToken(address token, uint256 amount, address target, bytes calldata data)",
  "function distributeTngblFees(uint256 amount, address target, bytes calldata data)",
]

const MANAGER_ABI = ["function rebase() returns (uint256)", "function claimLPRewards()"]

const MULTICALL_ABI = ["function aggregate(tuple(address target, bytes callData)[] calls) view returns (uint256, bytes[] memory)"]

const PAIR_FACTORY_ABI = ["function allPairsLength() view returns (uint256)", "function allPairs(uint256 _index) view returns (address)"]

const STRATEGY_ABI = [
  "function tokenId() view returns (uint256)",
  "function claimBribe(address[] memory _bribes, address[][] memory _tokens)",
  "function claimFee(address[] memory _fees, address[][] memory _tokens)",
]

const VE_ABI_ABI = [
  "function singlePairReward(uint256 _tokenId, address _pair) view returns (tuple(uint256 tokenId, uint256 amount, uint8 decimals, address pair, address token, address fee, address bribe, string symbol)[] memory reward)",
]

Web3Function.onRun(async (context: Web3FunctionContext) => {
  const { multiChainProvider, secrets } = context
  const {
    useAggregator,
    usdcAddress,
    usdrAddress,
    wusdrAddress,
    pearlPairFactoryAddress,
    pearlRouterAddress,
    pearlVEAPIAddress,
    feeManagerAddress,
    strategyAddress,
    managerAddress,
  } = context.userArgs as {
    useAggregator: boolean
    usdcAddress: string
    usdrAddress: string
    wusdrAddress: string
    pearlPairFactoryAddress: string
    pearlRewardAPIAddress: string
    pearlRouterAddress: string
    pearlVEAPIAddress: string
    feeManagerAddress: string
    strategyAddress: string
    managerAddress: string
  }

  const calls: { to: string; data: string }[] = []
  const ops: string[] = []
  const provider = multiChainProvider.default()

  const multicallAddress = "0xcA11bde05977b3631167028862bE2a173976CA11" // see https://www.multicall3.com/deployments

  const multicall = new Contract(multicallAddress, MULTICALL_ABI, provider)
  const pairFactory = new Contract(pearlPairFactoryAddress, PAIR_FACTORY_ABI, provider)
  const strategy = new Contract(strategyAddress, STRATEGY_ABI, provider)
  const manager = new Contract(managerAddress, MANAGER_ABI, provider)
  const veAPI = new Contract(pearlVEAPIAddress, VE_ABI_ABI, provider)

  // const claimedRebaseAmount = await manager.callStatic.rebase({ from: "0x897d873CafeF9a1F0163760Ea3D19A06B96ae8E9" })
  const claimedRebaseAmount = await manager.callStatic.rebase({ from: "0x708244908cf90731c6e4db26e0dbfee50fbb6f4d" })

  if (!claimedRebaseAmount.eq(ethers.constants.Zero)) {
    calls.push({
      to: managerAddress,
      data: manager.interface.encodeFunctionData("rebase"),
    })

    calls.push({
      to: managerAddress,
      data: manager.interface.encodeFunctionData("claimLPRewards"),
    })

    ops.push("rebasing")
    ops.push("claiming LP rewards")

    const [numPairs, tokenId] = await multicall.callStatic
      .aggregate([
        {
          target: pearlPairFactoryAddress,
          callData: pairFactory.interface.encodeFunctionData("allPairsLength"),
        },
        {
          target: strategyAddress,
          callData: strategy.interface.encodeFunctionData("tokenId"),
        },
      ])
      .then((result) => {
        const [, encoded] = result
        const [numPairs] = pairFactory.interface.decodeFunctionResult("allPairsLength", encoded[0])
        const [tokenId] = strategy.interface.decodeFunctionResult("tokenId", encoded[1])
        return [numPairs.toNumber(), tokenId]
      })

    const pairCalls = [...Array.from(Array(numPairs).keys())]
      .map((i) => pairFactory.interface.encodeFunctionData("allPairs", [i]))
      .map((data) => {
        return {
          target: pearlPairFactoryAddress,
          callData: data,
        }
      })

    const pairs = await multicall.callStatic
      .aggregate(pairCalls)
      .then((result) => {
        let [, encodedPairs] = result
        return encodedPairs.map((p) => pairFactory.interface.decodeFunctionResult("allPairs", p))
      })
      .then((results: string[][]) => results.flat())

    const rewardCalls = pairs
      .map((pair) => veAPI.interface.encodeFunctionData("singlePairReward", [tokenId, pair]))
      .map((data) => {
        return {
          target: pearlVEAPIAddress,
          callData: data,
        }
      })

    const rewards = (await multicall.callStatic
      .aggregate(rewardCalls)
      .then((result) => {
        let [, encodedRewards] = result
        return encodedRewards.map((r) => veAPI.interface.decodeFunctionResult("singlePairReward", r))
      })
      .then((results: any[][]) =>
        results
          .flat()
          .flat()
          .filter((reward) => reward.amount.gt(0))
          .reduce(
            (acc, item) => {
              const { bribe, fee, token } = item
              if (bribe !== ethers.constants.AddressZero) {
                if (!acc.bribes[bribe]) {
                  acc.bribes[bribe] = []
                }
                acc.bribes[bribe].push(token)
                return acc
              } else {
                if (!acc.fees[fee]) {
                  acc.fees[fee] = []
                }
                acc.fees[fee].push(token)
                return acc
              }
            },
            { bribes: {}, fees: {} }
          )
      )) as { bribes: { [key: string]: string[] }; fees: { [key: string]: string[] } }

    if (Object.keys(rewards.bribes).length != 0) {
      const bribes: string[] = []
      const tokens: string[][] = []
      let numClaims = 0
      for (const bribe of Object.keys(rewards.bribes)) {
        bribes.push(bribe)
        tokens.push(rewards.bribes[bribe])
        numClaims += rewards.bribes[bribe].length
      }
      calls.push({
        to: strategyAddress,
        data: strategy.interface.encodeFunctionData("claimBribe", [bribes, tokens]),
      })
      ops.push(`claiming ${numClaims} bribe reward${numClaims !== 1 ? "s" : ""}`)
    }

    if (Object.keys(rewards.fees).length != 0) {
      const fees: string[] = []
      const tokens: string[][] = []
      let numClaims = 0
      for (const fee of Object.keys(rewards.fees)) {
        fees.push(fee)
        tokens.push(rewards.fees[fee])
        numClaims += rewards.fees[fee].length
      }
      calls.push({
        to: strategyAddress,
        data: strategy.interface.encodeFunctionData("claimFee", [fees, tokens]),
      })
      ops.push(`claiming ${numClaims} trading fee${numClaims !== 1 ? "s" : ""}`)
    }
  } else {
    const caviarFeeManager = new Contract(feeManagerAddress, FEE_MANAGER_ABI, provider)
    const pearlExchange = new PearlExchange(provider, pearlRouterAddress)
    const aggregator = useAggregator ? new FallbackSwapProvider(new Kyber(await secrets.get("KYBER_OPTIONS")), new OpenOcean(), pearlExchange) : pearlExchange;
    const wusdr = new ethers.Contract(wusdrAddress, ["function previewRedeem(uint256 shares) view returns (uint256)"], provider)

    const [pendingTngblFee, canConvert, token, amount] = await multicall.callStatic
      .aggregate([
        {
          target: feeManagerAddress,
          callData: caviarFeeManager.interface.encodeFunctionData("pendingTngblFee"),
        },
        {
          target: feeManagerAddress,
          callData: caviarFeeManager.interface.encodeFunctionData("checkConvertibleRewards"),
        },
      ])
      .then((result) => {
        const [, encoded] = result
        const [pendingTngblFee] = caviarFeeManager.interface.decodeFunctionResult("pendingTngblFee", encoded[0])
        const [canConvert, token, amount] = caviarFeeManager.interface.decodeFunctionResult("checkConvertibleRewards", encoded[1])
        return [pendingTngblFee, canConvert, token, amount]
      })

    const pendingTngblFeeInUsdr = await wusdr.previewRedeem(pendingTngblFee)
    if (pendingTngblFeeInUsdr.gt(0)) {
      const { tx } = await aggregator.getSwap(caviarFeeManager.address, usdrAddress, 9, usdcAddress, 6, pendingTngblFeeInUsdr)
      const { to: target, data } = tx
      calls.push({
        to: caviarFeeManager.address,
        data: caviarFeeManager.interface.encodeFunctionData("distributeTngblFees", [pendingTngblFee, target, data]),
      })
      ops.push("distributing fees to Tangible")
    } else {
      if (canConvert) {
        const tokenContract = new ethers.Contract(token, ERC20_ABI, provider)
        const tokenDecimals = await tokenContract.decimals()
        let target: string
        let data: string
        if (token === usdrAddress) {
          target = ethers.constants.AddressZero;
          data = "0x";
        } else if (token === wusdrAddress) {
          target = wusdrAddress
          data = new ethers.utils.Interface([
            "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
          ]).encodeFunctionData("redeem", [amount, caviarFeeManager.address, caviarFeeManager.address])
        } else {
          const { tx } = await aggregator.getSwap(caviarFeeManager.address, token, tokenDecimals, usdrAddress, 9, amount)
          target = tx.to
          data = tx.data
        }
        calls.push({
          to: caviarFeeManager.address,
          data: caviarFeeManager.interface.encodeFunctionData("convertRewardToken", [token, amount, target, data]),
        })
        ops.push(`converting reward token ${token}`)
      }
    }
  }

  if (ops.length !== 0) {
    console.log(`Ops: ${ops.join(", ")}`)
  }

  let result: Web3FunctionResult

  if (calls.length != 0) {
    result = {
      canExec: true,
      callData: calls,
    }
  } else {
    result = {
      canExec: false,
      message: "no claimable fees",
    }
  }

  return result
})

interface ISwapProvider {
  getSwap(
    from: string,
    tokenIn: string,
    tokenInDecimals: number,
    tokenOut: string,
    tokenOutDecimals: number,
    amountIn: ethers.BigNumber
  ): Promise<{ toTokenAmount: ethers.BigNumber; tx: { from: string; to: string; value: number; data: string } }>
}

class FallbackSwapProvider implements ISwapProvider {
  private providers: ISwapProvider[]

  constructor(...providers: ISwapProvider[]) {
    this.providers = providers
  }

  async getSwap(
    from: string,
    tokenIn: string,
    tokenInDecimals: number,
    tokenOut: string,
    tokenOutDecimals: number,
    amountIn: ethers.BigNumber
  ): Promise<{ toTokenAmount: ethers.BigNumber; tx: { from: string; to: string; value: number; data: string } }> {
    for (const provider of this.providers) {
      try {
        return provider.getSwap(from, tokenIn, tokenInDecimals, tokenOut, tokenOutDecimals, amountIn);
      } catch {}
    }
    throw new Error('Unable to swap through any of the given swap providers');
  }
}

class PearlExchange implements ISwapProvider {
  private provider: providers.Provider
  private pearlRouterAddress: string

  constructor(provider: providers.Provider, pearlRouterAddress: string) {
    this.provider = provider
    this.pearlRouterAddress = pearlRouterAddress
  }

  async getSwap(
    from: string,
    tokenIn: string,
    tokenInDecimals: number,
    tokenOut: string,
    tokenOutDecimals: number,
    amountIn: ethers.BigNumber
  ): Promise<{ toTokenAmount: ethers.BigNumber; tx: { from: string; to: string; value: number; data: string } }> {
    const routerAbi = [
      "function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256 amount, bool stable)",
      "function swapExactTokensForTokensSimple(uint256 amountIn, uint256 amountOutMin, address tokenFrom, address tokenTo, bool stable, address to, uint256 deadline) external returns (uint256[])",
    ]

    const router = new ethers.Contract(this.pearlRouterAddress, routerAbi, this.provider)
    const [toTokenAmount, stable] = await router.getAmountOut(amountIn, tokenIn, tokenOut)
    const minAmountOut = toTokenAmount.mul(998).div(1000)
    const data = router.interface.encodeFunctionData("swapExactTokensForTokensSimple", [
      amountIn,
      minAmountOut,
      tokenIn,
      tokenOut,
      stable,
      from,
      ethers.constants.MaxUint256,
    ])

    return {
      toTokenAmount,
      tx: {
        from,
        to: router.address,
        value: 0,
        data,
      },
    }
  }
}

class OpenOcean implements ISwapProvider {
  async getSwap(
    from: string,
    tokenIn: string,
    tokenInDecimals: number,
    tokenOut: string,
    tokenOutDecimals: number,
    amountIn: ethers.BigNumber
  ): Promise<{ toTokenAmount: ethers.BigNumber; tx: { from: string; to: string; value: number; data: string } }> {
    const params = {
      account: from,
      inTokenAddress: tokenIn,
      outTokenAddress: tokenOut,
      amount: utils.formatUnits(amountIn, tokenInDecimals),
      slippage: 0.2,
      gasPrice: 30,
    }
    const headers = {
      // 'user-agent': 'Gelato',
    }
    return await axios.get("https://open-api.openocean.finance/v3/polygon/swap_quote", { params, headers }).then((res) => {
      const toTokenAmount = utils.parseUnits(res.data.data.outAmount, tokenOutDecimals)
      const tx = {
        from: res.data.data.from,
        to: res.data.data.to,
        value: res.data.data.value,
        data: res.data.data.data,
      }
      return { toTokenAmount, tx }
    })
  }
}

class Kyber implements ISwapProvider {
  private options?: string

  constructor(options?: string) {
    this.options = options; // TODO: from secrets
  }

  globalOptions(): any {
    if (this.options) {
      try {
        return JSON.parse(atob(this.options));
      } catch { }
    }
    return {};
  }

  async getSwap(
    from: string,
    tokenIn: string,
    tokenInDecimals: number,
    tokenOut: string,
    tokenOutDecimals: number,
    amountIn: ethers.BigNumber
  ): Promise<{ toTokenAmount: ethers.BigNumber; tx: { from: string; to: string; value: number; data: string } }> {
    let params = {
      tokenIn,
      tokenOut,
      amountIn: amountIn.toString(),
      to: from,
      saveGas: 0,
      gasInclude: 1,
      source: "caviar",
      ...this.globalOptions()
    }
    const headers = {
      'x-client-id': 'caviar',
    }
    const routes = await axios.get("https://aggregator-api.kyberswap.com/polygon/api/v1/routes", { params, headers }).then((res) => res.data as {data: any});
    params = {
      routeSummary: routes.data.routeSummary,
      deadline: 0,
      slippageTolerance: 50,
      recipient: from,
    }
    return await axios.post("https://aggregator-api.kyberswap.com/polygon/api/v1/route/build", params, { headers }).then((res) => {
      const toTokenAmount = utils.parseUnits(res.data.data.amountOut, tokenOutDecimals)
      const tx = {
        from,
        to: res.data.data.routerAddress,
        value: 0,
        data: res.data.data.data,
      }
      return { toTokenAmount, tx }
    });
  }
}