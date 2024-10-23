// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DeployDSCEngine is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_REDEEMED_COLLATERAL = 2 ether;
    uint256 public constant AMOUNT_DSC_MINTED = 2;
    uint256 public constant AMOUNT_DSC_TO_BURN = 1;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

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
    }

    /*===============================================
                    Constructor test          
    ===============================================*/
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(ethUsdPriceFeed);
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

    // Challenge: get DSCEngine coverage up to 85%

    /*===============================================
                     Health Factor         
    ===============================================*/
    function testHealthFactorWithNoCollateralDepositedShouldBeZero() public {
        vm.startPrank(USER);
        uint256 healthFactor = engine.getHealthFactor(USER);
        assertEq(healthFactor, 0);
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

    /*===============================================
                     Burn DSC          
    ===============================================*/
    function testBurnDscRevertIfHealthFactorBroken() public depositCollateral mintDsc {
        uint256 expectedHealthFactor = 0;

        vm.startPrank(USER);
        /*
            Need to approve DSCEngine to spend DSC on behalf of USER
            from DSC
        */
        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.burnDsc(AMOUNT_DSC_MINTED);
        vm.stopPrank();
    }

    function testBurnDscIsSuccessful() public depositCollateral mintDsc {
        uint256 expectedDscAmount = 1;
        uint256 dscToBurn = 1;

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

    /*===============================================
                     Liquidate          
    ===============================================*/
    function testLiquidateRevertIfAtStartHealthFactorIsOk() public depositCollateral mintDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
}
