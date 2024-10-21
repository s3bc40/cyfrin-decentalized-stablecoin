// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    string public constant NAME = "Decentralized Stable Coin";
    string public constant SYMBOL = "DSC";
    address public OWNER = makeAddr("owner");
    uint256 public constant DSC_MINTED = 10;

    DecentralizedStableCoin dsc;

    function setUp() public {
        vm.startBroadcast(OWNER);
        dsc = new DecentralizedStableCoin();
        vm.stopBroadcast();
    }

    /*===============================================
                     Initialization          
    ===============================================*/
    function testDSCName() public view {
        // Arrange / Act
        string memory name = dsc.name();
        string memory symbol = dsc.symbol();
        // Assert
        assertEq(keccak256(abi.encodePacked(NAME)), keccak256(abi.encodePacked(name)));
        assertEq(keccak256(abi.encodePacked(SYMBOL)), keccak256(abi.encodePacked(symbol)));
    }

    /*===============================================
                     Mint          
    ===============================================*/
    function testMintShouldRevertIfNotOwner() public {
        // Arrange
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        // Act / Assert
        vm.expectRevert();
        dsc.mint(notOwner, 1);
    }

    function testMintShouldRevertIfZeroAddress() public {
        // Arrange
        vm.prank(OWNER);
        // Act / Assert
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), DSC_MINTED);
    }

    function testMintShouldRevertIfAmountIsZero() public {
        // Arrange
        vm.prank(OWNER);
        // Act / Assert
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(OWNER, 0);
    }

    function testMintDscSuccess() public {
        // Arrange
        vm.prank(OWNER);
        // Act
        bool success = dsc.mint(OWNER, DSC_MINTED);
        // Assert
        assertTrue(success);
        assertEq(dsc.balanceOf(OWNER), DSC_MINTED);
    }

    /*===============================================
                     Burn          
    ===============================================*/
    function testBurnShouldRevertIfNotOwner() public {
        // Arrange
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        // Act / Assert
        vm.expectRevert();
        dsc.burn(1);
    }

    function testBurnShouldRevertIfAmountIsZero() public {
        // Arrange
        vm.prank(OWNER);
        // Act / Assert
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testBurnShouldRevertIfAmountExceedsBalance() public {
        // Arrange
        vm.startPrank(OWNER);
        dsc.mint(OWNER, DSC_MINTED); // Mint some DSC to the owner first
        uint256 burnAmount = DSC_MINTED + 1; // Trying to burn more than the balance

        // Act / Assert
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(burnAmount);
        vm.stopPrank();
    }

    function testBurnSuccess() public {
        // Arrange
        vm.startPrank(OWNER);
        dsc.mint(OWNER, DSC_MINTED); // Mint some DSC to the owner first
        uint256 initialBalance = dsc.balanceOf(OWNER);

        // Act
        dsc.burn(DSC_MINTED); // Burn the exact amount minted
        vm.stopPrank();

        // Assert
        assertEq(dsc.balanceOf(OWNER), initialBalance - DSC_MINTED);
    }
}
