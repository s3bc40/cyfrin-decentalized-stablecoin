// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

// Mock ERC20 that always fails on transferFrom
contract MockERC20FailingTransfer is ERC20Mock {
    constructor(string memory name, string memory symbol, address initialAccount, uint256 initialBalance)
        ERC20Mock(name, symbol, initialAccount, initialBalance)
    {}

    // Override transferFrom to return false (simulate failure)
    function transfer(address, uint256) public pure override returns (bool) {
        return false; // Simulate transfer failure
    }
}
