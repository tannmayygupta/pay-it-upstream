// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {UpstreamSplitter} from "../src/UpstreamSplitter.sol";

/// @notice Property tests: for ANY valid split and ANY amount, the money maths holds.
contract FuzzTest is Test {
    address internal maintainer = makeAddr("maintainer");
    address internal sponsor = makeAddr("sponsor");

    /// Build a random valid split of n recipients from a seed.
    function _randomSplit(uint256 seed, uint256 n) internal pure returns (UpstreamSplitter.Share[] memory sh) {
        sh = new UpstreamSplitter.Share[](n);
        uint256 remaining = 10_000;
        for (uint256 i; i < n; ++i) {
            uint256 left = n - i - 1; // recipients still to place after this one
            uint256 bps;
            if (left == 0) {
                bps = remaining;
            } else {
                uint256 maxHere = remaining - left; // leave >=1 bps for each later recipient
                bps = 1 + (uint256(keccak256(abi.encode(seed, i))) % maxHere);
            }
            remaining -= bps;
            sh[i] = UpstreamSplitter.Share(address(uint160(0x1000 + i)), uint16(bps), "r");
        }
    }

    /// credited == deposited, to the wei, for every split and amount.
    function testFuzz_conservation(uint256 seed, uint8 nRaw, uint96 amount) public {
        uint256 n = bound(nRaw, 1, 30);
        amount = uint96(bound(amount, 1, type(uint96).max));
        UpstreamSplitter s = new UpstreamSplitter("f", maintainer, _randomSplit(seed, n), 1 days);
        vm.deal(sponsor, amount);
        vm.prank(sponsor);
        (bool ok,) = address(s).call{value: amount}("");
        assertTrue(ok);

        uint256 sum;
        for (uint256 i; i < n; ++i) {
            sum += s.owed(address(uint160(0x1000 + i)));
        }
        assertEq(sum, amount, "sum of balances must equal deposit");
        assertEq(s.totalCredited(), amount);
        assertEq(address(s).balance, amount);
    }

    /// No recipient except the last can ever receive more than their exact proportional floor,
    /// and the last receives at most (n-1) wei above their proportional share (the dust bound).
    function testFuzz_dustIsBounded(uint256 seed, uint8 nRaw, uint96 amount) public {
        uint256 n = bound(nRaw, 1, 30);
        amount = uint96(bound(amount, 1, type(uint96).max));
        UpstreamSplitter.Share[] memory sh = _randomSplit(seed, n);
        UpstreamSplitter s = new UpstreamSplitter("f", maintainer, sh, 1 days);
        vm.deal(sponsor, amount);
        vm.prank(sponsor);
        (bool ok,) = address(s).call{value: amount}("");
        assertTrue(ok);

        for (uint256 i; i < n; ++i) {
            uint256 exactFloor = (uint256(amount) * sh[i].bps) / 10_000;
            uint256 got = s.owed(sh[i].account);
            if (i + 1 < n) {
                assertEq(got, exactFloor);
            } else {
                assertGe(got, exactFloor);
                assertLe(got - exactFloor, n - 1, "dust must be < n wei");
            }
        }
    }

    /// Many deposits then everyone withdraws: nobody is short, nothing is left behind.
    function testFuzz_depositsThenAllWithdraw(uint256 seed, uint8 nRaw, uint64[5] memory amounts) public {
        uint256 n = bound(nRaw, 1, 30);
        UpstreamSplitter s = new UpstreamSplitter("f", maintainer, _randomSplit(seed, n), 1 days);
        uint256 total;
        for (uint256 k; k < 5; ++k) {
            uint256 a = bound(amounts[k], 1, type(uint64).max);
            total += a;
            vm.deal(sponsor, a);
            vm.prank(sponsor);
            (bool ok,) = address(s).call{value: a}("");
            assertTrue(ok);
        }
        for (uint256 i; i < n; ++i) {
            address acct = address(uint160(0x1000 + i));
            if (s.owed(acct) > 0) {
                vm.prank(acct);
                s.withdraw();
            }
        }
        assertEq(address(s).balance, 0);
        assertEq(s.totalWithdrawn(), total);
    }

    /// Any split whose bps do not sum to 10_000 is rejected.
    function testFuzz_badSumRejected(uint16 a, uint16 b) public {
        vm.assume(uint256(a) + uint256(b) != 10_000);
        vm.assume(a > 0 && b > 0);
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = UpstreamSplitter.Share(address(0xA1), a, "");
        sh[1] = UpstreamSplitter.Share(address(0xA2), b, "");
        vm.expectRevert();
        new UpstreamSplitter("f", maintainer, sh, 1 days);
    }

    /// A stranger can never reduce, or withdraw, someone else's balance.
    function testFuzz_strangerCannotTouchOthers(uint96 amount, address stranger) public {
        amount = uint96(bound(amount, 1, type(uint96).max));
        UpstreamSplitter.Share[] memory sh = new UpstreamSplitter.Share[](2);
        sh[0] = UpstreamSplitter.Share(address(0xA1), 3000, "");
        sh[1] = UpstreamSplitter.Share(address(0xA2), 7000, "");
        UpstreamSplitter s = new UpstreamSplitter("f", maintainer, sh, 1 days);
        vm.assume(stranger != address(0xA1) && stranger != address(0xA2));
        vm.deal(sponsor, amount);
        vm.prank(sponsor);
        (bool ok,) = address(s).call{value: amount}("");
        assertTrue(ok);
        uint256 a1 = s.owed(address(0xA1));
        uint256 a2 = s.owed(address(0xA2));
        vm.prank(stranger);
        vm.expectRevert(UpstreamSplitter.NothingToWithdraw.selector);
        s.withdraw();
        assertEq(s.owed(address(0xA1)), a1);
        assertEq(s.owed(address(0xA2)), a2);
    }
}
