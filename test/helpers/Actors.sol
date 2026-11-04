// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UpstreamSplitter} from "../../src/UpstreamSplitter.sol";

/// @dev Recipient whose receive() re-enters withdraw(). Used to prove the reentrancy guard and
///      that balances are zeroed before the external call.
contract ReentrantRecipient {
    UpstreamSplitter public immutable target;
    bool public reenterAttempted;
    bool public reenterSucceeded;

    constructor(UpstreamSplitter t) {
        target = t;
    }

    function attack() external {
        target.withdraw();
    }

    receive() external payable {
        reenterAttempted = true;
        try target.withdraw() {
            reenterSucceeded = true;
        } catch {}
    }
}

/// @dev Recipient that always reverts when paid. Proves one bad address blocks only itself.
contract RevertingRecipient {
    function pull(UpstreamSplitter t) external {
        t.withdraw();
    }

    receive() external payable {
        revert("no thanks");
    }
}

/// @dev Recipient that answers with a huge returndata blob (returnbomb). Withdrawal must still work
///      because the splitter ignores returndata.
contract ReturnBombRecipient {
    function pull(UpstreamSplitter t) external {
        t.withdraw();
    }

    fallback() external payable {
        assembly {
            return(0, 200000)
        }
    }
}

/// @dev Plain contract recipient that can receive ETH (for contract-wallet tests).
contract AcceptingRecipient {
    function pull(UpstreamSplitter t) external {
        t.withdraw();
    }

    receive() external payable {}
}

/// @dev Pushes ETH into any address without calling receive().
contract ForceSender {
    function boom(address payable target) external payable {
        selfdestruct(target);
    }
}

/// @dev Sponsor whose receive() would need more than 2300 gas; used with .call so it works.
contract Sponsor {
    function pay(address payable to) external payable {
        (bool ok,) = to.call{value: msg.value}("");
        require(ok, "pay failed");
    }
}
