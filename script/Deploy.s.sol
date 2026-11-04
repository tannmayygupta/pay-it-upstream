// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UpstreamSplitter} from "../src/UpstreamSplitter.sol";

/// @notice Deploys one UpstreamSplitter for one project.
///
/// Required env:
///   PROJECT_NAME        e.g. "tiny-lib"
///   MAINTAINER          address that may propose split changes (holds no power over funds)
///   SPLIT_DELAY         seconds a change must be public before it can activate (3600..2592000)
///   RECIPIENTS          comma-free list is awkward in env, so we read numbered entries:
///   R0_ADDR, R0_BPS, R0_LABEL, R1_ADDR, R1_BPS, R1_LABEL, ... up to R29_*
/// Stops at the first missing R<i>_ADDR. BPS must sum to 10000 (the contract enforces it).
///
/// Usage:
///   forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
contract Deploy is Script {
    function run() external returns (UpstreamSplitter splitter) {
        string memory name = vm.envString("PROJECT_NAME");
        address maintainer = vm.envAddress("MAINTAINER");
        uint256 delay = vm.envOr("SPLIT_DELAY", uint256(2 days));

        UpstreamSplitter.Share[] memory tmp = new UpstreamSplitter.Share[](30);
        uint256 n;
        for (uint256 i; i < 30; ++i) {
            string memory k = vm.toString(i);
            string memory addrKey = string.concat("R", k, "_ADDR");
            if (!vm.envExists(addrKey)) break;
            tmp[i] = UpstreamSplitter.Share({
                account: vm.envAddress(addrKey),
                bps: uint16(vm.envUint(string.concat("R", k, "_BPS"))),
                label: vm.envString(string.concat("R", k, "_LABEL"))
            });
            ++n;
        }
        UpstreamSplitter.Share[] memory shares = new UpstreamSplitter.Share[](n);
        for (uint256 i; i < n; ++i) {
            shares[i] = tmp[i];
        }

        vm.startBroadcast();
        splitter = new UpstreamSplitter(name, maintainer, shares, delay);
        vm.stopBroadcast();

        console.log("UpstreamSplitter deployed at:", address(splitter));
        console.log("Project:", name);
        console.log("Recipients:", n);
    }
}
