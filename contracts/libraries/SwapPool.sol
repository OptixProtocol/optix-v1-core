pragma solidity 0.8.6;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "../interfaces/Interfaces.sol";
import "../OptionsLP.sol";
 
library SwapPool {

  function addLiquidity(
        address _from,
        IERC20 _collateralToken,
        IERC20 _hedgeToken,
        uint _underlyingToDeposit,
        IUniswapV2Factory _swapFactory,
        IUniswapV2Router02 _swapRouter
      ) public returns (uint mintedSwapTokens){
        // require(_tokenA == WETH || _tokenB == WETH, "!weth");
    
        IERC20(_collateralToken).transferFrom(_from, address(this), _underlyingToDeposit);
    
    
        address pair = IUniswapV2Factory(_swapFactory).getPair(address(_collateralToken), address(_hedgeToken));
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(pair).getReserves();
    
        uint swapAmount;
        if (IUniswapV2Pair(pair).token0() == address(_collateralToken)) {
          // swap from token0 to token1
          swapAmount = getSwapAmount(reserve0, _underlyingToDeposit);
        } else {
          // swap from token1 to token0
          swapAmount = getSwapAmount(reserve1, _underlyingToDeposit);
        }
    
        _swapTokens(_swapRouter, _collateralToken, _hedgeToken, swapAmount);
        mintedSwapTokens = _addLiquidity(_swapRouter, _collateralToken, _hedgeToken);
      }
    
    
      /*
  s = optimal swap amount
  r = amount of reserve for token a
  a = amount of token a the user currently has (not added to reserve yet)
  f = swap fee percent
  s = (sqrt(((2 - f)r)^2 + 4(1 - f)ar) - (2 - f)r) / (2(1 - f))
  */
  function getSwapAmount(uint r, uint a) public pure returns (uint) {
    return (sqrt(r*(r*(3988009) + a*(3988000)))-(r*(1997))) / 1994;
  }
  
  function sqrt(uint y) internal pure returns (uint z) {
    if (y > 3) {
      z = y;
      uint x = y / 2 + 1;
      while (x < z) {
        z = x;
        x = (y / x + x) / 2;
      }
    } else if (y != 0) {
      z = 1;
    }
    // else z = 0 (default value)
  }

 function _swapTokens(
    IUniswapV2Router02 _swapRouter,
    IERC20 _fromToken,
    IERC20 _toToken,
    uint _amount
  ) public returns (uint[] memory amounts) {
    IERC20(_fromToken).approve(address(_swapRouter), _amount);

    address[] memory path = new address[](2);
    path = new address[](2);
    path[0] = address(_fromToken);
    path[1] = address(_toToken);

    return IUniswapV2Router02(_swapRouter).swapExactTokensForTokens(
      _amount,
      0,
      path,
      address(this),
      block.timestamp
    );
  }
  
  function _addLiquidity(IUniswapV2Router02 _swapRouter, IERC20 _collateralToken, IERC20 _hedgeToken) internal returns (uint mintedSwapTokens){
    uint balA = IERC20(_collateralToken).balanceOf(address(this));
    uint balB = IERC20(_hedgeToken).balanceOf(address(this));
    IERC20(_collateralToken).approve(address(_swapRouter), balA);
    IERC20(_hedgeToken).approve(address(_swapRouter), balB);

    (, , mintedSwapTokens) = IUniswapV2Router02(_swapRouter).addLiquidity(
          address(_collateralToken),
          address(_hedgeToken),
          balA,
          balB,
          0,
          0,
          address(this),
          block.timestamp
        );
  }
  
      
    function removeLiquidity(
        address _to,
        IERC20 _collateralToken,
        IERC20 _hedgeToken,
        uint _amountToWithdraw,
        IUniswapV2Factory _swapFactory,
        IUniswapV2Router02 _swapRouter
    ) public returns (uint underlyingAmount, uint hedgeAmount){
    
        IUniswapV2Pair pair = IUniswapV2Pair(_swapFactory.getPair(address(_collateralToken), address(_hedgeToken)));
        pair.approve(address(_swapRouter), _amountToWithdraw);

        (underlyingAmount, hedgeAmount) = IUniswapV2Router02(_swapRouter).removeLiquidity(
          address(_collateralToken),
          address(_hedgeToken),
          _amountToWithdraw,
          0,
          0,
          _to,
          block.timestamp+(1800)
        );
        // IERC20(_collateralToken).approve(_swapRouter, underlyingAmount);
        // IERC20(_hedgeToken).approve(_swapRouter, hedgeAmount);
        
        // IERC20(_collateralToken).transferFrom(address(this), _to, underlyingAmount);
        // IERC20(_hedgeToken).transferFrom(address(this), _to, hedgeAmount);
    }
    
    
    
       //deposit delta reserves back into the pool 
       function resetDeltaReserves( OptionsLP optionsLP, uint poolId ) public {

        if(optionsLP.collateralReserves(poolId)==0 && optionsLP.hedgeReserves(poolId)==0){
            return;
        }
        optionsLP.collateralToken(poolId).approve(address(this), 1e64);
        optionsLP.hedgeToken(poolId).approve(address(this), 1e64);
        uint[] memory amounts;
        if(optionsLP.hedgeReserves(poolId)>0){
            amounts = _swapTokens(optionsLP.swapRouter(poolId), optionsLP.hedgeToken(poolId), optionsLP.collateralToken(poolId), optionsLP.hedgeReserves(poolId));
            addLiquidity(address(this), optionsLP.collateralToken(poolId), optionsLP.hedgeToken(poolId), optionsLP.collateralReserves(poolId)+amounts[1], optionsLP.swapFactory(poolId), optionsLP.swapRouter(poolId));
        }
        else{
            addLiquidity(address(this), optionsLP.collateralToken(poolId), optionsLP.hedgeToken(poolId), optionsLP.collateralReserves(poolId), optionsLP.swapFactory(poolId), optionsLP.swapRouter(poolId));
        }
       }
       
       //reset before calling
       //withdraw percent of pool tokens (0%) 0..10000 (100%)
       //swap toUnderlying or the hedgeToken 
       function setDeltaHedge( uint percent, bool _toCollateral, OptionsLP optionsLP, uint poolId) public returns (uint collateralAmount, uint hedgeAmount, uint[] memory swapAmounts) {
           
        //resetDeltaReserves(_collateralToken, _hedgeToken, _collateralReserves, _hedgeReserves, _swapPool);
        (collateralAmount, hedgeAmount, swapAmounts) = withdrawDeltaReserves(percent,_toCollateral,optionsLP, poolId);
       }
       
              //(0%) 0..10000 (100%)
       //
       function withdrawDeltaReserves(uint percent, bool _toCollateral, OptionsLP optionsLP, uint poolId ) public returns (uint underlyingAmount, uint hedgeAmount, uint[] memory swapAmounts) {
            //swapPool token balance
            IUniswapV2Pair pair = IUniswapV2Pair(optionsLP.swapFactory(poolId).getPair(address(optionsLP.collateralToken(poolId)), address(optionsLP.hedgeToken(poolId))));
            uint swapPoolBalance = pair.balanceOf(address(this));
            
            //withdraw % of balance 
            uint withdraw = swapPoolBalance*(percent)/(10000);
            (underlyingAmount, hedgeAmount) = removeLiquidity(address(this),optionsLP.collateralToken(poolId),optionsLP.hedgeToken(poolId),withdraw,optionsLP.swapFactory(poolId), optionsLP.swapRouter(poolId));

            //swap & return reserve balances
            
            if (_toCollateral){
              optionsLP.hedgeToken(poolId).approve(address(optionsLP.swapRouter(poolId)), hedgeAmount);
              swapAmounts = _swapTokens( optionsLP.swapRouter(poolId), optionsLP.hedgeToken(poolId), optionsLP.collateralToken(poolId), hedgeAmount);
            }
            else {
              optionsLP.collateralToken(poolId).approve(address( optionsLP.swapRouter(poolId)), underlyingAmount);
              swapAmounts = _swapTokens( optionsLP.swapRouter(poolId), optionsLP.collateralToken(poolId), optionsLP.hedgeToken(poolId), underlyingAmount);
            }
       }
    
}