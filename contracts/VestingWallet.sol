// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

// 0:uint256: startTimeInSec 1648003734
// 1:uint256: cliffTimeInSec 1648003734
// 2:uint256: endTimeInSec 2648003704
// 3:uint256: totalAmount 1000000000000
// 4:uint256: totalAmountWithdrawn 0
// 5:address: depositor 0xD445D873D0EDc0cD35ff4F61b334df8b7B822b1b
// 6:bool: isConfirmed false

contract VestingWallet is Ownable {

    uint _blockTimestamp;

    mapping(address => VestingSchedule) public schedules;        // vesting schedules for given addresses
    mapping(address => address) public addressChangeRequests;    // requested address changes

    IERC20 vestingToken;

    event VestingScheduleRegistered(
        address indexed registeredAddress,
        address depositor,
        uint startTimeInSec,
        uint cliffTimeInSec,
        uint endTimeInSec,
        uint unlockAmount, 
        uint totalAmount
    );
    event VestingScheduleConfirmed(
        address indexed registeredAddress,
        address depositor,
        uint startTimeInSec,
        uint cliffTimeInSec,
        uint endTimeInSec,
        uint unlockAmount,
        uint totalAmount
    );
    event Withdrawal(address indexed registeredAddress, uint amountWithdrawn);
    event VestingEndedByOwner(address indexed registeredAddress, uint amountWithdrawn, uint amountRefunded);
    event AddressChangeRequested(address indexed oldRegisteredAddress, address indexed newRegisteredAddress);
    event AddressChangeConfirmed(address indexed oldRegisteredAddress, address indexed newRegisteredAddress);

    struct VestingSchedule {
        uint startTimeInSec;
        uint cliffTimeInSec;
        uint endTimeInSec;
        uint unlockAmount;
        uint totalAmount;
        uint totalAmountWithdrawn;
        address depositor;
        bool isConfirmed;
    }

    modifier addressRegistered(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(vestingSchedule.depositor != address(0),"vestingSchedule.depositor != address(0)");
        _;
    }

    modifier addressNotRegistered(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(vestingSchedule.depositor == address(0),"vestingSchedule.depositor == address(0)");
        _;
    }

    modifier vestingScheduleConfirmed(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(vestingSchedule.isConfirmed,"vestingSchedule.isConfirmed");
        _;
    }

    modifier vestingScheduleNotConfirmed(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(!vestingSchedule.isConfirmed,"!vestingSchedule.isConfirmed");
        _;
    }

    modifier pendingAddressChangeRequest(address target) {
        require(addressChangeRequests[target] != address(0),"addressChangeRequests[target] != address(0)");
        _;
    }

    modifier pastCliffTime(address target) {
        VestingSchedule storage vestingSchedule = schedules[target];
        require(blockTimestamp() > vestingSchedule.cliffTimeInSec,"blockTimestamp() > vestingSchedule.cliffTimeInSec");
        _;
    }

    modifier validVestingScheduleTimes(uint startTimeInSec, uint cliffTimeInSec, uint endTimeInSec) {
        require(cliffTimeInSec >= startTimeInSec,"cliffTimeInSec >= startTimeInSec");
        require(endTimeInSec >= cliffTimeInSec,"endTimeInSec >= cliffTimeInSec");
        _;
    }

    modifier addressNotNull(address target) {
        require(target != address(0),"target != address(0)");
        _;
    }

    /// @dev Assigns a vesting token to the wallet.
    /// @param _vestingToken Token that will be vested.
    constructor (address _vestingToken) {
        vestingToken = IERC20(_vestingToken);
    }




    /// @dev Registers a vesting schedule to an address.
    /// @param _addressToRegister The address that is allowed to withdraw vested tokens for this schedule.
    /// @param _depositor Address that will be depositing vesting token.
    /// @param _startTimeInSec The time in seconds that vesting began.
    /// @param _cliffTimeInSec The time in seconds that tokens become withdrawable.
    /// @param _endTimeInSec The time in seconds that vesting ends.
    /// @param _unlockAmount The amount of tokens initially released 
    /// @param _totalAmount The total amount of tokens that the registered address can withdraw by the end of the vesting period.
    function registerVestingSchedule(
        address _addressToRegister,
        address _depositor,
        uint _startTimeInSec,
        uint _cliffTimeInSec,
        uint _endTimeInSec,
        uint _unlockAmount,
        uint _totalAmount
    )
        public
        onlyOwner
        addressNotNull(_depositor)
        vestingScheduleNotConfirmed(_addressToRegister)
        validVestingScheduleTimes(_startTimeInSec, _cliffTimeInSec, _endTimeInSec)
    {
        schedules[_addressToRegister] = VestingSchedule({
            startTimeInSec: _startTimeInSec,
            cliffTimeInSec: _cliffTimeInSec,
            endTimeInSec: _endTimeInSec,
            unlockAmount: _unlockAmount,
            totalAmount: _totalAmount,
            totalAmountWithdrawn: 0,
            depositor: _depositor,
            isConfirmed: false
        });

        emit VestingScheduleRegistered(
            _addressToRegister,
            _depositor,
            _startTimeInSec,
            _cliffTimeInSec,
            _endTimeInSec,
            _unlockAmount,
            _totalAmount
        );
    }

    /// @dev Confirms a vesting schedule and deposits necessary tokens. Throws if deposit fails or schedules do not match.
    /// @param _address The address to be confirmed
    function confirmVestingSchedule(
        address _address
    )
        public
        addressRegistered(_address)
        vestingScheduleNotConfirmed(_address)
    {
        VestingSchedule storage vestingSchedule = schedules[_address];

        // require(vestingSchedule.startTimeInSec == _startTimeInSec);
        // require(vestingSchedule.cliffTimeInSec == _cliffTimeInSec);
        // require(vestingSchedule.endTimeInSec == _endTimeInSec);
        // require(vestingSchedule.totalAmount == _totalAmount);

        vestingSchedule.isConfirmed = true;
        require(vestingToken.transferFrom(vestingSchedule.depositor, address(this), vestingSchedule.totalAmount),"tranferFrom");

        emit VestingScheduleConfirmed(
            msg.sender,
            vestingSchedule.depositor,
            vestingSchedule.startTimeInSec,
            vestingSchedule.cliffTimeInSec,
            vestingSchedule.endTimeInSec,
            vestingSchedule.unlockAmount,
            vestingSchedule.totalAmount
        );
    }

    /// @dev Allows a registered address to withdraw tokens that have already been vested.
    function withdraw()
        public
        vestingScheduleConfirmed(msg.sender)
        pastCliffTime(msg.sender)
    {
        VestingSchedule storage vestingSchedule = schedules[msg.sender];

        uint totalAmountVested = getTotalAmountVested(vestingSchedule);
        uint amountWithdrawable = totalAmountVested - vestingSchedule.totalAmountWithdrawn;
        vestingSchedule.totalAmountWithdrawn = totalAmountVested;

        if (amountWithdrawable > 0) {
            require(vestingToken.transfer(msg.sender, amountWithdrawable),"vestingToken.transfer(msg.sender, amountWithdrawable)");
            emit Withdrawal(msg.sender, amountWithdrawable);
        }
    }

    /// @dev Allows contract owner to terminate a vesting schedule, transfering remaining vested tokens to the registered address and refunding owner with remaining tokens.
    /// @param _addressToEnd Address that is currently registered to the vesting schedule that will be closed.
    /// @param _addressToRefund Address that will receive unvested tokens.
    function endVesting(address _addressToEnd, address _addressToRefund)
        public
        onlyOwner
        vestingScheduleConfirmed(_addressToEnd)
        addressNotNull(_addressToRefund)
    {
        VestingSchedule storage vestingSchedule = schedules[_addressToEnd];

        uint amountWithdrawable = 0;
        uint amountRefundable = 0;

        if (blockTimestamp() < vestingSchedule.cliffTimeInSec) {
            amountRefundable = vestingSchedule.totalAmount;
        } else {
            uint totalAmountVested = getTotalAmountVested(vestingSchedule);
            amountWithdrawable = totalAmountVested - vestingSchedule.totalAmountWithdrawn;
            amountRefundable = vestingSchedule.totalAmount - totalAmountVested;
        }

        delete schedules[_addressToEnd];
        require(amountWithdrawable == 0 || vestingToken.transfer(_addressToEnd, amountWithdrawable));
        require(amountRefundable == 0 || vestingToken.transfer(_addressToRefund, amountRefundable));

        emit VestingEndedByOwner(_addressToEnd, amountWithdrawable, amountRefundable);
    }

    /// @dev Allows a registered address to request an address change.
    /// @param _newRegisteredAddress Desired address to update to.
    function requestAddressChange(address _newRegisteredAddress)
        public
        vestingScheduleConfirmed(msg.sender)
        addressNotRegistered(_newRegisteredAddress)
        addressNotNull(_newRegisteredAddress)
    {
        addressChangeRequests[msg.sender] = _newRegisteredAddress;
        emit AddressChangeRequested(msg.sender, _newRegisteredAddress);
    }

    /// @dev Confirm an address change and migrate vesting schedule to new address.
    /// @param _oldRegisteredAddress Current registered address.
    /// @param _newRegisteredAddress Address to migrate vesting schedule to.
    function confirmAddressChange(address _oldRegisteredAddress, address _newRegisteredAddress)
        public
        onlyOwner
        pendingAddressChangeRequest(_oldRegisteredAddress)
        addressNotRegistered(_newRegisteredAddress)
    {
        address newRegisteredAddress = addressChangeRequests[_oldRegisteredAddress];
        require(newRegisteredAddress == _newRegisteredAddress);    // prevents race condition

        VestingSchedule memory vestingSchedule = schedules[_oldRegisteredAddress];
        schedules[newRegisteredAddress] = vestingSchedule;

        delete schedules[_oldRegisteredAddress];
        delete addressChangeRequests[_oldRegisteredAddress];

        emit AddressChangeConfirmed(_oldRegisteredAddress, _newRegisteredAddress);
    }

    function getTotalAmountVested(address _address) public view
        returns (uint)
    {
        return getTotalAmountVested(schedules[_address]);
    }

    /// @dev Calculates the total tokens that have been vested for a vesting schedule, assuming the schedule is past the cliff.
    /// @param vestingSchedule Vesting schedule used to calculate vested tokens.
    /// @return Total tokens vested for a vesting schedule.
    function getTotalAmountVested(VestingSchedule memory vestingSchedule) view
        internal
        returns (uint)
    {
        if (blockTimestamp() >= vestingSchedule.endTimeInSec) return vestingSchedule.totalAmount;

        uint timeSinceStartInSec = blockTimestamp() - vestingSchedule.startTimeInSec;
        uint totalVestingTimeInSec = vestingSchedule.endTimeInSec - vestingSchedule.startTimeInSec;
        uint totalAmountVested = (timeSinceStartInSec * vestingSchedule.totalAmount)/totalVestingTimeInSec;
        if (totalAmountVested+vestingSchedule.unlockAmount > vestingSchedule.totalAmount)
            return vestingSchedule.totalAmount;
        else 
            return totalAmountVested + vestingSchedule.unlockAmount;
    }

    function blockTimestamp() public view returns (uint) {
        // return block.timestamp;
        return _blockTimestamp;
    }

    function setBlockTimestamp(uint256 _newBlockTimestamp) public {
        _blockTimestamp = _newBlockTimestamp;
    }
}