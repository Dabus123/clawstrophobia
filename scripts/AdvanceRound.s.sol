// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/ClawstrophobiaGame.sol";

contract AdvanceRoundScript is Script {
    function run() external {
        address gameAddr = vm.envAddress("GAME_ADDRESS");
        uint256 keeperKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(keeperKey);
        ClawstrophobiaGame game = ClawstrophobiaGame(payable(gameAddr));
        game.advanceRound();
        vm.stopBroadcast();
        console.log("Round advanced");
    }
}
