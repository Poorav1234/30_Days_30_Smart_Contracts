// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
    Advanced DEX Aggregator (UniswapV2-router compatible) — OpenZeppelin-based

    Advanced Features:
    - Router allowlist
    - Auto best-router selection using getAmountsOut (on-chain quoting)
    - Best split routing (tries multiple bps splits across top routers)
    - Fee-on-transfer token support (balance-diff)
    - Per-route and total slippage checks
    - Protocol fee (bps) on output
    - Pausable
    - Optional commit-reveal for MEV mitigation (basic)

    Notes:
    - Works with UniswapV2-like routers (swapExactTokensForTokens + getAmountsOut).
    - On-chain route search is intentionally bounded to keep gas reasonable.
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path)
        external
        view
        returns (uint[] memory amounts);
}

contract AdvancedDexAggregator is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // -------------------- Admin Controls --------------------
    mapping(address => bool) public isAllowedRouter;

    uint16 public protocolFeeBps;         // e.g. 30 = 0.30%
    address public feeRecipient;          // receives protocol fee
    uint16 public constant MAX_FEE_BPS = 200; // hard cap 2%

    event RouterAllowed(address indexed router, bool allowed);
    event FeeConfigUpdated(uint16 feeBps, address indexed recipient);

    event PausedBy(address indexed by);
    event UnpausedBy(address indexed by);

    // -------------------- Swap Events --------------------
    event SwapBestSingle(
        address indexed user,
        address indexed router,
        address tokenIn,
        address tokenOut,
        uint256 amountInActual,
        uint256 amountOut,
        uint256 feeTaken
    );

    event SwapBestSplit(
        address indexed user,
        address indexed routerA,
        address indexed routerB,
        address tokenIn,
        address tokenOut,
        uint256 amountInActual,
        uint256 amountOutTotal,
        uint256 outA,
        uint256 outB,
        uint256 splitBpsToA,
        uint256 feeTaken
    );

    // -------------------- Commit-Reveal (Basic) --------------------
    // commitment = keccak256(abi.encode(user, amountIn, minOut, routers[], path[], deadline, salt))
    mapping(address => bytes32) public commitOf;
    mapping(address => uint64) public commitBlock; // anti-same-block reveal (optional)
    event SwapCommitted(address indexed user, bytes32 commitment);
    event SwapCommitCleared(address indexed user);

    // -------------------- Stack-too-deep Fix Helpers --------------------
    struct TopTwo {
        address r1;
        uint256 o1;
        address r2;
        uint256 o2;
    }

    struct Decision {
        bool doSplit;
        address routerA;
        address routerB;
        uint16 splitBpsToA;
        uint256 bestOut;
    }

    // packs common execution params to reduce stack pressure
    struct ExecCtx {
        address tokenIn;
        address tokenOut;
        uint256 deadline;
        uint256 minOutTotal;
    }

    struct SplitOut {
        uint256 outA;
        uint256 outB;
        uint256 totalOut;
    }

    constructor(address[] memory initialRouters, address _feeRecipient, uint16 _feeBps) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "FEE_RECIPIENT_ZERO");
        require(_feeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");

        feeRecipient = _feeRecipient;
        protocolFeeBps = _feeBps;

        for (uint256 i = 0; i < initialRouters.length; i++) {
            isAllowedRouter[initialRouters[i]] = true;
            emit RouterAllowed(initialRouters[i], true);
        }
        emit FeeConfigUpdated(_feeBps, _feeRecipient);
    }

    // -------------------- Admin --------------------
    function setAllowedRouter(address router, bool allowed) external onlyOwner {
        isAllowedRouter[router] = allowed;
        emit RouterAllowed(router, allowed);
    }

    function setFeeConfig(address _recipient, uint16 _feeBps) external onlyOwner {
        require(_recipient != address(0), "FEE_RECIPIENT_ZERO");
        require(_feeBps <= MAX_FEE_BPS, "FEE_TOO_HIGH");
        feeRecipient = _recipient;
        protocolFeeBps = _feeBps;
        emit FeeConfigUpdated(_feeBps, _recipient);
    }

    function pause() external onlyOwner {
        _pause(); // OZ Pausable will emit Paused(msg.sender) internally
        emit PausedBy(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause(); // OZ Pausable will emit Unpaused(msg.sender) internally
        emit UnpausedBy(msg.sender);
    }

    // -------------------- Commit-Reveal --------------------
    function commitSwap(bytes32 commitment) external whenNotPaused {
        commitOf[msg.sender] = commitment;
        commitBlock[msg.sender] = uint64(block.number);
        emit SwapCommitted(msg.sender, commitment);
    }

    function clearCommit() external {
        delete commitOf[msg.sender];
        delete commitBlock[msg.sender];
        emit SwapCommitCleared(msg.sender);
    }

    // -------------------- View: Quote Best --------------------
    // Bounded search:
    // - routers length must be small (recommend <= 5)
    // - split candidates: 0, 25, 50, 75, 100 (in bps)
    function quoteBest(
        uint256 amountIn,
        address[] calldata routers,
        address[] calldata path
    )
        external
        view
        returns (
            bool isSplit,
            address bestRouterOrA,
            address routerB,
            uint16 splitBpsToA,
            uint256 bestOut
        )
    {
        require(path.length >= 2, "BAD_PATH");
        require(routers.length >= 1 && routers.length <= 5, "ROUTERS_1_TO_5");

        (address bestSingle, uint256 bestSingleOut) = _bestSingleQuote(amountIn, routers, path);

        TopTwo memory tt = _topTwoRouters(amountIn, routers, path);

        if (tt.r2 == address(0)) {
            return (false, bestSingle, address(0), 0, bestSingleOut);
        }

        (uint16 bestSplitBps, uint256 bestSplitOut) = _bestSplitQuote(amountIn, tt.r1, tt.r2, path);

        if (bestSplitOut > bestSingleOut) {
            return (true, tt.r1, tt.r2, bestSplitBps, bestSplitOut);
        }
        return (false, bestSingle, address(0), 0, bestSingleOut);
    }

    // -------------------- Execute: Auto Best Swap --------------------
    // Supports fee-on-transfer tokens by measuring actual received input.
    // You pass candidate routers (allowed routers only), and the contract selects best single or best split.
    function swapBest(
        uint256 amountIn,
        uint256 minOutTotal,
        address[] calldata routers,
        address[] calldata path,
        uint256 deadline
    ) public nonReentrant whenNotPaused returns (uint256 outToUser) {
        require(path.length >= 2, "BAD_PATH");
        require(routers.length >= 1 && routers.length <= 5, "ROUTERS_1_TO_5");
        require(block.timestamp <= deadline, "DEADLINE_PASSED");

        for (uint256 i = 0; i < routers.length; i++) {
            require(isAllowedRouter[routers[i]], "ROUTER_NOT_ALLOWED");
        }

        ExecCtx memory ctx;
        ctx.tokenIn = path[0];
        ctx.tokenOut = path[path.length - 1];
        ctx.deadline = deadline;
        ctx.minOutTotal = minOutTotal;

        uint256 actualIn = _pullTokenIn(ctx.tokenIn, msg.sender, amountIn);
        require(actualIn > 0, "ZERO_IN");

        Decision memory d = _decideBest(actualIn, routers, path);

        if (!d.doSplit) {
            outToUser = _execSingle(ctx, d.routerA, actualIn, path);
        } else {
            outToUser = _execSplit(ctx, d.routerA, d.routerB, actualIn, d.splitBpsToA, path);
        }
    }

    // Same as swapBest, but requires a prior commitment (basic MEV mitigation).
    function swapBestReveal(
        uint256 amountIn,
        uint256 minOutTotal,
        address[] calldata routers,
        address[] calldata path,
        uint256 deadline,
        bytes32 salt
    ) external nonReentrant whenNotPaused returns (uint256 outToUser) {
        bytes32 expected = keccak256(abi.encode(msg.sender, amountIn, minOutTotal, routers, path, deadline, salt));
        require(commitOf[msg.sender] != bytes32(0), "NO_COMMIT");
        require(commitOf[msg.sender] == expected, "BAD_COMMIT");
        // optional: prevent same-block reveal
        require(commitBlock[msg.sender] < uint64(block.number), "REVEAL_NEXT_BLOCK");

        delete commitOf[msg.sender];
        delete commitBlock[msg.sender];
        emit SwapCommitCleared(msg.sender);

        outToUser = swapBest(amountIn, minOutTotal, routers, path, deadline);
    }

    // -------------------- Internals: Quote --------------------
    function _safeAmountsOut(address router, uint256 amountIn, address[] calldata path) internal view returns (uint256 out) {
        // if router reverts, treat as 0
        try IUniswapV2RouterLike(router).getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
            if (amounts.length > 0) return amounts[amounts.length - 1];
            return 0;
        } catch {
            return 0;
        }
    }

    function _bestSingleQuote(
        uint256 amountIn,
        address[] calldata routers,
        address[] calldata path
    )
        internal
        view
        returns (address bestRouter, uint256 bestOut)
    {
        bestRouter = address(0);
        bestOut = 0;

        for (uint256 i = 0; i < routers.length; i++) {
            uint256 out = _safeAmountsOut(routers[i], amountIn, path);
            if (out > bestOut) {
                bestOut = out;
                bestRouter = routers[i];
            }
        }
        require(bestRouter != address(0), "NO_ROUTE");
    }

    function _topTwoRouters(
        uint256 amountIn,
        address[] calldata routers,
        address[] calldata path
    )
        internal
        view
        returns (TopTwo memory tt)
    {
        tt.r1 = address(0); tt.o1 = 0;
        tt.r2 = address(0); tt.o2 = 0;

        for (uint256 i = 0; i < routers.length; i++) {
            uint256 out = _safeAmountsOut(routers[i], amountIn, path);
            if (out > tt.o1) {
                tt.r2 = tt.r1; tt.o2 = tt.o1;
                tt.r1 = routers[i]; tt.o1 = out;
            } else if (out > tt.o2 && routers[i] != tt.r1) {
                tt.r2 = routers[i]; tt.o2 = out;
            }
        }
    }

    function _bestSplitQuote(
        uint256 amountIn,
        address routerA,
        address routerB,
        address[] calldata path
    )
        internal
        view
        returns (uint16 bestSplitBps, uint256 bestOut)
    {
        // Try these splits (advanced but bounded)
        // 10000 = 100%
        uint16[5] memory candidates = [uint16(10000), 7500, 5000, 2500, 0];

        bestSplitBps = 10000;
        bestOut = 0;

        for (uint256 i = 0; i < candidates.length; i++) {
            uint16 bpsA = candidates[i];
            uint256 amtA = (amountIn * bpsA) / 10000;
            uint256 amtB = amountIn - amtA;

            uint256 outA = amtA == 0 ? 0 : _safeAmountsOut(routerA, amtA, path);
            uint256 outB = amtB == 0 ? 0 : _safeAmountsOut(routerB, amtB, path);

            uint256 total = outA + outB;
            if (total > bestOut) {
                bestOut = total;
                bestSplitBps = bpsA;
            }
        }
    }

    function _decideBest(
        uint256 actualIn,
        address[] calldata routers,
        address[] calldata path
    ) internal view returns (Decision memory d) {
        (address bestSingle, uint256 bestSingleOut) = _bestSingleQuote(actualIn, routers, path);
        TopTwo memory tt = _topTwoRouters(actualIn, routers, path);

        d.doSplit = false;
        d.routerA = bestSingle;
        d.routerB = address(0);
        d.splitBpsToA = 0;
        d.bestOut = bestSingleOut;

        if (tt.r2 != address(0)) {
            (uint16 bestSplitBps, uint256 bestSplitOut) = _bestSplitQuote(actualIn, tt.r1, tt.r2, path);
            if (bestSplitOut > d.bestOut) {
                d.doSplit = true;
                d.routerA = tt.r1;
                d.routerB = tt.r2;
                d.splitBpsToA = bestSplitBps;
                d.bestOut = bestSplitOut;
            }
        }
    }

    // -------------------- Internals: Execute --------------------
    function _pullTokenIn(address tokenIn, address from, uint256 amount) internal returns (uint256 actualIn) {
        uint256 beforeBal = IERC20(tokenIn).balanceOf(address(this));
        IERC20(tokenIn).safeTransferFrom(from, address(this), amount);
        uint256 afterBal = IERC20(tokenIn).balanceOf(address(this));
        actualIn = afterBal - beforeBal; // supports fee-on-transfer tokens
    }

    function _takeFee(address tokenOut, uint256 amountOut) internal returns (uint256 fee, uint256 net) {
        if (protocolFeeBps == 0) return (0, amountOut);
        fee = (amountOut * protocolFeeBps) / 10000;
        net = amountOut - fee;
        if (fee > 0) IERC20(tokenOut).safeTransfer(feeRecipient, fee);
    }

    function _approveExact(address token, address spender, uint256 amount) internal {
        // OpenZeppelin v5: safeApprove removed, use forceApprove
        IERC20(token).forceApprove(spender, amount);
    }

    function _swapToSelf(
        ExecCtx memory ctx,
        address router,
        uint256 amountInPortion,
        address[] calldata path,
        uint256 minOutRoute
    ) internal returns (uint256 outPortion) {
        if (amountInPortion == 0) return 0;

        _approveExact(ctx.tokenIn, router, amountInPortion);

        uint256 beforeOut = IERC20(ctx.tokenOut).balanceOf(address(this));

        IUniswapV2RouterLike(router).swapExactTokensForTokens(
            amountInPortion,
            minOutRoute,
            path,
            address(this),
            ctx.deadline
        );

        uint256 afterOut = IERC20(ctx.tokenOut).balanceOf(address(this));
        outPortion = afterOut - beforeOut; // tokenOut fee-on-transfer safe
    }

    // emit helpers (reduce stack pressure in caller)
    function _emitSwapBestSingle(
        ExecCtx memory ctx,
        address router,
        uint256 amountIn,
        uint256 netOut,
        uint256 fee
    ) internal {
        emit SwapBestSingle(msg.sender, router, ctx.tokenIn, ctx.tokenOut, amountIn, netOut, fee);
    }

    function _emitSwapBestSplit(
        ExecCtx memory ctx,
        address routerA,
        address routerB,
        uint256 amountIn,
        uint256 netOut,
        uint256 outA,
        uint256 outB,
        uint256 splitBpsToA,
        uint256 fee
    ) internal {
        emit SwapBestSplit(
            msg.sender,
            routerA,
            routerB,
            ctx.tokenIn,
            ctx.tokenOut,
            amountIn,
            netOut,
            outA,
            outB,
            splitBpsToA,
            fee
        );
    }

    function _execSingle(
        ExecCtx memory ctx,
        address router,
        uint256 amountIn,
        address[] calldata path
    ) internal returns (uint256 outToUser) {
        uint256 actualOut = _swapToSelf(ctx, router, amountIn, path, ctx.minOutTotal);

        require(actualOut >= ctx.minOutTotal, "SLIPPAGE_TOO_HIGH");

        (uint256 fee, uint256 net) = _takeFee(ctx.tokenOut, actualOut);
        IERC20(ctx.tokenOut).safeTransfer(msg.sender, net);

        _emitSwapBestSingle(ctx, router, amountIn, net, fee);
        return net;
    }

    function _execSplit(
        ExecCtx memory ctx,
        address routerA,
        address routerB,
        uint256 amountIn,
        uint16 splitBpsToA,
        address[] calldata path
    ) internal returns (uint256 outToUser) {
        // keep locals minimal to avoid "stack too deep" without viaIR
        uint256 amtA = (amountIn * splitBpsToA) / 10000;
        uint256 amtB = amountIn - amtA;

        SplitOut memory so;
        so.outA = _swapToSelf(ctx, routerA, amtA, path, 0);
        so.outB = _swapToSelf(ctx, routerB, amtB, path, 0);
        so.totalOut = so.outA + so.outB;

        require(so.totalOut >= ctx.minOutTotal, "SLIPPAGE_TOO_HIGH");

        (uint256 fee, uint256 net) = _takeFee(ctx.tokenOut, so.totalOut);
        IERC20(ctx.tokenOut).safeTransfer(msg.sender, net);

        return net;
    }

    // -------------------- Rescue --------------------
    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    receive() external payable {
        revert("NO_ETH");
    }
}