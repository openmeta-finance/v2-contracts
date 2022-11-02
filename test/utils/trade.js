const { ethers } = require("hardhat");
const { ZERO_ADDRESS, ORIGIN_ADDRESS } = require("./constants");
const dayjs = require('dayjs');

const ContractEnum = {
    TokenType: {
        type_base: 0,
        type_erc721: 1,
        type_erc1155: 2
    },
    SaleType: {
        type_base: 0,
        type_market: 1,
        type_auction: 2
    }
}

createMakerOrder = async (
    nftInfo,
    makerUser,
    paymentToken = ORIGIN_ADDRESS,
    saleType = ContractEnum.SaleType.type_market,
    quantity = 1,
    authorProtocolFee = 500,
) => {
    const nft_hash = ethers.utils.solidityKeccak256(
        ["address", "uint256[]", "uint256[]", "uint8", "uint256", "uint256"],
        [nftInfo.nftToken, nftInfo.batchTokenIds, nftInfo.batchTokenPrice, nftInfo.tokenType, nftInfo.chainId, nftInfo.salt]
    );

    const index = nftInfo.batchTokenIds.indexOf(nftInfo.tokenId);
    const price = nftInfo.batchTokenPrice[index] || 0;
    
    const makerOrder = {
        nftTokenHash: nft_hash,
        maker: makerUser.address,
        price,
        quantity,
        paymentToken,
        authorProtocolFee,
        saleType,
        startTime: new dayjs().add(1, 'm').unix(),
        endTime: new dayjs().add(7, 'd').unix(),
        createTime: new dayjs().unix(),
        cancelTime: 0
    }

    return makerOrder;
}

createTakerOrder = async (
    makerOrder,
    takerUser,
    author,
    deadline = 33205644081,
    rewardAmount = 0,
    minted = false
) => {
    let dealAmount = ethers.BigNumber.from(makerOrder.price).mul(makerOrder.quantity).toString();

    const dealOrder = {
        makerOrderHash: '',
        taker: takerUser.address,
        author,
        dealAmount,
        rewardAmount,
        salt: 123456789,
        minted,
        deadline,
        createTime: new dayjs().unix()
    }

    return dealOrder;
}

performDealOrder = async (
    nftInfo,
    tradeAddress,
    makerUser,
    makerOrder,
    takerUser,
    dealOrder,
    sigUser,
    orderQuantity = 1
) => {
    const maker_order_info = await makerOrderSig(makerUser, makerOrder, nftInfo.chainId, tradeAddress);
    makerOrder['signature'] = maker_order_info['signature'];
    dealOrder['makerOrderHash'] = maker_order_info['order_hash'];

    dealOrder['takerSig'] = await takerOrderSig(takerUser, dealOrder, nftInfo.chainId, tradeAddress);

    dealOrder['quantity'] = orderQuantity;
    dealOrder['signature'] = await dealOrderSig(sigUser, dealOrder, nftInfo.chainId, tradeAddress);

    return { makerOrder, dealOrder }
}

async function makerOrderSig(wallet, maker_order, chain_id, trade_address) {
    const domain = getDomain(chain_id, trade_address);

    const types = {
        MakerOrder: [
            { name: 'nftTokenHash', type: 'bytes32' },
            { name: 'maker', type: 'address' },
            { name: 'quantity', type: 'uint256' },
            { name: 'paymentToken', type: 'address' },
            { name: 'authorProtocolFee', type: 'uint256' },
            { name: 'saleType', type: 'uint8' },
            { name: 'startTime', type: 'uint256' },
            { name: 'endTime', type: 'uint256' },
            { name: 'createTime', type: 'uint256' },
            { name: 'cancelTime', type: 'uint256' }
        ]
    }

    const signature = await wallet._signTypedData(domain, types, maker_order);
    const order_hash = ethers.utils._TypedDataEncoder.hash(domain, types, maker_order);
    return { signature, order_hash };
}

async function takerOrderSig(wallet, deal_order, chain_id, trade_address) {
    const domain = getDomain(chain_id, trade_address);

    const types = {
        TakerOrder: [
            { name: 'makerOrderHash', type: 'bytes32' },
            { name: 'taker', type: 'address' },
            { name: 'author', type: 'address' },
            { name: 'dealAmount', type: 'uint256' },
            { name: 'rewardAmount', type: 'uint256' },
            { name: 'salt', type: 'uint256' },
            { name: 'minted', type: 'bool' },
            { name: 'createTime', type: 'uint256' }
        ]
    }

    const signature = await wallet._signTypedData(domain, types, deal_order);
    return signature
}

async function dealOrderSig(wallet, deal_order, chain_id, trade_address) {
    const domain = getDomain(chain_id, trade_address);
    const types = {
        DealOrder: [
            { name: 'makerOrderHash', type: 'bytes32' },
            { name: 'taker', type: 'address' },
            { name: 'author', type: 'address' },
            { name: 'dealAmount', type: 'uint256' },
            { name: 'rewardAmount', type: 'uint256' },
            { name: 'salt', type: 'uint256' },
            { name: 'minted', type: 'bool' },
            { name: 'deadline', type: 'uint256' },
            { name: 'createTime', type: 'uint256' },
            { name: 'takerSig', type: 'bytes' },
            { name: 'quantity', type: 'uint256' }
        ]
    }

    const signature = await wallet._signTypedData(domain, types, deal_order);
    return signature
}

function getDomain(chain_id, trade_address) {
    return {
        name: "Openmeta NFT Trade",
        version: "2.0.0",
        chainId: chain_id,
        verifyingContract: trade_address
    }
}

module.exports = {
    ContractEnum,
    createMakerOrder,
    createTakerOrder,
    performDealOrder,
}