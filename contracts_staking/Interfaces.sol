// SPDX-License-Identifier: --🦉--

pragma solidity =0.7.6;

interface IUniswapRouterV2 {

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (
        uint[] memory amounts
    );

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (
        uint[] memory amounts
    );

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (
        uint[] memory amounts
    );
}

// interface ERC20TokenI {

//     function transferFrom(
//         address _from,
//         address _to,
//         uint256 _value
//     )  external returns (
//         bool success
//     );

//     function approve(
//         address _spender,
//         uint256 _value
//     )  external returns (
//         bool success
//     );
// }

interface IGriseToken {

    function currentGriseDay()
        external view
        returns (uint64);

    function updateStakedToken(
        uint256 _stakedToken
    ) external;

    function setStaker(
        address _staker
    ) external;

    function resetStaker(
        address _staker
    ) external;

    function approve(
        address _spender,
        uint256 _value
    ) external returns (bool success);

    function totalSupply() 
        external view 
        returns (uint256);

    function mintSupply(
        address _investorAddress,
        uint256 _amount
    ) external;

    function burnSupply(
        address _investorAddress,
        uint256 _amount
    ) external;
}