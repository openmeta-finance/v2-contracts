// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interface/IERCToken.sol";
import "./interface/IOpenmetaTrade.sol";

/// The controller contract of the ERC1155 token contract is mainly used to
/// manage ERC1155 minting, transfer, payment tokens and transaction fees.
contract OpenmetaController is AccessControl {
    struct SupportPayment {
        address token;
        string symbol;
        bool status;
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant SETTLE_ROLE = keccak256("SETTLE_ROLE");
    uint256 public constant BASE_ROUND = 10000;
    address public constant ETH_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address public sigAddress;
    address public nftToken;
    address public feeTo;
    uint256 public feeRate;
    uint256 public maxFeeLimit;
    mapping(uint256 => address) public creaters;
    mapping(address => SupportPayment) public supportPayments;
    IOpenmetaTrade public openmetaTrade;

    modifier CheckCreater(uint256 _tokenId) {
        require(creaters[_tokenId] == address(0), "token id has been minted");
        _;
    }

    constructor(
        address _nftToken,
        address _sigAddress,
        uint256 _maxFeeLimit
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SETTLE_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(SETTLE_ROLE, _sigAddress);

        nftToken = _nftToken;
        sigAddress = _sigAddress;
        maxFeeLimit = _maxFeeLimit;
    }

    function initialize(
        address _openmetaTrade,
        address _feeTo,
        uint256 _feeRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        setFeeTo(_feeTo, _feeRate);

        grantRole(OPERATOR_ROLE, _openmetaTrade);
        openmetaTrade = IOpenmetaTrade(_openmetaTrade);
    }

    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) external CheckCreater(_tokenId) onlyRole(OPERATOR_ROLE) {
        _mint(_to, _tokenId, _amount, "");
        creaters[_tokenId] = _to;
    }

    function isOriginToken(address _paymentToken)
        external
        pure
        returns (bool res)
    {
        res = _paymentToken == ETH_ADDRESS;
    }

    function getMaximumFee(uint256 _amount)
        public
        view
        returns (uint256 maximumFee)
    {
        maximumFee = (_amount * maxFeeLimit) / BASE_ROUND;
    }

    function checkFeeAmount(uint256 _amount, uint256 _authorProtocolFee)
        external
        view
        returns (
            uint256 txAmount,
            uint256 totalFee,
            uint256 txFee,
            uint256 authorFee
        )
    {
        if (_authorProtocolFee > 0) {
            authorFee = (_amount * _authorProtocolFee) / BASE_ROUND;
        }

        bool feeOn = feeTo != address(0);
        if (feeOn && feeRate > 0) {
            txFee = (_amount * feeRate) / BASE_ROUND;
        }

        totalFee = authorFee + txFee;
        uint256 maximumFee = getMaximumFee(_amount);
        require(totalFee <= maximumFee, "exceeding the maximum fee limit");

        txAmount = _amount - totalFee;
        require(txAmount <= _amount, "unverified fee amount");
    }

    function isSigAddress(address _addr) external view returns (bool) {
        return _addr == sigAddress;
    }

    function isSupportPayment(address _paymentToken)
        external
        view
        returns (bool isSupport)
    {
        SupportPayment memory payment = supportPayments[_paymentToken];
        if (payment.token != address(0) && payment.status) {
            isSupport = true;
        }
    }

    function setSigAddress(address _sigAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_sigAddress != address(0), "zero sig address");
        sigAddress = _sigAddress;
    }

    function batchSettlePayment(
        address[] memory _paymentTokens,
        string[] memory _paymentSymbols
    ) external onlyRole(SETTLE_ROLE) {
        require(
            _paymentTokens.length == _paymentSymbols.length,
            "not equal length"
        );

        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            SupportPayment storage payment = supportPayments[_paymentTokens[i]];
            require(payment.token == address(0), "payment token already exist");

            payment.token = _paymentTokens[i];
            payment.symbol = _paymentSymbols[i];
            payment.status = true;
        }
    }

    function batchRemovePayment(address[] memory _paymentTokens)
        external
        onlyRole(SETTLE_ROLE)
    {
        for (uint256 i = 0; i < _paymentTokens.length; i++) {
            require(
                supportPayments[_paymentTokens[i]].token != address(0),
                "payment token does not exist"
            );
            delete supportPayments[_paymentTokens[i]];
        }
    }

    function setFeeTo(address _feeTo, uint256 _feeRate)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_feeTo != address(0), "zero fee to address");
        require(_feeRate > 0, "wrong fee rate");

        feeTo = _feeTo;
        feeRate = _feeRate;
    }

    function setNftToken(address _nftToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_nftToken != address(0), "zero fee to address");

        nftToken = _nftToken;
    }

    function setMaxFeeLimit(uint256 _maxFeeLimit)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            _maxFeeLimit >= feeRate && _maxFeeLimit < BASE_ROUND,
            "verification fee limit failed"
        );
        maxFeeLimit = _maxFeeLimit;
    }

    function batchGrantOperator(address[] memory _operators)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < _operators.length; i++) {
            require(_operators[i] != address(0), "zero operator address");

            grantRole(OPERATOR_ROLE, _operators[i]);
        }
    }

    function setTradeController(address _newController)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        openmetaTrade.setController(_newController);
    }

    function _mint(
        address _to,
        uint256 _tokenId,
        uint256 _amount,
        bytes memory _data
    ) private {
        IERCToken(nftToken).mint(_to, _tokenId, _amount, _data);

        creaters[_tokenId] = _to;
    }
}
