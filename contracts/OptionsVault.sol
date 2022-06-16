pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "./libraries/SwapPool.sol";
import "./OptionsVault1155.sol";
import "hardhat/console.sol";

// Rinkeby
//  oracle LINK/USD = 0xd8bD0a1cB028a31AA859A21A3758685a95dE4623 
//  collateralToken USDC(Fake) = 0xDF171B622CEF319fbe31358A817e85bE3642e990
//  hedgeToken MATIC(Fake) = 0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797
//  swapFactory uniswap = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
//  swapRouter uniswap = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
//  uniswap pool pair USDC/MATIC = 0x9672dCD6C535119827Cac94Ec787A9F837dDa2c1


contract OptionsVault is AccessControl, IOptions {
    using SafeERC20 for IERC20;

    uint256 public vaultCount = 0;

    // internal vault properties
    mapping(uint256 => IOracle) public oracle;
    mapping(uint256 => IERC20) public collateralToken; 
    mapping(uint256 => IERC20) public hedgeToken; 
    mapping(uint256 => IUniswapV2Factory) public swapFactory; 
    mapping(uint256 => IUniswapV2Router02) public swapRouter; 
    mapping(uint256 => uint256) public totalCollateral;
    mapping(uint256 => uint256) public collateralReserves;
    mapping(uint256 => uint256) public pairTokenSupply;
    mapping(uint256 => uint256) public hedgeReserves;    
    mapping(uint256 => uint256) public deltaPercent;
    mapping(uint256 => bool) public deltaToCollateral;

    // mapping(uint256 => uint256) public lockedCollateral;
    mapping(uint256 => uint256) public lockedCollateralCall;
    mapping(uint256 => uint256) public lockedCollateralPut;
    LockedCollateral[] public lockedCollateral;
 
    // updatable by vault owner/operator 
    mapping(uint256 => address) public vaultOwner;
    mapping(uint256 => address) public vaultFeeRecipient;
    mapping(uint256 => IFeeCalcs) public vaultFeeCalc;
    mapping(uint256 => string) public ipfsHash;
    mapping(uint256 => bool) public readOnly;
    mapping(uint256 => uint256) public maxInvest;
    mapping(uint256 => uint256) public lockupPeriod;
    mapping(uint256 => uint256) public collateralizationRatio;
    mapping(IOracle => mapping(uint256 => bool)) public oracleEnabled; 
    mapping(uint256 => bool) public lpWhitelistOnly;     


    mapping(uint256 => mapping(address => uint256)) public lastProvideTimestamp; 
    OptionsVault1155 public optionsVault1155;

    
    mapping(IOracle => bool) public oracleWhitelisted; 


    // constants 
    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");
    
    constructor(OptionsVault1155 _optionsVault1155)  {
        optionsVault1155 = _optionsVault1155;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
   function createVault(IOracle _oracle, IERC20 _collateralToken, IERC20 _hedgeToken, IUniswapV2Factory _swapFactory, IUniswapV2Router02 _swapRouter) public IsDefaultAdmin {
        require(oracleWhitelisted[_oracle],"OptionsVault: oracle must be whitelisted");

        oracle[vaultCount] = _oracle;
        collateralToken[vaultCount] = _collateralToken;
        hedgeToken[vaultCount] = _hedgeToken;
        swapFactory[vaultCount] = _swapFactory;
        swapRouter[vaultCount] = _swapRouter;
        totalCollateral[vaultCount] = 0;
        collateralReserves[vaultCount] = 0; 
        hedgeReserves[vaultCount] = 0;
        deltaPercent[vaultCount] = 5000;
        
        // lockedCollateral[vaultCount] = 0;
        lockedCollateralCall[vaultCount] = 0;
        lockedCollateralPut[vaultCount] = 0;
        
        vaultOwner[vaultCount] = _msgSender();        
        vaultFeeRecipient[vaultCount] = _msgSender();        
        ipfsHash[vaultCount] = "";
        readOnly[vaultCount] = false;
        maxInvest[vaultCount] = 1e18;
        lockupPeriod[vaultCount] = 2 weeks;
        collateralizationRatio[vaultCount] = 10000;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(VAULT_OPERATOR_ROLE(vaultCount), 0x0000000000000000000000000000000000000000);
        
        
        oracleEnabled[_oracle][vaultCount] = true;
        emit CreateVault(vaultCount, _oracle, _collateralToken, _hedgeToken, _swapFactory, _swapRouter);
        emit UpdateOracle(_oracle, vaultCount, true);

        vaultCount += 1;
   }

    function VAULT_OPERATOR_ROLE(uint _vaultId) public view returns(bytes32){
        return keccak256(abi.encode("VAULT_OPERATOR_ROLE-", Strings.toString(_vaultId)));
    }

    function VAULT_LPWHITELIST_ROLE(uint _vaultId) public view returns(bytes32){
        return keccak256(abi.encode("VAULT_LPWHITELIST_ROLE-", Strings.toString(_vaultId)));
    }    

    /*
     * @nonce A provider supplies token to the vault and receives optix vault1155 tokens
     * @param account account who will be the owner of the minted tokens 
     * @param vaultId Pool to provide to 
     * @param collateralAmount Amount to deposit in the collatoral token
     * @return mintTokens Tokens minted to represent ownership
     */
    function provide(address account, uint _vaultId, uint256 collateralAmount) external returns (uint256 mintTokens, uint swapAmount){
        if(lpWhitelistOnly[_vaultId]){
            require(hasRole(VAULT_LPWHITELIST_ROLE(_vaultId), _msgSender()), "OptionsVault: must be in LP Whitelist");
        }
        // OptionMarket memory market = optionMarkets[vaultId];
        lastProvideTimestamp[_vaultId][account] = block.timestamp;
        
        // require(collateralAmount<=maxInvest[_vaultId],"OptionsVault: Max invest limit reached");
        //uint startBal = collateralToken[_vaultId].balanceOf(address(this));
        IUniswapV2Pair pair = IUniswapV2Pair(swapFactory[_vaultId].getPair(address(collateralToken[_vaultId]), address(hedgeToken[_vaultId])));
        (mintTokens, swapAmount) = SwapPool.addLiquidity(account, collateralToken[_vaultId], hedgeToken[_vaultId], collateralAmount, swapFactory[_vaultId], swapRouter[_vaultId]);
        uint toMint = mintTokens;

        // if (optionsVault1155.totalSupply(_vaultId)==0){
        //     toMint = mintTokens;
        // }
        // else{
        //     toMint = mintTokens;// * pair.balanceOf(address(this)) / optionsVault1155.totalSupply(_vaultId);
        // }
        optionsVault1155.mint(account, _vaultId, toMint, "");

        totalCollateral[_vaultId] = totalCollateral[_vaultId]+collateralAmount;
        
        emit Provide(account, _vaultId, collateralAmount, mintTokens);
    }    

    /*
     * @nonce Sends tokens to the vault without receiving 1155 minted tokens in return. 
     *  You will receive no ownership tokens from this function.
     *  To be used to increase the vault with profits/returns etc. 
     */     
    function addToVault(address account, uint _vaultId, uint256 collateralAmount) external returns (uint256 mintTokens, uint swapAmount){
        IUniswapV2Pair pair = IUniswapV2Pair(swapFactory[_vaultId].getPair(address(collateralToken[_vaultId]), address(hedgeToken[_vaultId])));
        (mintTokens,swapAmount) = SwapPool.addLiquidity(account, collateralToken[_vaultId], hedgeToken[_vaultId], collateralAmount, swapFactory[_vaultId], swapRouter[_vaultId]);
        totalCollateral[_vaultId] = totalCollateral[_vaultId]+collateralAmount;
        //emit
    }
    
    /*
     * @nonce Provider burns vault tokens and receives erc20 tokens from the vault
     * @param amount Amount of erc20 tokens to receive
     * @param maxBurn Maximum amount of tokens that can be burned
     */
    function withdraw(address account, uint _vaultId, uint256 burnTokens)  external  {
    
        IUniswapV2Pair pair = IUniswapV2Pair(swapFactory[_vaultId].getPair(address(collateralToken[_vaultId]), address(hedgeToken[_vaultId])));

        
        uint toBurn = burnTokens * pair.balanceOf(address(this))/optionsVault1155.totalSupply(_vaultId);

        optionsVault1155.burn(account, _vaultId, burnTokens); //will fail if they don't have enough
        (uint amountA,) = SwapPool.removeLiquidity(account, collateralToken[_vaultId], hedgeToken[_vaultId], toBurn, swapFactory[_vaultId], swapRouter[_vaultId],true);
        totalCollateral[_vaultId] = amountA;
        emit Withdraw(account, _vaultId, amountA, 0, burnTokens);
    }
    
    /* 
     * @nonce calls by Options to lock funds
     * @param amount Amount of funds that should be locked in an option
     */
    function lock(uint optionId, uint256 optionSize, IFeeCalcs.Fees memory _premium, uint vaultId, OptionType optionType ) public  {
        require(optionId == lockedCollateral.length, "OptionsVault: Wrong id");
        require(
                optionSize <= vaultCollateralAvailable(vaultId),
                "OptionsVault: Not enough vault collateral available."
        );
        require(hasRole(CONTRACT_CALLER_ROLE, _msgSender()), "OptionsVault: must have contract caller role");

 
        lockedCollateral.push(LockedCollateral(optionSize, _premium.total, true, vaultId, optionType));
        if(optionType == OptionType.Put){
            lockedCollateralPut[vaultId] = lockedCollateralPut[vaultId]+optionSize;
        }
        else{
            lockedCollateralCall[vaultId] = lockedCollateralCall[vaultId]+optionSize;
        }

        //add the premium less the protocol & vault fees
        collateralReserves[vaultId] = collateralReserves[vaultId] + _premium.total-_premium.protocolFee-_premium.vaultFee;
        // totalCollateral[vaultId] = totalCollateral[vaultId]+_premium.total-_premium.protocolFee-_premium.vaultFee;
    }
    
    /*
     * @nonce Calls by Options to unlock funds
     * @param amount Amount of funds that should be unlocked in an expired option
     */
    function unlock(uint256 optionId) public  {
        LockedCollateral storage ll = lockedCollateral[optionId];
        require(ll.locked, "OptionsVault: lockedCollateral with id has already unlocked");
        require(hasRole(CONTRACT_CALLER_ROLE, _msgSender()), "OptionsVault: must have contract caller role");

        ll.locked = false;

        if(ll.optionType == OptionType.Put)
          lockedCollateralPut[ll.vaultId] = lockedCollateralPut[ll.vaultId]-ll.premium;
        else
          lockedCollateralCall[ll.vaultId] = lockedCollateralCall[ll.vaultId]-ll.premium;

        emit VaultProfit(optionId, ll.vaultId, ll.premium);
    }

    /*
     * @nonce calls by Options to send funds to liquidity providers after an option's expiration
     * @param to Provider
     * @param amount Funds that should be sent
     */
    function send(uint optionId, address to, uint256 amount) public {
        LockedCollateral storage ll = lockedCollateral[optionId];
        require(ll.locked, "OptionsVault: id already unlocked");
        require(to != address(0));
        require(hasRole(CONTRACT_CALLER_ROLE, _msgSender()), "OptionsVault: must have contract caller role");


        ll.locked = false;
        if(ll.optionType == OptionType.Put)
          lockedCollateralPut[ll.vaultId] = lockedCollateralPut[ll.vaultId]-ll.amount;
        else
          lockedCollateralCall[ll.vaultId] = lockedCollateralCall[ll.vaultId]-ll.amount;

        uint transferAmount = amount > ll.amount ? ll.amount : amount;

        //TODO
        IERC20(collateralToken[ll.vaultId]).safeTransfer(to, transferAmount);

        if (transferAmount <= ll.premium)
            emit VaultProfit(optionId, ll.vaultId, ll.premium - transferAmount);
        else
            emit VaultLoss(optionId, ll.vaultId, transferAmount - ll.premium);
    }

    /*
     * An approximation of the amount of collateral available for selling options 
     * the swap pool reserves*2 plus collateral reserves
     * adjusted for collatorization ratio & adjusted for delta reserves
     */
    function vaultCollateralTotal(uint _vaultId) public view returns (uint256) {
                
        IUniswapV2Pair swappair = IUniswapV2Pair(swapFactory[_vaultId].getPair(address(collateralToken[_vaultId]), address(hedgeToken[_vaultId])));
        (uint112 reserve0, uint112 reserve1, ) = swappair.getReserves();
        uint supply = swappair.totalSupply();
        uint vaultBalance = totalCollateral[_vaultId];
        return vaultBalance*1e4/collateralizationRatio[_vaultId];
        // uint tokenBalance = 0;
        
        // if (address(collateralToken[_vaultId]) == swappair.token0() ){
        //     tokenBalance = reserve0*vaultBalance/supply; 
        // }
        // else{
        //     tokenBalance = reserve1*vaultBalance/supply; 
        // }
        // return tokenBalance*2*1e4/collateralizationRatio[_vaultId];
    }

    function vaultCollateralLocked(uint _vaultId) public view returns (uint256){
        return lockedCollateralPut[_vaultId]+lockedCollateralCall[_vaultId];
    }

    function vaultCollateralAvailable(uint _vaultId) public view returns (uint256) {
        return vaultCollateralTotal(_vaultId)-vaultCollateralLocked(_vaultId);
    }

 

    function resetDeltaHedge(uint _vaultId) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "OptionsVault: must have admin role");

        if(collateralReserves[_vaultId] > 0){
            SwapPool.resetDeltaHedge(this, _vaultId, true);
            collateralReserves[_vaultId] = 0;
        }
        if(hedgeReserves[_vaultId] > 0){
            SwapPool.resetDeltaHedge(this, _vaultId, false);
            hedgeReserves[_vaultId] = 0;
        }
    }

    
    function setDeltaHedge(uint _vaultId, uint percent, bool _toCollateral) public returns (uint collateralAmount, uint hedgeAmount, uint[] memory swapAmounts) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "OptionsVault: must have admin role");        

        resetDeltaHedge(_vaultId);

        uint startBal = collateralToken[_vaultId].balanceOf(address(this));

        (collateralAmount, hedgeAmount, swapAmounts) = SwapPool.setDeltaHedge(percent, _toCollateral, this, _vaultId);
        if(_toCollateral){
            collateralReserves[_vaultId] = collateralAmount+swapAmounts[1];
            hedgeReserves[_vaultId] = 0;
        }
        else{
            collateralReserves[_vaultId] = 0;
            hedgeReserves[_vaultId] = hedgeAmount+swapAmounts[1];
        }
        uint endBal = collateralToken[_vaultId].balanceOf(address(this));
        deltaPercent[_vaultId] = percent;
        deltaToCollateral[_vaultId] = _toCollateral;
    }

    modifier IsVaultOwner(uint vaultId) {
        require(_msgSender()==vaultOwner[vaultId], "OptionsVault: must have owner role");
        _;
    }

    modifier IsVaultOwnerOrOperator(uint vaultId) {
        require(
            (_msgSender()==vaultOwner[vaultId]) ||
              (hasRole(VAULT_OPERATOR_ROLE(vaultId),_msgSender()))
            , "OptionsVault: must have owner or operator role");
        _;
    }

    modifier IsDefaultAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "OptionsVault: must have admin role");
        _;
    }


    function setVaultOwner(uint vaultId, address value) external IsVaultOwner(vaultId) {
        vaultOwner[vaultId] = value;
    }

    function setVaultFeeRecipient(uint vaultId, address value) external IsVaultOwner(vaultId) {
        vaultFeeRecipient[vaultId] = value;
    }    
    
    function grantVaultOperatorRole(uint vaultId, address value) external IsVaultOwner(vaultId)  {
        grantRole(VAULT_OPERATOR_ROLE(vaultId),value);
    }
    function revokeVaultOperatorRole(uint vaultId, address value) external IsVaultOwner(vaultId)  {
        revokeRole(VAULT_OPERATOR_ROLE(vaultId),value);
    }

    function grantLPWhitelistRole(uint vaultId, address value) external IsVaultOwnerOrOperator(vaultId)  {
        grantRole(VAULT_LPWHITELIST_ROLE(vaultId),value);
    }
    function revokeLPWhitelistRole(uint vaultId, address value) external IsVaultOwnerOrOperator(vaultId)  {
        revokeRole(VAULT_LPWHITELIST_ROLE(vaultId),value);
    }

    function setVaultFeeCalc(uint vaultId, IFeeCalcs value) external IsVaultOwnerOrOperator(vaultId) {
        
        vaultFeeCalc[vaultId] = value;
    }   
    function setIpfsHash(uint vaultId, string memory value) external IsVaultOwnerOrOperator(vaultId) {
        ipfsHash[vaultId] = value;
    }  
    function setReadOnly(uint vaultId, bool value) external IsVaultOwnerOrOperator(vaultId) {
        readOnly[vaultId] = value;
    }
    function setMaxInvest(uint vaultId, uint256 value) external IsVaultOwnerOrOperator(vaultId) {
        maxInvest[vaultId] = value;
    }     
    function setLockupPeriod(uint vaultId, uint256 value) external IsVaultOwnerOrOperator(vaultId) {
        lockupPeriod[vaultId] = value;
    }   
    function setOracleEnabled(uint vaultId, IOracle _oracle, bool value) external IsVaultOwnerOrOperator(vaultId) {
        require(oracleWhitelisted[_oracle],"OptionsVault: oracle must be whitelisted");
        oracleEnabled[_oracle][vaultId] = value; 
        emit UpdateOracle(_oracle, vaultId, value);
    }    
    function setLPWhitelistOnly(uint vaultId, bool value) external IsVaultOwnerOrOperator(vaultId) {
        lpWhitelistOnly[vaultId] = value; 
        // emit LPWhitelistOnly(_oracle, vaultId, value);
    }     


    function setCollaterizationRatio(uint vaultId, uint256 value) external IsDefaultAdmin  {
        collateralizationRatio[vaultId] = value;
    }

    function setOracleWhitelisted(IOracle _oracle, bool value) external IsDefaultAdmin() {
        oracleWhitelisted[_oracle] = value;         
    }  
}