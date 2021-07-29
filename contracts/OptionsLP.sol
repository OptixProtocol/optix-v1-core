pragma solidity 0.8.6;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "./libraries/SwapPool.sol";
import "./OptionsLP1155.sol";

// Rinkeby
//  oracle LINK/USD = 0xd8bD0a1cB028a31AA859A21A3758685a95dE4623 
//  collateralToken USDC(Fake) = 0xDF171B622CEF319fbe31358A817e85bE3642e990
//  hedgeToken MATIC(Fake) = 0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797
//  swapFactory uniswap = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
//  swapRouter uniswap = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
//  uniswap pool pair USDC/MATIC = 0x9672dCD6C535119827Cac94Ec787A9F837dDa2c1

// Create Pool 
//  createPool: "0xd8bD0a1cB028a31AA859A21A3758685a95dE4623","0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"

// Provide 
//  optionsLP1155.grantRole: give minter role to optionsLP
//  USDC.approve: approve optionsLP 
//  provide $1000: "0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b","0","1000000000"

// Withdraw 
//  optionsLP1155.setApprovalForAll: optionsLP
//  withdraw : "0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b","0","1000000000000000000000000000"

// Buy Option 
// options.deploy: "0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b","0xeacED67cE6b60e0f31A2A530B1245221868417c7","Optyn","OPTYN","asdlfjldksfj"
// optionsLP.grantRole: give contract caller role to options 
// USDC.approve: approve options 
// options.fees: "86400","1000000000","1816780025","1","0","0xd8bD0a1cB028a31AA859A21A3758685a95dE4623"
// options.create4: "0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b","86400","1000000000","1816780025","1","0","0xd8bD0a1cB028a31AA859A21A3758685a95dE4623"


contract OptionsLP is AccessControl {
    
    uint256 public poolCount = 0;

    // internal pool properties
    mapping(uint256 => IOracle) public oracle;
    mapping(uint256 => IERC20) public collateralToken; 
    mapping(uint256 => IERC20) public hedgeToken; 
    mapping(uint256 => IUniswapV2Factory) public swapFactory; 
    mapping(uint256 => IUniswapV2Router02) public swapRouter; 
    mapping(uint256 => uint256) public swapBalanceOf;
    mapping(uint256 => uint256) public collateralReserves;
    mapping(uint256 => uint256) public hedgeReserves;    
    mapping(uint256 => uint256) public lockedCollateral;
    mapping(uint256 => uint256) public lockedCollateralCall;
    mapping(uint256 => uint256) public lockedCollateralPut;

    // updatable by pool owner/operator
    mapping(uint256 => address) public poolOwner;
    mapping(uint256 => address) public poolOperator;
    mapping(uint256 => IFeeCalcs) public poolFeeCalc;
    mapping(uint256 => uint256) public poolFee;
    mapping(uint256 => string) public ipfsHash;
    mapping(uint256 => bool) public readOnly;
    mapping(uint256 => uint256) public maxInvest;
    mapping(uint256 => uint256) public periodMin;
    mapping(uint256 => uint256) public periodMax;
    mapping(uint256 => uint256) public lockupPeriod;
    mapping(uint256 => uint256) public collateralizationRatio;
    mapping(IOracle => mapping(uint256 => bool)) public oracleEnabled; 
    
    mapping(uint256 => mapping(address => uint256)) public lastProvideTimestamp; 
    IOptions.LockedLiquidity[] public lockedLiquidity;
    OptionsLP1155 public optionsLP1155;
 
    // constants 
    uint256 public constant INITIAL_RATE = 1e18;
    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");
    string public commitHash;
    
    constructor(OptionsLP1155 _optionsLP1155, string memory _commitHash)  {
        optionsLP1155 = _optionsLP1155;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        commitHash = _commitHash;
    }
    
   function createPool(IOracle _oracle, IERC20 _collateralToken, IERC20 _hedgeToken, IUniswapV2Factory _swapFactory, IUniswapV2Router02 _swapRouter) public {
        oracle[poolCount] = _oracle;
        collateralToken[poolCount] = _collateralToken;
        hedgeToken[poolCount] = _hedgeToken;
        swapFactory[poolCount] = _swapFactory;
        swapRouter[poolCount] = _swapRouter;
        swapBalanceOf[poolCount] = 0;
        collateralReserves[poolCount] = 0; 
        hedgeReserves[poolCount] = 0;
        collateralizationRatio[poolCount] = 1e4;
        
        lockedCollateral[poolCount] = 0;
        lockedCollateralCall[poolCount] = 0;
        lockedCollateralPut[poolCount] = 0;
        
        poolOwner[poolCount] = _msgSender();
        poolOperator[poolCount] = _msgSender();
        poolFee[poolCount] = 0;
        ipfsHash[poolCount] = "";
        readOnly[poolCount] = false;
        maxInvest[poolCount] = 1e18;
        periodMin[poolCount] = 1 days;
        periodMax[poolCount] = 4 weeks;
        lockupPeriod[poolCount] = 2 weeks;
        collateralizationRatio[poolCount] = 10000;
        
        oracleEnabled[_oracle][poolCount] = true;
        
        poolCount += 1;
   }


 /*
     * @nonce A provider supplies token to the pool and receives optynLP1155 tokens
     * @param account account who will be the owner of the minted tokens 
     * @param poolId Pool to provide to 
     * @param minMint Minimum amount of tokens that should be received by a provider.
                      Calling the provide function will require the minimum amount of tokens to be minted.
                      The actual amount that will be minted could vary but can only be higher (not lower) than the minimum value.
     * @return mintedLP1155Tokens Tokens minted to represent ownership
     */
    function provide(address account, uint _poolId, uint256 collateralAmount) external returns (uint256 mintedLP1155Tokens){
        // OptionMarket memory market = optionMarkets[marketId];
        lastProvideTimestamp[_poolId][account] = block.timestamp;
        
        uint256 supply = optionsLP1155.totalSupply(_poolId);
        uint balance = swapBalanceOf[_poolId];
        if (supply > 0 && balance > 0){
            mintedLP1155Tokens = collateralAmount*supply/balance;
        }
        else
            mintedLP1155Tokens = collateralAmount*INITIAL_RATE;

        // require(mintedLPTokens >= minMint, "OptionsLP: Mint limit is too large");
        require(mintedLP1155Tokens > 0, "OptionsLP: Amount is too small");

        // require(swapPair[marketId].balanceOf(account)>=collateralAmount,
        //     "OptionsLP: Please lower the amount of premiums that you want to send."
        // );        
        require(collateralAmount<=maxInvest[_poolId],"OptionsLP: Max invest limit reached");

        uint mintedSwapTokens = SwapPool.addLiquidity(account, collateralToken[_poolId], hedgeToken[_poolId], collateralAmount, swapFactory[_poolId], swapRouter[_poolId]);
        swapBalanceOf[_poolId] = swapBalanceOf[_poolId]+mintedSwapTokens;

        optionsLP1155.mint(account, _poolId, mintedLP1155Tokens, "");

        // emit Provide(account, _pool, collateralAmount, mintedLPTokens, mintedSwapTokens);
    }    
    
     /*
     * @nonce Provider burns writer tokens and receives erc20 tokens from the pool
     * @param amount Amount of erc20 tokens to receive
     * @param maxBurn Maximum amount of tokens that can be burned
     * @return mint Amount of tokens to be burnt
     */
      function withdraw(address account, uint _poolId, uint256 burnLP1155Tokens)  external returns (uint256 burnSwapTokens) {
    
        // OptionMarket memory market = optionMarkets[marketId];
        // require(
        //     lastProvideTimestamp[swapPair[marketId]][account].add(lockupPeriod[swapPair[marketId]]) <= block.timestamp,
        //     "SwapLiquiditiyPool: Withdrawal is locked up"
        // );
        
        //calculate proportion of lp1155 pool the burn tokens represent 
        //calculate proportion of swap pool token to burn 
        
        
        // uint256 supply = optionsLP1155.totalSupply(_poolId);
        burnSwapTokens = swapBalanceOf[_poolId] * optionsLP1155.balanceOf(account,_poolId) / optionsLP1155.totalSupply(_poolId);
        optionsLP1155.burn(account, _poolId, burnLP1155Tokens); //will fail if they don't have enough

        (uint amountA, uint amountB) = SwapPool.removeLiquidity(account, collateralToken[_poolId], hedgeToken[_poolId], burnSwapTokens, swapFactory[_poolId], swapRouter[_poolId]);
        // emit Withdraw(account, _pool, burnLPTokens, burnSwapTokens);
    }
    
    /* 
     * @nonce calls by Options to lock funds
     * @param amount Amount of funds that should be locked in an option
     */
    function lock(uint id, uint256 amount, IFeeCalcs.Fees memory _premium, uint poolId, IOptions.OptionType optionType) public  {
        //   OptionMarket memory market = optionMarkets[marketId];
        require(id == lockedLiquidity.length, "OptionsLP: Wrong id");
        //   require(
        //         lockedAmount[swapPair[marketId]].add(amount) <= totalBalance(swapPair[marketId]),
        //         "OptionsLP: Amount is too large."
        //     );
        require(hasRole(CONTRACT_CALLER_ROLE, _msgSender()), "OptionsLP: must have contract caller role");

 
        lockedLiquidity.push(IOptions.LockedLiquidity(amount, _premium.total, true, poolId, optionType));
        if(optionType == IOptions.OptionType.Put){
            lockedCollateralPut[poolId] = lockedCollateralPut[poolId]+_premium.total;
        }
        else{
            lockedCollateralCall[poolId] = lockedCollateralCall[poolId]+_premium.total;
        }
        lockedCollateral[poolId] = lockedCollateral[poolId]+_premium.total;
        collateralReserves[poolId] = collateralReserves[poolId] + _premium.total-_premium.protocolFee-_premium.poolFee;

    }
    
    /*
     * @nonce Calls by Options to unlock funds
     * @param amount Amount of funds that should be unlocked in an expired option
     */
    function unlock(uint256 optionId) public  {
        IOptions.LockedLiquidity storage ll = lockedLiquidity[optionId];
        // OptionMarket memory market = optionMarkets[ll.marketId];
        require(ll.locked, "OptionsLP: LockedLiquidity with id has already unlocked");
        require(hasRole(CONTRACT_CALLER_ROLE, _msgSender()), "OptionsLP: must have contract caller role");

        ll.locked = false;

        if(ll.optionType == IOptions.OptionType.Put)
          lockedCollateralPut[ll.poolId] = lockedCollateralPut[ll.poolId]-ll.premium;
        else
          lockedCollateralCall[ll.poolId] = lockedCollateralCall[ll.poolId]-ll.premium;
        lockedCollateral[ll.poolId] = lockedCollateral[ll.poolId]-ll.amount;

        // emit Profit(optionId, ll.marketId, ll.premium);
    }

    /*
     * @nonce calls by Options to send funds to liquidity providers after an option's expiration
     * @param to Provider
     * @param amount Funds that should be sent
     */
    function send(uint optionId, address payable to, uint marketId, uint256 amount) public {
        IOptions.LockedLiquidity storage ll = lockedLiquidity[optionId];
        // OptionMarket memory market = optionMarkets[ll.marketId];
        require(ll.locked, "OptionsLP: id already unlocked");
        require(to != address(0));
        require(hasRole(CONTRACT_CALLER_ROLE, _msgSender()), "OptionsLP: must have contract caller role");


        ll.locked = false;
        if(ll.optionType == IOptions.OptionType.Put)
          lockedCollateralPut[ll.poolId] = lockedCollateralPut[ll.poolId]-ll.premium;
        else
          lockedCollateralCall[ll.poolId] = lockedCollateralCall[ll.poolId]-ll.premium;

        lockedCollateral[ll.poolId] = lockedCollateral[ll.poolId]-ll.amount;

        uint transferAmount = amount > ll.amount ? ll.amount : amount;
        // ll.pool.safeTransfer(to, transferAmount);

        // if (transferAmount <= ll.premium)
        //     emit Profit(optionId, marketId, ll.premium - transferAmount);
        // else
        //     emit Loss(optionId, marketId, transferAmount - ll.premium);
    }


    function poolTotalCollateralBalance(uint _poolId) public view returns (uint256) {
        
        //get swappair reserves 
        //get swappair totalSupply 
        //get swapBalanceOf[_poolId];
        //uint token0 = reserve0*userBalance/totalPoolSupply;
        
        IUniswapV2Pair swappair = IUniswapV2Pair(swapFactory[_poolId].getPair(address(collateralToken[_poolId]), address(hedgeToken[_poolId])));
        (uint112 reserve0, uint112 reserve1, ) = swappair.getReserves();
        uint supply = swappair.totalSupply();
        uint poolBalance = swapBalanceOf[_poolId];
        uint tokenBalance = 0;
        
        if (address(collateralToken[_poolId]) == swappair.token0() ){
            tokenBalance = reserve0*poolBalance/supply; 
        }
        else{
            tokenBalance = reserve1*poolBalance/supply; 
        }
        
        return tokenBalance*2;

        
        //Considerations
        //in reserves, which token is the collateralToken
        //n option pools to 1 swappool
        //option pool is delta hedged 
    }
    
    function poolAvailableCollateralBalance(uint _poolId) public view returns (uint256) {
        return poolTotalCollateralBalance(_poolId)-lockedCollateral[_poolId];
    }


    function poolUtilisation(uint _poolId) public view returns (uint256) {
        return lockedCollateral[_poolId]*(1e4)/(poolTotalCollateralBalance(_poolId));
    }
    
    function putRatio(uint _poolId) public view returns (uint256){
       if (lockedCollateral[_poolId]==0)
            return 5e3;

        int256 ratio = int256((lockedCollateralPut[_poolId]*(1e4))/(lockedCollateral[_poolId]));
        if (ratio<0)
            return 0;
        else
            return uint256(ratio);
    }

     function callRatio(uint _poolId) public view returns (uint256){
       if (lockedCollateral[_poolId]==0)
            return 5e3;

        int256 ratio = int256((lockedCollateralCall[_poolId]*(1e4))/(lockedCollateral[_poolId]));
        if (ratio<0)
            return 0;
        else
            return uint256(ratio);
    }
    function resetDeltaReserves(uint _poolId, bool resetCollateral) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "OptionsLP: must have admin role");

        if(resetCollateral){
            SwapPool.resetDeltaReserves(this, _poolId);
            collateralReserves[_poolId] = 0;
        }
        else{
            SwapPool.resetDeltaReserves(this, _poolId);
            hedgeReserves[_poolId] = 0;
        }
    }
    
    function setDeltaHedge(uint _poolId, uint percent, bool _toCollateral) public returns (uint collateralAmount, uint hedgeAmount, uint[] memory swapAmounts) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "OptionsLP: must have admin role");
        require(hedgeReserves[_poolId]==0 && collateralReserves[_poolId]==0, "SwapLiquidityPool: Reserves not 0");
 
        (collateralAmount, hedgeAmount, swapAmounts) = SwapPool.setDeltaHedge(percent, _toCollateral, this, _poolId);
        if(_toCollateral){
            collateralReserves[_poolId] = collateralAmount+swapAmounts[1];
            hedgeReserves[_poolId] = 0;
        }
        else{
            collateralReserves[_poolId] = 0;
            hedgeReserves[_poolId] = hedgeAmount+swapAmounts[1];
        }
    }

  
    function setPoolOwner(uint poolId, address value) external  {
        poolOwner[poolId] = value;
    }
    function setPoolOperator(uint poolId, address value) external  {
        poolOperator[poolId] = value;
    }
    function setPoolFeeCalc(uint poolId, IFeeCalcs value) external  {
        poolFeeCalc[poolId] = value;
    }   
    function setPoolFee(uint poolId, uint256 value) external  {
        poolFee[poolId] = value;
    }   
    function setIpfsHash(uint poolId, string memory value) external  {
        ipfsHash[poolId] = value;
    }  
    function setReadOnly(uint poolId, bool value) external  {
        readOnly[poolId] = value;
    }
    function setMaxInvest(uint poolId, uint256 value) external  {
        maxInvest[poolId] = value;
    }   
    function setPeriodMin(uint poolId, uint256 value) external  {
        periodMin[poolId] = value;
    }   
    function setPeriodMax(uint poolId, uint256 value) external  {
        periodMax[poolId] = value;
    }   
    function setLockupPeriod(uint poolId, uint256 value) external  {
        lockupPeriod[poolId] = value;
    }   
    function setCollaterizationRatio(uint poolId, uint256 value) external  {
        collateralizationRatio[poolId] = value;
    }
    function setOracleEnabled(uint poolId, IOracle _oracle, bool value) external  {
        oracleEnabled[_oracle][poolId] = value; 
    }    
    
}