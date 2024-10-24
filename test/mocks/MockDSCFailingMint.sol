// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockDSCFailingMint is ERC20Burnable, Ownable {
    constructor() ERC20("Failing Mint DSC", "FMD") {}

    function mint(address, uint256) external view onlyOwner returns (bool) {
        return false; // Always return false to simulate mint failure
    }
}
