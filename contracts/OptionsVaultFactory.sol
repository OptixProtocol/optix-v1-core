pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "./libraries/OptionsLib.sol";
import "./OptionsVaultERC20.sol";


contract OptionsVaultFactory is IOptions, AccessControl, IStructs {

    OptionsVaultERC20[] public vaults;
    mapping(address => uint256) public vaultId;

    address public optionsContract;
    address public optionVaultERC20Implementation;

    mapping(IOracle => bool) public oracleWhitelisted; 
    mapping(IERC20 => bool) public collateralTokenWhitelisted; 
    mapping(OptionsVaultERC20 => uint256) public collateralizationRatio;

    BoolState public createVaultIsPermissionless = BoolState.FalseMutable;
    BoolState public oracleIsPermissionless = BoolState.FalseMutable;
    BoolState public collateralTokenIsPermissionless = BoolState.FalseMutable;

    uint256 public withdrawWindow = 2 days;

    //constants
    bytes32 public constant CREATE_VAULT_ROLE = keccak256("CREATE_VAULT_ROLE");
    bytes32 public constant COLLATERAL_RATIO_ROLE = keccak256("COLLATERAL_RATIO_ROLE");
    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");

    constructor(address _optionVaultERC20Implementation)  {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(COLLATERAL_RATIO_ROLE, _msgSender());
        _setupRole(CREATE_VAULT_ROLE, _msgSender());
        optionVaultERC20Implementation = _optionVaultERC20Implementation;
    }

    function initialize(address _optionsContract) public {
        isDefaultAdmin();        
        if (optionsContract == address(0)){
            optionsContract = _optionsContract;
        }
    }

   function createVault(address _owner, IOracle _oracle, IERC20 _collateralToken, IFeeCalcs _vaultFeeCalc) public returns (address){
        if(!OptionsLib.boolStateIsTrue(createVaultIsPermissionless)){
            require(hasRole(CREATE_VAULT_ROLE, _msgSender()), "OptionsVaultFactory: must hold CREATE_VAULT_ROLE");
        }
                
        if(!OptionsLib.boolStateIsTrue(oracleIsPermissionless)){
            require(oracleWhitelisted[_oracle],"OptionsVaultFactory: oracle must be in whitelist");
        }
        if(!OptionsLib.boolStateIsTrue(collateralTokenIsPermissionless)){
            require(collateralTokenWhitelisted[_collateralToken],"OptionsVaultFactory: collateral token must be in whitelist");
        }    

        address vault = Clones.clone(optionVaultERC20Implementation);
        OptionsVaultERC20(vault).initialize(_owner,_oracle,_collateralToken,_vaultFeeCalc);
        
        emit CreateVault(vaults.length, _oracle, _collateralToken, vault);
        emit UpdateOracle(_oracle, vaults.length, true, _collateralToken, _oracle.decimals(), _oracle.description());

        vaultId[vault] = vaults.length;
        vaults.push(OptionsVaultERC20(vault));
        return vault;
   }

    function vaultsLength() public view returns(uint) {
        return vaults.length;
    }

    function setCreateVaultIsPermissionlessImmutable(BoolState _value) public {
        isDefaultAdmin();        
        require(OptionsLib.boolStateIsMutable(createVaultIsPermissionless),"OptionsVaultFactory: setting is immutable");
        emit SetGlobalBoolState(_msgSender(),SetVariableType.CreateVaultIsPermissionless, createVaultIsPermissionless, _value);
        createVaultIsPermissionless = _value;   
    }  

    function setOracleIsPermissionlessImmutable(BoolState _value) public {
        isDefaultAdmin();        
        require(OptionsLib.boolStateIsMutable(oracleIsPermissionless),"OptionsVaultFactory: setting is immutable");
        emit SetGlobalBoolState(_msgSender(),SetVariableType.OracleIsPermissionless, oracleIsPermissionless, _value);
        oracleIsPermissionless = _value;   
    } 

    function setCollateralTokenIsPermissionlessImmutable(BoolState _value) public {
        isDefaultAdmin();        
        require(OptionsLib.boolStateIsMutable(collateralTokenIsPermissionless),"OptionsVaultFactory: setting is immutable");
        emit SetGlobalBoolState(_msgSender(),SetVariableType.CollateralTokenIsPermissionless, collateralTokenIsPermissionless, _value);
        collateralTokenIsPermissionless = _value;   
    } 

    function setOracleWhitelisted(IOracle _oracle, bool _value) public {
        isDefaultAdmin();                
        emit SetGlobalBool(_msgSender(),SetVariableType.OracleWhitelisted, oracleWhitelisted[_oracle], _value);
        oracleWhitelisted[_oracle] = _value;
    }  

    function setCollateralTokenWhitelisted(IERC20 _collateralToken, bool _value) public {
        isDefaultAdmin();        
        emit SetGlobalBool(_msgSender(),SetVariableType.CollateralTokenWhitelisted, collateralTokenWhitelisted[_collateralToken], _value);
        collateralTokenWhitelisted[_collateralToken] = _value;   
    }  

    function isDefaultAdmin() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "OptionsVaultFactory: must have admin role");
    }

    function getCollateralizationRatio(OptionsVaultERC20 _address) public view returns (uint256) {
        if (collateralizationRatio[_address]==0){
            return 10000;
        }
        else{
            collateralizationRatio[_address];
        }
    }

    function setCollateralizationRatioBulk(OptionsVaultERC20[] calldata _address, uint256[] calldata _ratio) public {
        require(_address.length == _ratio.length, "OptionsVaultFactory: lengths different");

        uint arrayLength = _address.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            setCollateralizationRatio(_address[i], _ratio[i]);
        }
    }


    function setCollateralizationRatio(OptionsVaultERC20 _address, uint256 _ratio) public {
        require(hasRole(COLLATERAL_RATIO_ROLE, _msgSender()), "OptionsVaultFactory: must have admin role");
        collateralizationRatio[_address] = _ratio;
    }
    
}

