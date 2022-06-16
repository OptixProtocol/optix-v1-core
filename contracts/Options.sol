pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "./OptionsVault.sol";
import "./Referrals.sol";


contract Options is ERC721, AccessControl, IFeeCalcs, IOptions {
    using SafeERC20 for IERC20;
    
    Option[] public options;
    OptionsVault public optionsVault;
    Referrals public referrals;
    address public protocolFeeRecipient;
    
    uint public protocolFee = 50;  //.5%
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
        (Fees memory _fees) = fees(period, optionSize, strike, optionType, vaultId, oracle, referredBy);
        _premium.protocolFee = _fees.protocolFee*optionSize/10000;
        _premium.referFee = _fees.referFee*optionSize/10000;
        _premium.strikeFee = _fees.strikeFee*optionSize/10000;
        _premium.periodFee = _fees.periodFee*optionSize/10000;
        _premium.demandFee = _fees.demandFee*optionSize/10000;
        _premium.vaultFee = _fees.vaultFee*optionSize/10000;
        _premium.total = _premium.protocolFee + _premium.referFee + _premium.strikeFee + _premium.periodFee + _premium.demandFee + _premium.vaultFee;
    }
    
      function fees(
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
        IFeeCalcs feeCalcs = (address(optionsVault.vaultFeeCalc(vaultId))==address(0))? this : optionsVault.vaultFeeCalc(vaultId);
        uint256 latestPrice = latestAnswer(oracle);
        _fees.protocolFee = protocolFee;
        _fees.referFee = referrals.referFee();
        _fees.strikeFee = feeCalcs.getStrikeFee(period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.periodFee = feeCalcs.getPeriodFee(period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.demandFee = feeCalcs.getDemandFee(period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.vaultFee = feeCalcs.getVaultFee(period, optionSize, strike, latestPrice, optionType, vaultId, oracle);
        _fees.total = _fees.protocolFee + _fees.referFee + _fees.strikeFee + _fees.periodFee + _fees.demandFee + _fees.vaultFee;
    }

    
 


    function getStrikeFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint vaultId,
        IOracle oracle
    )
        override
        external
        pure
        returns (uint256)
    {
      return 100;       
    }


    function getPeriodFee(
        uint256 period,
        uint256 optionSize,
        uint256 strike, 
        uint256 currentPrice,
        OptionType optionType,
        uint vaultId,
        IOracle oracle
    ) override external view returns (uint256) {
       return 100;
    }

    function getDemandFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint vaultId,
        IOracle oracle
    )
        override
        external
        view
        returns (uint256)
    {
        return 100;        
    }


    function getVaultFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint vaultId,
        IOracle oracle)         
        override
        external
        view
        returns (uint256)
    {
        return 100;
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
        (Fees memory _premium) = premium(period, optionSize, strike, optionType, vaultId, oracle, referredBy);
        

        optionID = options.length;  
        address writeReferrer = referrals.captureReferral(holder, referredBy);      
        Option memory option = _createOption(holder,period,optionSize,strike,optionType,vaultId,oracle,_premium,writeReferrer); 

        //pay protocol, referer & vault owner
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, address(protocolFeeRecipient), _premium.protocolFee);
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, address(writeReferrer), _premium.referFee);
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, optionsVault.vaultOwner(vaultId), _premium.vaultFee);


        uint remain = _premium.total-_premium.protocolFee-_premium.vaultFee-_premium.referFee;
        optionsVault.collateralToken(vaultId).safeTransferFrom(holder, address(this), remain);
        IERC20(optionsVault.collateralToken(vaultId)).approve(address(optionsVault), remain);
        optionsVault.addToVault(address(this), vaultId, remain);
        optionsVault.lock(optionID, option.lockedAmount, _premium, vaultId, optionType);
        
        options.push(option);
        _safeMint(holder, optionID);
        
        emit CreateOption(optionID, holder, option.expiration, optionSize, strike, optionType, vaultId, oracle, _premium.protocolFee, _premium.vaultFee, _premium.total, writeReferrer);
    }
    


      function _createOption(address holder, 
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint256 vaultId, IOracle oracle, Fees memory _premium, address referrer) internal view returns (Option memory option){

        // uint256 strikeAmount = optionSize;
        // uint optPremium = (_premium.total.sub(_premium.protocolFee));
       
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
        uint256 profit = payProfit(optionID);

        emit Exercise(optionID, option.vaultId, profit);
    }


    /**
     * @notice Sends profits in erc20 tokens from the token vault to an option holder's address
     * @param optionID A specific option contract id
     */
    function payProfit(uint optionID)
        internal
        returns (uint profit)
    {
        Option memory option = options[optionID];
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

        option.holder = newHolder;
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


      function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // this block is equivalent to r = uint256(1) << (BitMath.mostSignificantBit(x) / 2);
        // however that code costs significantly more gas
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
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



    function setReferrals(Referrals value) external IsDefaultAdmin  {
        referrals = value;
    }


}


