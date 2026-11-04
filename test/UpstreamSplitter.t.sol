// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UpstreamSplitter} from "../src/UpstreamSplitter.sol";
import {
    ReentrantRecipient,
    RevertingRecipient,
    ReturnBombRecipient,
    AcceptingRecipient,
    ForceSender,
    Sponsor
} from "./helpers/Actors.sol";

contract UpstreamSplitterTest is Test {
    UpstreamSplitter internal s;

    address internal maintainer = makeAddr("maintainer");
    address internal alice = makeAddr("alice"); // contributor
    address internal bob = makeAddr("bob"); // contributor
    address internal libA = makeAddr("libA"); // upstream project
    address internal libB = makeAddr("libB"); // upstream project
    address internal sponsor = makeAddr("sponsor");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant DELAY = 2 days;

    function _share(address a, uint16 bps, string memory l) internal pure returns (UpstreamSplitter.Share memory) {
        return UpstreamSplitter.Share(a, bps, l);
    }

    function _defaultSplit() internal view returns (UpstreamSplitter.Share[] memory sh) {
        sh = new UpstreamSplitter.Share[](5);
        sh[0] = _share(maintainer, 4000, "Maintainer");
        sh[1] = _share(alice, 2000, "Alice");
        sh[2] = _share(bob, 1000, "Bob");
        sh[3] = _share(libA, 2000, "libA");
        sh[4] = _share(libB, 1000, "libB");
    }

    function setUp() public {
        s = new UpstreamSplitter("Demo", maintainer, _defaultSplit(), DELAY);
        vm.deal(sponsor, 1_000 ether);
    }

    function _fund(uint256 amount) internal {
        vm.prank(sponsor);
        (bool ok,) = address(s).call{value: amount}("");
        assertTrue(ok);
    }

    // ------------------------------------------------------------------ construction

    function test_constructor_setsState() public view {
        assertEq(s.projectName(), "Demo");
        assertEq(s.owner(), maintainer);
        assertEq(s.splitVersion(), 1);
        assertEq(s.splitChangeDelay(), DELAY);
        assertEq(s.recipientCount(), 5);
        UpstreamSplitter.Share[] memory got = s.getSplit();
        assertEq(got[0].account, maintainer);
        assertEq(got[0].bps, 4000);
        assertEq(got[0].label, "Maintainer");
        assertEq(got.length, 5);
    }

    function test_constructor_rejectsDelayTooShort() public {
        UpstreamSplitter.Share[] memory sh = _defaultSplit();
        vm.expectRevert(UpstreamSplitter.DelayOutOfRange.selector);
        new UpstreamSplitter("x", maintainer, sh, 1 minutes);
    }

    function test_constructor_rejectsDelayTooLong() public {
        UpstreamSplitter.Share[] memory sh = _defaultSplit();
        vm.expectRevert(UpstreamSplitter.DelayOutOfRange.selector);
        new UpstreamSplitter("x", maintainer, sh, 31 days);
    }

    function test_constructor_rejectsNameTooLong() public {
        UpstreamSplitter.Share[] memory sh = _defaultSplit();
        bytes memory longName = new bytes(97);
        for (uint256 i; i < longName.length; ++i) {
            longName[i] = "a";
        }
        vm.expectRevert(UpstreamSplitter.NameTooLong.selector);
        new UpstreamSplitter(string(longName), maintainer, sh, DELAY);
    }

    function test_constructor_acceptsMaxLengthName() public {
        bytes memory name = new bytes(96);
        for (uint256 i; i < name.length; ++i) {
            name[i] = "a";
        }
        UpstreamSplitter t = new UpstreamSplitter(string(name), maintainer, _defaultSplit(), DELAY);
        assertEq(bytes(t.projectName()).length, 96);
    }

    // ------------------------------------------------------------------ validation (via constructor)

    function test_validate_empty() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](0);
        vm.expectRevert(UpstreamSplitter.NoRecipients.selector);
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    function test_validate_tooMany() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](31);
        for (uint256 i; i < 31; ++i) {
            sh[i] = _share(address(uint160(i + 1)), 1, "");
        }
        vm.expectRevert(UpstreamSplitter.TooManyRecipients.selector);
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    function test_validate_maxRecipientsWorks() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](30);
        for (uint256 i; i < 30; ++i) {
            // 29 * 333 = 9657, last gets 343 -> 10000
            sh[i] = _share(address(uint160(i + 1)), i == 29 ? 343 : 333, "");
        }
        UpstreamSplitter big = new UpstreamSplitter("big", maintainer, sh, DELAY);
        vm.deal(sponsor, 10 ether);
        vm.prank(sponsor);
        (bool ok,) = address(big).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(big.totalCredited(), 1 ether);
    }

    function test_validate_zeroAddress() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](1);
        sh[0] = _share(address(0), 10_000, "");
        vm.expectRevert(UpstreamSplitter.ZeroAddress.selector);
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    function test_validate_zeroShare() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = _share(alice, 0, "");
        sh[1] = _share(bob, 10_000, "");
        vm.expectRevert(UpstreamSplitter.ZeroShare.selector);
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    function test_validate_sumNot10000() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = _share(alice, 5000, "");
        sh[1] = _share(bob, 4999, "");
        vm.expectRevert(abi.encodeWithSelector(UpstreamSplitter.BpsDoNotSumTo10000.selector, 9999));
        new UpstreamSplitter("x", maintainer, sh, DELAY);
        sh[1] = _share(bob, 5001, "");
        vm.expectRevert(abi.encodeWithSelector(UpstreamSplitter.BpsDoNotSumTo10000.selector, 10_001));
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    function test_validate_duplicate() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = _share(alice, 5000, "");
        sh[1] = _share(alice, 5000, "");
        vm.expectRevert(abi.encodeWithSelector(UpstreamSplitter.DuplicateRecipient.selector, alice));
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    function test_validate_labelTooLong() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](1);
        sh[0] = _share(alice, 10_000, string(new bytes(65)));
        vm.expectRevert(UpstreamSplitter.LabelTooLong.selector);
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    function test_validate_cannotPayTheSplitterItself() public {
        // Predict the address the constructor will run at and name it as a recipient.
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](1);
        sh[0] = _share(predicted, 10_000, "");
        vm.expectRevert(UpstreamSplitter.RecipientIsSplitter.selector);
        new UpstreamSplitter("x", maintainer, sh, DELAY);
    }

    // ------------------------------------------------------------------ money in

    function test_receive_creditsEveryShare() public {
        _fund(10 ether);
        assertEq(s.owed(maintainer), 4 ether);
        assertEq(s.owed(alice), 2 ether);
        assertEq(s.owed(bob), 1 ether);
        assertEq(s.owed(libA), 2 ether);
        assertEq(s.owed(libB), 1 ether);
        assertEq(s.totalCredited(), 10 ether);
        assertEq(s.outstanding(), 10 ether);
        assertEq(address(s).balance, 10 ether);
        assertEq(s.totalEarned(maintainer), 4 ether);
    }

    function test_fund_function_sameAsReceive() public {
        vm.prank(sponsor);
        s.fund{value: 3 ether}();
        assertEq(s.owed(alice), 0.6 ether);
        assertEq(s.totalCredited(), 3 ether);
    }

    function test_zeroValueReverts() public {
        vm.prank(sponsor);
        (bool ok,) = address(s).call{value: 0}("");
        assertFalse(ok);
        vm.prank(sponsor);
        vm.expectRevert(UpstreamSplitter.ZeroValue.selector);
        s.fund{value: 0}();
    }

    function test_dust_goesToLastShare_andNothingIsLost() public {
        // 7 wei over 4000/2000/1000/2000/1000:
        // maintainer 2 (2.8), alice 1 (1.4), bob 0 (0.7), libA 1 (1.4), libB gets remainder 7-4=3
        _fund(7);
        assertEq(s.owed(maintainer), 2);
        assertEq(s.owed(alice), 1);
        assertEq(s.owed(bob), 0);
        assertEq(s.owed(libA), 1);
        assertEq(s.owed(libB), 3);
        assertEq(s.totalCredited(), 7);
        assertEq(
            s.owed(maintainer) + s.owed(alice) + s.owed(bob) + s.owed(libA) + s.owed(libB),
            7
        );
    }

    function test_oneWei_goesToLast() public {
        _fund(1);
        assertEq(s.owed(libB), 1);
        assertEq(s.totalCredited(), 1);
    }

    function test_preview_matchesRealCredit() public {
        (address[] memory a, uint256[] memory amt) = s.preview(7);
        assertEq(a.length, 5);
        _fund(7);
        for (uint256 i; i < a.length; ++i) {
            assertEq(s.owed(a[i]), amt[i]);
        }
    }

    function test_sponsorContractUsingCallWorks() public {
        Sponsor sp = new Sponsor();
        vm.deal(address(sp), 5 ether);
        sp.pay{value: 5 ether}(payable(address(s)));
        assertEq(s.totalCredited(), 5 ether);
    }

    // ------------------------------------------------------------------ forced ETH

    function test_forcedEth_doesNotCorruptAccounting_andCanBeSynced() public {
        _fund(10 ether);
        ForceSender f = new ForceSender();
        vm.deal(address(f), 1 ether);
        f.boom(payable(address(s)));

        assertEq(address(s).balance, 11 ether);
        assertEq(s.totalCredited(), 10 ether); // not fooled by balance
        assertEq(s.unaccounted(), 1 ether);

        vm.prank(stranger);
        s.sync();
        assertEq(s.totalCredited(), 11 ether);
        assertEq(s.unaccounted(), 0);
        assertEq(s.owed(alice), 2.2 ether);
    }

    function test_sync_revertsWhenNothingStray() public {
        _fund(1 ether);
        vm.expectRevert(UpstreamSplitter.ZeroValue.selector);
        s.sync();
    }

    function test_unaccounted_zeroWhenBalanceBelowOutstanding() public view {
        assertEq(s.unaccounted(), 0);
    }

    // ------------------------------------------------------------------ money out

    function test_withdraw_paysCallerOnly() public {
        _fund(10 ether);
        uint256 before_ = alice.balance;
        vm.prank(alice);
        s.withdraw();
        assertEq(alice.balance - before_, 2 ether);
        assertEq(s.owed(alice), 0);
        assertEq(s.owed(bob), 1 ether); // untouched
        assertEq(s.totalWithdrawn(), 2 ether);
        assertEq(s.outstanding(), 8 ether);
        assertEq(s.totalEarned(alice), 2 ether); // lifetime figure survives
    }

    function test_withdraw_nothingOwedReverts() public {
        vm.prank(alice);
        vm.expectRevert(UpstreamSplitter.NothingToWithdraw.selector);
        s.withdraw();
        _fund(1 ether);
        vm.prank(alice);
        s.withdraw();
        vm.prank(alice);
        vm.expectRevert(UpstreamSplitter.NothingToWithdraw.selector);
        s.withdraw(); // double withdraw
    }

    function test_strangerCannotWithdrawOthers() public {
        _fund(1 ether);
        vm.prank(stranger);
        vm.expectRevert(UpstreamSplitter.NothingToWithdraw.selector);
        s.withdraw();
    }

    function test_withdrawTo_otherAddress() public {
        _fund(10 ether);
        address cold = makeAddr("cold");
        vm.prank(alice);
        s.withdrawTo(cold);
        assertEq(cold.balance, 2 ether);
        assertEq(s.owed(alice), 0);
    }

    function test_withdrawTo_zeroAddressReverts() public {
        _fund(1 ether);
        vm.prank(alice);
        vm.expectRevert(UpstreamSplitter.ZeroAddress.selector);
        s.withdrawTo(address(0));
    }

    function test_withdraw_toRevertingContract_failsAndKeepsBalance() public {
        RevertingRecipient bad = new RevertingRecipient();
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = _share(address(bad), 5000, "bad");
        sh[1] = _share(alice, 5000, "alice");
        UpstreamSplitter t = new UpstreamSplitter("t", maintainer, sh, DELAY);
        vm.deal(sponsor, 10 ether);
        vm.prank(sponsor);
        (bool ok,) = address(t).call{value: 4 ether}("");
        assertTrue(ok);

        vm.expectRevert(UpstreamSplitter.TransferFailed.selector);
        bad.pull(t);
        assertEq(t.owed(address(bad)), 2 ether); // still credited, not lost, not stolen

        // The bad recipient cannot block the good one, and can still redirect its money.
        vm.prank(alice);
        t.withdraw();
        assertEq(alice.balance, 2 ether);
        vm.prank(address(bad));
        t.withdrawTo(makeAddr("rescue"));
        assertEq(makeAddr("rescue").balance, 2 ether);
    }

    function test_withdraw_reentrancyIsBlocked() public {
        // The attacker is deployed first and told where the splitter WILL be (next nonce).
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        ReentrantRecipient atk = new ReentrantRecipient(UpstreamSplitter(payable(predicted)));
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = _share(address(atk), 5000, "evil");
        sh[1] = _share(alice, 5000, "alice");
        UpstreamSplitter fin = new UpstreamSplitter("fin", maintainer, sh, DELAY);
        assertEq(address(fin), predicted);

        vm.deal(sponsor, 10 ether);
        vm.prank(sponsor);
        (bool ok,) = address(fin).call{value: 2 ether}("");
        assertTrue(ok);

        atk.attack();
        assertTrue(atk.reenterAttempted());
        assertFalse(atk.reenterSucceeded());
        assertEq(address(atk).balance, 1 ether); // exactly its own share, once
        assertEq(address(fin).balance, 1 ether); // Alice's money is intact
        assertEq(fin.owed(alice), 1 ether);
    }

    function test_withdraw_returnBombDoesNotBlock() public {
        ReturnBombRecipient bomb = new ReturnBombRecipient();
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = _share(address(bomb), 5000, "bomb");
        sh[1] = _share(alice, 5000, "alice");
        UpstreamSplitter t = new UpstreamSplitter("t", maintainer, sh, DELAY);
        vm.deal(sponsor, 10 ether);
        vm.prank(sponsor);
        (bool ok,) = address(t).call{value: 2 ether}("");
        assertTrue(ok);
        bomb.pull(t);
        assertEq(address(bomb).balance, 1 ether);
    }

    function test_withdraw_acceptingContractWorks() public {
        AcceptingRecipient w = new AcceptingRecipient();
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](1);
        sh[0] = _share(address(w), 10_000, "wallet");
        UpstreamSplitter t = new UpstreamSplitter("t", maintainer, sh, DELAY);
        vm.deal(sponsor, 10 ether);
        vm.prank(sponsor);
        (bool ok,) = address(t).call{value: 1 ether}("");
        assertTrue(ok);
        w.pull(t);
        assertEq(address(w).balance, 1 ether);
    }

    // ------------------------------------------------------------------ governance

    function _newSplit() internal view returns (UpstreamSplitter.Share[] memory sh) {
        sh = new UpstreamSplitter.Share[](2);
        sh[0] = _share(maintainer, 9000, "Maintainer");
        sh[1] = _share(libA, 1000, "libA");
    }

    function test_onlyOwnerCanGovern() public {
        UpstreamSplitter.Share[] memory sh = _newSplit();
        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        s.proposeSplit(sh);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        s.cancelSplitProposal();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        s.freezeSplit();
        vm.stopPrank();
    }

    function test_propose_waitsForDelay_thenAnyoneActivates() public {
        UpstreamSplitter.Share[] memory sh = _newSplit();
        vm.prank(maintainer);
        s.proposeSplit(sh);

        (UpstreamSplitter.Share[] memory pend, uint256 eta) = s.getPendingSplit();
        assertEq(pend.length, 2);
        assertEq(eta, block.timestamp + DELAY);

        vm.expectRevert(abi.encodeWithSelector(UpstreamSplitter.SplitNotReady.selector, eta));
        s.activateSplit();

        // old split still in force during the delay
        _fund(10 ether);
        assertEq(s.owed(alice), 2 ether);

        vm.warp(eta);
        vm.prank(stranger);
        s.activateSplit();
        assertEq(s.splitVersion(), 2);
        assertEq(s.pendingActivatesAt(), 0);
        assertEq(s.recipientCount(), 2);
        (pend, eta) = s.getPendingSplit();
        assertEq(pend.length, 0);
        assertEq(eta, 0);

        // new split applies to NEW money only. Alice keeps what she was already credited.
        assertEq(s.owed(alice), 2 ether);
        _fund(10 ether);
        assertEq(s.owed(alice), 2 ether);
        assertEq(s.owed(maintainer), 4 ether + 9 ether);
        assertEq(s.owed(libA), 2 ether + 1 ether);
    }

    function test_activate_withoutProposalReverts() public {
        vm.expectRevert(UpstreamSplitter.NoPendingSplit.selector);
        s.activateSplit();
    }

    function test_propose_invalidSplitReverts() public {
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](1);
        sh[0] = _share(alice, 9999, "");
        vm.prank(maintainer);
        vm.expectRevert(abi.encodeWithSelector(UpstreamSplitter.BpsDoNotSumTo10000.selector, 9999));
        s.proposeSplit(sh);
    }

    function test_cancel() public {
        vm.startPrank(maintainer);
        vm.expectRevert(UpstreamSplitter.NoPendingSplit.selector);
        s.cancelSplitProposal();
        s.proposeSplit(_newSplit());
        s.cancelSplitProposal();
        vm.stopPrank();
        assertEq(s.pendingActivatesAt(), 0);
        vm.expectRevert(UpstreamSplitter.NoPendingSplit.selector);
        s.activateSplit();
    }

    function test_reproposeResetsTimer() public {
        vm.startPrank(maintainer);
        s.proposeSplit(_newSplit());
        vm.warp(block.timestamp + 1 days);
        s.proposeSplit(_newSplit());
        vm.stopPrank();
        assertEq(s.pendingActivatesAt(), block.timestamp + DELAY);
    }

    function test_freeze_locksSplitForever() public {
        vm.startPrank(maintainer);
        s.proposeSplit(_newSplit());
        s.freezeSplit();
        assertTrue(s.splitFrozen());
        assertEq(s.pendingActivatesAt(), 0);
        vm.expectRevert(UpstreamSplitter.SplitIsFrozen.selector);
        s.proposeSplit(_newSplit());
        vm.expectRevert(UpstreamSplitter.SplitIsFrozen.selector);
        s.freezeSplit();
        vm.stopPrank();
        vm.expectRevert(UpstreamSplitter.NoPendingSplit.selector);
        s.activateSplit();
    }

    function test_ownership_twoStep() public {
        vm.prank(maintainer);
        s.transferOwnership(alice);
        assertEq(s.owner(), maintainer); // not yet
        vm.prank(alice);
        s.acceptOwnership();
        assertEq(s.owner(), alice);
    }

    // ------------------------------------------------------------------ the core promise

    /// @dev The owner role can do everything it is allowed to do, and no recipient loses a wei or
    ///      the contract loses solvency.
    function test_ownerCannotTouchFunds() public {
        _fund(10 ether);
        uint256 contractBefore = address(s).balance;
        uint256 ownerBefore = maintainer.balance;

        vm.startPrank(maintainer);
        s.proposeSplit(_newSplit());
        s.cancelSplitProposal();
        s.proposeSplit(_newSplit());
        s.freezeSplit();
        s.transferOwnership(alice);
        vm.stopPrank();
        vm.prank(alice);
        s.acceptOwnership();

        assertEq(address(s).balance, contractBefore);
        assertEq(maintainer.balance, ownerBefore);
        assertEq(s.owed(alice), 2 ether);
        assertEq(s.owed(bob), 1 ether);
        assertEq(s.owed(libA), 2 ether);
        assertEq(s.owed(libB), 1 ether);
        assertEq(s.owed(maintainer), 4 ether);
    }

    /// @dev Everyone can fully drain exactly what they are owed and the contract ends at zero.
    function test_everyoneWithdraws_contractEndsAtZero() public {
        _fund(10 ether + 7 wei);
        address[5] memory all = [maintainer, alice, bob, libA, libB];
        for (uint256 i; i < all.length; ++i) {
            if (s.owed(all[i]) > 0) {
                vm.prank(all[i]);
                s.withdraw();
            }
        }
        assertEq(address(s).balance, 0);
        assertEq(s.outstanding(), 0);
        assertEq(s.totalWithdrawn(), s.totalCredited());
    }

    // ------------------------------------------------------------------ review fixes

    function test_renounceOwnership_isDisabled() public {
        vm.prank(maintainer);
        vm.expectRevert(UpstreamSplitter.RenounceDisabled.selector);
        s.renounceOwnership();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        s.renounceOwnership();
        assertEq(s.owner(), maintainer);
    }

    function test_strayEth_isSplitByTheSplitInForceWhenItArrived() public {
        // 1 ETH is forced in under the old split. The owner then pushes a 100%-to-self split.
        ForceSender f = new ForceSender();
        vm.deal(address(f), 1 ether);
        f.boom(payable(address(s)));

        UpstreamSplitter.Share[] memory greedy = new UpstreamSplitter.Share[](1);
        greedy[0] = _share(maintainer, 10_000, "greedy");
        vm.prank(maintainer);
        s.proposeSplit(greedy);
        vm.warp(block.timestamp + DELAY);

        s.activateSplit(); // settles the stray ETH under the OLD split first
        assertEq(s.owed(maintainer), 0.4 ether);
        assertEq(s.owed(alice), 0.2 ether);
        assertEq(s.owed(libB), 0.1 ether);
        assertEq(s.unaccounted(), 0);
        vm.expectRevert(UpstreamSplitter.ZeroValue.selector);
        s.sync();
    }

    function test_activate_withNoStrayEth_stillWorks() public {
        vm.prank(maintainer);
        s.proposeSplit(_newSplit());
        vm.warp(block.timestamp + DELAY);
        s.activateSplit();
        assertEq(s.splitVersion(), 2);
        assertEq(s.totalCredited(), 0);
    }

    function test_fundWithVersion_protectsAgainstSplitSwap() public {
        vm.prank(maintainer);
        s.proposeSplit(_newSplit());
        vm.warp(block.timestamp + DELAY);
        s.activateSplit(); // version is now 2; the sponsor signed against version 1

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(UpstreamSplitter.WrongSplitVersion.selector, 1, 2));
        s.fundWithVersion{value: 1 ether}(1);

        vm.prank(sponsor);
        s.fundWithVersion{value: 1 ether}(2);
        assertEq(s.owed(libA), 0.1 ether);
        assertEq(s.totalCredited(), 1 ether);
    }

    function test_fundWithVersion_zeroValueReverts() public {
        vm.prank(sponsor);
        vm.expectRevert(UpstreamSplitter.ZeroValue.selector);
        s.fundWithVersion{value: 0}(1);
    }
}
