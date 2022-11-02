// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "./interface/IOpenmetaController.sol";

abstract contract TradeModel is EIP712 {
    bytes32 public constant MAKER_ORDER_TYPEHASH =
        keccak256(
            "MakerOrder(bytes32 nftTokenHash,address maker,uint256 quantity,address paymentToken,uint256 authorProtocolFee,uint8 saleType,uint256 startTime,uint256 endTime,uint256 createTime,uint256 cancelTime)"
        );
    bytes32 public constant TAKER_ORDER_TYPEHASH =
        keccak256(
            "TakerOrder(bytes32 makerOrderHash,address taker,address author,uint256 dealAmount,uint256 rewardAmount,uint256 salt,bool minted,uint256 createTime)"
        );
    bytes32 public constant DEAL_ORDER_TYPEHASH =
        keccak256(
            "DealOrder(bytes32 makerOrderHash,address taker,address author,uint256 dealAmount,uint256 rewardAmount,uint256 salt,bool minted,uint256 deadline,uint256 createTime,bytes takerSig,uint256 quantity)"
        );

    enum TokenType {
        TYPE_BASE,
        TYPE_ERC721,
        TYPE_ERC1155
    } /// Unused type: TYPE_BASE
    enum SaleType {
        TYPE_BASE,
        TYPE_MARKET,
        TYPE_AUCTION
    } // Unused type: TYPE_BASE, TYPE_MARKET

    struct NftInfo {
        address nftToken; // The NFT contract address of the transaction
        uint256 tokenId; // The tokenid of the NFT contract address
        uint256[] batchTokenIds;
        uint256[] batchTokenPrice;
        TokenType tokenType; // Order nft token type: ERC721 or ERC1155
        uint256 chainId;
        uint256 salt;
    }

    struct MakerOrder {
        bytes32 nftTokenHash; // Struct NftInfo hash
        address maker; // Maker's address for the order
        uint256 price; // The price of the order
        uint256 quantity; // Quantity of the order NFT sold
        address paymentToken; // Token address for payment
        uint256 authorProtocolFee; // Copyright fees for NFT authors
        SaleType saleType; // Order trade type: Market or Auction
        uint256 startTime; // Sales start time
        uint256 endTime; // Sales end time
        uint256 createTime;
        uint256 cancelTime;
        bytes signature;
    }

    struct DealOrder {
        bytes32 makerOrderHash; // Maker order hash
        address taker; // Taker's address for the order
        address author; // NFT author address
        uint256 dealAmount; // The final transaction amount of the order
        uint256 rewardAmount; // Reward amount returned by holding coins
        uint256 salt;
        bool minted; // Whether the NFT has been minted
        uint256 deadline; // Deal order deadline
        uint256 createTime;
        bytes takerSig; // Taker's address signature
        uint256 quantity; // The actual quantity of NFTs in the deal order
        bytes signature; // Operator address signature
    }

    function getOrderHashBySig(
        NftInfo memory _nftInfo,
        MakerOrder memory _makerOrder,
        DealOrder memory _dealOrder,
        IOpenmetaController _controller
    ) internal view returns (bytes32 dealOrderHash) {
        require(
            _makerOrder.quantity >= _dealOrder.quantity &&
                _dealOrder.quantity > 0,
            "order quantity verification failed"
        );

        require(
            _nftInfo.batchTokenIds.length == _nftInfo.batchTokenPrice.length,
            "batch token arrays do not match"
        );

        bool hashTokenId = false;
        uint256 tokenIdLen = _nftInfo.batchTokenIds.length;
        for (uint256 i = 0; i < tokenIdLen; i++) {
            if (
                _nftInfo.batchTokenIds[i] == _nftInfo.tokenId &&
                _nftInfo.batchTokenPrice[i] == _makerOrder.price
            ) {
                hashTokenId = true;
            }
        }
        require(hashTokenId, "nft token data validation failed");

        uint256 dealAmount = _makerOrder.price * _dealOrder.quantity;
        require(
            _dealOrder.dealAmount >= dealAmount,
            "order deal amount verification failed"
        );

        bytes32 makerOrderHash = _makerOrderSig(_nftInfo, _makerOrder);
        require(
            makerOrderHash == _dealOrder.makerOrderHash,
            "maker order hash does not match"
        );

        _takerOrderSig(_dealOrder);
        dealOrderHash = _dealOrderSig(_dealOrder, _controller);
    }

    function _makerOrderSig(NftInfo memory _nftInfo, MakerOrder memory _order)
        private
        view
        returns (bytes32 makerOrderHash)
    {
        bytes32 nftTokenHash = keccak256(
            abi.encodePacked(
                _nftInfo.nftToken,
                _nftInfo.batchTokenIds,
                _nftInfo.batchTokenPrice,
                _nftInfo.tokenType,
                block.chainid,
                _nftInfo.salt
            )
        );
        require(
            nftTokenHash == _order.nftTokenHash,
            "Failed to verify nft token hash"
        );

        makerOrderHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    MAKER_ORDER_TYPEHASH,
                    nftTokenHash,
                    _order.maker,
                    _order.quantity,
                    _order.paymentToken,
                    _order.authorProtocolFee,
                    _order.saleType,
                    _order.startTime,
                    _order.endTime,
                    _order.createTime,
                    _order.cancelTime
                )
            )
        );

        address signer = ECDSA.recover(makerOrderHash, _order.signature);
        require(signer == _order.maker, "Failed to verify maker signature");
    }

    function _takerOrderSig(DealOrder memory _order) private view {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    TAKER_ORDER_TYPEHASH,
                    _order.makerOrderHash,
                    _order.taker,
                    _order.author,
                    _order.dealAmount,
                    _order.rewardAmount,
                    _order.salt,
                    _order.minted,
                    _order.createTime
                )
            )
        );

        address signer = ECDSA.recover(digest, _order.takerSig);
        require(signer == _order.taker, "Failed to verify taker signature");
    }

    function _dealOrderSig(
        DealOrder memory _order,
        IOpenmetaController _controller
    ) private view returns (bytes32 dealOrderHash) {
        dealOrderHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    DEAL_ORDER_TYPEHASH,
                    _order.makerOrderHash,
                    _order.taker,
                    _order.author,
                    _order.dealAmount,
                    _order.rewardAmount,
                    _order.salt,
                    _order.minted,
                    _order.deadline,
                    _order.createTime,
                    keccak256(_order.takerSig),
                    _order.quantity
                )
            )
        );
        address signer = ECDSA.recover(dealOrderHash, _order.signature);

        require(
            _controller.isSigAddress(signer),
            "Failed to verify singer signature"
        );
    }
}
