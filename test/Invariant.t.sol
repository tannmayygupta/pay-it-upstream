// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {UpstreamSplitter} from "../src/UpstreamSplitter.sol";
import {ForceSender} from "./helpers/Actors.sol";

/// @dev Random walk over everything a sponsor, recipient, stranger or the OWNER can do.
///      The owner is part of the walk on purpose: the invariants must hold even when the
///      maintainer misbehaves as much as the contract lets them.
contract Handler is Test {
    UpstreamSplitter public immutable s;
    address public immutable owner_;
    address[] public actors;

    uint256 public ghostFunded; // ETH sent through receive/fund
    uint256 public ghostForced; // ETH forced in by selfdestruct
    uint256 public ghostSynced; // forced ETH that was later credited
    uint256 public ghostWithdrawn;
    mapping(address => uint256) public ghostWithdrawnBy;

    constructor(UpstreamSplitter s_, address owner__, address[] memory actors_) {
        s = s_;
        owner_ = owner__;
        actors = actors_;
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function fund(uint96 amount, uint8 who) external {
        amount = uint96(bound(amount, 1, 1000 ether));
        address from = actors[who % actors.length];
        vm.deal(from, amount);
        vm.prank(from);
        (bool ok,) = address(s).call{value: amount}("");
        require(ok);
        ghostFunded += amount;
    }

    function force(uint96 amount) external {
        amount = uint96(bound(amount, 1, 100 ether));
        ForceSender f = new ForceSender();
        vm.deal(address(f), amount);
        f.boom(payable(address(s)));
        ghostForced += amount;
    }

    function sync() external {
        uint256 before_ = s.totalCredited();
        vm.prank(actors[0]);
        try s.sync() {
            ghostSynced += s.totalCredited() - before_;
        } catch {}
    }

    function withdraw(uint8 who) external {
        address a = actors[who % actors.length];
        uint256 amt = s.owed(a);
        vm.prank(a);
        try s.withdraw() {
            ghostWithdrawn += amt;
            ghostWithdrawnBy[a] += amt;
        } catch {}
    }

    function withdrawTo(uint8 who, address to) external {
        if (to == address(0) || to == address(s)) return;
        address a = actors[who % actors.length];
        uint256 amt = s.owed(a);
        vm.prank(a);
        try s.withdrawTo(to) {
            ghostWithdrawn += amt;
            ghostWithdrawnBy[a] += amt;
        } catch {}
    }

    // ---- owner actions: every power the maintainer has, fuzzed

    function ownerPropose(uint256 seed, uint8 nRaw) external {
        uint256 n = bound(nRaw, 1, actors.length);
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](n);
        uint256 remaining = 10_000;
        for (uint256 i; i < n; ++i) {
            uint256 left = n - i - 1;
            uint256 bps = left == 0 ? remaining : 1 + (uint256(keccak256(abi.encode(seed, i))) % (remaining - left));
            remaining -= bps;
            sh[i] = UpstreamSplitter.Share(actors[i], uint16(bps), "x");
        }
        vm.prank(owner_);
        try s.proposeSplit(sh) {} catch {}
    }

    function ownerCancel() external {
        vm.prank(owner_);
        try s.cancelSplitProposal() {} catch {}
    }

    function ownerFreeze(uint8 coin) external {
        if (coin % 16 != 0) return; // freeze rarely so the walk stays interesting
        vm.prank(owner_);
        try s.freezeSplit() {} catch {}
    }

    function activate() external {
        uint256 before_ = s.totalCredited();
        try s.activateSplit() {
            // activation settles any stray ETH under the old split
            ghostSynced += s.totalCredited() - before_;
        } catch {}
    }

    function warp(uint32 secs) external {
        vm.warp(block.timestamp + bound(secs, 0, 5 days));
    }
}

contract InvariantTest is StdInvariant, Test {
    UpstreamSplitter internal s;
    Handler internal h;
    address internal maintainer = makeAddr("maintainer");

    function setUp() public {
        address[] memory actors = new address[](6);
        actors[0] = maintainer;
        for (uint256 i = 1; i < 6; ++i) {
            actors[i] = address(uint160(0x2000 + i));
        }
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](4);
        sh[0] = UpstreamSplitter.Share(actors[0], 4000, "m");
        sh[1] = UpstreamSplitter.Share(actors[1], 3000, "a");
        sh[2] = UpstreamSplitter.Share(actors[2], 2000, "b");
        sh[3] = UpstreamSplitter.Share(actors[3], 1000, "c");
        s = new UpstreamSplitter("inv", maintainer, sh, 1 days);
        h = new Handler(s, maintainer, actors);
        targetContract(address(h));
    }

    /// The contract can always pay everyone it owes.
    function invariant_solvent() public view {
        assertGe(address(s).balance, s.outstanding());
    }

    /// Money in minus money out is exactly what the contract holds.
    function invariant_balanceMatchesFlows() public view {
        assertEq(address(s).balance, h.ghostFunded() + h.ghostForced() - h.ghostWithdrawn());
    }

    /// Every wei credited was either deposited or synced from stray ETH: nothing created, nothing lost.
    function invariant_creditedEqualsDepositedPlusSynced() public view {
        assertEq(s.totalCredited(), h.ghostFunded() + h.ghostSynced());
    }

    /// Stray ETH is exactly the forced ETH that has not been synced.
    function invariant_unaccountedIsUnsyncedForced() public view {
        assertEq(s.unaccounted(), h.ghostForced() - h.ghostSynced());
    }

    /// Sum of individual balances is exactly the outstanding total.
    function invariant_sumOfBalancesEqualsOutstanding() public view {
        uint256 sum;
        for (uint256 i; i < h.actorsLength(); ++i) {
            sum += s.owed(h.actors(i));
        }
        assertEq(sum, s.outstanding());
    }

    /// Nobody ever withdrew more than they were credited.
    function invariant_noOneTookMoreThanTheyEarned() public view {
        for (uint256 i; i < h.actorsLength(); ++i) {
            address a = h.actors(i);
            assertLe(h.ghostWithdrawnBy(a), s.totalEarned(a));
            assertEq(s.totalEarned(a), s.owed(a) + h.ghostWithdrawnBy(a));
        }
    }

    /// The active split is always valid: sums to 10_000.
    function invariant_splitAlwaysSumsTo10000() public view {
        UpstreamSplitter.Share[] memory sh = s.getSplit();
        uint256 sum;
        for (uint256 i; i < sh.length; ++i) {
            sum += sh[i].bps;
        }
        assertEq(sum, 10_000);
    }
}
