pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "./libraries/SwapPool.sol";
import "./OptionsVault1155.sol";

contract OptionsVault is AccessControl, IOptions, IStructs {
    using SafeERC20 for IERC20;

    uint256 public vaultCount = 0;

    // internal vault properties
    mapping(uint256 => IERC20) public collateralToken; 
    mapping(uint256 => IERC20) public hedgeToken; 
    mapping(uint256 => IUniswapV2Factory) public swapFactory; 
    mapping(uint256 => IUniswapV2Router02) public swapRouter; 
    mapping(uint256 => uint256) public collateralReserves;
    mapping(uint256 => uint256) public swapBalance;
    mapping(uint256 => uint256) public hedgeReserves;    
    mapping(uint256 => uint256) public deltaPercent;
    mapping(uint256 => bool) public deltaToCollateral;

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
    mapping(uint256 => uint256) public withdrawDelayPeriod;
    mapping(uint256 => mapping(address => uint256)) public withdrawInitiated; 
    mapping(uint256 => uint256) public collateralizationRatio;
    mapping(uint256 => mapping(IOracle => bool)) public oracleEnabled; 
    mapping(uint256 => bool) public lpWhitelistOnly;     

    OptionsVault1155 public optionsVault1155;
    mapping(IOracle => bool) public oracleWhitelisted; 

    // constants 
    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");
    
    constructor(OptionsVault1155 _optionsVault1155)  {
        optionsVault1155 = _optionsVault1155;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
    
   function createVault(IOracle _oracle, IERC20 _collateralToken, IERC20 _hedgeToken, IUniswapV2Factory _swapFactory, IUniswapV2Router02 _swapRouter, IFeeCalcs _vaultFeeCalc) public {
        isDefaultAdmin();
        require(oracleWhitelisted[_oracle],"OptionsVault: oracle must be whitelisted");

        collateralToken[vaultCount] = _collateralToken;
        hedgeToken[vaultCount] = _hedgeToken;
        swapFactory[vaultCount] = _swapFactory;
        swapRouter[vaultCount] = _swapRouter;        
        collateralReserves[vaultCount] = 0; 
        hedgeReserves[vaultCount] = 0;
        deltaPercent[vaultCount] = 5000;
        
        lockedCollateralCall[vaultCount] = 0;
        lockedCollateralPut[vaultCount] = 0;
        
        vaultOwner[vaultCount] = _msgSender();        
        vaultFeeRecipient[vaultCount] = _msgSender();    
        vaultFeeCalc[vaultCount] = _vaultFeeCalc;    
        ipfsHash[vaultCount] = "";
        readOnly[vaultCount] = false;
        maxInvest[vaultCount] = 1e18;
        withdrawDelayPeriod[vaultCount] = 1 weeks;
        collateralizationRatio[vaultCount] = 10000;
        
        _setupRole(VAULT_OPERATOR_ROLE(vaultCount), _msgSender());
                
        oracleEnabled[vaultCount][_oracle] = true;
        emit CreateVault(vaultCount, _oracle, _collateralToken, _hedgeToken, _swapFactory, _swapRouter);
        emit UpdateOracle(_oracle, vaultCount, true, _collateralToken, _hedgeToken, _oracle.decimals(), _oracle.description());

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
     * @param collateralIn Amount to deposit in the collatoral token
     * @return mint1155Tokens Tokens minted to represent ownership
     */
    function provide(address account, uint _vaultId, uint256 collateralIn) public returns (uint256 mint1155Tokens){
        return provideAndMint(account,_vaultId,collateralIn,true);
    }    

    /*
     * @nonce Sends tokens to the vault optionally receiving 1155 minted tokens in return. 
     *  mint=false means you will receive no ownership tokens from this function.
     *  To be used to increase the vault with premium collected etc. 
     */     
    function provideAndMint(address account, uint _vaultId, uint256 collateralIn, bool mint) public returns (uint256 mint1155Tokens){
        
        if(lpWhitelistOnly[_vaultId]){
            require(hasRole(VAULT_LPWHITELIST_ROLE(_vaultId), _msgSender()), "OptionsVault: must be in LP Whitelist");
        }
        require(vaultCollateralTotal(_vaultId)+(collateralIn*1e4/collateralizationRatio[_vaultId])<=maxInvest[_vaultId],"OptionsVault: Max invest limit reached");
        
        uint delta = deltaPercent[_vaultId]; 
        if (delta!=5000){
            resetDeltaHedge(_vaultId);
        }  
        IUniswapV2Pair swapPair = IUniswapV2Pair(swapFactory[_vaultId].getPair(address(collateralToken[_vaultId]), address(hedgeToken[_vaultId])));
        (uint mintSwapTokens, ) = SwapPool.addLiquidity(account, collateralToken[_vaultId], hedgeToken[_vaultId], collateralIn, swapFactory[_vaultId], swapRouter[_vaultId]);
    
        if(optionsVault1155.totalSupply(_vaultId)!=0){
            mint1155Tokens = mintSwapTokens*(swapPair.balanceOf(address(this))-mintSwapTokens)/swapBalance[_vaultId];
        }
        else{
            mint1155Tokens = mintSwapTokens;
        }

        if(mint){
            optionsVault1155.mint(account, _vaultId, mint1155Tokens, "");
        }
        swapBalance[_vaultId] += mint1155Tokens;
  
        if(delta!=5000){
            setDeltaHedge(_vaultId, delta, deltaToCollateral[_vaultId]);
        }  
               
        emit Provide(account, _vaultId, collateralIn, mint1155Tokens, mint);
    }
    
    /*
     * @nonce Can't withdraw unless initiated first and within of the withdraw delay period
     */
    function initiateWithdraw(address account, uint _vaultId)  external  {
        if (optionsVault1155.isApprovedForAll(account, _msgSender())){
            withdrawInitiated[_vaultId][account] = block.timestamp;
        }
    }

    /*
     * @nonce Withdraw from the vault, burning the user tokens
     */
    function withdraw(address account, uint _vaultId, uint256 burn1155Tokens) public returns (uint collateralOut) {
       return withdrawAndBurn(account, _vaultId, burn1155Tokens, true);
    }

    /*
     * @nonce Withdraw from the vault, optionally burning the user tokens
     */
    function withdrawAndBurn(address account, uint _vaultId, uint256 burn1155Tokens, bool burn) public returns (uint collateralOut) {
        if(burn1155Tokens==0){
            return 0;
        }

        // Can't withdraw unless initiated first and within of the withdraw delay period
        if(withdrawDelayPeriod[_vaultId]>0){
            if ((withdrawInitiated[_vaultId][account]==0) ||
            ((block.timestamp-withdrawDelayPeriod[_vaultId]>withdrawInitiated[_vaultId][account]) &&
            (block.timestamp-withdrawDelayPeriod[_vaultId]>withdrawInitiated[_vaultId][account]-1 weeks))){
                require(false, "OptionsVault: Invalid withdraw initiation date");
            }
        }
        
        uint delta = deltaPercent[_vaultId]; 
        if (delta!=5000){
            resetDeltaHedge(_vaultId);
        }        
        IUniswapV2Pair swapPair = IUniswapV2Pair(swapFactory[_vaultId].getPair(address(collateralToken[_vaultId]), address(hedgeToken[_vaultId])));        
        uint burnSwapTokens = swapBalance[_vaultId]*burn1155Tokens*swapBalance[_vaultId]/optionsVault1155.totalSupply(_vaultId)/swapPair.balanceOf(address(this));

        if(burn){
            optionsVault1155.burn(account, _vaultId, burn1155Tokens); //will fail if they don't have enough
        }
        (collateralOut,) = SwapPool.removeLiquidity(account, collateralToken[_vaultId], hedgeToken[_vaultId], burnSwapTokens, swapFactory[_vaultId], swapRouter[_vaultId],true);
        swapBalance[_vaultId] -= burn1155Tokens;

        if(delta!=5000){
            setDeltaHedge(_vaultId, delta, deltaToCollateral[_vaultId]);
        }
        emit Withdraw(account, _vaultId, collateralOut, burn1155Tokens, burn);
    }
    
    /* 
     * @nonce Called by Options to lock funds
     */
    function lock(uint optionId, uint256 optionSize, IStructs.Fees memory _premium, uint vaultId, OptionType optionType ) public  {
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

        collateralReserves[vaultId] = collateralReserves[vaultId] + _premium.intrinsicFee + _premium.extrinsicFee;
        emit Lock(optionId, optionSize);
    }
    
    /*
     * @nonce Called by Options to unlock funds
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

        emit Unlock(optionId);
    }

    /*
     * @nonce Send fund to option holder
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

        IUniswapV2Pair swapPair = IUniswapV2Pair(swapFactory[ll.vaultId].getPair(address(collateralToken[ll.vaultId]), address(hedgeToken[ll.vaultId])));       
        withdrawAndBurn(to, ll.vaultId, transferAmount*swapPair.totalSupply()/swapPairCollateralReserves(ll.vaultId,swapPair)/2,false);

        if (transferAmount <= ll.premium)
            //technically not a profit if transfer amt is less premium-fees
            emit VaultProfit(optionId, ll.vaultId, ll.premium - transferAmount);
        else
            emit VaultLoss(optionId, ll.vaultId, transferAmount - ll.premium);
    }

    /*
     * @nonce An approximation of the amount of collateral available for selling options adjusted for collatorization ratio
     * the swap pool reserves*2 plus collateral reserves
     * adjusted for collatorization ratio & adjusted for delta reserves
     */
    function vaultCollateralTotal(uint _vaultId) public view returns (uint256) {              
        IUniswapV2Pair swapPair = IUniswapV2Pair(swapFactory[_vaultId].getPair(address(collateralToken[_vaultId]), address(hedgeToken[_vaultId])));

        if(optionsVault1155.totalSupply(_vaultId)==0){
            return 0;
        }

        return (swapPairCollateralReserves(_vaultId,swapPair)*1e4*swapPair.balanceOf(address(this))/optionsVault1155.totalSupply(_vaultId)/collateralizationRatio[_vaultId]);
    }

    /*
     * @nonce Amount of collateral reserves in the swap pair
     */
    function swapPairCollateralReserves(uint _vaultId, IUniswapV2Pair swapPair) internal view returns (uint256 swapReserves){
        (uint112 reserve0, uint112 reserve1, ) = swapPair.getReserves();
        if(swapPair.token0()==address(collateralToken[_vaultId])){
            swapReserves = reserve0;
        }
        else{
            swapReserves = reserve1;
        }
    }

    /*
     * @nonce Sum of locked collateral puts & calls 
     */
    function vaultCollateralLocked(uint _vaultId) public view returns (uint256){
        return lockedCollateralPut[_vaultId]+lockedCollateralCall[_vaultId];
    }

    /*
     * @nonce The total collateral less the amount locked
     */
    function vaultCollateralAvailable(uint _vaultId) public view returns (uint256) {
        return vaultCollateralTotal(_vaultId)-vaultCollateralLocked(_vaultId);
    }

    /*
     * @nonce Deposit reserves back into the pool back to 50/50
     */
    function resetDeltaHedge(uint _vaultId) public {
        isVaultOwnerOrOperator(_vaultId,_msgSender());

        if(collateralReserves[_vaultId] > 0){
            SwapPool.resetDeltaHedge(this, _vaultId, true);
            collateralReserves[_vaultId] = 0;
        }
        if(hedgeReserves[_vaultId] > 0){
            SwapPool.resetDeltaHedge(this, _vaultId, false);
            hedgeReserves[_vaultId] = 0;
        }
        deltaPercent[_vaultId] = 5000;
    }

    /*
     * @nonce Set the delta hedge by withdrawing from the pool and swapping the tokens
     */
    function setDeltaHedge(uint _vaultId, uint percent, bool _toCollateral) public returns (uint collateralAmount, uint hedgeAmount, uint[] memory swapAmounts) {
        isVaultOwnerOrOperator(_vaultId,_msgSender());

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

    function isVaultOwner(uint vaultId) public {
        require(_msgSender()==vaultOwner[vaultId], "OptionsVault: must have owner role");
    }

    function isVaultOwnerOrOperator(uint vaultId, address account) public {
        require(
            (account==vaultOwner[vaultId]) ||
              (hasRole(VAULT_OPERATOR_ROLE(vaultId),account))
            , "OptionsVault: must have owner or operator role");
    }

    function isDefaultAdmin() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "OptionsVault: must have admin role");
    }

    function setVaultOwner(uint vaultId, address value) external  {
        isVaultOwner(vaultId);
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultOwner, vaultId, vaultOwner[vaultId], value);
        vaultOwner[vaultId] = value;
    }

    function setVaultFeeRecipient(uint vaultId, address value) external {
        isVaultOwner(vaultId);
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultFeeRecipient, vaultId, vaultFeeRecipient[vaultId], value);
        vaultFeeRecipient[vaultId] = value;
    }    
    
    function grantVaultOperatorRole(uint vaultId, address value) external {
        isVaultOwner(vaultId);
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantVaultOperatorRole, vaultId, address(0), value);
        grantRole(VAULT_OPERATOR_ROLE(vaultId),value);
    }

    function revokeVaultOperatorRole(uint vaultId, address value) external {
        isVaultOwner(vaultId);
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeVaultOperatorRole, vaultId, value, address(0));
        revokeRole(VAULT_OPERATOR_ROLE(vaultId),value);
    }

    function grantLPWhitelistRole(uint vaultId, address value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantLPWhitelistRole, vaultId, address(0), value);
        grantRole(VAULT_LPWHITELIST_ROLE(vaultId),value);
    }

    function revokeLPWhitelistRole(uint vaultId, address value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeLPWhitelistRole, vaultId, value, address(0));
        revokeRole(VAULT_LPWHITELIST_ROLE(vaultId),value);
    }

    function setVaultFeeCalc(uint vaultId, IFeeCalcs value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultFeeCalc, vaultId, address(vaultFeeCalc[vaultId]), address(value));
        vaultFeeCalc[vaultId] = value;
    }  

    function setIpfsHash(uint vaultId, string memory value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        ipfsHash[vaultId] = value;
    }  

    function setReadOnly(uint vaultId, bool value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        emit SetVaultBool(_msgSender(),SetVariableType.ReadOnly, vaultId, readOnly[vaultId], value);
        readOnly[vaultId] = value;
    }

    function setMaxInvest(uint vaultId, uint256 value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        emit SetVaultUInt(_msgSender(),SetVariableType.MaxInvest, vaultId, maxInvest[vaultId], value);
        maxInvest[vaultId] = value;
    }   

    function setWithdrawDelayPeriod(uint vaultId, uint256 value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        emit SetVaultUInt(_msgSender(),SetVariableType.WithdrawDelayPeriod, vaultId, withdrawDelayPeriod[vaultId], value);
        withdrawDelayPeriod[vaultId] = value;
    }
    
    function setOracleEnabled(uint vaultId, IOracle _oracle, bool value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        require(oracleWhitelisted[_oracle],"OptionsVault: oracle must be whitelisted");
        oracleEnabled[vaultId][_oracle] = value; 
        emit UpdateOracle(_oracle, vaultCount, value, collateralToken[vaultId], hedgeToken[vaultId], _oracle.decimals(), _oracle.description());
    }    

    function setLPWhitelistOnly(uint vaultId, bool value) external {
        isVaultOwnerOrOperator(vaultId,_msgSender());
        emit SetVaultBool(_msgSender(),SetVariableType.LPWhitelistOnly, vaultId, lpWhitelistOnly[vaultId], value);
        lpWhitelistOnly[vaultId] = value; 
    }     

    function setCollaterizationRatio(uint vaultId, uint256 value) external {
        isDefaultAdmin();
        emit SetVaultUInt(_msgSender(),SetVariableType.CollateralizationRatio, vaultId, collateralizationRatio[vaultId], value);
        collateralizationRatio[vaultId] = value;
    }

    function setOracleWhitelisted(IOracle _oracle, bool value) external {
        isDefaultAdmin();        
        emit SetGlobalBool(_msgSender(),SetVariableType.OracleWhitelisted, oracleWhitelisted[_oracle], value);
        oracleWhitelisted[_oracle] = value;   
    }  
}