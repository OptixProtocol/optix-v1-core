pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "./interfaces/Interfaces.sol";
import "hardhat/console.sol";

contract Referrals is AccessControl {
   //referral    
    uint public referFee = 50;  //.5%
    address public referralFeeRecipient;
    uint public referralPeriod = 26 weeks;  //6 months
    mapping(address => address) public referredBy;
    mapping(address => uint256) public referredDate;
    mapping(address => uint256) public referrerId;
    address[] public referrers;

    mapping(address => bool) public blacklisted;

    bytes32 public constant CONTRACT_CALLER_ROLE = keccak256("CONTRACT_CALLER_ROLE");
    
    constructor(address _referralFeeRecipient) {  
        require(_referralFeeRecipient!=address(0), "Referrals: referralFeeRecipient can't be null"); 
        referralFeeRecipient = _referralFeeRecipient;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());     
        _setupRole(CONTRACT_CALLER_ROLE, _msgSender());
    }

    // Always pay current tx to referred by if passed in, regardless of whether there is one on record
    // If there is none passed in then check if there is valid one on record and use that
    // If there is no valid one on record then capture a new referral record
    // Store in an array so there can be a number that links the referrer's address for nice urls
    function captureReferral(address holder, address referredByIn) public returns (address referredByOut) {
        require(hasRole(CONTRACT_CALLER_ROLE, _msgSender()), "Referrals: must have contract caller role");

        if(blacklisted[referredByIn]){
            //clear the referrer if its blacklisted
            if (referredBy[holder] == referredByIn){
                referredBy[holder] = address(0);
                referredDate[holder] = block.timestamp; 
            }  
            referredByIn = address(0);
        }

        if(referredByIn == address(0) || referredByIn == holder){
            //no referredBy passed in or same as holder
            if((referredBy[holder]!=address(0)) && (referredDate[holder] + referralPeriod>=block.timestamp)){
                //valid referred by on record, so use that
                referredByOut = referredBy[holder];            
            }
            else{

                //on record referred by either expired or null so use the protocol recipient                
                referredByOut = referralFeeRecipient;  
            }
        }
        else{
            //use the referred by passed in
            referredByOut = referredByIn;
        }

        if((referredBy[holder]==address(0)) || (referredDate[holder] + referralPeriod<=block.timestamp)){
            // its null or expired so 
            referredBy[holder] = referredByOut;
            referredDate[holder] = block.timestamp;            
        }

        if(referrerId[referredByOut]==0){
            // id for a friendly url
            referrerId[referredByOut] = referrers.length;
            referrers.push(referredByOut);
        }
        require(referredByOut!=address(0), "Referrals: can't be null");
    }

    modifier IsDefaultAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Referrals: must have admin role");
        _;
    }

    function setReferralFeeRecipient(address value) external IsDefaultAdmin  {
        referralFeeRecipient = value;
    }

    function setBlacklisted(address value, bool isBlacklisted) public IsDefaultAdmin  {
        blacklisted[value] = isBlacklisted;
    }   

    function setBlacklistedAll(address[] calldata addresses, bool isBlacklisted) external IsDefaultAdmin  {
        uint arrayLength = addresses.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            setBlacklisted(addresses[i],isBlacklisted);
        }
    }    
}