// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERCToken {
    function isApprovedForAll(address account, address operator) external view returns(bool);
    function mint(address account, uint256 id, uint256 amount, bytes memory data) external;
    function hasCreater(uint256 _tokenId) external view returns (bool);
}