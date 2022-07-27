// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/Interfaces.sol";
import "./libraries/OptionsLib.sol";
import "./OptionsVaultFactory.sol";
import "hardhat/console.sol";

contract OptionsVaultERC20 is ERC20, AccessControl, IStructs, IOptions {
    using SafeERC20 for IERC20;

    // internal vault properties
    IERC20 public collateralToken; 
    uint256 public collateralReserves;

    uint256 public lockedCollateralCall;
    uint256 public lockedCollateralPut;
    LockedCollateral[] public lockedCollateralArray;
    mapping(uint256 => LockedCollateral) public lockedCollateral;

    // updatable by vault owner/operator 
    address public vaultOwner;
    address public vaultFeeRecipient;
    IFeeCalcs public vaultFeeCalc;
    string public ipfsHash;
    bool public readOnly;
    uint256 public maxInvest;
    uint256 public withdrawDelayPeriod;
    BoolState public withdrawDelayPeriodLocked;    
    mapping(address => uint256) public withdrawInitiated;     
    mapping(IOracle => bool) public oracleEnabled; 
    BoolState public oracleEnabledLocked;    
    BoolState public lpWhitelistOnly;     
    BoolState public buyerWhitelistOnly;  

    //constants
    uint256 public constant INITIAL_RATE = 1e18;
    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");
    bytes32 public constant VAULT_OPERATOR_ROLE = keccak256("VAULT_OPERATOR_ROLE");
    bytes32 public constant VAULT_BUYERWHITELIST_ROLE = keccak256("VAULT_BUYERWHITELIST_ROLE");
    bytes32 public constant VAULT_LPWHITELIST_ROLE = keccak256("VAULT_LPWHITELIST_ROLE");
    
    OptionsVaultFactory public factory;

    constructor() ERC20("Optix Vault V1", "OPTIX-VAULT-V1") {}

    function initialize(address owner, IOracle _oracle, IERC20 _collateralToken, IFeeCalcs _vaultFeeCalc) external {
        require(address(factory) == address(0), "OptionsVaultERC20: FORBIDDEN"); 
        collateralToken = _collateralToken;
        collateralReserves = 0; 
        
        lockedCollateralCall = 0;
        lockedCollateralPut = 0;
        
        vaultOwner = owner;        
        vaultFeeRecipient = owner;    
        vaultFeeCalc = _vaultFeeCalc;    
        ipfsHash = "";
        readOnly = false;
        maxInvest = 1e18;
        withdrawDelayPeriod = 1 weeks;
        withdrawDelayPeriodLocked = BoolState.FalseMutable;
        lpWhitelistOnly = BoolState.TrueMutable;
        buyerWhitelistOnly = BoolState.FalseMutable;
        oracleEnabledLocked = BoolState.FalseMutable;
        factory = OptionsVaultFactory(msg.sender);
        
        _setupRole(VAULT_OPERATOR_ROLE, owner);
        _setupRole(VAULT_LPWHITELIST_ROLE, owner);
        _setupRole(VAULT_BUYERWHITELIST_ROLE, owner);
                
        oracleEnabled[_oracle] = true;
    }

     /*
     * @nonce A provider supplies token to the vault and receives optix vault1155 tokens
     * @param account account who will be the owner of the minted tokens 
     * @param vaultId Pool to provide to 
     * @param collateralIn Amount to deposit in the collatoral token
     * @return mintTokens Tokens minted to represent ownership
     */
    function provide(address account, uint256 collateralIn) public returns (uint256 mintTokens){
        return provideAndMint(account,collateralIn,true,false);
    }    

    /*
     * @nonce Sends tokens to the vault optionally receiving 1155 minted tokens in return. 
     *  mint=false means you will receive no ownership tokens from this function.
     *  To be used to increase the vault with premium collected etc. 
     */     
    function provideAndMint(address account, uint256 collateralIn, bool mint, bool collectedWithPremium) public returns (uint256 mintTokens){
        
        uint _vaultId = getVaultId();
        if(mint && OptionsLib.boolStateIsTrue(lpWhitelistOnly)){            

            require(hasRole(VAULT_LPWHITELIST_ROLE, account), "OptionsVaultERC20: must be in LP Whitelist");
        }
        require(vaultCollateralTotal()+(collateralIn*factory.getCollateralizationRatio(this)/1e4)<=maxInvest,"OptionsVaultERC20: Max invest limit reached");

        if(collectedWithPremium){            
            require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");
        }
        else{
            collateralToken.safeTransferFrom(account, address(this), collateralIn);
        }

        uint256 supply = totalSupply();
        uint balance = collateralReserves;
        if (supply > 0 && balance > 0){
            mintTokens = collateralIn*supply/balance;
        }
        else
            mintTokens = collateralIn*INITIAL_RATE;
        require(mintTokens > 0, "OptionsVaultERC20: Amount is too small");


        collateralReserves += collateralIn;               
        emit Provide(account, _vaultId, collateralIn, mintTokens, mint);
        if(mint){
            _mint(account, mintTokens);
        }
    }

    /*
     * @nonce Can't withdraw unless initiated first and within of the withdraw delay period
     */
    function initiateWithdraw(address account)  external  {
        if (allowance(account, address(this))>0){
            if (withdrawInitiated[account] == 0){
                withdrawInitiated[account] = block.timestamp;
            }
            else{
                if(block.timestamp > withdrawInitiated[account] + withdrawDelayPeriod + factory.withdrawWindow()){
                    withdrawInitiated[account] = block.timestamp;
                }
                else{
                    require(false, "OptionsVaultERC20: Invalid withdraw initiation date");
                }
            }
            
        }
    }


    /*
     * @nonce Withdraw from the vault, burning the user tokens
     */
    function withdraw(address account, uint256 burnTokens) public returns (uint collateralOut) {
       return withdrawAndBurn(account, burnTokens, true);
    }

    /*
     * @nonce Withdraw from the vault, optionally burning the user tokens
     */
    function withdrawAndBurn(address account, uint256 burnTokens, bool burn) internal returns (uint collateralOut) {
        uint _vaultId = getVaultId();
        if(burnTokens==0){
            return 0;
        }
        
        // Can't withdraw unless initiated first and within of the withdraw delay period
        if (withdrawDelayPeriod>0){
            if ((withdrawInitiated[account]==0) ||
                ((block.timestamp < withdrawInitiated[account] + withdrawDelayPeriod) ||
                (block.timestamp > withdrawInitiated[account] + withdrawDelayPeriod + factory.withdrawWindow()))) {
                    require(false, "OptionsVaultERC20: Invalid withdraw initiation date");
            }
        }
        collateralOut = collateralReserves * burnTokens / totalSupply();
        if(burn){
            require(collateralOut <= vaultCollateralAvailable(),"OptionsVaultERC20: not enough unlocked collateral available");
        }

        collateralReserves -= collateralOut;
        collateralToken.approve(address(this),collateralOut);
        collateralToken.safeTransferFrom(address(this), account, collateralOut);
        if(burn){            
            _burn(account, burnTokens); //will fail if they don't have enough
        }

        emit Withdraw(account, _vaultId, collateralOut, burnTokens, burn);
    }


    /* 
     * @nonce Called by Options to lock funds
     */
    function lock(uint optionId, uint256 optionSize, IStructs.Fees memory _premium, OptionType optionType ) public  {
        uint _vaultId = getVaultId();
        require(
                optionSize <= vaultCollateralAvailable(),
                "OptionsVaultERC20: Not enough vault collateral available."
        );
        require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");

        lockedCollateral[optionId] = LockedCollateral(optionSize, _premium, true, _vaultId, optionType);
        if(optionType == OptionType.Put){
            lockedCollateralPut = lockedCollateralPut+optionSize;
        }
        else{
            lockedCollateralCall = lockedCollateralCall+optionSize;
        }

        emit Lock(optionId, optionSize);
    }
    
    /*
     * @nonce Called by Options to unlock funds
     */
    function unlock(uint256 optionId) public  {
        LockedCollateral storage ll = lockedCollateral[optionId];        
        require(ll.locked, "OptionsVaultERC20: lockedCollateral with id has already unlocked");
        require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");

        ll.locked = false;

        if(ll.optionType == OptionType.Put)
          lockedCollateralPut = lockedCollateralPut-ll.optionSize;
        else
          lockedCollateralCall = lockedCollateralCall-ll.optionSize;

        emit VaultProfit(optionId, ll.vaultId, ll.premium.intrinsicFee+ll.premium.extrinsicFee);
        emit Unlock(optionId);
    }

    /*
     * @nonce Send fund to option holder
     */
    function send(uint optionId, address to, uint256 amount) public {
        LockedCollateral storage ll = lockedCollateral[optionId];
        require(ll.locked, "OptionsVaultERC20: id already unlocked");
        require(to != address(0));
        require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");

        ll.locked = false;
        if(ll.optionType == OptionType.Put)
          lockedCollateralPut = lockedCollateralPut-ll.optionSize;
        else
          lockedCollateralCall = lockedCollateralCall-ll.optionSize;

        uint transferAmount = amount > ll.optionSize ? ll.optionSize : amount;
        withdrawAndBurn(to, amount*totalSupply() / collateralReserves, false);

        if (transferAmount <= ll.premium.intrinsicFee+ll.premium.extrinsicFee)
            emit VaultProfit(optionId, ll.vaultId, ll.premium.intrinsicFee+ll.premium.extrinsicFee-transferAmount);
        else
            emit VaultLoss(optionId, ll.vaultId, transferAmount-ll.premium.intrinsicFee+ll.premium.extrinsicFee);
    }

    function isOptionValid(address buyer, IOracle _oracle, uint256 optionSize) public view returns (bool) {
        require(!readOnly, "OptionsVaultERC20: vault is readonly");
        if(!OptionsLib.boolStateIsTrue(factory.oracleIsPermissionless())){
            require(factory.oracleWhitelisted(_oracle),"OptionsVaultERC20: oracle must be in whitelist");
        }
        require(oracleEnabled[_oracle],"OptionsVaultERC20: oracle not enabled for this vault");        
        if(OptionsLib.boolStateIsTrue(buyerWhitelistOnly)){            
            require(hasRole(VAULT_BUYERWHITELIST_ROLE, buyer), "OptionsVaultERC20: must be in buyer whitelist");
        }
        require(vaultCollateralAvailable()>=optionSize, "OptionsVaultERC20: Not enough available collateral");

        return true;
    }

     /*
     */
    function vaultCollateralTotal() public view returns (uint256) {              
        if(totalSupply()==0){
            return 0;
        }

        return factory.getCollateralizationRatio(this)*collateralReserves/1e4;
    }

    /*
     * @nonce Sum of locked collateral puts & calls 
     */
    function vaultCollateralLocked() public view returns (uint256){
        return lockedCollateralPut+lockedCollateralCall;
    }

    /*
     * @nonce The total collateral less the amount locked
     */
    function vaultCollateralAvailable() public view returns (uint256) {
        return vaultCollateralTotal()-vaultCollateralLocked();
    }

    function isVaultOwner() public {
        require(_msgSender()==vaultOwner, "OptionsVaultERC20: must have owner role");
    }

    function isVaultOwnerOrOperator(address account) public {
        require(
            (account==vaultOwner) ||
                (hasRole(VAULT_OPERATOR_ROLE,account))
            , "OptionsVaultERC20: must have owner or operator role");
    }
    
    function setWithdrawDelayPeriod(uint256 value) external {
        isVaultOwnerOrOperator(_msgSender());
        require(!OptionsLib.boolStateIsTrue(withdrawDelayPeriodLocked),"OptionsVaultERC20: setting is immutable");
        emit SetVaultUInt(_msgSender(),SetVariableType.WithdrawDelayPeriod, getVaultId(), withdrawDelayPeriod, value);
        withdrawDelayPeriod = value;
    }

    function setWithdrawDelayPeriodLockedImmutable(BoolState value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(withdrawDelayPeriodLocked),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.WithdrawDelayPeriodLocked, getVaultId(), withdrawDelayPeriodLocked, value);
        withdrawDelayPeriodLocked = value; 
    } 

       function setLPWhitelistOnly(bool value) public {
        if (value){
            setLPWhitelistOnlyImmutable(BoolState.TrueMutable);
        }
        else{
            setLPWhitelistOnlyImmutable(BoolState.FalseMutable);
        }
    }

    function setLPWhitelistOnlyImmutable(BoolState value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(lpWhitelistOnly),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.LPWhitelistOnly, getVaultId(), lpWhitelistOnly, value);
        lpWhitelistOnly = value; 
    }   

    function setVaultOwner(address value) external  {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultOwner, getVaultId(), vaultOwner, value);
        vaultOwner = value;
    }    

    function setVaultFeeRecipient(address value) external {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultFeeRecipient, getVaultId(), vaultFeeRecipient, value);
        vaultFeeRecipient = value;
    }       

    function grantVaultOperatorRole(address value) external {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantVaultOperatorRole, getVaultId(), address(0), value);
        _grantRole(VAULT_OPERATOR_ROLE,value);
    }

    function revokeVaultOperatorRole(address value) external {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeVaultOperatorRole, getVaultId(), value, address(0));
        _revokeRole(VAULT_OPERATOR_ROLE,value);
    }    


    function setMaxInvest(uint256 value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultUInt(_msgSender(),SetVariableType.MaxInvest, getVaultId(), maxInvest, value);
        maxInvest = value;
    }  

    function grantLPWhitelistRole(address value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantLPWhitelistRole, getVaultId(), address(0), value);
        grantRole(VAULT_LPWHITELIST_ROLE,value);
    }

    function revokeLPWhitelistRole(address value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeLPWhitelistRole, getVaultId(), value, address(0));
        revokeRole(VAULT_LPWHITELIST_ROLE,value);
    }

    function grantBuyerWhitelistRole(address value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantBuyerWhitelistRole, getVaultId(), address(0), value);
        grantRole(VAULT_BUYERWHITELIST_ROLE,value);
    }

    function revokeBuyerWhitelistRole(address value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeBuyerWhitelistRole, getVaultId(), value, address(0));
        revokeRole(VAULT_BUYERWHITELIST_ROLE,value);
    }    


  function setBuyerWhitelistOnly(bool value) public {
        if (value){
            setBuyerWhitelistOnlyImmutable(BoolState.TrueMutable);
        }
        else{
            setBuyerWhitelistOnlyImmutable(BoolState.FalseMutable);
        }
    }  

    function setBuyerWhitelistOnlyImmutable(BoolState value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(buyerWhitelistOnly),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.BuyerWhitelistOnly, getVaultId(), buyerWhitelistOnly, value);
        buyerWhitelistOnly = value; 
    } 
    
    function setReadOnly(bool value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultBool(_msgSender(),SetVariableType.ReadOnly, getVaultId(), readOnly, value);
        readOnly = value;
    }


    function setVaultFeeCalc(IFeeCalcs value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultFeeCalc, getVaultId(), address(vaultFeeCalc), address(value));
        vaultFeeCalc = value;
    }  

    function setIpfsHash(string memory value) external {
        isVaultOwnerOrOperator(_msgSender());
        ipfsHash = value;
    }  

     function setOracleEnabled(IOracle _oracle, bool value) external {
        isVaultOwnerOrOperator(_msgSender());
        if(!OptionsLib.boolStateIsTrue(factory.oracleIsPermissionless())){
            require(factory.oracleWhitelisted(_oracle),"OptionsVaultERC20: oracle must be in whitelist");
        }
        require(!OptionsLib.boolStateIsTrue(oracleEnabledLocked),"OptionsVaultERC20: setting is immutable");
        oracleEnabled[_oracle] = value; 
        emit UpdateOracle(_oracle, getVaultId(), value, collateralToken, _oracle.decimals(), _oracle.description());
    }    

    function setOracleEnabledLockedImmutable(BoolState value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(oracleEnabledLocked),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.OracleEnabledLocked, getVaultId(), oracleEnabledLocked, value);
        oracleEnabledLocked = value; 
    }   
 
    function getVaultId() public view returns (uint256) {
        return factory.vaultId(address(this));
    }
    
}