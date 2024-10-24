// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {MockERC20FailingTransfer} from "test/mocks/MockERC20FailingTransfer.sol";
import {MockERC20FailingTransferFrom} from "test/mocks/MockERC20FailingTransferFrom.sol";
import {MockDSCFailingMint} from "test/mocks/MockDSCFailingMint.sol";
import {MockDSCFailingTransferFrom} from "test/mocks/MockDSCFailingTransferFrom.sol";

contract DeployDSCEngine is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    address public USER = makeAddr("USER");
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_REDEEMED_COLLATERAL = 2 ether;
    uint256 public constant AMOUNT_DSC_MINTED = 100 ether;
    uint256 public constant AMOUNT_DSC_TO_BURN = 50 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 private constant PRECISION = 1e18;

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mintDsc() {
        vm.prank(USER);
        engine.mintDsc(AMOUNT_DSC_MINTED);
        _;
    }

    modifier burnDsc() {
        vm.startPrank(USER);
        /*
            Need to approve DSCEngine to spend DSC on behalf of USER
            from DSC
        */
        dsc.approve(address(engine), AMOUNT_DSC_TO_BURN);
        engine.burnDsc(AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    /*===============================================
                    Constructor test          
    ===============================================*/

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedsLengthsMustMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*===============================================
                     Price Tests          
    ===============================================*/
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    /*===============================================
                    Deposit Collateral          
    ===============================================*/
    function testDepositCollateralRevertIfZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositCollateralRevertOnFailedTransfer() public {
        // Deploy the failing mock token
        MockERC20FailingTransferFrom mockFailingToken =
            new MockERC20FailingTransferFrom("WETH", "WETH", msg.sender, 1000e8);
        tokenAddresses.push(address(mockFailingToken));
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine failedEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        ERC20Mock(address(mockFailingToken)).mint(USER, STARTING_ERC20_BALANCE);

        vm.startPrank(USER);
        // Approve the DSCEngine to transfer tokens on behalf of the user
        mockFailingToken.approve(address(failedEngine), AMOUNT_COLLATERAL);
        // Expect the DSCEngine to revert with TransferFailed error
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        // Try depositing collateral with the failing token
        failedEngine.depositCollateral(address(mockFailingToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // Challenge: get DSCEngine coverage up to 85%

    /*===============================================
                     Health Factor         
    ===============================================*/
    function testHealthFactorWithNoDscMinted() public depositCollateral {
        vm.startPrank(USER);
        uint256 healthFactor = engine.getHealthFactor(USER);
        assertEq(healthFactor, engine.getMinHealthFactor());
        vm.stopPrank();
    }

    /*===============================================
                     Mint DSC          
    ===============================================*/
    function testMintDscRevertIfHealthFactorBroken() public {
        uint256 expectedHealthFactor = 0;

        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMintDscAfterDepositCollateralSuccess() public depositCollateral {
        vm.prank(USER);
        engine.mintDsc(AMOUNT_DSC_MINTED);
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, AMOUNT_DSC_MINTED);
    }

    function testMintDscRevertsOnMintFailure() public {
        // Deploy the mock DSC contract with a failing mint function
        MockDSCFailingMint failingDSC = new MockDSCFailingMint();
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        // Replace the DSC contract in the DSCEngine with the failing mock
        DSCEngine failedEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(failingDSC)); // Use mock DSC
        // Change ownership as the deployer script does
        failingDSC.transferOwnership(address(failedEngine));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(failedEngine), AMOUNT_COLLATERAL);
        failedEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        // Attempt to mint DSC and expect the DSCEngine to revert with MintFailed error
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        failedEngine.mintDsc(AMOUNT_DSC_MINTED);
        vm.stopPrank();
    }

    /*===============================================
                     Burn DSC          
    ===============================================*/
    function testBurnDscIsSuccessful() public depositCollateral mintDsc {
        uint256 dscToBurn = 10 ether;
        uint256 expectedDscAmount = AMOUNT_DSC_MINTED - dscToBurn;

        vm.startPrank(USER);
        /*
            Need to approve DSCEngine to spend DSC on behalf of USER
            from DSC
        */
        dsc.approve(address(engine), dscToBurn);
        engine.burnDsc(dscToBurn);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, expectedDscAmount);
    }

    function testBurnDscRevertsOnTransferFromFailure() public {
        // Deploy the mock DSC contract with a failing mint function
        MockDSCFailingTransferFrom failingDSC = new MockDSCFailingTransferFrom();
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        // Replace the DSC contract in the DSCEngine with the failing mock
        DSCEngine failedEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(failingDSC)); // Use mock DSC
        // Change ownership as the deployer script does
        failingDSC.transferOwnership(address(failedEngine));

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(failedEngine), AMOUNT_COLLATERAL);
        failedEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        failedEngine.mintDsc(AMOUNT_DSC_MINTED);

        // Attempt to burn DSC and expect the DSCEngine to revert with Tranfer failed error
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        failedEngine.burnDsc(AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
    }

    /*===============================================
                    Redeem Collateral          
    ===============================================*/
    function testRedeemCollateralRevertIfZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralBreakHealthFactor() public depositCollateral mintDsc {
        uint256 expectedHealthFactor = 0;
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
    }

    function testRedeemCollateralIsASuccess() public depositCollateral mintDsc burnDsc {
        vm.prank(USER);
        engine.redeemCollateral(weth, AMOUNT_REDEEMED_COLLATERAL);

        (, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(AMOUNT_COLLATERAL - AMOUNT_REDEEMED_COLLATERAL, expectedDepositAmount);
    }

    function testRedeemCollateralRevertOnFailedTransfer() public {
        // Deploy the failing mock token
        MockERC20FailingTransfer mockFailingToken = new MockERC20FailingTransfer("WETH", "WETH", msg.sender, 1000e8);
        tokenAddresses.push(address(mockFailingToken));
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine failedEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        // Change ownership as the deployer script does
        vm.prank(address(engine));
        dsc.transferOwnership(address(failedEngine));
        ERC20Mock(address(mockFailingToken)).mint(USER, STARTING_ERC20_BALANCE);

        vm.startPrank(USER);
        // Approve the DSCEngine to transfer tokens on behalf of the user
        mockFailingToken.approve(address(failedEngine), AMOUNT_COLLATERAL);
        // Depositing collateral and minting with the failing token
        failedEngine.depositCollateral(address(mockFailingToken), AMOUNT_COLLATERAL);
        failedEngine.mintDsc(AMOUNT_DSC_MINTED);
        // Expect the DSCEngine to revert with TransferFailed error
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        failedEngine.redeemCollateral(address(mockFailingToken), AMOUNT_REDEEMED_COLLATERAL);
        vm.stopPrank();
    }

    /*===============================================
                     Liquidate          
    ===============================================*/
    function testLiquidateRevertIfAtStartHealthFactorIsOk() public depositCollateral mintDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testSuccessfulLiquidation() public depositCollateral mintDsc {
        // Init Liquidator
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();
        // Deploy and set up mock aggregator with an initial price
        MockV3Aggregator mockAggregator = MockV3Aggregator(ethUsdPriceFeed); // 200 * 10^8
        mockAggregator.updateAnswer(20e8);
        // Price of the collateral drops, decreasing the health factor
        uint256 debtToCover = 5 ether;

        // Now LIQUIDATOR attempts to liquidate USER
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(engine), debtToCover);
        engine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();

        // Assertions
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        uint256 liquidatedCollateral = engine.getTokenAmountFromUsd(weth, debtToCover);
        // Check the user's DSC debt was reduced
        assertEq(totalDscMinted, AMOUNT_DSC_MINTED - debtToCover);
        // Check the collateral was transferred
        assertEq(
            ERC20Mock(weth).balanceOf(LIQUIDATOR),
            liquidatedCollateral
                + (liquidatedCollateral * engine.getLiquidationBonus()) / engine.getLiquidationPrecision()
        );
    }

    function testLiquidationDoesNotImproveHealthFactor() public depositCollateral mintDsc {
        // Init Liquidator
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();
        // Deploy and set up mock aggregator with an initial price
        MockV3Aggregator mockAggregator = MockV3Aggregator(ethUsdPriceFeed); // 200 * 10^8
        mockAggregator.updateAnswer(10e8);
        // Price of the collateral drops, decreasing the health factor
        uint256 debtToCover = 10 ether;

        // Now LIQUIDATOR attempts to liquidate USER
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(engine), debtToCover);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        engine.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
    }

    /*===============================================
                    Deposit and Mint          
    ===============================================*/
    function testDepositCollateralAndMintDscWithEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, AMOUNT_DSC_MINTED);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /*===============================================
                Redeem Collateral For Dsc      
    ===============================================*/
    function testRedeemCollateralForDsc() public depositCollateral mintDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositAmount, 0);
    }

    /*===============================================
                Account Collateral Value          
    ===============================================*/
    function testAccountCollateralValue() public depositCollateral mintDsc {
        (uint256 totalCollateralValueInUsd) = engine.getAccountCollateralValueInUsd(USER);
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, totalCollateralValueInUsd);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }
}
