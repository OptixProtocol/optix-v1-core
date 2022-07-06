pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "./OptionsVault.sol";
import "./Referrals.sol";

contract Options is ERC721, AccessControl, IStructs, IOptions, IProtocolFeeCalcs {
    using SafeERC20 for IERC20;
    
    Option[] public options;
    OptionsVault public optionsVault;
    Referrals public referrals;
    address public protocolFeeRecipient;
    IProtocolFeeCalcs public protocolFeeCalcs;
    
    uint public protocolFee = 100;  //1%
    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");
    uint public autoExercisePeriod = 30 minutes;
    


    constructor(
        address _protocolFeeRecipient,
        OptionsVault _optionsVault,
        Referrals _referrals,
        string memory name,
        string memory symbol
    ) ERC721(name, symbol)  {
        optionsVault = _optionsVault;
        referrals = _referrals;
        protocolFeeRecipient = _protocolFeeRecipient;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(CONTRACT_CALLER_ROLE, _msgSender());
    }
    
    
     function premium(
        address holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint vaultId,
        IOracle oracle,
        address referredBy
    )   public 
        view
        returns (
            Fees memory _premium 
        )
    {
        (Fees memory _fees) = fees(holder, period, optionSize, strike, optionType, vaultId, oracle, referredBy);
        _premium.protocolFee = _fees.protocolFee*optionSize/1e4;
        _premium.referFee = _fees.referFee*optionSize/1e4;
        _premium.intrinsicFee = _fees.intrinsicFee*optionSize/1e4;
        _premium.extrinsicFee = _fees.extrinsicFee*optionSize/1e4;
        _premium.vaultFee = _fees.vaultFee*optionSize/1e4;
        _premium.total = _premium.protocolFee + _premium.referFee + _premium.intrinsicFee + _premium.extrinsicFee + _premium.vaultFee;
    }
    
      function fees(
        address holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint vaultId,
        IOracle oracle,
        address referredBy
    )   public
        view
        returns (
            Fees memory _fees 
        )
    {
        IFeeCalcs feeCalcs = optionsVault.vaultFeeCalc(vaultId);
        IProtocolFeeCalcs protocolFeesCalcs = (address(protocolFeeCalcs)==address(0))? this : protocolFeeCalcs;
        require(!optionsVault.readOnly(vaultId), "Options: OptionVault is readonly");
        require(optionsVault.oracleWhitelisted(oracle), "Options: Oracle is not whitelisted");
        require(optionsVault.oracleEnabled(vaultId,oracle), "Options: Oracle is not enabled for this vault");
        require(optionsVault.vaultCollateralAvailable(vaultId)>=optionSize, "Options: Not enough available collateral");

        uint256 latestPrice = latestAnswer(oracle);        
        
        _fees.protocolFee = protocolFeesCalcs.getProtocolFee(holder, period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.referFee = protocolFeesCalcs.getReferFee(holder, period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.intrinsicFee = feeCalcs.getIntrinsicFee(holder, period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.extrinsicFee = feeCalcs.getExtrinsicFee(holder, period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.vaultFee = feeCalcs.getVaultFee(holder, period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.total = _fees.protocolFee + _fees.referFee + _fees.intrinsicFee + _fees.extrinsicFee + _fees.vaultFee;
    }
    
    function getProtocolFee(
        address holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        IStructs.OptionType optionType,
        uint vaultId,
        IOracle oracle)
    external view returns (uint256){
        return protocolFee;
    }

    function getReferFee(address holder,uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IStructs.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256){
        return referrals.referFee();
    }
    
     /**
     * @notice Creates a new option
     * @param period Option period in seconds 
     * @param optionSize Option size
     * @param strike Strike price of the option
     * @param optionType Call or Put option type
     * @return optionID Created option's ID
     */
    function create(
        address holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint256 vaultId,
        IOracle oracle,
        address referredBy
    )
        public        
        returns (uint optionID)
    {
        require(
            optionType == OptionType.Call || optionType == OptionType.Put,
            "Options: Wrong option type"
        );
        optionsVault.isVaultOracleActive(vaultId,oracle);

        (Fees memory _premium) = premium(holder, period, optionSize, strike, optionType, vaultId, oracle, referredBy);

        optionID = options.length;  
        address writeReferrer = referrals.captureReferral(holder, referredBy);      
        Option memory option = _createOption(holder,period,optionSize,strike,optionType,vaultId,oracle,_premium,writeReferrer); 

        //pay protocol, referer & vault owner
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, address(protocolFeeRecipient), _premium.protocolFee);
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, address(writeReferrer), _premium.referFee);
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, optionsVault.vaultOwner(vaultId), _premium.vaultFee);

        uint remain = _premium.intrinsicFee+_premium.extrinsicFee;
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, address(this), remain);
        IERC20(optionsVault.collateralToken(vaultId)).approve(address(optionsVault), remain);
        optionsVault.provideAndMint(address(this), vaultId, remain,false);
        optionsVault.lock(optionID, option.lockedAmount, _premium, vaultId, optionType);
        
        options.push(option);
        _safeMint(holder, optionID);
        
        emit CreateOption(optionID, holder, option.expiration, optionSize, strike, optionType, vaultId, oracle, _premium.protocolFee, _premium.vaultFee, _premium.total, writeReferrer);
    }
    
    function _createOption(
        address holder, 
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint256 vaultId, 
        IOracle oracle, 
        Fees memory _premium, 
        address referrer) 
    internal view 
    returns (Option memory option){
        option = Option(
           State.Active,
            holder,
            strike,
            optionSize,
            optionSize, //*optionsVault.collateralizationRatio(vaultId)/10000,
            _premium.total,
            block.timestamp + period,
            optionType,
            vaultId,
            oracle,
            referrer
        );
    }
      
    //Negative prices aren't supported and are all treated as 0
    function latestAnswer(IOracle oracle) public view returns (uint256){
        if(oracle.latestAnswer() <= 0)
            return 0;
        else    
            return uint256(oracle.latestAnswer());
    }
    
    /**
     * @notice Exercises an active option
     * @param optionID ID of your option
     */
    function exercise(uint256 optionID) external {
        Option storage option = options[optionID];

        require(option.expiration >= block.timestamp, "Options: Option has expired");
        require(option.state == State.Active, "Options: Wrong state");

        //only holder or approved can excercise within the auto exercise period
        if(block.timestamp < option.expiration-autoExercisePeriod){
            require((option.holder == msg.sender)||isApprovedForAll(option.holder,msg.sender), "Options: Not sender or approved");
        }

        option.state = State.Exercised;

        uint256 profit;
        uint256 currentPrice = latestAnswer(option.oracle);

        if (option.optionType == OptionType.Call) {
            require(option.strike <= currentPrice, "Options: Current price is too low");
            profit = (currentPrice-option.strike)*(option.optionSize)/(option.strike);
        } else if (option.optionType == OptionType.Put) {
            require(option.strike >= currentPrice, "Options: Current price is too high");
            profit = (option.strike-currentPrice)*(option.optionSize)/(option.strike);
        }

        if (profit > option.optionSize)
            profit = option.optionSize;

        optionsVault.send(optionID, option.holder, profit);

        emit Exercise(optionID, option.vaultId, profit);
    }
 
    /**
     * @notice Transfers an active option
     * @param optionID ID of your option
     * @param newHolder Address of new option holder
     */
    function transfer(uint256 optionID, address newHolder) external {
        Option storage option = options[optionID];

        require(newHolder != address(0), "Options: New holder address is zero");
        require(option.expiration >= block.timestamp, "Options: Option has expired");
        require(option.holder == msg.sender, "Options: Wrong msg.sender");
        require(option.state == State.Active, "Options: Only active option could be transferred");

        address oldHolder = option.holder;
        option.holder = newHolder;
        emit TransferOption(optionID, oldHolder, newHolder);
    }

     /**
     * @notice Unlock funds locked in the expired options
     * @param optionID ID of the option
     */
      function unlock(uint256 optionID) public {
        Option storage option = options[optionID];
        require(option.state == State.Active, "Options: Option is not active");
        require(option.expiration < block.timestamp, "Options: Option has not expired yet");
        option.state = State.Expired;
        optionsVault.unlock(optionID);
        emit Expire(optionID, option.vaultId, option.premium);
      }

     /**
     * @notice Unlocks an array of options
     * @param optionIDs array of options
     */
      function unlockAll(uint256[] calldata optionIDs) public {
        uint arrayLength = optionIDs.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            unlock(optionIDs[i]);
        }
      }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    modifier IsDefaultAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Options: must have admin role");
        _;
    }

   function setProtocolFee(uint value) external IsDefaultAdmin {
        require(value<=500,"value<=500");
        
        protocolFee = value;
        //emit UpdateProtocolFee(value);
    }  


    function setProtocolFeeRecipient(address value) external IsDefaultAdmin  {
        protocolFeeRecipient = value;
    }

    function setProtocolFeeCalc(IProtocolFeeCalcs value) external IsDefaultAdmin {
        emit SetGlobalAddress(_msgSender(),SetVariableType.ProtocolFeeCalc, address(protocolFeeCalcs), address(value));
        protocolFeeCalcs = value;
        //emit UpdateProtocolFee(value);
    }  

    function setReferrals(Referrals value) external IsDefaultAdmin  {
        emit SetGlobalAddress(_msgSender(),SetVariableType.Referrals, address(referrals), address(value));
        referrals = value;
    }
}