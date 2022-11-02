// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./TradeModel.sol";
import "./utils/Validation.sol";
import "./libraries/TransferHelper.sol";

contract OpenmetaTrade is Validation, TradeModel {
    struct DealOrderStatus {
        bool dealRes;
        bool auctionRes;
    }

    IOpenmetaController public controller;
    address public feeRewardToken;
    mapping(address => uint256) public feeReturns;
    mapping(bytes32 => DealOrderStatus) public dealOrderStatus;

    modifier checkOrderCaller(
        MakerOrder memory _makerOrder,
        DealOrder memory _dealOrder
    ) {
        if (_makerOrder.saleType == SaleType.TYPE_AUCTION) {
            require(
                controller.isSigAddress(msg.sender),
                "caller is not the signer"
            );
        } else {
            require(msg.sender == _dealOrder.taker, "caller is not the taker");
        }
        _;
    }

    event PerformOrder(
        bytes32 indexed makerOrderHash,
        bytes32 indexed dealOrderHash,
        SaleType saleType,
        address maker,
        address taker,
        uint256 dealAmount,
        uint256 totalFee,
        DealOrderStatus dealRes
    );
    event Claim(address indexed user, uint256 amount);

    constructor(address _controller, address _rewardToken)
        EIP712("Openmeta NFT Trade", "2.0.0")
    {
        controller = IOpenmetaController(_controller);
        feeRewardToken = _rewardToken;
    }

    function performOrder(
        NftInfo memory _nftInfo,
        MakerOrder memory _makerOrder,
        DealOrder memory _dealOrder
    )
        external
        payable
        checkOrderCaller(_makerOrder, _dealOrder)
        checkDeadline(_dealOrder.deadline)
        returns (bytes32 dealOrderHash, uint256 totalFee)
    {
        require(
            controller.isSupportPayment(_makerOrder.paymentToken),
            "not support payment token"
        );
        require(
            _dealOrder.quantity <= _makerOrder.quantity,
            "order quantity not verified"
        );

        dealOrderHash = getOrderHashBySig(
            _nftInfo,
            _makerOrder,
            _dealOrder,
            controller
        );
        require(
            !dealOrderStatus[dealOrderHash].dealRes,
            "deal order has been completed"
        );

        /// When the order type is auction, check whether the conditions are met.
        /// If not, the transfer will not be processed and the event flag will be false
        bool processRes = true;
        bool isOriginToken = controller.isOriginToken(_makerOrder.paymentToken);
        if (_makerOrder.saleType == SaleType.TYPE_AUCTION) {
            require(
                !isOriginToken,
                "auctions do not support chain-based coins"
            );

            (uint256 nftBalance, uint256 amountBalance) = getOrderUserBalance(
                _nftInfo,
                _makerOrder,
                _dealOrder.taker,
                isOriginToken
            );

            if (
                (_dealOrder.minted && nftBalance < _dealOrder.quantity) ||
                amountBalance < _dealOrder.dealAmount
            ) {
                processRes = false;
            }
        }

        /// If the conditions are met, initiate a transfer to complete the order transaction
        if (processRes) {
            totalFee = _transferForTakeFee(
                _nftInfo,
                _makerOrder,
                _dealOrder,
                isOriginToken
            );
        }

        DealOrderStatus memory deal_res = DealOrderStatus(true, processRes);
        dealOrderStatus[dealOrderHash] = deal_res;

        emit PerformOrder(
            _dealOrder.makerOrderHash,
            dealOrderHash,
            _makerOrder.saleType,
            _makerOrder.maker,
            _dealOrder.taker,
            _dealOrder.dealAmount,
            totalFee,
            deal_res
        );
    }

    /// ### Transaction fee refund ###
    /// Takers can get transaction fee rebates by holding MDX Token
    function claim() external {
        uint256 amount = feeReturns[msg.sender];
        require(amount > 0, "insufficient reward");

        uint256 balance = IERC20(feeRewardToken).balanceOf(address(this));
        require(balance >= amount, "insufficient balance");

        feeReturns[msg.sender] = feeReturns[msg.sender] - amount;
        TransferHelper.safeTransfer(feeRewardToken, msg.sender, amount);

        emit Claim(msg.sender, amount);
    }

    function setController(address _controller) external {
        require(_controller != address(0), "zero address");
        require(
            msg.sender == address(controller),
            "the caller is not the controller"
        );

        controller = IOpenmetaController(_controller);
    }

    function getOrderUserBalance(
        NftInfo memory _nftInfo,
        MakerOrder memory _makerOrder,
        address _taker,
        bool _originToken
    ) public view returns (uint256 nftBalance, uint256 amountBalance) {
        if (_nftInfo.tokenType == TokenType.TYPE_ERC721) {
            if (
                IERC721(_nftInfo.nftToken).ownerOf(_nftInfo.tokenId) ==
                _makerOrder.maker
            ) {
                nftBalance = 1;
            }
        }

        if (_nftInfo.tokenType == TokenType.TYPE_ERC1155) {
            nftBalance = IERC1155(_nftInfo.nftToken).balanceOf(
                _makerOrder.maker,
                _nftInfo.tokenId
            );
        }

        if (_originToken) {
            amountBalance = _taker.balance;
        } else {
            amountBalance = IERC20(_makerOrder.paymentToken).balanceOf(_taker);
        }
    }

    function _transferForTakeFee(
        NftInfo memory _nftInfo,
        MakerOrder memory _makerOrder,
        DealOrder memory _dealOrder,
        bool _originToken
    ) internal returns (uint256) {
        /// Calculate the total fees for this order
        address feeTo = controller.feeTo();
        (
            uint256 amount,
            uint256 totalFee,
            uint256 txFee,
            uint256 authorFee
        ) = controller.checkFeeAmount(
                _dealOrder.dealAmount,
                _makerOrder.authorProtocolFee
            );

        /// Complete transaction transfer based on payment token type
        if (_originToken) {
            require(msg.value >= _dealOrder.dealAmount, "insufficient value");

            TransferHelper.safeTransferETH(_makerOrder.maker, amount);

            if (txFee > 0) {
                TransferHelper.safeTransferETH(feeTo, txFee);
            }

            if (authorFee > 0) {
                TransferHelper.safeTransferETH(_dealOrder.author, authorFee);
            }
        } else {
            TransferHelper.safeTransferFrom(
                _makerOrder.paymentToken,
                _dealOrder.taker,
                _makerOrder.maker,
                amount
            );

            if (txFee > 0) {
                require(feeTo != address(0), "zero fee address");
                TransferHelper.safeTransferFrom(
                    _makerOrder.paymentToken,
                    _dealOrder.taker,
                    feeTo,
                    txFee
                );
            }

            if (authorFee > 0) {
                require(_dealOrder.author != address(0), "zero author address");
                TransferHelper.safeTransferFrom(
                    _makerOrder.paymentToken,
                    _dealOrder.taker,
                    _dealOrder.author,
                    authorFee
                );
            }
        }

        /// Check whether the order NFT Token has been minted.
        /// If it has been minted, call the contract transfer method,
        /// otherwise mint the NFT tokenid and send it to the taker
        if (_dealOrder.minted) {
            if (_nftInfo.tokenType == TokenType.TYPE_ERC721) {
                IERC721(_nftInfo.nftToken).safeTransferFrom(
                    _makerOrder.maker,
                    _dealOrder.taker,
                    _nftInfo.tokenId
                );
            }
            if (_nftInfo.tokenType == TokenType.TYPE_ERC1155) {
                IERC1155(_nftInfo.nftToken).safeTransferFrom(
                    _makerOrder.maker,
                    _dealOrder.taker,
                    _nftInfo.tokenId,
                    _dealOrder.quantity,
                    ""
                );
            }
        } else {
            require(_makerOrder.quantity == 1, "mint quantity not verified");

            controller.mint(_dealOrder.taker, _nftInfo.tokenId, 1);
        }

        feeReturns[_dealOrder.taker] =
            feeReturns[_dealOrder.taker] +
            _dealOrder.rewardAmount;

        return totalFee;
    }
}
