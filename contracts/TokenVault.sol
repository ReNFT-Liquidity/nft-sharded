pragma solidity ^0.8.0;

import "../Interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "./ERC721Template.sol";
import "./InitableOwnable.sol";
import "./SafeMath.sol";
import "../Interfaces/ISettings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVault is InitableOwnable, IERC20, ERC721Holder {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    address private _nftContract;
    string private _name;
    string private _symbol;
    uint256 private _totalSupply;
    uint8 private _decimals;
    uint private _initialized = 0;
    address public settings;
    uint8 public feeLevel;
    address public curator;

    //pool
    struct UserInfo {
        uint256 amount;
        uint256 depositRewarded;
        uint256 rewardDebt;
        uint256 pending;
        uint256 startTime;
    }

    struct PoolInfo {
        IERC20 token;
        uint256 startTime;
        uint256 endTime;
        uint256 PerTime;
        uint256 lastRewardTime;
        uint256 accPerShare;
        uint256 totalStake;
    }

    PoolInfo public pool;
    mapping(address => UserInfo) public users;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount, uint256 release);
    event ReclaimStakingReward(address user, uint256 amount);
    event Set(uint256 allocPoint, bool withUpdate);

    /// -----------------------------------
    /// -------- BASIC INFORMATION --------
    /// -----------------------------------
    /// @notice weth address
    address public weth;

    /// -----------------------------------
    /// -------- TOKEN INFORMATION --------
    /// -----------------------------------
    /// @notice the ERC721 token ID of the vault's token
    uint256 public id;

    /// -------------------------------------
    /// -------- AUCTION INFORMATION --------
    /// -------------------------------------

    /// @notice the unix timestamp end time of the token auction
    uint256 public auctionEnd;

    /// @notice the length of auctions
    uint256 public auctionLength;

    /// @notice reservePrice * votingTokens
    uint256 public reserveTotal;

    /// @notice the current price of the token during an auction
    uint256 public livePrice;

    /// @notice the current user winning the token auction
    address payable public winning;

    enum State {inactive, live, ended, redeemed}

    State public auctionState;

    /// -----------------------------------
    /// -------- VAULT INFORMATION --------
    /// -----------------------------------

    /// @notice the last timestamp where fees were claimed
    uint256 public lastClaimed;

    /// @notice a boolean to indicate if the vault has closed
    bool public vaultClosed;

    /// @notice the number of ownership tokens voting on the reserve price at any given time
    uint256 public votingTokens;

    /// @notice a mapping of users to their desired token price
    mapping(address => uint256) public userPrices;

    /// ------------------------
    /// -------- EVENTS --------
    /// ------------------------

    /// @notice An event emitted when a user updates their price
    event PriceUpdate(address indexed user, uint price);

    /// @notice An event emitted when an auction starts
    event Start(address indexed buyer, uint price);

    /// @notice An event emitted when a bid is made
    event Bid(address indexed buyer, uint price);

    /// @notice An event emitted when an auction is won
    event Won(address indexed buyer, uint price);

    /// @notice An event emitted when someone redeems all tokens for the NFT
    event Redeem(address indexed redeemer);

    /// @notice An event emitted when someone cashes in ERC20 tokens for ETH from an ERC721 token sale
    event Cash(address indexed owner, uint256 shares);

    function initialize(address nftContract_, address owner_, string memory name_, string memory symbol_,
        uint8 decimals_, address _settings) onlyOwner external {
        require(_initialized == 0, "ERC20:called once by the factory at time of deployment");
        _initialized = 1;
        _nftContract = nftContract_;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        curator = owner_;
        settings = _settings;
        weth = ISettings(settings).weth();
    }


    function initialize1(uint256 totalSupply_, uint8 _feeLevel, uint256 poolPreTime, uint256 _listPrice, uint256 _id, address reNft) onlyOwner external {
        require(_initialized == 1, "ERC20:called once by the factory at time of deployment");
        _initialized = 2;
        _totalSupply = totalSupply_;
        feeLevel = _feeLevel;
        uint256 rate = ISettings(settings).onceUseFee(_feeLevel);
        uint256 poolTime = ISettings(settings).poolTime();
        if (rate > 0) {
            uint256 tax = totalSupply_.mul(rate).div(10000);
            totalSupply_ = totalSupply_.sub(tax);
            _balances[address(this)] = tax;
            emit Transfer(address(0), address(this), tax);
            uint256 startTime = block.timestamp + poolPreTime;
            uint256 endTime = startTime + poolTime;
            uint256 PerTime = tax.div(poolTime);
            pool = PoolInfo({
            token : IERC20(reNft),
            startTime : startTime,
            endTime : endTime,
            PerTime : PerTime,
            lastRewardTime : startTime,
            accPerShare : 0,
            totalStake : 0
            });
        }
        _balances[curator] = totalSupply_;
        emit Transfer(address(0), curator, totalSupply_);
        id = _id;
        reserveTotal = _listPrice * totalSupply_;
        auctionLength = ISettings(settings).auctionLength();
        lastClaimed = block.timestamp;
        votingTokens = _listPrice == 0 ? 0 : totalSupply_;
        auctionState = State.inactive;
        userPrices[curator] = _listPrice;
    }


    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "ERC20: amount must greater than zero");
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        uint256 rate = ISettings(settings).copyrightTaxFee(feeLevel);
        _balances[sender] = senderBalance - amount;
        address feeReceiver = ISettings(settings).feeReceiver();
        if (rate > 0 && sender != feeReceiver && sender != address(this) && recipient != feeReceiver) {
            uint256 fee = amount.mul(rate).div(1000);
            _balances[curator] += fee;
            _updatePrice(sender, recipient, amount, amount.sub(fee));
            amount = amount.sub(fee);
            emit Transfer(sender, curator, fee);
        }
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    //pool
    modifier validatePool() {
        require(pool.startTime > 0, " pool exists?");
        _;
    }

    function getPool() view public returns (PoolInfo memory){
        return pool;
    }

    function setPerTime(uint256 _PerTime) public onlyOwner validatePool() {
        updatePool();
        pool.PerTime = _PerTime;
    }

    function getMultiplier(PoolInfo storage pool_) internal view returns (uint256) {
        uint256 from = pool_.lastRewardTime;
        uint256 to = block.timestamp < pool_.endTime ? block.timestamp : pool_.endTime;
        if (from >= to) {
            return 0;
        }
        return to.sub(from);
    }

    function updatePool() public validatePool() {
        if (block.timestamp <= pool.lastRewardTime || pool.lastRewardTime > pool.endTime) {
            return;
        }

        uint256 totalStake = pool.totalStake;
        if (totalStake == 0) {
            if (block.timestamp > pool.endTime) {
                pool.lastRewardTime = pool.endTime;
            }
            return;
        }

        uint256 multiplier = getMultiplier(pool);
        uint256 Reward = multiplier.mul(pool.PerTime);
        pool.accPerShare = pool.accPerShare.add(Reward.mul(1e18).div(totalStake));
        pool.lastRewardTime = block.timestamp < pool.endTime ? block.timestamp : pool.endTime;
    }

    function pending(address _user) public view validatePool() returns (uint256 total, uint256 fee)  {
        UserInfo storage user = users[_user];
        uint256 accPerShare = pool.accPerShare;
        uint256 totalStake = pool.totalStake;
        if (block.timestamp > pool.lastRewardTime && totalStake > 0) {
            uint256 multiplier = getMultiplier(pool);
            uint256 Reward = multiplier.mul(pool.PerTime);
            accPerShare = accPerShare.add(Reward.mul(1e18).div(totalStake));
        }
        total = user.pending.add(user.amount.mul(accPerShare).div(1e18)).sub(user.rewardDebt);
        uint256 diff = block.timestamp.sub(user.startTime);
        uint256 feeRate = ISettings(settings).preWithdrawFeeRate(diff);
        fee = total.mul(feeRate).div(100);
    }

    //抵押
    function deposit(uint256 _amount) public validatePool() {
        UserInfo storage user = users[msg.sender];

        updatePool();
        if (user.amount > 0) {
            uint256 reward = user.amount.mul(pool.accPerShare).div(1e18).sub(user.rewardDebt);
            user.pending = user.pending.add(reward);
        }
        pool.token.safeTransferFrom(_msgSender(), address(this), _amount);
        pool.totalStake = pool.totalStake.add(_amount);
        //(startTime*amount + now+_amount )/(amount+_amount)
        if (block.timestamp < pool.lastRewardTime) {
            user.startTime = pool.lastRewardTime;
        } else {
            user.startTime = user.startTime.mul(user.amount).add(block.timestamp.mul(_amount)).div(user.amount.add(_amount));
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }


    //提取抵押
    function withdraw(uint256 _amount) public validatePool() {
        UserInfo storage user = users[msg.sender];
        require(user.amount >= _amount, "withdraw: No deposit");
        updatePool();
        uint256 reward = user.pending.add(user.amount.mul(pool.accPerShare).div(1e18).sub(user.rewardDebt));
        uint256 release = reward.mul(_amount).div(user.amount);
        release = reclaimRelease(reward, release);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accPerShare).div(1e18);
        pool.totalStake = pool.totalStake.sub(_amount);
        pool.token.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount, release);
    }

    function reclaimRelease(uint256 reward, uint256 release) private returns (uint256) {
        UserInfo storage user = users[msg.sender];
        user.pending = reward.sub(release);
        if (release > 0) {
            uint256 end = block.timestamp > pool.endTime ? pool.endTime : block.timestamp;
            uint256 diff = end.sub(user.startTime);
            uint256 feeRate = ISettings(settings).preWithdrawFeeRate(diff);
            uint256 fee = release.mul(feeRate).div(100);
            if (fee > 0) {
                address feeReceiver = ISettings(settings).feeReceiver();
                safeTransfer(feeReceiver, fee);
            }
            release = release.sub(fee);
            safeTransfer(msg.sender, release);
            user.depositRewarded = user.depositRewarded.add(release);
        }
        return release;
    }

    function safeTransfer(address _to, uint256 _amount) internal {
        if (_amount > 0) {
            _transfer(address(this), _to, _amount);
        }
    }




    /// --------------------------------
    /// -------- VIEW FUNCTIONS --------
    /// --------------------------------

    function reservePrice() public view returns (uint256) {
        return votingTokens == 0 ? 0 : reserveTotal / votingTokens;
    }

    /// -------------------------------
    /// -------- GOV FUNCTIONS --------
    /// -------------------------------

    /// @notice allow governance to boot a bad actor curator
    /// @param _curator the new curator
    function kickCurator(address _curator) external {
        require(msg.sender == Ownable(settings).owner(), "kick:not gov");

        curator = _curator;
    }

    /// @notice allow governance to remove bad reserve prices
    function removeReserve(address _user) external {
        require(msg.sender == Ownable(settings).owner(), "remove:not gov");
        require(auctionState == State.inactive, "update:auction live cannot update price");

        uint256 old = userPrices[_user];
        require(0 != old, "update:not an update");
        uint256 weight = balanceOf(_user);

        votingTokens -= weight;
        reserveTotal -= weight * old;

        userPrices[_user] = 0;

        emit PriceUpdate(_user, 0);
    }

    /// -----------------------------------
    /// -------- CURATOR FUNCTIONS --------
    /// -----------------------------------

    /// @notice allow curator to update the curator address
    /// @param _curator the new curator
    function updateCurator(address _curator) external {
        require(msg.sender == curator, "update:not curator");

        curator = _curator;
    }

    /// @notice allow curator to update the auction length
    /// @param _length the new base price
    function updateAuctionLength(uint256 _length) external {
        require(msg.sender == curator, "update:not curator");
        require(_length >= ISettings(settings).minAuctionLength() && _length <= ISettings(settings).maxAuctionLength(), "update:invalid auction length");

        auctionLength = _length;
    }


    /// --------------------------------
    /// -------- CORE FUNCTIONS --------
    /// --------------------------------

    /// @notice a function for an end user to update their desired sale price
    /// @param _new the desired price in ETH
    function updateUserPrice(uint256 _new) external {
        require(auctionState == State.inactive, "update:auction live cannot update price");
        uint256 old = userPrices[msg.sender];
        require(_new != old, "update:not an update");
        uint256 weight = balanceOf(msg.sender);

        reserveTotal = reserveTotal.add(weight.mul(_new)).sub(weight.mul(old));

        if (votingTokens != 0 && weight != votingTokens && old == 0 && _new != 0) {
            uint256 averageReserve = reserveTotal.div(votingTokens);

            uint256 reservePriceMin = averageReserve * ISettings(settings).minReserveFactor() / 1000;
            require(_new >= reservePriceMin, "update:reserve price too low");
            uint256 reservePriceMax = averageReserve * ISettings(settings).maxReserveFactor() / 1000;
            require(_new <= reservePriceMax, "update:reserve price too high");
        }
        if (old == 0) {
            votingTokens = votingTokens.add(weight);
        } else if (_new == 0) {
            votingTokens = votingTokens.sub(weight);
        }
        userPrices[msg.sender] = _new;
        emit PriceUpdate(msg.sender, _new);
    }

    /// @notice an internal function used to update sender and receivers price on token transfer
    /// @param _from the ERC20 token sender
    /// @param _to the ERC20 token receiver
    function _updatePrice(address _from, address _to, uint256 _fromAmount, uint256 _toAmount) internal {
        if (auctionState == State.inactive) {
            uint256 fromPrice = userPrices[_from];
            uint256 toPrice = userPrices[_to];

            // only do something if users have different reserve price
            if (toPrice != fromPrice) {
                // new holder is not a voter
                if (toPrice == 0) {
                    // get the average reserve price ignoring the senders amount
                    votingTokens = votingTokens.sub(_fromAmount);
                }
                // old holder is not a voter
                else if (fromPrice == 0) {
                    votingTokens = votingTokens.add(_toAmount);
                }
                reserveTotal = reserveTotal + (_toAmount * toPrice) - (_fromAmount * fromPrice);
            }
        }
    }

    /// @notice kick off an auction. Must send reservePrice in ETH
    function start() external payable {
        require(auctionState == State.inactive, "start:no auction starts");
        require(msg.value >= reservePrice(), "start:too low bid");
        require(votingTokens * 1000 >= ISettings(settings).minVotePercentage() * totalSupply(), "start:not enough voters");

        auctionEnd = block.timestamp + auctionLength;
        auctionState = State.live;

        livePrice = msg.value;
        winning = payable(msg.sender);

        emit Start(msg.sender, msg.value);
    }

    /// @notice an external function to bid on purchasing the vaults NFT. The msg.value is the bid amount
    function bid() external payable {
        require(auctionState == State.live, "bid:auction is not live");
        uint256 increase = ISettings(settings).minBidIncrease() + 1000;
        require(msg.value * 1000 <= livePrice * increase, "bid:too high bid");
        require(msg.value >= livePrice, "bid:too low bid");
        require(block.timestamp < auctionEnd, "bid:auction ended");

        // If bid is within 15 minutes of auction end, extend auction
        if (auctionEnd - block.timestamp <= 15 minutes) {
            auctionEnd += 15 minutes;
        }

        _sendETHOrWETH(winning, livePrice);

        livePrice = msg.value;
        winning = payable(msg.sender);

        emit Bid(msg.sender, msg.value);
    }

    /// @notice an external function to end an auction after the timer has run out
    function end() external {
        require(auctionState == State.live, "end:vault has already closed");
        require(block.timestamp >= auctionEnd, "end:auction live");

        // transfer erc721 to winner
        ERC721Template(_nftContract).safeTransferFrom(address(this), winning, id);

        auctionState = State.ended;

        emit Won(winning, livePrice);
    }

    /// @notice an external function to burn all ERC20 tokens to receive the ERC721 token
    function redeem() external {
        require(auctionState == State.inactive, "redeem:no redeeming");
        _burn(msg.sender, totalSupply());

        // transfer erc721 to redeemer
        ERC721Template(_nftContract).safeTransferFrom(address(this), msg.sender, id);

        auctionState = State.redeemed;

        emit Redeem(msg.sender);
    }

    /// @notice an external function to burn ERC20 tokens to receive ETH from ERC721 token purchase
    function cash() external {
        require(block.timestamp >= auctionEnd, "cash:auction live");
        require(auctionState == State.ended || auctionState == State.live, "cash:vault not closed yet");
        uint256 bal = balanceOf(msg.sender);
        require(bal > 0, "cash:no tokens to cash out");
        uint256 share = bal * address(this).balance / totalSupply();
        _burn(msg.sender, bal);

        _sendETHOrWETH(payable(msg.sender), share);

        emit Cash(msg.sender, share);
    }

    // Will attempt to transfer ETH, but will transfer WETH instead if it fails.
    function _sendETHOrWETH(address to, uint256 value) internal {
        // Try to transfer ETH to the given recipient.
        if (!_attemptETHTransfer(to, value)) {
            // If the transfer fails, wrap and send as WETH, so that
            // the auction is not impeded and the recipient still
            // can claim ETH via the WETH contract (similar to escrow).
            IWETH(weth).deposit{value : value}();
            IWETH(weth).transfer(to, value);
            // At this point, the recipient can unwrap WETH.
        }
    }

    // Sending ETH is not guaranteed complete, and the method used here will return false if
    // it fails. For example, a contract can block ETH transfer, or might use
    // an excessive amount of gas, thereby griefing a new bidder.
    // We should limit the gas used in transfers, and handle failure cases.
    function _attemptETHTransfer(address to, uint256 value)
    internal
    returns (bool)
    {
        // Here increase the gas limit a reasonable amount above the default, and try
        // to send ETH to the recipient.
        // NOTE: This might allow the recipient to attempt a limited reentrancy attack.
        (bool success,) = to.call{value : value, gas : 30000}("");
        return success;
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
    unchecked {
        _balances[account] = accountBalance - amount;
    }
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    /// @notice an external function to burn ERC20 tokens to receive ETH from ERC721 token purchase
    function cashAll() external {
        address feeReceiver = ISettings(settings).feeReceiver();
        require(feeReceiver == msg.sender, "cashAll:not manager");
        require(block.timestamp > auctionEnd + ISettings(settings).poolTime(), "cashAll:time error");
        uint256 bal = address(this).balance;
        require(bal > 0, "cashAll:no tokens to cash out");
        _sendETHOrWETH(payable(msg.sender), bal);
        emit Cash(msg.sender, bal);
    }
}
