const { expect } = require("chai");
const { ethers } = require("hardhat");
const dayjs = require('dayjs');
const {
    ContractEnum,
    createMakerOrder,
    createTakerOrder,
    performDealOrder,
} = require('./utils/trade');
const { getSigners, deployNew } = require("./utils/helpers");
const { ZERO_ADDRESS, ORIGIN_ADDRESS } = require("./utils/constants");

describe("V2 - Openmeta Trade", function () {
    let sigUser, bob, alice, user3, badUser1, chain_id, token_id, batchTokenIds, batchTokenPrice, quantity;
    let openmetaTrade, openmetaNFT, controller, mockPaymentToken, mockRewardToken, nftInfo, perMakerOrder, perTakerOrder;

    before(async function () {
        ({ sigUser, bob, alice, user3, badUser1 } = await getSigners(ethers));

        const network = await ethers.provider.getNetwork();
        chain_id = network.chainId;
        token_id = 8000001000001;
        batchTokenIds = [8000001000001, 8000001000002, 8000001000003]
        batchTokenPrice = [
            ethers.utils.parseEther("1").toString(),
            ethers.utils.parseEther("2").toString(),
            ethers.utils.parseEther("5").toString()
        ]
        quantity = 1;
    });

    beforeEach(async function () {
        openmetaNFT = await deployNew("OpenmetaNFT", [
            "Openmeta NFT",
            "OMTT"
        ]);

        mockPaymentToken = await deployNew("MockToken", [
            "Mock payment token",
            "MPMT",
            ethers.constants.MaxUint256
        ]);

        mockRewardToken = await deployNew("MockToken", [
            "Mock reward token",
            "MRWT",
            ethers.constants.MaxUint256
        ]);

        controller = await deployNew("OpenmetaController", [
            openmetaNFT.address,
            sigUser.address,
            2500
        ]);
        await controller.batchSettlePayment([ORIGIN_ADDRESS, mockPaymentToken.address], ["ETH", "MPMT"]);

        openmetaTrade = await deployNew("OpenmetaTrade", [
            controller.address,
            mockRewardToken.address
        ]);

        const minter_role = await openmetaNFT.MINTER_ROLE();
        await openmetaNFT.grantRole(minter_role, controller.address);
        await controller.initialize(openmetaTrade.address, sigUser.address, 200);

        nftInfo = {
            nftToken: openmetaNFT.address,
            tokenId: token_id,
            batchTokenIds,
            batchTokenPrice,
            tokenType: ContractEnum.TokenType.type_erc1155,
            chainId: chain_id,
            salt: 1901238923489
        };

        perMakerOrder = await createMakerOrder(nftInfo, bob, ORIGIN_ADDRESS, ContractEnum.SaleType.type_market, quantity);
        perTakerOrder = await createTakerOrder(
            perMakerOrder,
            alice,
            user3.address
        );
    });

    describe("Check contract base configuration", () => {
        it("Controller address check", async () => {
            expect(await openmetaTrade.controller()).to.equal(controller.address);
        });

        it("Fee reward token check", async () => {
            expect(await openmetaTrade.feeRewardToken()).to.equal(mockRewardToken.address);
        });
    });

    describe("Check controller settings", () => {
        it("Only controller can set the trade's controller address", async () => {
            await expect(
                openmetaTrade.setController(controller.address)
            ).to.be.revertedWith("the caller is not the controller");
        });

        it("Cannot set controller to zero address", async () => {
            await expect(
                controller.setTradeController(ZERO_ADDRESS)
            ).to.be.revertedWith("zero address");
        });

        it("Set a new controller address", async () => {
            await controller.setTradeController(badUser1.address);
            expect(await openmetaTrade.controller()).to.equal(badUser1.address);
        });
    });

    describe("Trading order precondition check", () => {
        it("Caller is not the order taker check", async () => {
            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser
            );

            await expect(
                openmetaTrade.connect(badUser1).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("caller is not the taker");
        });

        it("Order deadline has expired", async () => {
            perTakerOrder = await createTakerOrder(
                perMakerOrder,
                alice,
                user3.address,
                dayjs().subtract(10, 'm').unix()
            );

            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("Transaction too old");
        });

        it("Not support payment token check", async () => {
            perMakerOrder = await createMakerOrder(nftInfo, bob, mockRewardToken.address);

            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("not support payment token");
        });

        it("Order quantity check", async () => {
            perMakerOrder = await createMakerOrder(nftInfo, bob);

            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser,
                quantity + 1
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("order quantity not verified");
        });

        it("Batch token arrays do not match", async () => {
            nftInfo.batchTokenIds = [
                8000001000001, 8000001000002
            ]
            perMakerOrder = await createMakerOrder(nftInfo, bob);

            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser,
                quantity
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("batch token arrays do not match");
        })

        it("TokenId price mismatch", async () => {
            perMakerOrder = await createMakerOrder(nftInfo, bob);

            nftInfo.batchTokenPrice[0] = ethers.utils.parseEther("100").toString();
            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser,
                quantity
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("nft token data validation failed");
        })

        it("Transactions with tokenid not in batch range", async () => {
            nftInfo.tokenId = 7000001000001;
            perMakerOrder = await createMakerOrder(nftInfo, bob);

            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser,
                quantity
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("nft token data validation failed");
        })
    })

    describe("Trading order user signature check", () => {
        it("Maker order signature failed check", async () => {
            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                badUser1,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("Failed to verify maker signature");
        });

        it("Taker order signature failed check", async () => {
            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                badUser1,
                perTakerOrder,
                sigUser
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("Failed to verify taker signature");
        });

        it("Deal order signature failed check", async () => {
            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                badUser1
            );

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("Failed to verify singer signature");
        });

    })

    describe("Final trade check for trade orders", () => {
        it("Deal order repeat transaction", async () => {
            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser
            );

            await openmetaTrade.connect(alice).performOrder(
                nftInfo,
                makerOrder,
                dealOrder,
                { value: dealOrder.dealAmount }
            )

            await expect(
                openmetaTrade.connect(alice).performOrder(
                    nftInfo,
                    makerOrder,
                    dealOrder,
                    { value: dealOrder.dealAmount }
                )
            ).to.be.revertedWith("deal order has been completed");
        });

        it("Check unminted market order transactions", async () => {
            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser,
                quantity
            );

            await openmetaTrade.connect(alice).performOrder(
                nftInfo,
                makerOrder,
                dealOrder,
                { value: dealOrder.dealAmount }
            );

            expect(await openmetaNFT.balanceOf(alice.address, token_id)).to.equal(quantity);
        });

        it("Check minted market order transactions", async () => {
            perTakerOrder = await createTakerOrder(
                perMakerOrder,
                alice,
                user3.address,
                dayjs().add(10, 'm').unix(),
                0,
                true
            );

            const { makerOrder, dealOrder } = await performDealOrder(
                nftInfo,
                openmetaTrade.address,
                bob,
                perMakerOrder,
                alice,
                perTakerOrder,
                sigUser,
                quantity
            );

            await expect(openmetaTrade.connect(alice).performOrder(
                nftInfo,
                makerOrder,
                dealOrder,
                { value: dealOrder.dealAmount }
            )).to.be.revertedWith("ERC1155: caller is not token owner nor approved");

            await openmetaNFT.connect(bob).setApprovalForAll(openmetaTrade.address, true);
            await expect(openmetaTrade.connect(alice).performOrder(
                nftInfo,
                makerOrder,
                dealOrder,
                { value: dealOrder.dealAmount }
            )).to.be.revertedWith("ERC1155: insufficient balance for transfer");

            await openmetaNFT.mint(bob.address, token_id, quantity, '0x');
            await openmetaTrade.connect(alice).performOrder(
                nftInfo,
                makerOrder,
                dealOrder,
                { value: dealOrder.dealAmount }
            );
            expect(await openmetaNFT.balanceOf(alice.address, token_id)).to.equal(quantity);
        });
    })
});