// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/ClawstrophobiaToken.sol";
import "../contracts/ClawstrophobiaGame.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ClawstrophobiaToken token = new ClawstrophobiaToken();
        address devAddress = vm.envOr("DEV_ADDRESS", address(0));
        ClawstrophobiaGame game = new ClawstrophobiaGame(address(token), devAddress != address(0) ? devAddress : msg.sender);

        vm.stopBroadcast();

        console.log("ClawstrophobiaToken:", address(token));
        console.log("ClawstrophobiaGame:", address(game));
    }
}
