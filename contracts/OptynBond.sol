pragma solidity 0.8.6;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */

// Rinkeby
//  payoutToken USDC(Fake) = 0xDF171B622CEF319fbe31358A817e85bE3642e990
//  principalToken MATIC(Fake) = 0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797

//  1000 MATIC
// NewIssuance: "0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","1000000000000000000000"

// Buy bond
// "0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","0","1000000000000000000000","1000000000000000000000000000","0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b"

// bondIssuance
// "0xDF171B622CEF319fbe31358A817e85bE3642e990","0xCA6759a88Ee3498aD2354261DCf8A0eEe7Aee797","0"

import "./interfaces/Interfaces.sol";




contract OptynBond  {
    using SafeERC20 for IERC20;

    /* ======== EVENTS ======== */
    event IssuanceCreated( IERC20 payoutToken, IERC20 principalToken, uint _amount, uint issuanceId );
    event BondCreated( address despsitor, uint deposit, uint payout, uint expires, uint bondId );
    event BondRedeemed( uint bondId, uint payout, uint remaining );
    event BondPriceChanged( uint internalPrice, uint debtRatio );
    event ControlVariableAdjustment( uint initialBCV, uint newBCV, uint adjustment, bool addition );
    
     /* ======== STATE VARIABLES ======== */
    Bond[] public bonds; // stores bond information for depositors
    Issuance[] public issuances; 


    /* ======== STRUCTS ======== */

    struct Issuance {
        IERC20 payoutToken;
        IERC20 principalToken;        
        address owner;
        address treasury;
        uint principalAvailable; //how much can be issued
        uint principalBonded; //how much as been bonded
        uint vestingTerm; // in blocks
        uint minimumPrice; // vs principal value
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
        uint truePricePaid; // Price paid (principal tokens per payout token) in ten-millionths - 4000000 = 0.4
        address depositor; //
    }


    constructor(){
 
    }

    function newIssuance(IERC20 payoutToken, IERC20 principalToken, uint _principalAvailable) public {
        require( _principalAvailable <= principalToken.balanceOf(msg.sender), "Not enough balance" );

        Issuance storage issuance = issuances[issuances.length];
        issuance.payoutToken = payoutToken;
        issuance.principalToken = principalToken;
        issuance.owner = msg.sender;
        issuance.treasury = msg.sender;
        issuance.principalAvailable = _principalAvailable;
        issuance.vestingTerm = 5 days;
        issuance.startingPrice = 100000;
        issuance.startAt = block.timestamp;
        issuance.expiresAt = block.timestamp + 7 days;
        issuance.priceDeductionRate = 50;      

        emit IssuanceCreated( payoutToken, principalToken, _principalAvailable, issuances.length);
    }

    function buyBond(IERC20 payoutToken, IERC20 principalToken, uint issuanceId, uint _principalAmount, uint _maxPrice, address _depositor) external returns (uint) {
        require( _principalAmount <= principalToken.balanceOf(issuances[issuanceId].treasury), "Not enough treasury balance" );
        require( _principalAmount <= issuances[issuanceId].principalAvailable-issuances[issuanceId].principalBonded, "Not enough issuance balance" );

        // depositor info is stored
        uint payout = _payoutFor( issuanceId, _principalAmount ); // payout to bonder is computed

        uint fee = 0;

        // transfer the principal & payout to the contract 
        principalToken.safeTransferFrom( msg.sender, address(this), _principalAmount );
        payoutToken.safeTransferFrom( issuances[issuanceId].treasury, address(this), payout );


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

        emit BondCreated( _depositor, _principalAmount, payout, block.number + issuances[issuanceId].vestingTerm, bonds.length-1 );
        issuances[issuanceId].principalBonded = issuances[issuanceId].principalBonded + _principalAmount; // total bonded increased

        return payout;
    }

    function redeemBond(uint bondId) external returns (uint) {
         Bond memory bond = bonds[ bondId ]; 
        uint percentVested = percentVestedFor( bondId ); // (blocks since last interaction / vesting term remaining)

        if ( percentVested >= 10000 ) { // if fully vested
            delete bonds[ bondId ]; // delete bond info
            emit BondRedeemed( bondId, bond.payout, 0 ); // emit bond data
            issuances[bonds[ bondId ].issuanceId].payoutToken.transfer( bonds[ bondId ].depositor, bond.payout );
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
            issuances[bonds[ bondId ].issuanceId].payoutToken.transfer( bonds[ bondId ].depositor, payout );
            return payout;
        }
        

    }

    /* ======== POLICY FUNCTIONS ======== */

    enum PARAMETER { VESTING, PAYOUT, DEBT }
    /**
     *  @notice set parameters for new bonds
     *  @param _parameter PARAMETER
     *  @param _input uint
     */
    // function setBondTerms ( PARAMETER _parameter, uint _input ) external onlyPolicy() {
    //     if ( _parameter == PARAMETER.VESTING ) { // 0
    //         require( _input >= 10000, "Vesting must be longer than 36 hours" );
    //         terms.vestingTerm = _input;
    //     };
    // }

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

    function _payoutFor( uint issuanceId, uint _principalAmount ) internal view returns ( uint ) {
        return bondPrice(issuanceId)/_principalAmount;
    }
}