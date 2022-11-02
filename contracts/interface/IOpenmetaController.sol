// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOpenmetaController {
    struct SupportPayment {
        address token;
        string symbol;
        bool status;
    }

    function feeTo() external view returns(address);

    function sigAddress() external view returns(address);

    function creaters(uint256) external view returns(address);

    function supportPayments(address) external view returns(SupportPayment memory);

    function isOriginToken(address _paymentToken) external pure returns(bool res);

    function checkFeeAmount(
        uint256 _amount,
        uint256 _authorProtocolFee
    ) external view returns(uint256 txAmount, uint256 totalFee, uint256 txFee, uint256 authorFee);

    function getMaximumFee(uint256 _amount) external view returns(uint256 maximumFee);

    function isSigAddress(address _addr) external view returns(bool);

    function isSupportPayment(address _paymentToken) external view returns(bool isSupport);
    
    function mint(address _to, uint256 _tokenId, uint256 _amount) external;
}