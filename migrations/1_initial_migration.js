let commitHash = require('child_process').execSync('git rev-parse HEAD').toString();
let poolUrl = "https://optixprotocol.com/api/pool/{id}.​json"
let optionUrl = "https://optixprotocol.com/api/option/{id}.​json"

const SwapPool = artifacts.require("SwapPool")
const OptionsLP1155 = artifacts.require("OptionsLP1155")
const OptionsLP = artifacts.require("OptionsLP")
const Options = artifacts.require("Options")

module.exports = async function (deployer, network, [account]) {
    // if (["development", "develop", 'soliditycoverage'].indexOf(network) >= 0) {
    await deployer.deploy(SwapPool);
    deployer.link(SwapPool, [OptionsLP]);
    const lp1155 = await deployer.deploy(OptionsLP1155, poolUrl, commitHash);
    const lp = await deployer.deploy(OptionsLP, OptionsLP1155.address, commitHash);
    const opt = await deployer.deploy(Options,
        "0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b",
        OptionsLP.address,
        "Optix Contract",
        "OptixContract",            
        commitHash
    )

    await lp1155.grantRole(await lp1155.MINTER_ROLE(), OptionsLP.address);
    await lp.grantRole(await lp.CONTRACT_CALLER_ROLE(), Options.address);
    // switch (network) {
    //   case "rinkeby": {

        //0xECe365B379E1dD183B20fc5f022230C044d51404 BTC
        // IOracle _oracle, IERC20 _collateralToken, IERC20 _hedgeToken, IUniswapV2Factory _swapFactory, IUniswapV2Router02 _swapRouter) public {
        await lp.createPool("0xECe365B379E1dD183B20fc5f022230C044d51404","0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")
        await lp.setOracleEnabled(0,"0x3539F2E214d8BC7E611056383323aC6D1b01943c",1); //0x3539F2E214d8BC7E611056383323aC6D1b01943c ATOM
        await lp.setOracleEnabled(0,"0x21c095d2aDa464A294956eA058077F14F66535af",1); // AUD
        await lp.setOracleEnabled(0,"0x031dB56e01f82f20803059331DC6bEe9b17F7fC9",1); // BAT
        await lp.setOracleEnabled(0,"0xcf0f51ca2cDAecb464eeE4227f5295F2384F84ED",1); // BNB
        await lp.setOracleEnabled(0,"0x5e601CF5EF284Bcd12decBDa189479413284E1d2",1); // CHF
        await lp.setOracleEnabled(0,"0x8A753747A1Fa494EC906cE90E9f37563A8AF630e",1); // ETH
        await lp.setOracleEnabled(0,"0x78F9e60608bF48a1155b4B2A5e31F32318a1d85F",1); // EUR
        await lp.setOracleEnabled(0,"0x7B17A813eEC55515Fb8F49F2ef51502bC54DD40F",1); // GBP
        await lp.setOracleEnabled(0,"0x3Ae2F46a2D84e3D5590ee6Ee5116B80caF77DeCA",1); // JPY
        await lp.setOracleEnabled(0,"0xd8bD0a1cB028a31AA859A21A3758685a95dE4623",1); // LINK
        await lp.setOracleEnabled(0,"0x4d38a35C2D87976F334c2d2379b535F1D461D9B4",1); // LTC
        await lp.setOracleEnabled(0,"0x7794ee502922e2b723432DDD852B3C30A911F021",1); // MATIC
        await lp.setOracleEnabled(0,"0x6292aA9a6650aE14fbf974E5029f36F95a1848Fd",1); // OIL
        await lp.setOracleEnabled(0,"0x9331b55D9830EF609A2aBCfAc0FBCE050A52fdEa",1); // REP
        await lp.setOracleEnabled(0,"0xE96C4407597CD507002dF88ff6E0008AB41266Ee",1); // SNX
        await lp.setOracleEnabled(0,"0xb29f616a0d54FF292e997922fFf46012a63E2FAe",1); // TRX
        await lp.setOracleEnabled(0,"0x9c1946428f4f159dB4889aA6B218833f467e1BfD",1); // XAG
        await lp.setOracleEnabled(0,"0x81570059A0cb83888f1459Ec66Aad1Ac16730243",1); // XAU
        await lp.setOracleEnabled(0,"0xc3E76f41CAbA4aB38F00c7255d4df663DA02A024",1); // XRP
        await lp.setOracleEnabled(0,"0xf57FCa8B932c43dFe560d3274262b2597BCD2e5A",1); // XTZ
        await lp.setOracleEnabled(0,"0xF7Bbe4D7d13d600127B6Aa132f1dCea301e9c8Fc",1); // ZRX
        await lp.setOracleEnabled(0,"0x1a602D4928faF0A153A520f58B332f9CAFF320f7",1); // sCEX
        await lp.setOracleEnabled(0,"0x0630521aC362bc7A19a4eE44b57cE72Ea34AD01c",1); // sDEFI 


        // "0xd8bD0a1cB028a31AA859A21A3758685a95dE4623","0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
      }
    // }
// }





// const BN = web3.utils.BN



// const Exchange = artifacts.require("FakeExchange")

// const ERC20Options = artifacts.require("ERC20Options")
// const WriterPool = artifacts.require("WriterPool")
// const ERC20LiquidityPool = artifacts.require("ERC20LiquidityPool")

// const WBTC = artifacts.require("FakeWBTC")
// const WETH = artifacts.require("FakeWETH")
// const LINK = artifacts.require("FakeLink")
// const UNI = artifacts.require("FakeUniswap")
// const SUSHI = artifacts.require("FakeSushiswap")
// const AAVE = artifacts.require("FakeAAVE")

// const PriceProvider = artifacts.require("FakePriceProvider")
// const BTCPriceProvider = artifacts.require("FakeBTCPriceProvider")
// const ETHPriceProvider = artifacts.require("FakeETHPriceProvider")
// const LinkPriceProvider = artifacts.require("FakeLinkPriceProvider")
// const FastGasPriceProvider = artifacts.require("FastGasPriceProvider")
// const UniswapPriceProvider = artifacts.require("UniswapPriceProvider")
// const GoldPriceProvider = artifacts.require("GoldPriceProvider")
// const SushiswapPriceProvider = artifacts.require("SushiswapPriceProvider")
// const AavePriceProvider = artifacts.require("AavePriceProvider")



// // const BC = artifacts.require("BondingCurveLinear")

// const CONTRACTS_FILE = process.env.CONTRACTS_FILE

// const params = {
//     BTCPrice: new BN("5000000000000"),
//     ETHPrice: new BN("166121147421"),
//     ETHFastGasPrice:  new BN("70200000000"),
//     GoldPrice: new BN("184462450000"),
//     ChainlinkPrice:  new BN("2269700876"),
//     UniSwapPrice: new BN("14845000000000000"),
//     SushiSwapPrice: new BN("6372000000000000"),
//     AAVEPrice: new BN("31017005853"),

            

//     ETHtoBTC() { return this.ETHPrice.mul(new BN("10000000000000000000000000000000")).div(this.BTCPrice) },
//     ExchangePrice: new BN(30e8),
//     BC:{
//         k: new BN("100830342800"),
//         startPrice: new BN("350000000000000")
//     }
// }

// module.exports = async function (deployer, network, [account]) {
//     if (["development", "develop", 'soliditycoverage'].indexOf(network) >= 0) {
//         const w = await deployer.deploy(WBTC)
//         // await WBTC.mintTo(account, "100000000000000000000")
//         // await WBTC.mintTo("0x1a4037400B5211Dc9881d088252F907B9Ed76169", "100000000000000000000");

//         const i = await deployer.deploy(WETH)
//         const o = await deployer.deploy(LINK)
//         await deployer.deploy(UNI);
//         await deployer.deploy(SUSHI);
//         await deployer.deploy(AAVE);
        
//         // await deployer.deploy(ETHPool)
//         const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//         const lp = await deployer.deploy(ERC20LiquidityPool, wp.address, commitHash)
//         // await deployer.deploy(BC, ALF.address, params.BC.k, params.BC.startPrice)
//         await deployer.deploy(Exchange, WBTC.address, params.ETHtoBTC())

//         await deployer.deploy(BTCPriceProvider, params.BTCPrice, "BTC / USD")
//         await deployer.deploy(ETHPriceProvider, params.ETHPrice, "ETH / USD")
//         await deployer.deploy(FastGasPriceProvider, params.ETHFastGasPrice, "Fast Gas / Gwei")
//         await deployer.deploy(GoldPriceProvider, params.GoldPrice, "XAU / USD")
//         await deployer.deploy(LinkPriceProvider, params.ChainlinkPrice, "LINK / USD")
//         // await deployer.deploy(UniswapPriceProvider,params.UniSwapPrice, "Uniswap / ETH")
//         // await deployer.deploy(SushiswapPriceProvider, params.SushiSwapPrice, "SushiSwap / ETH")        
//         // await deployer.deploy(AavePriceProvider, params.AAVEPrice, "AAVE / USD")

      
//         const opt = await deployer.deploy(ERC20Options,
//             WBTC.address,
//             lp.address,
//             "Option Contract",
//             "OPTION",            
//             commitHash
//         )
//         await lp.grantRole(await lp.CONTRACT_CALLER_ROLE(), opt.address);

//         // await h.mintTo(BC.address, "753001000000000000000000000")
//         await lp.createMarket(BTCPriceProvider.address,
//             WBTC.address)
//         lp.setMaxInvest(WBTC.address, "100000000000000000000000000000000000000000");
//         await lp.createMarket(ETHPriceProvider.address,
//             WETH.address)
//         lp.setMaxInvest(WETH.address, "100000000000000000000000000000000000000000");
//         await lp.createMarket(FastGasPriceProvider.address,
//             WETH.address)
//         await lp.createMarket(GoldPriceProvider.address,
//             WETH.address)
//         // console.log("LinkPriceProvider.address:",LinkPriceProvider.address)
//         // console.log("LINK.address:",LINK.address)
//         await lp.createMarket(LinkPriceProvider.address,
//             LINK.address)
//         //    await lp.createMarket(UniswapPriceProvider.address,
//         //         UNI.address)        
//         //    await lp.createMarket(SushiswapPriceProvider.address,
//         //         SUSHI.address)  
//         //    await lp.createMarket(AavePriceProvider.address,
//         //         AAVE.address)  
        
//         // await lp.transferOwnership(ERC20Options.address);
//         // await lp.transferOwnership("0x6a17c567315ED3d9C378A5fd79726C2286595528");
//         // await opt.transferOwnership("0x6a17c567315ED3d9C378A5fd79726C2286595528");

//         // await btcp.setPrice('3972704584246')
//         await wp.grantRole(await wp.MINTER_ROLE(), lp.address);

//         if (CONTRACTS_FILE) {
//             const fs = require('fs');
//             console.log("> Contracts writing: " + CONTRACTS_FILE)
//             fs.writeFileSync(CONTRACTS_FILE, JSON.stringify({
//                 WBTC: {
//                     address: WBTC.address,
//                     abi: WBTC.abi
//                 },
//                 WETH: {
//                     address: WETH.address,
//                     abi: WETH.abi
//                 },
//                 ETHPriceProvider: {
//                     address: PriceProvider.address,
//                     abi: PriceProvider.abi
//                 },
//                 BTCPriceProvider: {
//                     address: BTCPriceProvider.address,
//                     abi: BTCPriceProvider.abi
//                 },
//                 ERC20Options: {
//                     address: ERC20Options.address,
//                     abi: ERC20Options.abi
//                 },
//                 ERC20LiquidityPool: {
//                     address: ERC20LiquidityPool.address,
//                     abi: await ERC20LiquidityPool.abi
//                 },
//                 // BC:{
//                 //     address: BC.address,
//                 //     abi: BC.abi
//                 // },
//             }))
//         }
//     } else {
//         switch (network) {
//             case "rinkeby": {
       
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }
//             case "binanceTestnet": {
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }
//             case "moonbeamTestnet": {
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }
//             case "polygonTestnet": {
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }
//             case "polygonMainnet": {
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }                
//             case "fantomTestnet": {
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }
//             case "plasmTestnet": {
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }
//             case "avalancheTestnet": {
//                 const wp = await deployer.deploy(WriterPool, poolUrl, commitHash);
//                 const lp = await deployer.deploy(ERC20LiquidityPool, WriterPool.address, commitHash)
//                 const opt = await deployer.deploy(ERC20Options,
//                     "0x5976120623b76fa441525A3784bBFFD5A00dBAD3",
//                     ERC20LiquidityPool.address,
//                     "Option Contract",
//                     "OPTION",                    
//                     commitHash)
//                 break;
//             }                
//             default: {
//                 throw Error(`Network not configured in migration: ${network}`)
//             }        
//         }
//     }
// }
