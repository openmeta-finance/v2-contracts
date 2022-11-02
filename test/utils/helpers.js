getSigners = async (ethers) => {
    const [owner, proxyOwner, bob, alice, user3, user4, badUser1, badUser2, fakeContract, sigUser] = await ethers.getSigners()
    bob.name = "bob"
    alice.name = "alice"

    return {
        owner,
        proxyOwner,
        bob,
        alice,
        user3,
        user4,
        badUser1,
        badUser2,
        fakeContract,
        sigUser,
    }
}

deployNew = async (contractName, params = []) => {
    const C = await ethers.getContractFactory(contractName)
    return await C.deploy(...params)
}

module.exports = {
    getSigners,
    deployNew
}
