import "dotenv/config";

import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

require("dotenv").config();

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    paths: {
        artifacts: "./artifacts",
    },
    networks: {
        hardhat: {
            forking: {
                url: "https://rockbeard-eth-cartio.berachain.com/",
                blockNumber: 586534,
            },
        },
        berachainTestnet: {
            chainId: 80084,
            url: "https://bartio.rpc.berachain.com/",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        },
        cartio: {
            chainId: 80000,
            url: "https://rockbeard-eth-cartio.berachain.com/",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        },
    },
};

export default config;
