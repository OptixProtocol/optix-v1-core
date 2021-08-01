pragma solidity 0.8.6;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "./OptionsLP.sol";

contract Options is ERC721, AccessControl, IFeeCalcs, IOptions {
    using SafeERC20 for IERC20;
    
    Option[] public options;
    OptionsLP optionsLP;
    address public protocolFeeRecipient;
    // IFeeCalcs public feeCalcs;
    
    uint public protocolFee = 100;  //1%
    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");
    
    string public commitHash;
    
    constructor(
        address _protocolFeeRecipient,
        OptionsLP _optionsLP,
        string memory name,
        string memory symbol,
        string memory _commitHash 
    ) ERC721(name, symbol)  {
        optionsLP = _optionsLP;
        protocolFeeRecipient = _protocolFeeRecipient;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(CONTRACT_CALLER_ROLE, _msgSender());
        commitHash = _commitHash;        
    }
    
    
     function premium(
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint poolId,
        IOracle oracle
    )   public 
        view
        returns (
            Fees memory _premium 
        )
    {
        (Fees memory _fees) = fees(period, optionSize, strike, optionType, poolId, oracle);
        _premium.protocolFee = _fees.protocolFee*optionSize/10000;
        _premium.strikeFee = _fees.strikeFee*optionSize/10000;
        _premium.periodFee = _fees.periodFee*optionSize/10000;
        _premium.balanceUtilisationFee = _fees.balanceUtilisationFee*optionSize/10000;
        _premium.poolFee = _fees.poolFee*optionSize/10000;
        _premium.total = _premium.protocolFee + _premium.strikeFee + _premium.periodFee + _premium.balanceUtilisationFee + _premium.poolFee;
    }
    
      function fees(
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint poolId,
        IOracle oracle
    )   public
        view
        returns (
            Fees memory _fees 
        )
    {
        IFeeCalcs feeCalcs = (address(optionsLP.poolFeeCalc(poolId))==address(0))? this : optionsLP.poolFeeCalc(poolId);
        uint256 latestPrice = optionsLP.oracle(poolId).latestAnswer();
        _fees.protocolFee = feeCalcs.getProtocolFee(period, optionSize, strike, latestPrice, optionType, poolId, oracle);
        _fees.strikeFee = feeCalcs.getStrikeFee(period, optionSize, strike, latestPrice, optionType, poolId, oracle);
        _fees.periodFee = feeCalcs.getPeriodFee(period, optionSize, strike, latestPrice, optionType, poolId, oracle);
        _fees.balanceUtilisationFee = feeCalcs.getBalanceUtilisationFee(period, optionSize, strike, latestPrice, optionType, poolId, oracle);
        _fees.poolFee = feeCalcs.getPoolFee(period, optionSize, strike, latestPrice, optionType, poolId, oracle);
        _fees.total = _fees.protocolFee + _fees.strikeFee + _fees.periodFee + _fees.balanceUtilisationFee + _fees.poolFee;
    }

    
    
     function getProtocolFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint poolId,
        IOracle oracle)
        override
        external
        view
        returns (uint256)
    {
        return protocolFee;
    }


    function getStrikeFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint poolId,
        IOracle oracle
    )
        override
        external
        pure
        returns (uint256)
    {
      if (strike > currentPrice && optionType == OptionType.Put)
            return (strike-currentPrice)*1e4/currentPrice;
        if (strike < currentPrice && optionType == OptionType.Call)
            return (currentPrice-strike)*1e4/currentPrice;
        return 0;        
    }


    function getPeriodFee(
        uint256 period,
        uint256 optionSize,
        uint256 strike, 
        uint256 currentPrice,
        OptionType optionType,
        uint poolId,
        IOracle oracle
    ) override external view returns (uint256) {
        if (optionType == OptionType.Put)
            return uint256(2)*sqrt(period)*strike/currentPrice/uint256(4);
        else
            return uint256(2)*sqrt(period)*currentPrice/strike/uint256(4);
    }

    function getBalanceUtilisationFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint poolId,
        IOracle oracle
    )
        override
        external
        view
        returns (uint256)
    {
        //(utilisation^2/4) * (put or call^2/4) / 62500000000
        if( optionType == OptionType.Call ){ 
            return (optionsLP.poolUtilisation(poolId)*optionsLP.poolUtilisation(poolId)/4) * (optionsLP.callRatio(poolId)*optionsLP.callRatio(poolId)/4) / 62500000000;
        }
        if( optionType == OptionType.Put ){ 
            return (optionsLP.poolUtilisation(poolId)*optionsLP.poolUtilisation(poolId)/4) * (optionsLP.putRatio(poolId)*optionsLP.putRatio(poolId)/4) / 62500000000; 
        }         
    }


    function getPoolFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint poolId,
        IOracle oracle)         
        override
        external
        view
        returns (uint256)
    {
        return optionsLP.poolFee(poolId);
    }
    
    
     /**
     * @notice Creates a new option
     * @param period Option period in seconds (1 days <= period <= 4 weeks)
     * @param optionSize Option size
     * @param strike Strike price of the option
     * @param optionType Call or Put option type
     * @return optionID Created option's ID
     */
    function create(
        address payable holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint256 poolId,
        IOracle oracle
    )
        public        
        returns (uint256 optionID)
    {
        require(
            optionType == OptionType.Call || optionType == OptionType.Put,
            "Options: Wrong option type"
        );
        require(period >= optionsLP.periodMin(poolId), "Options: Period is too short");
        require(period <= optionsLP.periodMax(poolId), "Options: Period is too long");
        (Fees memory _premium) = premium(period, optionSize, strike, optionType, poolId, oracle);
        
        optionID = options.length;        
        Option memory option = _createOption(holder,period,optionSize,strike,optionType,poolId,oracle,_premium); 

        optionsLP.collateralToken(poolId).transferFrom(holder, address(protocolFeeRecipient), _premium.protocolFee);
        optionsLP.collateralToken(poolId).transferFrom(holder, optionsLP.poolOwner(poolId), _premium.poolFee);
        optionsLP.collateralToken(poolId).transferFrom(holder, address(optionsLP),  _premium.total-_premium.protocolFee-_premium.poolFee);

        optionsLP.lock(optionID, option.lockedAmount, _premium, poolId, optionType);
        
        options.push(option);
        _safeMint(holder, optionID);
        
        emit CreateOption(optionID, holder, period, optionSize, strike, optionType, poolId, oracle, _premium.protocolFee, _premium.poolFee, _premium.total);
    }
    
      function _createOption(address payable holder, 
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        OptionType optionType,
        uint256 poolId, IOracle oracle, Fees memory _premium) internal view returns (Option memory option){

        // uint256 strikeAmount = optionSize;
        // uint optPremium = (_premium.total.sub(_premium.protocolFee));
        option = Option(
           State.Active,
            holder,
            strike,
            optionSize,
            optionSize*10000/(optionsLP.collateralizationRatio(poolId)),
            _premium.total,
            block.timestamp + period,
            optionType,
            poolId,
            oracle
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
        require((option.holder == msg.sender)||isApprovedForAll(option.holder,msg.sender), "Options: Not sender or approved");
        require(option.state == State.Active, "Options: Wrong state");

        option.state = State.Exercised;
        uint256 profit = payProfit(optionID);

        emit Exercise(optionID, option.poolId, profit);
    }


    /**
     * @notice Sends profits in erc20 tokens from the token pool to an option holder's address
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
        if (profit > option.lockedAmount)
            profit = option.lockedAmount;
        optionsLP.send(optionID, option.holder, profit);
    }

    
      /**
     * @notice Transfers an active option
     * @param optionID ID of your option
     * @param newHolder Address of new option holder
     */
    function transfer(uint256 optionID, address payable newHolder) external {
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
        require(option.expiration < block.timestamp, "Options: Option has not expired yet");
        require(option.state == State.Active, "Options: Option is not active");
        option.state = State.Expired;
        optionsLP.unlock(optionID);
        // emit Expire(optionID, option.marketId, option.premium);
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
}


