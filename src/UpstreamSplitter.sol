// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title UpstreamSplitter
/// @notice One address sponsors pay. A public split decides who is owed what.
///         Every contributor and upstream project withdraws their own share.
///
/// @dev THE PROMISE, in two lines:
///      1. The maintainer never touches the money: the owner role can only edit the
///         split for FUTURE deposits, after a public delay. There is no function that
///         moves ETH on behalf of anyone but the caller's own balance.
///      2. Nobody can quietly keep what belongs to someone else: balances are credited
///         at deposit time and can only be zeroed by their own owner via `withdraw`.
///
///      Design rules (each is proven by a test in test/):
///      - Pull, don't push. `receive` only writes balances. No external call is made
///        to any recipient while funds come in, so one bad address cannot block anyone.
///      - Integer math. Shares are basis points (10_000 = 100%). Every share except
///        the last is `amount * bps / 10_000` rounded down; the LAST listed share gets
///        `amount - (sum of the others)`. So credited == deposited, to the wei.
///      - Accounting never reads `address(this).balance` to decide what is owed, so
///        ETH forced in by `selfdestruct` cannot corrupt balances. Anyone can call
///        `sync()` to split such stray ETH using the current split.
///      - Guarded exit: `withdraw` zeroes the balance before sending and is
///        `nonReentrant`.
///      - The owner cannot raise a split on money already credited: a new split
///        applies only to deposits made after it is activated.
contract UpstreamSplitter is Ownable2Step, ReentrancyGuard {
    // ---------------------------------------------------------------------
    // Types and constants
    // ---------------------------------------------------------------------

    /// @param account Where this share is credited (a maintainer, contributor or upstream project).
    /// @param bps     Share of every deposit, in basis points (100 = 1%).
    /// @param label   Human-readable name shown in the UI, e.g. "viem (upstream)".
    struct Share {
        address account;
        uint16 bps;
        string label;
    }

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_RECIPIENTS = 30;
    uint256 public constant MAX_LABEL_BYTES = 64;
    uint256 public constant MAX_NAME_BYTES = 96;
    uint256 public constant MIN_DELAY = 1 hours;
    uint256 public constant MAX_DELAY = 30 days;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroValue();
    error ZeroAddress();
    error NoRecipients();
    error TooManyRecipients();
    error ZeroShare();
    error BpsDoNotSumTo10000(uint256 sum);
    error DuplicateRecipient(address account);
    error RecipientIsSplitter();
    error LabelTooLong();
    error NameTooLong();
    error DelayOutOfRange();
    error SplitIsFrozen();
    error NoPendingSplit();
    error SplitNotReady(uint256 activatesAt);
    error NothingToWithdraw();
    error TransferFailed();

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event Funded(address indexed sponsor, uint256 amount, uint256 indexed splitVersion);
    event Credited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, address indexed to, uint256 amount);
    event SplitProposed(uint256 activatesAt, Share[] shares);
    event SplitProposalCancelled();
    event SplitActivated(uint256 indexed version, Share[] shares);
    event SplitFrozenForever();
    event StrayEthSynced(uint256 amount);

    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------

    /// @notice Name of the project this address funds.
    string public projectName;

    /// @notice How long a proposed split must be public before it can take effect.
    uint256 public immutable splitChangeDelay;

    /// @notice Increments every time the active split changes. Starts at 1.
    uint256 public splitVersion;

    /// @notice Once true the split can never change again.
    bool public splitFrozen;

    /// @notice Timestamp at which the pending split may be activated. 0 = none pending.
    uint256 public pendingActivatesAt;

    /// @notice What each account can withdraw right now.
    mapping(address account => uint256 wei_) public owed;

    /// @notice Everything an account was ever credited (withdrawn or not).
    mapping(address account => uint256 wei_) public totalEarned;

    /// @notice Sum of every credit ever made.
    uint256 public totalCredited;

    /// @notice Sum of every withdrawal ever made.
    uint256 public totalWithdrawn;

    Share[] private _shares;
    Share[] private _pending;

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    /// @param projectName_ Public name of the project being funded.
    /// @param maintainer   Address allowed to propose split changes. It holds NO power over funds.
    /// @param shares       The initial split. Basis points must sum to exactly 10_000.
    /// @param delay        Seconds a proposed change stays public before it can activate.
    constructor(string memory projectName_, address maintainer, Share[] memory shares, uint256 delay)
        Ownable(maintainer)
    {
        if (bytes(projectName_).length > MAX_NAME_BYTES) revert NameTooLong();
        if (delay < MIN_DELAY || delay > MAX_DELAY) revert DelayOutOfRange();
        projectName = projectName_;
        splitChangeDelay = delay;
        _validate(shares);
        _store(_shares, shares);
        splitVersion = 1;
        emit SplitActivated(1, shares);
    }

    // ---------------------------------------------------------------------
    // Money in
    // ---------------------------------------------------------------------

    /// @notice Pay the project. Plain ETH transfers land here.
    receive() external payable {
        if (msg.value == 0) revert ZeroValue();
        emit Funded(msg.sender, msg.value, splitVersion);
        _credit(msg.value);
    }

    /// @notice Same as sending ETH directly. Convenient for wallets that need a function call.
    function fund() external payable {
        if (msg.value == 0) revert ZeroValue();
        emit Funded(msg.sender, msg.value, splitVersion);
        _credit(msg.value);
    }

    /// @notice Split ETH that arrived without calling `receive` (e.g. forced in by selfdestruct
    ///         or sent as a block reward). Anyone may call; nobody gains special rights.
    function sync() external {
        uint256 owedNow = totalCredited - totalWithdrawn;
        uint256 balance = address(this).balance;
        uint256 stray = balance > owedNow ? balance - owedNow : 0;
        if (stray == 0) revert ZeroValue();
        emit StrayEthSynced(stray);
        _credit(stray);
    }

    // ---------------------------------------------------------------------
    // Money out
    // ---------------------------------------------------------------------

    /// @notice Withdraw everything you are owed to your own address.
    function withdraw() external nonReentrant {
        _withdraw(msg.sender, msg.sender);
    }

    /// @notice Withdraw everything you are owed to another address (e.g. a cold wallet).
    function withdrawTo(address to) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        _withdraw(msg.sender, to);
    }

    function _withdraw(address from, address to) private {
        uint256 amount = owed[from];
        if (amount == 0) revert NothingToWithdraw();
        // Effects before interaction: balance is zero before any external call happens.
        owed[from] = 0;
        totalWithdrawn += amount;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(from, to, amount);
    }

    // ---------------------------------------------------------------------
    // Governance of the split (maintainer power: future deposits only)
    // ---------------------------------------------------------------------

    /// @notice Propose a new split. It is public immediately and can activate after `splitChangeDelay`.
    ///         It never affects balances that are already credited.
    function proposeSplit(Share[] calldata shares) external onlyOwner {
        if (splitFrozen) revert SplitIsFrozen();
        _validate(shares);
        _store(_pending, shares);
        pendingActivatesAt = block.timestamp + splitChangeDelay;
        emit SplitProposed(pendingActivatesAt, shares);
    }

    /// @notice Drop the pending proposal.
    function cancelSplitProposal() external onlyOwner {
        if (pendingActivatesAt == 0) revert NoPendingSplit();
        delete _pending;
        pendingActivatesAt = 0;
        emit SplitProposalCancelled();
    }

    /// @notice Make the pending split active. Anyone may call once the delay has passed.
    function activateSplit() external {
        uint256 eta = pendingActivatesAt;
        if (eta == 0) revert NoPendingSplit();
        if (block.timestamp < eta) revert SplitNotReady(eta);
        delete _shares;
        uint256 n = _pending.length;
        for (uint256 i; i < n; ++i) {
            _shares.push(_pending[i]);
        }
        delete _pending;
        pendingActivatesAt = 0;
        unchecked {
            ++splitVersion;
        }
        emit SplitActivated(splitVersion, _shares);
    }

    /// @notice Lock the current split forever. Also drops any pending proposal. Irreversible.
    function freezeSplit() external onlyOwner {
        if (splitFrozen) revert SplitIsFrozen();
        splitFrozen = true;
        delete _pending;
        pendingActivatesAt = 0;
        emit SplitFrozenForever();
    }

    // ---------------------------------------------------------------------
    // Reading (what the UI shows in plain language)
    // ---------------------------------------------------------------------

    /// @notice The active split.
    function getSplit() external view returns (Share[] memory) {
        return _shares;
    }

    /// @notice The proposed split and when it can take effect (0 = none).
    function getPendingSplit() external view returns (Share[] memory shares, uint256 activatesAt) {
        return (_pending, pendingActivatesAt);
    }

    function recipientCount() external view returns (uint256) {
        return _shares.length;
    }

    /// @notice ETH the contract holds that is owed to recipients.
    function outstanding() public view returns (uint256) {
        return totalCredited - totalWithdrawn;
    }

    /// @notice ETH held that nobody has been credited for yet (forced-in ETH). Call `sync()` to split it.
    function unaccounted() external view returns (uint256) {
        uint256 o = outstanding();
        uint256 b = address(this).balance;
        return b > o ? b - o : 0;
    }

    /// @notice How a deposit of `amount` wei would be credited under the active split.
    function preview(uint256 amount) external view returns (address[] memory accounts, uint256[] memory amounts) {
        uint256 n = _shares.length;
        accounts = new address[](n);
        amounts = new uint256[](n);
        uint256 distributed;
        for (uint256 i; i < n; ++i) {
            accounts[i] = _shares[i].account;
            if (i + 1 == n) {
                amounts[i] = amount - distributed;
            } else {
                amounts[i] = (amount * _shares[i].bps) / BPS_DENOMINATOR;
                distributed += amounts[i];
            }
        }
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    /// @dev Credit `amount` across the active split. Writes balances only; makes no external call.
    function _credit(uint256 amount) private {
        uint256 n = _shares.length;
        uint256 distributed;
        for (uint256 i; i < n; ++i) {
            Share storage s = _shares[i];
            uint256 part;
            if (i + 1 == n) {
                part = amount - distributed; // remainder (at most n-1 wei of dust) goes to the last share
            } else {
                part = (amount * s.bps) / BPS_DENOMINATOR;
                distributed += part;
            }
            if (part != 0) {
                owed[s.account] += part;
                totalEarned[s.account] += part;
                emit Credited(s.account, part);
            }
        }
        totalCredited += amount;
    }

    function _validate(Share[] memory shares) private view {
        uint256 n = shares.length;
        if (n == 0) revert NoRecipients();
        if (n > MAX_RECIPIENTS) revert TooManyRecipients();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address a = shares[i].account;
            if (a == address(0)) revert ZeroAddress();
            if (a == address(this)) revert RecipientIsSplitter();
            if (shares[i].bps == 0) revert ZeroShare();
            if (bytes(shares[i].label).length > MAX_LABEL_BYTES) revert LabelTooLong();
            for (uint256 j; j < i; ++j) {
                if (shares[j].account == a) revert DuplicateRecipient(a);
            }
            sum += shares[i].bps;
        }
        if (sum != BPS_DENOMINATOR) revert BpsDoNotSumTo10000(sum);
    }

    function _store(Share[] storage dest, Share[] memory src) private {
        while (dest.length != 0) dest.pop();
        for (uint256 i; i < src.length; ++i) {
            dest.push(src[i]);
        }
    }
}
