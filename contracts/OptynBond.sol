pragma solidity 0.8.6;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */

// Rinkeby
//  payOutToken MATIC(Fake) = 0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797
//  payInToken USDC(Fake) = 0xDF171B622CEF319fbe31358A817e85bE3642e990
//  payInToken WETH(Fake) = 0x58194288A4B15008F800dB474ACcAb134879b577
//  payInToken WBTC(Fake) = 0xe35C17Fe56F2F9052476588B635519184f740Fe3

// USDC, 1000 MATIC
// NewIssuance 1: "0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","1000000000000000000000"

// WETH, 1000 MATIC
// NewIssuance 2: "0x58194288A4B15008F800dB474ACcAb134879b577","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","1000000000000000000000"

// WBTC, 1000 MATIC
// NewIssuance 3: "0xe35C17Fe56F2F9052476588B635519184f740Fe3","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","1000000000000000000000"


// Buy bond
// "0","1000000000000000000000","1000000000000000000000000000","0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b"

// bondIssuance
// "0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","0"

import "./interfaces/Interfaces.sol";




contract OptynBond  {
    using SafeERC20 for IERC20;

    /* ======== EVENTS ======== */
    event IssuanceCreated( IERC20 payOutToken, IERC20 payInToken, uint _amount, uint issuanceId );
    event BondCreated( address despsitor, uint deposit, uint payout, uint expires, uint bondId );
    event BondRedeemed( uint bondId, uint payout, uint remaining );
    // event BondPriceChanged( uint internalPrice, uint debtRatio );
    event ControlVariableAdjustment( uint initialBCV, uint newBCV, uint adjustment, bool addition );
    
     /* ======== STATE VARIABLES ======== */
    Bond[] public bonds; // stores bond information for depositors
    Issuance[] public issuances; 


    /* ======== STRUCTS ======== */

    struct Issuance {
        IERC20 payOutToken;
        IERC20 payInToken;        
        address owner;
        address treasury;
        uint payOutTokenAvailable; //how much can be issued
        uint payOutTokenBonded; //how much as been bonded
        uint vestingTerm; // in blocks
        uint minimumPrice; // vs payIn value
        uint startingPrice;
        uint startAt;
        uint expiresAt;
        uint priceDeductionRate;
    }

    // // Info for bond holder
    struct Bond {
        uint issuanceId; //issuance params for this bond
        uint payout; // payout token remaining to be paid
        uint vesting; // Blocks left to vest
        uint lastBlock; // Last interaction
        uint truePricePaid; // Price paid (payIn tokens per payOut token) in ten-millionths - 4000000 = 0.4
        address depositor; //
    }


    constructor(){
 
    }

    function newIssuance(IERC20 payInToken, IERC20 payOutToken, uint _payOutTokenAvailable) public {
        require( _payOutTokenAvailable <= payOutToken.balanceOf(msg.sender), "Not enough balance" );

      Issuance memory issuance = Issuance(
          payOutToken,
          payInToken,
          msg.sender,                   //owner
          msg.sender,                   //treasury
          _payOutTokenAvailable,
          0,                            //payoutTokenBonded
          5 days,                       //vestingTerm
          100000,                       //mimiumPrice
          200000,                       //startingPrice
          block.timestamp,              //startsAt
          block.timestamp + 30 days,    //expiresAt
          50                            //priceDeductionRate
        );
        issuances.push(issuance);

        emit IssuanceCreated( payOutToken, payInToken, _payOutTokenAvailable, issuances.length);
    }

    function buyBond(uint issuanceId, uint payInAmount, uint _maxPrice, address _depositor) external returns (uint) {
        require( payInAmount <= issuances[issuanceId].payInToken.balanceOf(issuances[issuanceId].treasury), "Not enough treasury balance" );
        require( payInAmount <= issuances[issuanceId].payOutTokenAvailable-issuances[issuanceId].payOutTokenBonded, "Not enough issuance balance" );

        // depositor info is stored
        uint payout = payoutFor( issuanceId, payInAmount ); // payout to bonder is computed

        uint fee = 0;

        // transfer the payin & payout to the contract 
        issuances[issuanceId].payInToken.safeTransferFrom( _depositor, address(this), payInAmount );
        issuances[issuanceId].payOutToken.safeTransferFrom( issuances[issuanceId].treasury, address(this), payout );


        // // depositor info is stored
        Bond memory bond =  Bond({ 
            issuanceId: issuanceId,
            payout: payout,
            vesting: issuances[issuanceId].vestingTerm,
            lastBlock: block.number,
            truePricePaid: bondPrice(issuanceId),
            depositor: _depositor
        });
        bonds.push(bond);

        emit BondCreated( _depositor, payInAmount, payout, block.number + issuances[issuanceId].vestingTerm, bonds.length-1 );
        issuances[issuanceId].payOutTokenBonded = issuances[issuanceId].payOutTokenBonded + payInAmount; // total bonded increased

        return payout;
    }

    function redeemBond(uint bondId) external returns (uint) {
         Bond memory bond = bonds[ bondId ]; 
        uint percentVested = percentVestedFor( bondId ); // (blocks since last interaction / vesting term remaining)

        if ( percentVested >= 10000 ) { // if fully vested
            delete bonds[ bondId ]; // delete bond info
            emit BondRedeemed( bondId, bond.payout, 0 ); // emit bond data
            issuances[bonds[ bondId ].issuanceId].payOutToken.transfer( bonds[ bondId ].depositor, bond.payout );
            return bond.payout;

        } else { // if unfinished
            // calculate payout vested
            uint payout = bond.payout * ( percentVested ) / ( 10000 );

            // store updated deposit info
            bonds[ bondId ] = Bond({
                issuanceId: bonds[ bondId ].issuanceId,
                payout: bond.payout - ( payout ),
                vesting: bond.vesting - ( block.number - ( bond.lastBlock ) ),
                lastBlock: block.number,
                truePricePaid: bond.truePricePaid,
                depositor: bonds[ bondId ].depositor
            });

            emit BondRedeemed( bondId, payout, bonds[ bondId ].payout );
            issuances[bonds[ bondId ].issuanceId].payOutToken.transfer( bonds[ bondId ].depositor, payout );
            return payout;
        }
        

    }

    /* ======== POLICY FUNCTIONS ======== */

    enum PARAMETER { VESTING, AVAILABLE, STARTING_PRICE, MINIMUM_PRICE }
    /**
     *  @notice set parameters for new bonds
     *  @param _parameter PARAMETER
     *  @param _input uint
     */
    function setBondTerms ( uint _issuanceId, PARAMETER _parameter, uint _input ) external {

        if ( _parameter == PARAMETER.VESTING ) { // 0
            // require( _input >= 10000, "Vesting must be longer than 36 hours" );
            issuances[_issuanceId].vestingTerm = _input;
        }
        if ( _parameter == PARAMETER.AVAILABLE ) { // 1
            require( _input <= issuances[_issuanceId].payOutToken.balanceOf(msg.sender), "Not enough balance" );
            issuances[_issuanceId].payOutTokenAvailable = _input;
        }
        if ( _parameter == PARAMETER.STARTING_PRICE ) { // 2
            issuances[_issuanceId].startingPrice = _input;
        }
        if ( _parameter == PARAMETER.MINIMUM_PRICE ) { // 3
            issuances[_issuanceId].minimumPrice = _input;
        }        
    }

     /* ======== VIEW FUNCTIONS ======== */

    /**
     *  @notice calculate current bond premium
     *  @return price_ uint
     */
    function bondPrice(uint issuanceId) public view returns ( uint price_ ) {   
         
        uint timeElapsed = block.timestamp - issuances[issuanceId].startAt;    
        uint deduction = issuances[issuanceId].priceDeductionRate * timeElapsed;
        price_ = issuances[issuanceId].startingPrice - deduction;
        if ( price_ < issuances[issuanceId].minimumPrice ) {
            price_ = issuances[issuanceId].minimumPrice;
        }
    }

     /**
     *  @notice calculate how far into vesting a depositor is
     *  @param bondId uint
     *  @return percentVested_ uint
     */
    function percentVestedFor( uint bondId ) public view returns ( uint percentVested_ ) {
        Bond memory bond = bonds[ bondId ];
        uint blocksSinceLast = block.number - ( bond.lastBlock );
        uint vesting = bond.vesting;

        if ( vesting > 0 ) {
            percentVested_ = blocksSinceLast * ( 10000 ) / ( vesting );
        } else {
            percentVested_ = 0;
        }
    }

    function payoutFor( uint issuanceId, uint payInAmount ) public view returns ( uint ) {
        return bondPrice(issuanceId)/payInAmount;
    }
}