// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ClawstrophobiaToken
 * @dev ERC20 token for Clawstrophobia game entry (10_000 per join).
 */
contract ClawstrophobiaToken is ERC20, Ownable {
    uint256 public constant ENTRY_COST = 10_000 * 1e18;

    constructor() ERC20("Clawstrophobia", "CLAW") Ownable(msg.sender) {
        // Mint initial supply to owner for testing / distribution
        _mint(msg.sender, 1_000_000 * 1e18);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
