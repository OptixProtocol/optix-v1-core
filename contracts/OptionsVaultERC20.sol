// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/Interfaces.sol";
import "./libraries/OptionsLib.sol";
import "./OptionsVaultFactory.sol";

contract OptionsVaultERC20 is ERC20, AccessControl, IStructs, IOptions {
    using SafeERC20 for IERC20;

    OptionsVaultFactory public factory;

    // internal vault properties
    IERC20 public collateralToken; 
    uint256 public collateralReserves;

    uint256 public lockedCollateralCall;
    uint256 public lockedCollateralPut;    
    mapping(uint256 => LockedCollateral) public lockedCollateral;

    // updatable by vault owner/operator 
    address public vaultOwner;
    address public vaultFeeRecipient;
    IFeeCalcs public vaultFeeCalc;
    BoolState public vaultFeeCalcLocked;   
    uint256 public vaultFee = 100;
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
    bytes32 public constant VAULT_OPERATOR_ROLE = keccak256("VAULT_OPERATOR_ROLE");
    bytes32 public constant VAULT_BUYERWHITELIST_ROLE = keccak256("VAULT_BUYERWHITELIST_ROLE");
    bytes32 public constant VAULT_LPWHITELIST_ROLE = keccak256("VAULT_LPWHITELIST_ROLE");
    
    constructor() ERC20("Optix Vault V1", "OPTIX-VAULT-V1") {}

    function name() public view override returns (string memory) {
        return string.concat("Optix Vault V1-",Strings.toString(getVaultId()));
    }

    function symbol() public view override returns (string memory) {
        return string.concat("OPTIX-VAULT-V1-",Strings.toString(getVaultId()));
    }

    function initialize(address _owner, IOracle _oracle, IERC20 _collateralToken, IFeeCalcs _vaultFeeCalc) external {
        require(address(factory) == address(0), "OptionsVaultERC20: FORBIDDEN"); 
        collateralToken = _collateralToken;
        collateralReserves = 0; 
        
        lockedCollateralCall = 0;
        lockedCollateralPut = 0;
        
        vaultOwner = _owner;        
        vaultFeeRecipient = _owner;    
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
        
        _setupRole(VAULT_OPERATOR_ROLE, _owner);
        _setupRole(VAULT_LPWHITELIST_ROLE, _owner);
        _setupRole(VAULT_BUYERWHITELIST_ROLE, _owner);
                
        oracleEnabled[_oracle] = true;
    }

     /*
     * @nonce A provider supplies token to the vault and receives optix vault tokens
     * @param account account who will be the owner of the minted tokens 
     * @param vaultId Pool to provide to 
     * @param collateralIn Amount to deposit in the collatoral token
     * @return mintTokens Tokens minted to represent ownership
     */
    function provide(address _account, uint256 _collateralIn) public returns (uint256 mintTokens){
        return provideAndMint(_account,_collateralIn,true,false);
    }    

    /*
     * @nonce Sends tokens to the vault optionally receiving minted tokens in return. 
     *  mint=false means you will receive no ownership tokens from this function.
     *  To be used to increase the vault with premium collected etc. 
     */     
    function provideAndMint(address _account, uint256 _collateralIn, bool _mintVaultTokens, bool _collectedWithPremium) public returns (uint256 mintTokens){
        
        uint _vaultId = getVaultId();
        if(_mintVaultTokens && OptionsLib.boolStateIsTrue(lpWhitelistOnly)){            

            require(hasRole(VAULT_LPWHITELIST_ROLE, _account), "OptionsVaultERC20: must be in LP Whitelist");
        }
        require(vaultCollateralTotal()+(_collateralIn*factory.getCollateralizationRatio(this)/1e4)<=maxInvest,"OptionsVaultERC20: Max invest limit reached");

        if(_collectedWithPremium){            
            require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");
        }
        else{
            collateralToken.safeTransferFrom(_account, address(this), _collateralIn);
        }

        uint256 supply = totalSupply();
        uint balance = collateralReserves;
        if (supply > 0 && balance > 0){
            mintTokens = _collateralIn*supply/balance;
        }
        else
            mintTokens = _collateralIn*INITIAL_RATE;
        require(mintTokens > 0, "OptionsVaultERC20: Amount is too small");


        collateralReserves += _collateralIn;               
        emit Provide(_account, _vaultId, _collateralIn, mintTokens, _mintVaultTokens);
        if(_mintVaultTokens){
            _mint(_account, mintTokens);
        }
    }

    /*
     * @nonce Can't withdraw unless initiated first and within of the withdraw delay period
     */
    function initiateWithdraw(address _account)  external  {
        if (allowance(_account, address(this))>0){
            if (withdrawInitiated[_account] == 0){
                withdrawInitiated[_account] = block.timestamp;
            }
            else{
                if(block.timestamp > withdrawInitiated[_account] + withdrawDelayPeriod + factory.withdrawWindow()){
                    withdrawInitiated[_account] = block.timestamp;
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
    function withdraw(address _account, uint256 _tokensToBurn) public returns (uint collateralOut) {
       return withdrawAndBurn(_account, _tokensToBurn, true);
    }

    /*
     * @nonce Withdraw from the vault, optionally burning the user tokens
     */
    function withdrawAndBurn(address _account, uint256 _tokensToBurn, bool _burnVaultTokens) internal returns (uint collateralOut) {
        uint _vaultId = getVaultId();
        if(_tokensToBurn==0){
            return 0;
        }
        
        // Can't withdraw unless initiated first and within of the withdraw delay period
        if (withdrawDelayPeriod>0){
            if ((withdrawInitiated[_account]==0) ||
                ((block.timestamp < withdrawInitiated[_account] + withdrawDelayPeriod) ||
                (block.timestamp > withdrawInitiated[_account] + withdrawDelayPeriod + factory.withdrawWindow()))) {
                    require(false, "OptionsVaultERC20: Invalid withdraw initiation date");
            }
        }
        collateralOut = collateralReserves * _tokensToBurn / totalSupply();
        if(_burnVaultTokens){
            require(collateralOut <= vaultCollateralAvailable(),"OptionsVaultERC20: not enough unlocked collateral available");
        }

        collateralReserves -= collateralOut;
        collateralToken.approve(address(this),collateralOut);
        collateralToken.safeTransferFrom(address(this), _account, collateralOut);
        emit Withdraw(_account, _vaultId, collateralOut, _tokensToBurn, _burnVaultTokens);

        if(_burnVaultTokens){            
            _burn(_account, _tokensToBurn); //will fail if they don't have enough
        }
    }


    /* 
     * @nonce Called by Options to lock funds
     */
    function lock(uint _optionId, uint256 _optionSize, IStructs.Fees memory _premium, OptionType _optionType ) public  {
        uint _vaultId = getVaultId();
        require(
                _optionSize <= vaultCollateralAvailable(),
                "OptionsVaultERC20: Not enough vault collateral available."
        );
        require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");

        lockedCollateral[_optionId] = LockedCollateral(_optionSize, _premium, true, _vaultId, _optionType);
        if(_optionType == OptionType.Put){
            lockedCollateralPut = lockedCollateralPut+_optionSize;
        }
        else{
            lockedCollateralCall = lockedCollateralCall+_optionSize;
        }

        emit Lock(_optionId, _optionSize);
    }
    
    /*
     * @nonce Called by Options to unlock funds
     */
    function unlock(uint256 _optionId) public  {
        LockedCollateral storage ll = lockedCollateral[_optionId];        
        require(ll.locked, "OptionsVaultERC20: lockedCollateral with id has already unlocked");
        require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");

        ll.locked = false;

        if(ll.optionType == OptionType.Put)
          lockedCollateralPut = lockedCollateralPut-ll.optionSize;
        else
          lockedCollateralCall = lockedCollateralCall-ll.optionSize;

        emit VaultProfit(_optionId, ll.vaultId, ll.premium.intrinsicFee+ll.premium.extrinsicFee);
        emit Unlock(_optionId);
    }

    /*
     * @nonce Send fund to option holder
     */
    function send(uint _optionId, address _to, uint256 _amount) public {
        LockedCollateral storage ll = lockedCollateral[_optionId];
        require(ll.locked, "OptionsVaultERC20: id already unlocked");
        require(_to != address(0));
        require(factory.optionsContract() == msg.sender, "OptionsVaultERC20: must be called from options contract");

        ll.locked = false;
        if(ll.optionType == OptionType.Put)
          lockedCollateralPut = lockedCollateralPut-ll.optionSize;
        else
          lockedCollateralCall = lockedCollateralCall-ll.optionSize;

        uint transferAmount = _amount > ll.optionSize ? ll.optionSize : _amount;
        withdrawAndBurn(_to, _amount*totalSupply() / collateralReserves, false);

        if (transferAmount <= ll.premium.intrinsicFee+ll.premium.extrinsicFee)
            emit VaultProfit(_optionId, ll.vaultId, ll.premium.intrinsicFee+ll.premium.extrinsicFee-transferAmount);
        else
            emit VaultLoss(_optionId, ll.vaultId, transferAmount-ll.premium.intrinsicFee+ll.premium.extrinsicFee);
        emit Unlock(_optionId);
    }

    function isOptionValid(address _buyer, IOracle _oracle, uint256 _optionSize) public view returns (bool) {
        require(!readOnly, "OptionsVaultERC20: vault is readonly");
        if(!OptionsLib.boolStateIsTrue(factory.oracleIsPermissionless())){
            require(factory.oracleWhitelisted(_oracle),"OptionsVaultERC20: oracle must be in whitelist");
        }
        if(!OptionsLib.boolStateIsTrue(factory.collateralTokenIsPermissionless())){
            require(factory.collateralTokenWhitelisted(collateralToken),"OptionsVaultERC20: collateral token must be in whitelist");
        }          
        require(oracleEnabled[_oracle],"OptionsVaultERC20: oracle not enabled for this vault");        
        if(OptionsLib.boolStateIsTrue(buyerWhitelistOnly)){            
            require(hasRole(VAULT_BUYERWHITELIST_ROLE, _buyer), "OptionsVaultERC20: must be in _buyer whitelist");
        }        
        require(vaultCollateralAvailable()>=_optionSize, "OptionsVaultERC20: Not enough available collateral");

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

    // How much is the vault utilized from 0...10000 (100%) if the optionSize is included 
    // Used for calculating 
    function vaultUtilization(uint256 _includingOptionSize) public view returns (uint256) {
        return (vaultCollateralLocked()+_includingOptionSize)*1e4/vaultCollateralTotal();        
    }

    function isVaultOwner() public {
        require(_msgSender()==vaultOwner, "OptionsVaultERC20: must have owner role");
    }

    function isVaultOwnerOrOperator(address _account) public {
        require(
            (_account==vaultOwner) ||
                (hasRole(VAULT_OPERATOR_ROLE,_account))
            , "OptionsVaultERC20: must have owner or operator role");
    }
    
    function setVaultFee(uint256 _value) external {
        isVaultOwnerOrOperator(_msgSender());        
        emit SetVaultUInt(_msgSender(),SetVariableType.VaultFee, getVaultId(), vaultFee, _value);
        vaultFee = _value;
    }

    function setWithdrawDelayPeriod(uint256 _value) external {
        isVaultOwnerOrOperator(_msgSender());
        require(!OptionsLib.boolStateIsTrue(withdrawDelayPeriodLocked),"OptionsVaultERC20: setting is immutable");
        emit SetVaultUInt(_msgSender(),SetVariableType.WithdrawDelayPeriod, getVaultId(), withdrawDelayPeriod, _value);
        withdrawDelayPeriod = _value;
    }

    function setWithdrawDelayPeriodLockedImmutable(BoolState _value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(withdrawDelayPeriodLocked),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.WithdrawDelayPeriodLocked, getVaultId(), withdrawDelayPeriodLocked, _value);
        withdrawDelayPeriodLocked = _value; 
    } 

       function setLPWhitelistOnly(bool _value) public {
        if (_value){
            setLPWhitelistOnlyImmutable(BoolState.TrueMutable);
        }
        else{
            setLPWhitelistOnlyImmutable(BoolState.FalseMutable);
        }
    }

    function setLPWhitelistOnlyImmutable(BoolState _value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(lpWhitelistOnly),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.LPWhitelistOnly, getVaultId(), lpWhitelistOnly, _value);
        lpWhitelistOnly = _value; 
    }   

    function setVaultOwner(address _value) external  {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultOwner, getVaultId(), vaultOwner, _value);
        vaultOwner = _value;
    }    

    function setVaultFeeRecipient(address _value) external {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultFeeRecipient, getVaultId(), vaultFeeRecipient, _value);
        vaultFeeRecipient = _value;
    }       

    function grantVaultOperatorRole(address _value) external {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantVaultOperatorRole, getVaultId(), address(0), _value);
        _grantRole(VAULT_OPERATOR_ROLE,_value);
    }

    function revokeVaultOperatorRole(address _value) external {
        isVaultOwner();
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeVaultOperatorRole, getVaultId(), _value, address(0));
        _revokeRole(VAULT_OPERATOR_ROLE,_value);
    }    


    function setMaxInvest(uint256 _value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultUInt(_msgSender(),SetVariableType.MaxInvest, getVaultId(), maxInvest, _value);
        maxInvest = _value;
    }  

    function grantLPWhitelistRole(address _value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantLPWhitelistRole, getVaultId(), address(0), _value);
        grantRole(VAULT_LPWHITELIST_ROLE,_value);
    }

    function revokeLPWhitelistRole(address _value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeLPWhitelistRole, getVaultId(), _value, address(0));
        revokeRole(VAULT_LPWHITELIST_ROLE,_value);
    }

    function grantBuyerWhitelistRole(address _value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.GrantBuyerWhitelistRole, getVaultId(), address(0), _value);
        grantRole(VAULT_BUYERWHITELIST_ROLE,_value);
    }

    function revokeBuyerWhitelistRole(address _value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultAddress(_msgSender(),SetVariableType.RevokeBuyerWhitelistRole, getVaultId(), _value, address(0));
        revokeRole(VAULT_BUYERWHITELIST_ROLE,_value);
    }    


  function setBuyerWhitelistOnly(bool _value) public {
        if (_value){
            setBuyerWhitelistOnlyImmutable(BoolState.TrueMutable);
        }
        else{
            setBuyerWhitelistOnlyImmutable(BoolState.FalseMutable);
        }
    }  

    function setBuyerWhitelistOnlyImmutable(BoolState _value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(buyerWhitelistOnly),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.BuyerWhitelistOnly, getVaultId(), buyerWhitelistOnly, _value);
        buyerWhitelistOnly = _value; 
    } 
    
    function setReadOnly(bool _value) external {
        isVaultOwnerOrOperator(_msgSender());
        emit SetVaultBool(_msgSender(),SetVariableType.ReadOnly, getVaultId(), readOnly, _value);
        readOnly = _value;
    }


    function setVaultFeeCalc(IFeeCalcs _value) external {
        isVaultOwnerOrOperator(_msgSender());
        require(!OptionsLib.boolStateIsTrue(vaultFeeCalcLocked),"OptionsVaultERC20: vaultFeeCalc is locked");        
        emit SetVaultAddress(_msgSender(),SetVariableType.VaultFeeCalc, getVaultId(), address(vaultFeeCalc), address(_value));
        vaultFeeCalc = _value;
    }  

    function setVaultFeeCalcLockedImmutable(BoolState _value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(vaultFeeCalcLocked),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.VaultFeeCalcLocked, getVaultId(), vaultFeeCalcLocked, _value);
        vaultFeeCalcLocked = _value; 
    }       

    function setIpfsHash(string memory _value) external {
        isVaultOwnerOrOperator(_msgSender());
        ipfsHash = _value;
    }  

     function setOracleEnabled(IOracle _oracle, bool _value) external {
        isVaultOwnerOrOperator(_msgSender());
        if(!OptionsLib.boolStateIsTrue(factory.oracleIsPermissionless())){
            require(factory.oracleWhitelisted(_oracle),"OptionsVaultERC20: oracle must be in whitelist");
        }
        require(!OptionsLib.boolStateIsTrue(oracleEnabledLocked),"OptionsVaultERC20: setting is immutable");
        oracleEnabled[_oracle] = _value; 
        emit UpdateOracle(_oracle, getVaultId(), _value, collateralToken, _oracle.decimals(), _oracle.description());
    }    

    function setOracleEnabledLockedImmutable(BoolState _value) public {
        isVaultOwnerOrOperator(_msgSender());
        require(OptionsLib.boolStateIsMutable(oracleEnabledLocked),"OptionsVaultERC20: setting is immutable");
        emit SetVaultBoolState(_msgSender(),SetVariableType.OracleEnabledLocked, getVaultId(), oracleEnabledLocked, _value);
        oracleEnabledLocked = _value; 
    }   
 
    function getVaultId() public view returns (uint256) {
        return factory.vaultId(address(this));
    }
    
}