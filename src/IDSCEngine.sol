// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

/**
 * @title IDSCEngine
 * @author s3bc40
 * Interface implementation of DSCEngine to be sure of what function we need to implement
 *
 * - Deposit collateral and mint the `DSC` token
 * This is how users acquire the stablecoin, they deposit collateral greater than the value of the `DSC` minted
 *
 * - Redeem their collateral for `DSC`
 * Users will need to be able to return DSC to the protocol in exchange for their underlying collateral
 *
 * - Burn `DSC`
 * If the value of a user's collateral quickly falls, users will need a way to quickly rectify the collateralization of their `DSC`.
 *
 * - The ability to `liquidate` an account
 * Because our protocol must always be over-collateralized (more collateral must be deposited then `DSC` is minted), if a user's collateral value falls below what's required to support their minted `DSC`, they can be `liquidated`. Liquidation allows other users to close an under-collateralized position
 *
 * - View an account's `healthFactor`
 * `healthFactor` will be defined as a certain ratio of collateralization a user has for the DSC they've minted. As the value of a user's collateral falls, as will their `healthFactor`, if no changes to `DSC` held are made. If a user's `healthFactor` falls below a defined threshold, the user will be at risk of liquidation.
 * eg. If the threshold to `liquidate` is 150% collateralization, an account with $75 in ETH can support $50 in `DSC`. If the value of ETH falls to \$74, the `healthFactor` is broken and the account can be `liquidated`
 */
interface IDSCEngine {
    function depositCollateralAndMintDsc() external;

    function depositCollateral() external;

    function redeemCollateralForDsc() external;

    function redeemCollateral() external;

    function mintDsc(uint256 _amount) external;

    function burnDsc() external;

    function liquidate() external;

    function getHealthFactor() external view;
}
