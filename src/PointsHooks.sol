// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {Currency} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";

contract PointsHooks is BaseHook, ERC1155 {

    uint256 constant POINTS_PER_ETH = 0.2 ether;

    constructor (address _poolManager) BaseHook(IPoolManager(_poolManager)) {

    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    /**
     * when we get a our _sender this isn't actually the EOA
     * | EOA -> Router | -> Uniswap -> Hook (multiple times)
     * 
     * msg.sender is Uniswap
     * tx.origin is EOA
     * _sender is Router
     */
    function _afterSwap(address _sender, PoolKey calldata _poolKey, SwapParams calldata _swapParams, BalanceDelta _delta, bytes calldata _hookData)
        internal
        virtual
        override
        returns (bytes4, int128)
    {
        // make sure this is an eth <> token pool
        if(!_poolKey.currency0.isAddressZero()) {
            return (this.afterSwap.selector, 0);
        }

        // make sure the swap is to BUT TOKEN in exchange for the
        // we know that eth is currecy0
        // in swap params we have the attrubuted `zeroForOne`
        if(!_swapParams.zeroForOne) {
            return (this.afterSwap.selector, 0);
        }


        // mint points equal to 20% of the amount of ETH being swapped in
        // sine its is a zwroForOne swap
        // if amountSpecified < 0;
        //     "exact input for output" swap
        //     amount of ETH that spent is equal to `amountSpecified`
        //     This should be the same amount as e-delta.amount0()
        // If amountSpecified > 0;
        //     "exact output for input" swap
        //     amount of ETH that spent is equal to BalanceDelta.amount0()
        uint256 ethSpendAmount = uint256(int256(-_delta.amount0()));
        uint256 pointsForSwap = (ethSpendAmount * POINTS_PER_ETH) / 1 ether;

        // Assign the points to the user
        _assignPoints(_poolKey.toId(), _hookData, pointsForSwap);

        // return our selector        
        return (this.afterSwap.selector, 0);
    }

    function _assignPoints(PoolId _poolId, bytes calldata _hookData, uint256 _points) internal {
        // Ensure that we have hooksData passed in, if missiong, no points
        if(_hookData.length == 0) return;

        // extract a user address from the hook Data
        address user = abi.decode(_hookData, (address));

        // If the user address is decoded as a zero address, no points,
        if (user == address(0)) return;

        // mint the points to the user
        uint256 poolIdUint = uint256(PoolId.unwrap(_poolId));
        _mint(user, poolIdUint, _points, '');
    }
    // Implement the ERC1155 `uri` function
    function uri(uint256 id) public view virtual override returns (string memory) {
        return string(abi.encodePacked("https://example.com/points/", Strings.toString(id)));
    }
}