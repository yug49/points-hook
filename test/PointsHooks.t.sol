// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Hooks} from "v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {Deployers} from "v4-periphery/lib/v4-core/test/utils/Deployers.sol";
import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PointsHooks} from "../src/PointsHooks.sol";
import {Currency, CurrencyLibrary} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "v4-periphery/lib/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolSwapTest} from "v4-periphery/lib/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import {PoolManager} from "v4-periphery/lib/v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {SqrtPriceMath} from "v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-periphery/lib/v4-core/src/types/PoolOperation.sol";


contract PointsHookTest is Test, Deployers, ERC1155TokenReceiver {
    // 0000 0000 0100 0000
    // deployCodeTo -- deploy a contract code to an arbitrary address
    uint160 constant POINTS_HOOK_FLAG = Hooks.AFTER_SWAP_FLAG;

    PointsHooks pointsHook;
    MockERC20 token;

    function setUp() public {
        address hookAddress = address(POINTS_HOOK_FLAG);
        console.log("Hooks address: ", hookAddress);

        // deploy the uniswap v4 pool manager
        // pool managaer - facilitates swap
        // swapRouter - facilitates swap
        // modifyPosionRouter - facilitate liquidity management
        deployFreshManagerAndRouters();
        // deploy the ERC20 Token contract
        token = new MockERC20("TOKEN", "TKN", 18);

        // Mint a bunch of tokens to test with
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);

        deployCodeTo('PointsHook.sol', abi.encode((address(manager)), hookAddress));
        pointsHook = PointsHooks(hookAddress);

        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // initialize the pool eth <> token
        (key, ) = initPool(
            Currency.wrap(address(0)),    // EthCurrency
            Currency.wrap(address(token)),  // TokenCurrency
            pointsHook,   // PointsHooks
            3000,   // 0.3% fee
            SQRT_PRICE_1_1  // Initial sqrt(p) = 1
        );

        // add liquidity to the pool
        uint256 ethToAdd = 0.003 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            sqrtPriceAtTickUpper,
            ethToAdd
        );
        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            liquidityDelta
        );

        modifyLiqudityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );


    }

    function test_swap() public {
        deal(address(token), address(this), 0);

        // pass in this testers address to be allocated our points
        bytes memory hookData = abi.encode(address(this));

        // call out swap router to make a 0.001 eth swap
        swapRouter.swap{value: 0.001 ether}({
            poolKey: poolKey,
            swapParamas: SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            testSettings: PoolSwapTest.TestSettings(false, false),
            hookData: hookData
        });

        // confirm my points balance
        assertEq(pointsHook.balanceOf(address(this)), 0.002 ether, 'Invalid user Points balance');

        // confirm my token holding
        assertEq(pointsHook.balanceOf(address(this)), 0 ether, 'User should have token');
    }
}