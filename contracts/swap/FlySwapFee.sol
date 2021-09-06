// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/proxy/Initializable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '../interfaces/IFlyFactory.sol';
import '../interfaces/IFlyRouter.sol';
import '../libraries/FlyLibrary.sol';
import '../interfaces/IFlyPair.sol';
import 'hardhat/console.sol';

contract FlySwapFee is Ownable, Initializable {
    using SafeMath for uint;
    using Address for address;

    address public constant hole = 0x000000000000000000000000000000000000dEaD;
    address public profit;
    address public node;
    IFlyRouter public router;
    IFlyFactory public factory;
    address public WETH;
    address public VDR;
    address public USDT;
    address public receiver;
    address public caller;

    function initialize(address profit_, address node_, IFlyRouter router_, IFlyFactory factory_, address WETH_, address VDR_, address USDT_, address receiver_, address caller_) external initializer {
        profit = profit_; 
        node = node_;
        router = router_;
        factory = factory_;
        WETH = WETH_;
        VDR = VDR_;
        USDT = USDT_;
        receiver = receiver_;
        caller = caller_;
    }

    function setCaller(address newCaller_) external onlyOwner {
        require(newCaller_ != address(0), "caller is zero");
        caller = newCaller_;
    }

    function setReceiver(address newReceiver_) external onlyOwner {
        require(newReceiver_ != address(0), "receiver is zero");
        receiver = newReceiver_;
    }

    function transferToProfit(IFlyPair pair, uint balance) internal returns (uint balanceRemained) {
        uint balanceUsed = balance.mul(2).div(7); //2/7
        balanceRemained = balance.sub(balanceUsed);
        SafeERC20.safeTransfer(IERC20(address(pair)), profit, balanceUsed);
    }

    function transferToNode(address token, uint balance) internal returns (uint balanceRemained) {
        uint balanceUsed = balance.mul(3).div(7); //3/7
        balanceRemained = balance.sub(balanceUsed);
        SafeERC20.safeTransfer(IERC20(token), node, balanceUsed);
    }

    function canRemove(IFlyPair pair) internal view returns (bool) {
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint balance0 = IERC20(token0).balanceOf(address(pair));
        uint balance1 = IERC20(token1).balanceOf(address(pair));
        uint totalSupply = pair.totalSupply();
        if (totalSupply == 0) {
            return false;
        }
        uint liquidity = pair.balanceOf(address(this));
        uint amount0 = liquidity.mul(balance0) / totalSupply; // using balances ensures pro-rata distribution
        uint amount1 = liquidity.mul(balance1) / totalSupply; // using balances ensures pro-rata distribution
        if (amount0 == 0 || amount1 == 0) {
            return false;
        }
        return true;
    }

    function doHardwork(address[] calldata pairs, uint minAmount) external {
        require(msg.sender == caller, "illegal caller");
        for (uint i = 0; i < pairs.length; i ++) {
            IFlyPair pair = IFlyPair(pairs[i]);
            if (pair.token0() != USDT && pair.token1() != USDT) {
                continue;
            }
            uint balance = pair.balanceOf(address(this));
            if (balance == 0) {
                continue;
            }
            if (balance < minAmount) {
                continue;
            }
            if (!canRemove(pair)) {
                continue;
            }
            balance = transferToProfit(pair, balance);
            address token = pair.token0() != USDT ? pair.token0() : pair.token1();
            pair.approve(address(router), balance);
            router.removeLiquidity(
                token,
                USDT,
                balance,
                0,
                0,
                address(this),
                block.timestamp
            );
            address[] memory path = new address[](2);
            path[0] = token;path[1] = USDT;
            balance = IERC20(token).balanceOf(address(this));
            IERC20(token).approve(address(router), balance);
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                balance,
                0,
                path,
                address(this),
                block.timestamp
            );
        }
    }

    function destroyAll() external onlyOwner {
        uint balance = IERC20(USDT).balanceOf(address(this));
        balance = transferToNode(USDT, balance);
        address[] memory path = new address[](2);
        path[0] = USDT;path[1] = VDR;
        balance = IERC20(USDT).balanceOf(address(this));
        IERC20(USDT).approve(address(router), balance);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            balance,
            0,
            path,
            address(this),
            block.timestamp
        );
        balance = IERC20(VDR).balanceOf(address(this));
        SafeERC20.safeTransfer(IERC20(VDR), hole, balance);
    }

    function transferOut(address token, uint amount) external onlyOwner {
        IERC20 erc20 = IERC20(token);
        uint balance = erc20.balanceOf(address(this));
        if (balance < amount) {
            amount = balance;
        }
        SafeERC20.safeTransfer(erc20, receiver, amount);
    }
}
