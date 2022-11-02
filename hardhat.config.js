require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [{
            version: "0.8.15",
            settings: {
                optimizer: { enabled: true, runs: 200 }
            }
        }]
    },
    networks: {
        hardhat: {}
    },
};
