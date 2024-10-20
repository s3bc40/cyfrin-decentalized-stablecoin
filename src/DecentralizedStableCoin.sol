/*
    Contract elements should be laid out in the following order:
        Pragma statements
        Import statements
        Events
        Errors
        Interfaces
        Libraries
        Contracts
    Inside each contract, library or interface, use the following order:
        Type declarations
        State variables
        Events
        Errors
        Modifiers
        Functions
 */

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author s3bc40
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stabiity: Pegged to USD
 *
 * Contract meant to be governed by DSCEngine. ERC20 implementation of our stablecoin
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn (uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        // WIP 10:57
    }
}
