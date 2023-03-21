// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FirstCoin is ERC20 {
    constructor() ERC20("FirstCoin", "FIRST") {
        _mint(msg.sender, 1000000000);
    }
}